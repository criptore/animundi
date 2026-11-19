using System;
using System.Collections;
using System.Collections.Generic;
using System.IO;
using System.IO.Compression;
using System.Reflection;
using System.Runtime.CompilerServices;

namespace Animundi.Sim;

/// <summary>
/// Saving and loading a whole world (1.0, docs/POLISH.md): everything the simulation holds (the
/// land, every creature, plant, village, building, kingdom, culture, invention, spirit, legend,
/// sickness, the ages, the mood of the world, the chronicle, even the dice) is written as one
/// compressed blob, and read back into a simulation started on the same land.
///
/// The writer walks the simulation's fields by reflection, keeping shared objects shared (a
/// spirit and the record of its kind). Lists, dictionaries and sets are written as their items
/// and built again on loading, so hash codes (which change from one run to the next) never travel.
/// What belongs to drawing (meshes, buffers, caches), to the scheduler (its systems are made by
/// Start) and to questions still waiting for the model is left out: drawing is made again, and a
/// mind whose question was lost simply asks again.
/// </summary>
public partial class Simulation
{
	public const int SaveVersion = 1;

	/// <summary>Fields of the simulation that are not the world's state: drawing and its caches.</summary>
	private static readonly HashSet<string> NotSaved = new()
	{
		"Scheduler", "_renderingReady", "_quad", "_atlasTexture", "_shadowTexture", "_regions", "_colors", "_atlasSizes", "_library",
		"_spriteInfo", "_unitMaterial", "_plantMaterial", "_shadowMaterial", "_plantShadowLayer", "_plantLayer", "_unitMesh",
		"_unitShadowMesh", "_unitShadowInstance", "_unitBuffer", "_unitShadowBuffer", "_keys", "_stripDirty", "_strips", "_drawMs",
		"_drawSamples", "_zoom", "_peopleFrames", "_speciesFrames", "_buildingSprites", "_fx", "_items", "_view", "_near",
		"_processRows", "_stepMs", "_stepSamples", "_accumulate", "_powerFound", "_found",
	};

	/// <summary>The whole simulation as a compressed blob (see LoadState).</summary>
	public byte[] SaveState()
	{
		using var raw = new MemoryStream();
		using (var zip = new DeflateStream(raw, CompressionLevel.Fastest, leaveOpen: true))
		using (var w = new BinaryWriter(zip))
		{
			w.Write("ANIMUNDI");
			w.Write(SaveVersion);
			w.Write(Scheduler.Time);
			w.Write(Scheduler.StepScale);
			var writer = new StateWriter(w);
			foreach (var f in SavedFields())
			{
				w.Write(f.Name);
				writer.Write(f.GetValue(this));
			}
			w.Write("");
		}
		return raw.ToArray();
	}

	/// <summary>Reads a blob of SaveState into this simulation, which must have been started on
	/// the same land (Start). Returns "" or why it could not.</summary>
	public string LoadState(byte[] blob)
	{
		if (blob == null || blob.Length == 0)
			return "empty";
		var fields = new Dictionary<string, FieldInfo>();
		foreach (var f in SavedFields())
			fields[f.Name] = f;
		try
		{
			using var zip = new DeflateStream(new MemoryStream(blob), CompressionMode.Decompress);
			using var r = new BinaryReader(zip);
			if (r.ReadString() != "ANIMUNDI")
				return "not a saved world";
			int version = r.ReadInt32();
			if (version > SaveVersion)
				return $"saved by a newer version ({version})";
			double time = r.ReadDouble();
			int stepScale = r.ReadInt32();
			var reader = new StateReader(r);
			var values = new List<(FieldInfo f, object v)>();
			for (string name = r.ReadString(); name != ""; name = r.ReadString())
			{
				object v = reader.Read();
				if (fields.TryGetValue(name, out var f) && (v == null || f.FieldType.IsInstanceOfType(v)))
					values.Add((f, v));
			}
			// Nothing is changed before the whole blob has been read.
			foreach (var (f, v) in values)
				f.SetValue(this, v);
			Scheduler.Time = time;
			Scheduler.StepScale = Math.Clamp(stepScale, 1, 30);
		}
		catch (Exception e)
		{
			return "could not read it: " + e.Message;
		}
		AfterLoad();
		return "";
	}

	private static IEnumerable<FieldInfo> SavedFields()
	{
		foreach (var f in typeof(Simulation).GetFields(BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.DeclaredOnly))
			if (!NotSaved.Contains(f.Name) && StateWriter.Saveable(f.FieldType))
				yield return f;
	}

	/// <summary>After a load: zones, plants and every texture of the map are made again.</summary>
	private void AfterLoad()
	{
		Zones = new ZoneGrid(World.Width, World.Height);
		Zones.Rebuild(Units);
		if (_stripDirty.Length > 0)
			Array.Fill(_stripDirty, true);
		_buildingSprites.Clear();
		_scorchChanged.Clear();
		_overlayChanged.Clear();
		for (int t = 0; t < World.Width * World.Height; t++)
		{
			if (Scorch[t] > 0)
				_scorchChanged.Add(t);
			_overlayChanged.Add(t);
		}
		foreach (var v in Villages)
			v.ModsDirty = true;
		// Questions to the model were not saved: the minds ask again.
		foreach (var k in Kingdoms)
		{
			k.AgeAsking = null;
			if (k.Culture != null)
				k.Culture.Asking = null;
		}
		foreach (var s in Spirits)
			s.Asking = null;
		foreach (var s in Strains)
			s.Asking = null;
		_chapterAsking = null;
		_minds.Clear();
	}

	// ------------------------------------------------------------------ the writer

	private enum Tag : byte { Null, Value, Ref, Back }

	private sealed class StateWriter
	{
		private readonly BinaryWriter _w;
		private readonly Dictionary<object, int> _seen = new(ReferenceEqualityComparer.Instance);
		private readonly Dictionary<Type, int> _types = new();

		public StateWriter(BinaryWriter w) => _w = w;

		/// <summary>Whether values of this type are part of the world's state: not Godot's objects
		/// and collections, not delegates, tasks or the model's pending questions.</summary>
		public static bool Saveable(Type t)
		{
			if (t.IsArray)
				return Saveable(t.GetElementType());
			if (typeof(Godot.GodotObject).IsAssignableFrom(t) || typeof(Delegate).IsAssignableFrom(t)
				|| typeof(System.Threading.Tasks.Task).IsAssignableFrom(t) || t == typeof(Question) || t == typeof(Type)
				|| t.Namespace == "Godot.Collections" || t == typeof(System.Net.Http.HttpClient))
				return false;
			if (t.IsGenericType)
				foreach (var a in t.GetGenericArguments())
					if (!Saveable(a))
						return false;
			return true;
		}

		private void WriteType(Type t)
		{
			if (_types.TryGetValue(t, out int id))
			{
				_w.Write(id);
				return;
			}
			_w.Write(-1);
			_w.Write(t.AssemblyQualifiedName ?? t.FullName);
			_types[t] = _types.Count;
		}

		public void Write(object v)
		{
			if (v == null || !Saveable(v.GetType()))
			{
				_w.Write((byte)Tag.Null);
				return;
			}
			var t = v.GetType();
			if (t.IsValueType || v is string)
			{
				_w.Write((byte)Tag.Value);
				WriteType(t);
				WriteBody(v, t);
				return;
			}
			if (_seen.TryGetValue(v, out int back))
			{
				_w.Write((byte)Tag.Back);
				_w.Write(back);
				return;
			}
			_seen[v] = _seen.Count;
			_w.Write((byte)Tag.Ref);
			WriteType(t);
			WriteBody(v, t);
		}

		private void WriteBody(object v, Type t)
		{
			switch (v)
			{
				case string s: _w.Write(s); return;
				case bool b: _w.Write(b); return;
				case byte b: _w.Write(b); return;
				case sbyte b: _w.Write(b); return;
				case short s: _w.Write(s); return;
				case ushort s: _w.Write(s); return;
				case int i: _w.Write(i); return;
				case uint i: _w.Write(i); return;
				case long l: _w.Write(l); return;
				case ulong l: _w.Write(l); return;
				case float f: _w.Write(f); return;
				case double d: _w.Write(d); return;
				case char c: _w.Write(c); return;
				case decimal m: _w.Write(m); return;
			}
			if (t.IsEnum)
			{
				_w.Write(System.Convert.ToInt64(v));
				return;
			}
			if (v is Array array)
			{
				if (array.Rank != 1)
					throw new NotSupportedException($"arrays of rank {array.Rank}");
				_w.Write(array.Length);
				var e = t.GetElementType();
				if (e.IsPrimitive)
				{
					var bytes = new byte[Buffer.ByteLength(array)];
					Buffer.BlockCopy(array, 0, bytes, 0, bytes.Length);
					_w.Write(bytes.Length);
					_w.Write(bytes);
					return;
				}
				foreach (var item in array)
					Write(item);
				return;
			}
			if (t.IsGenericType)
			{
				var g = t.GetGenericTypeDefinition();
				if (g == typeof(List<>) || g == typeof(HashSet<>) || g == typeof(Queue<>) || g == typeof(Stack<>))
				{
					var items = new List<object>();
					foreach (var item in (IEnumerable)v)
						items.Add(item);
					// A stack is written from the bottom, so pushing again keeps its order.
					if (g == typeof(Stack<>))
						items.Reverse();
					_w.Write(items.Count);
					foreach (var item in items)
						Write(item);
					return;
				}
				if (g == typeof(Dictionary<,>))
				{
					var d = (IDictionary)v;
					_w.Write(d.Count);
					foreach (DictionaryEntry kv in d)
					{
						Write(kv.Key);
						Write(kv.Value);
					}
					return;
				}
			}
			// Any other object or struct: its fields, by name.
			foreach (var f in AllFields(t))
			{
				if (!Saveable(f.FieldType))
					continue;
				_w.Write(f.Name);
				Write(f.GetValue(v));
			}
			_w.Write("");
		}
	}

	/// <summary>The instance fields of a type and of its bases.</summary>
	private static IEnumerable<FieldInfo> AllFields(Type t)
	{
		for (var c = t; c != null && c != typeof(object) && c != typeof(ValueType); c = c.BaseType)
			foreach (var f in c.GetFields(BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.DeclaredOnly))
				yield return f;
	}

	// ------------------------------------------------------------------ the reader

	private sealed class StateReader
	{
		private readonly BinaryReader _r;
		private readonly List<object> _seen = new();
		private readonly List<Type> _types = new();

		public StateReader(BinaryReader r) => _r = r;

		private Type ReadType()
		{
			int id = _r.ReadInt32();
			if (id >= 0)
				return _types[id];
			string name = _r.ReadString();
			var t = Type.GetType(name, an =>
			{
				if (an.Name == typeof(Simulation).Assembly.GetName().Name)
					return typeof(Simulation).Assembly;
				foreach (var a in AppDomain.CurrentDomain.GetAssemblies())
					if (a.GetName().Name == an.Name)
						return a;
				return null;
			}, null, true);
			_types.Add(t);
			return t;
		}

		public object Read()
		{
			var tag = (Tag)_r.ReadByte();
			switch (tag)
			{
				case Tag.Null:
					return null;
				case Tag.Back:
					return _seen[_r.ReadInt32()];
				case Tag.Value:
				{
					var t = ReadType();
					return ReadBody(t, -1);
				}
				default:
				{
					var t = ReadType();
					int slot = _seen.Count;
					_seen.Add(null);
					return ReadBody(t, slot);
				}
			}
		}

		/// <summary>A value of type t; a reference object is put in its slot before its content is
		/// read, so objects that point back at it find it.</summary>
		private object ReadBody(Type t, int slot)
		{
			if (t == typeof(string)) return _r.ReadString();
			if (t == typeof(bool)) return _r.ReadBoolean();
			if (t == typeof(byte)) return _r.ReadByte();
			if (t == typeof(sbyte)) return _r.ReadSByte();
			if (t == typeof(short)) return _r.ReadInt16();
			if (t == typeof(ushort)) return _r.ReadUInt16();
			if (t == typeof(int)) return _r.ReadInt32();
			if (t == typeof(uint)) return _r.ReadUInt32();
			if (t == typeof(long)) return _r.ReadInt64();
			if (t == typeof(ulong)) return _r.ReadUInt64();
			if (t == typeof(float)) return _r.ReadSingle();
			if (t == typeof(double)) return _r.ReadDouble();
			if (t == typeof(char)) return _r.ReadChar();
			if (t == typeof(decimal)) return _r.ReadDecimal();
			if (t.IsEnum)
				return Enum.ToObject(t, _r.ReadInt64());
			if (t.IsArray)
			{
				int n = _r.ReadInt32();
				var e = t.GetElementType();
				var array = Array.CreateInstance(e, n);
				if (slot >= 0)
					_seen[slot] = array;
				if (e.IsPrimitive)
				{
					int bytes = _r.ReadInt32();
					Buffer.BlockCopy(_r.ReadBytes(bytes), 0, array, 0, bytes);
					return array;
				}
				for (int k = 0; k < n; k++)
					array.SetValue(Read(), k);
				return array;
			}
			if (t.IsGenericType)
			{
				var g = t.GetGenericTypeDefinition();
				if (g == typeof(List<>) || g == typeof(HashSet<>) || g == typeof(Queue<>) || g == typeof(Stack<>))
				{
					var c = Activator.CreateInstance(t);
					if (slot >= 0)
						_seen[slot] = c;
					var add = t.GetMethod(g == typeof(Queue<>) ? "Enqueue" : g == typeof(Stack<>) ? "Push" : "Add");
					int n = _r.ReadInt32();
					for (int k = 0; k < n; k++)
						add.Invoke(c, new[] { Read() });
					return c;
				}
				if (g == typeof(Dictionary<,>))
				{
					var d = (IDictionary)Activator.CreateInstance(t);
					if (slot >= 0)
						_seen[slot] = d;
					int n = _r.ReadInt32();
					for (int k = 0; k < n; k++)
					{
						object key = Read();
						d[key] = Read();
					}
					return d;
				}
			}
			object o = RuntimeHelpers.GetUninitializedObject(t);
			if (slot >= 0)
				_seen[slot] = o;
			var fields = new Dictionary<string, FieldInfo>();
			foreach (var f in AllFields(t))
				fields.TryAdd(f.Name, f);
			for (string name = _r.ReadString(); name != ""; name = _r.ReadString())
			{
				object v = Read();
				if (fields.TryGetValue(name, out var f) && (v == null ? !f.FieldType.IsValueType : f.FieldType.IsInstanceOfType(v)))
					f.SetValue(o, v);
			}
			// Fields that were not saved (left out, or new since) keep a sensible value.
			foreach (var f in fields.Values)
				if (f.GetValue(o) == null && !f.FieldType.IsValueType && f.FieldType.GetConstructor(Type.EmptyTypes) != null
					&& (f.FieldType.IsGenericType || f.FieldType.Namespace == "Animundi.Sim") && StateWriter.Saveable(f.FieldType))
					f.SetValue(o, Activator.CreateInstance(f.FieldType));
			return o;
		}
	}
}
