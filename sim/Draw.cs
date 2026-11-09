using System;
using System.Collections.Generic;
using System.Diagnostics;
using Godot;

namespace Animundi.Sim;

/// <summary>
/// Drawing of the simulation, straight into MultiMesh buffers (no node per creature or plant):
/// - plants: one MultiMesh per strip of 16 tile rows, sorted by feet height, rebuilt only when a
///   plant in the strip grew, appeared, burned or died; their shadows in a layer under them;
/// - creatures: one MultiMesh rebuilt every frame, sorted by feet height, young ones smaller;
/// - flames: a three-frame pixel-art flame (made in scripts/render2d/sprite_atlas.gd) over every
///   burning plant, drawn with the creatures so it sorts by height with them.
/// All sprites come from the shared atlas (scripts/render2d/sprite_atlas.gd).
/// </summary>
public partial class Simulation
{
	private const int StripRows = 16;
	// Floats per instance: Transform2D (8) + colour (4) + custom data (4).
	private const int Stride = 16;

	private bool _renderingReady;
	private Mesh _quad;
	private Texture2D _atlasTexture;
	private Texture2D _shadowTexture;
	private Godot.Collections.Dictionary _regions;
	private Godot.Collections.Dictionary _colors;
	private Godot.Collections.Dictionary _atlasSizes;
	private GDScript _library;
	private readonly Dictionary<string, (Vector2 size, Rect2 rect, Color color)> _spriteInfo = new();

	private ShaderMaterial _unitMaterial;
	private ShaderMaterial _plantMaterial;
	private ShaderMaterial _shadowMaterial;
	private Node2D _plantShadowLayer;
	private Node2D _plantLayer;
	private MultiMesh _unitMesh;
	private MultiMesh _unitShadowMesh;
	private MultiMeshInstance2D _unitShadowInstance;
	private float[] _unitBuffer = Array.Empty<float>();
	private float[] _unitShadowBuffer = Array.Empty<float>();
	private int[] _order = Array.Empty<int>();
	private float[] _keys = Array.Empty<float>();
	private bool[] _stripDirty = Array.Empty<bool>();
	private (Vector2 size, Rect2 rect, Color color)[] _speciesSprites = Array.Empty<(Vector2, Rect2, Color)>();
	private readonly List<(MultiMesh plants, MultiMesh shadows)> _strips = new();
	private double _drawMs;
	private int _drawSamples;

	private void SetupRendering()
	{
		var batchScript = GD.Load<GDScript>("res://scripts/render2d/sprite_batch.gd");
		var atlas = GD.Load<GDScript>("res://scripts/render2d/sprite_atlas.gd").Call("shared").AsGodotObject();
		_library = GD.Load<GDScript>("res://scripts/render3d/sprite_library.gd");
		_regions = atlas.Get("regions").AsGodotDictionary();
		_colors = atlas.Get("colors").AsGodotDictionary();
		_atlasSizes = atlas.Get("sizes").AsGodotDictionary();
		_atlasTexture = atlas.Get("texture").As<Texture2D>();
		_shadowTexture = batchScript.Call("shadow_texture").As<Texture2D>();
		_quad = batchScript.Call("unit_quad").As<Mesh>();
		var shader = GD.Load<Shader>("res://shaders/sprite_batch.gdshader");
		_shadowMaterial = new ShaderMaterial { Shader = shader };
		_shadowMaterial.SetShaderParameter("from_atlas", false);
		_plantMaterial = new ShaderMaterial { Shader = shader };
		_unitMaterial = new ShaderMaterial { Shader = shader };
		_unitMaterial.SetShaderParameter("wind", 0.0f);

		// Children in drawing order: plant shadows, plants, creature shadows, then creatures and
		// flames together (sorted by height, so a flame in front covers what stands behind).
		_plantShadowLayer = new Node2D();
		_plantLayer = new Node2D();
		AddChild(_plantShadowLayer);
		AddChild(_plantLayer);
		_unitShadowMesh = new MultiMesh { TransformFormat = MultiMesh.TransformFormatEnum.Transform2D, Mesh = _quad };
		_unitShadowInstance = Instance(_unitShadowMesh, _shadowMaterial, _shadowTexture);
		AddChild(_unitShadowInstance);
		_unitMesh = new MultiMesh
		{
			TransformFormat = MultiMesh.TransformFormatEnum.Transform2D, UseColors = true, UseCustomData = true, Mesh = _quad,
		};
		AddChild(Instance(_unitMesh, _unitMaterial, _atlasTexture));
		_renderingReady = true;
	}

	private static MultiMeshInstance2D Instance(MultiMesh mesh, Material material, Texture2D texture) => new()
	{
		Multimesh = mesh, Material = material, Texture = texture,
		TextureFilter = TextureFilterEnum.NearestWithMipmaps,
	};

	/// <summary>Size in world pixels, atlas rectangle and average colour of a sprite.</summary>
	private (Vector2 size, Rect2 rect, Color color) SpriteInfo(string id)
	{
		if (!_spriteInfo.TryGetValue(id, out var info))
		{
			// Effects made in the atlas (flames) have no file: their size is their pixel size.
			info = (id.StartsWith("effects/") ? _atlasSizes[id].AsVector2() : _library.Call("world_size", id).AsVector2() * Tile,
				_regions.ContainsKey(id) ? _regions[id].AsRect2() : new Rect2(),
				_colors.ContainsKey(id) ? _colors[id].AsColor() : Colors.Magenta);
			_spriteInfo[id] = info;
		}
		return info;
	}

	private Vector2 PlantSize(int sprite) => SpriteInfo(_plantSprites[sprite]).size;

	/// <summary>Follows the camera zoom (screen pixels per world pixel): far away, sprites are
	/// dots and shadows are hidden.</summary>
	public void SetZoom(float zoom)
	{
		_unitMaterial?.SetShaderParameter("zoom", zoom);
		_plantMaterial?.SetShaderParameter("zoom", zoom);
		bool shadows = zoom >= 0.6f;
		if (_unitShadowInstance != null)
		{
			_unitShadowInstance.Visible = shadows;
			_plantShadowLayer.Visible = shadows;
		}
	}

	/// <summary>Shows or hides plants and creatures (the data layers of the map hide them).</summary>
	public void SetLifeVisible(bool on) => Visible = on;

	private void ClearDrawing()
	{
		foreach (var child in _plantLayer.GetChildren())
			child.QueueFree();
		foreach (var child in _plantShadowLayer.GetChildren())
			child.QueueFree();
		_strips.Clear();
		int strips = (World.Height + StripRows - 1) / StripRows;
		for (int k = 0; k < strips; k++)
		{
			var plants = new MultiMesh
			{
				TransformFormat = MultiMesh.TransformFormatEnum.Transform2D, UseColors = true, UseCustomData = true, Mesh = _quad,
			};
			var shadows = new MultiMesh { TransformFormat = MultiMesh.TransformFormatEnum.Transform2D, Mesh = _quad };
			_plantShadowLayer.AddChild(Instance(shadows, _shadowMaterial, _shadowTexture));
			_plantLayer.AddChild(Instance(plants, _plantMaterial, _atlasTexture));
			_strips.Add((plants, shadows));
		}
		_stripDirty = new bool[strips];
		Array.Fill(_stripDirty, true);
	}

	private void MarkStrip(int tileRow)
	{
		int k = tileRow / StripRows;
		if (k >= 0 && k < _stripDirty.Length)
			_stripDirty[k] = true;
	}

	private void DrawAll()
	{
		long started = Stopwatch.GetTimestamp();
		for (int k = 0; k < _stripDirty.Length; k++)
			if (_stripDirty[k])
			{
				_stripDirty[k] = false;
				DrawStrip(k);
			}
		DrawUnits();
		_drawMs += Stopwatch.GetElapsedTime(started).TotalMilliseconds;
		_drawSamples++;
	}

	/// <summary>Average milliseconds spent filling the MultiMeshes per frame since the last call
	/// (CPU side of drawing).</summary>
	public double TakeDrawMs()
	{
		double ms = _drawSamples > 0 ? _drawMs / _drawSamples : 0.0;
		_drawMs = 0;
		_drawSamples = 0;
		return ms;
	}

	/// <summary>Draws `frames` frames right away (tools: measures drawing).</summary>
	public void DrawFrames(int frames)
	{
		for (int k = 0; k < frames; k++)
			DrawAll();
	}

	/// <summary>Writes one sprite instance: feet at (ox, oy), size (sx may be negative to mirror).</summary>
	private static void WriteSprite(float[] buf, int o, float sx, float sy, float ox, float oy, Rect2 rect, Color avg, float heightPx)
	{
		// Transform2D rows: (x.x, y.x, 0, origin.x), (x.y, y.y, 0, origin.y).
		buf[o] = sx; buf[o + 1] = 0f; buf[o + 2] = 0f; buf[o + 3] = ox;
		buf[o + 4] = 0f; buf[o + 5] = sy; buf[o + 6] = 0f; buf[o + 7] = oy;
		// Colour: average colour (the far-away dot) and height in world pixels / 256.
		buf[o + 8] = avg.R; buf[o + 9] = avg.G; buf[o + 10] = avg.B; buf[o + 11] = heightPx / 256f;
		buf[o + 12] = rect.Position.X; buf[o + 13] = rect.Position.Y; buf[o + 14] = rect.Size.X; buf[o + 15] = rect.Size.Y;
	}

	private static void WriteShadow(float[] buf, int q, float width, float ox, float oy)
	{
		float w = width * 0.75f, h = width * 0.28f;
		buf[q] = w; buf[q + 1] = 0f; buf[q + 2] = 0f; buf[q + 3] = ox + width * 0.08f;
		buf[q + 4] = 0f; buf[q + 5] = h; buf[q + 6] = 0f; buf[q + 7] = oy + h * 0.45f;
	}

	private void DrawStrip(int k)
	{
		var (plants, shadows) = _strips[k];
		var list = new List<int>();
		int y1 = Math.Min(World.Height, (k + 1) * StripRows);
		for (int y = k * StripRows; y < y1; y++)
			for (int x = 0; x < World.Width; x++)
				for (int p = _tileFirst[World.Index(x, y)]; p >= 0; p = _pNext[p])
					list.Add(p);
		list.Sort((a, b) => _pY[a] != _pY[b] ? _pY[a].CompareTo(_pY[b]) : _pX[a].CompareTo(_pX[b]));
		int n = list.Count;
		if (plants.InstanceCount < n || plants.InstanceCount > n * 2 + 64)
		{
			plants.InstanceCount = n + n / 4 + 16;
			shadows.InstanceCount = plants.InstanceCount;
		}
		var buf = new float[plants.InstanceCount * Stride];
		var sbuf = new float[shadows.InstanceCount * 8];
		for (int m = 0; m < n; m++)
		{
			int p = list[m];
			var (size, rect, avg) = SpriteInfo(_plantSprites[_pSprite[p]]);
			float s = _pScale[p] * _pGrowth[p];
			float w = size.X * s, h = size.Y * s;
			float ox = _pX[p] * Tile, oy = _pY[p] * Tile;
			WriteSprite(buf, m * Stride, _pFlip[p] ? -w : w, h, ox, oy, rect, avg, h);
			WriteShadow(sbuf, m * 8, w, ox, oy);
		}
		plants.VisibleInstanceCount = n;
		shadows.VisibleInstanceCount = n;
		if (plants.InstanceCount > 0)
		{
			RenderingServer.MultimeshSetBuffer(plants.GetRid(), buf);
			RenderingServer.MultimeshSetBuffer(shadows.GetRid(), sbuf);
		}
	}

	/// <summary>Writes every living creature and every flame into the MultiMesh buffers, nearest
	/// (lowest) last. Flames are stored in the order as ~plant (negative numbers).</summary>
	private void DrawUnits()
	{
		int cap = Units.Capacity + _burning.Count + _burningTiles.Count;
		if (_order.Length < cap)
		{
			_order = new int[cap];
			_keys = new float[cap];
		}
		int n = 0;
		for (int i = 0; i < Units.Capacity; i++)
		{
			if (!Units.Alive[i])
				continue;
			_order[n] = i;
			_keys[n] = Units.Y[i];
			n++;
		}
		foreach (int p in _burning)
		{
			if (!_pAlive[p])
				continue;
			_order[n] = ~p;
			_keys[n] = _pY[p] + 0.01f;
			n++;
		}
		// Burning tiles: codes below -2^30 (int.MinValue + tile).
		foreach (int t in _burningTiles)
		{
			_order[n] = int.MinValue + t;
			_keys[n] = t / World.Width + 0.85f;
			n++;
		}
		Array.Sort(_keys, _order, 0, n);
		// Sprite of every species, looked up once per frame (not once per creature).
		if (_speciesSprites.Length != Assets.Species.Count)
		{
			_speciesSprites = new (Vector2, Rect2, Color)[Assets.Species.Count];
			for (int s = 0; s < Assets.Species.Count; s++)
				_speciesSprites[s] = SpriteInfo(Assets.Species[s].Sprite);
		}
		var fireFrames = new (Rect2 rect, Color color)[3];
		for (int f = 0; f < 3; f++)
		{
			var info = SpriteInfo($"effects/Fire_{f}");
			fireFrames[f] = (info.rect, info.color);
		}

		if (_unitMesh.InstanceCount < n)
		{
			int size = Math.Max(n, _unitMesh.InstanceCount * 2);
			_unitMesh.InstanceCount = size;
			_unitShadowMesh.InstanceCount = size;
			_unitBuffer = new float[size * Stride];
			_unitShadowBuffer = new float[size * 8];
		}
		for (int k = 0; k < n; k++)
		{
			int i = _order[k];
			if (i < -(1 << 30))
			{
				// A burning tile: a small flame standing in the middle of it.
				int t = i - int.MinValue;
				float life = Math.Clamp(TileBurn[t] / Math.Max(_burnTime[World.Biome[t]], 0.1f), 0f, 1f);
				float fh = 7f * (MathF.Sin(MathF.PI * life) * 0.5f + 0.5f);
				var (trect, tcolor) = fireFrames[(int)((float)Scheduler.Time * 9f + t * 7) % 3];
				float fx = (t % World.Width + 0.5f) * Tile;
				float fy = (t / World.Width + 0.85f) * Tile;
				WriteSprite(_unitBuffer, k * Stride, fh * 0.75f, fh, fx, fy, trect, tcolor, fh);
				WriteShadow(_unitShadowBuffer, k * 8, 0f, 0f, 0f);
				continue;
			}
			if (i < 0)
			{
				// A flame over a burning plant: as wide as the plant, rising then dying down,
				// flickering through its three frames. No shadow (a zero-size one).
				int p = ~i;
				var plant = PlantSize(_pSprite[p]) * _pScale[p] * _pGrowth[p];
				float life = Math.Clamp(_pBurn[p] / BurnSeconds, 0f, 1f);
				float strength = MathF.Sin(MathF.PI * life) * 0.6f + 0.4f;
				var (frect, fcolor) = fireFrames[(int)((float)Scheduler.Time * 9f + p) % 3];
				float fh = plant.Y * 0.75f * strength;
				WriteSprite(_unitBuffer, k * Stride, plant.X * 0.7f, fh, _pX[p] * Tile, _pY[p] * Tile, frect, fcolor, fh);
				WriteShadow(_unitShadowBuffer, k * 8, 0f, 0f, 0f);
				continue;
			}
			var sp = Assets.Species[Units.Species[i]];
			var (size, rect, avg) = _speciesSprites[Units.Species[i]];
			// The young grow from 55% to full size.
			float grown = Math.Clamp(Units.Age[i] / (sp.Lifespan * Maturity), 0f, 1f);
			size *= 0.55f + 0.45f * grown;
			float ox = Units.X[i] * Tile;
			float oy = Units.Y[i] * Tile;
			float sx = Units.FacingLeft[i] ? -size.X : size.X;
			// Walking: a two-frame hop, the cheap version of WorldBox's walk cycles.
			float sy = size.Y;
			float hop = 0f;
			if (!AtTarget(i))
			{
				bool up = MathF.Sin((float)Scheduler.Time * 9f + i * 0.37f) > 0f;
				hop = up ? 0.8f : 0f;
				sy *= up ? 1.04f : 0.97f;
			}
			WriteSprite(_unitBuffer, k * Stride, sx, sy, ox, oy - hop, rect, avg, size.Y);
			WriteShadow(_unitShadowBuffer, k * 8, size.X, ox, oy);
		}
		_unitMesh.VisibleInstanceCount = n;
		_unitShadowMesh.VisibleInstanceCount = n;
		if (n > 0)
		{
			RenderingServer.MultimeshSetBuffer(_unitMesh.GetRid(), _unitBuffer);
			RenderingServer.MultimeshSetBuffer(_unitShadowMesh.GetRid(), _unitShadowBuffer);
		}
	}

}
