using System;
using System.Collections.Generic;
using System.Diagnostics;
using Godot;

namespace Animundi.Sim;

/// <summary>
/// Drawing of the simulation, straight into MultiMesh buffers (no node per creature or plant):
/// - plants: one MultiMesh per strip of 16 tile rows, sorted by feet height, rebuilt only when a
///   plant in the strip grew, appeared, burned or died; their shadows in a layer under them;
/// - creatures: one MultiMesh rebuilt every frame, sorted by feet height, young ones smaller,
///   animated with the poses of art/creatures.py (walking steps, strikes) and leaving remains;
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
	private float[] _keys = Array.Empty<float>();
	private bool[] _stripDirty = Array.Empty<bool>();
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
		_zoom = zoom;
		_unitMaterial?.SetShaderParameter("zoom", zoom);
		_plantMaterial?.SetShaderParameter("zoom", zoom);
		bool shadows = zoom >= 0.6f;
		if (_unitShadowInstance != null)
		{
			_unitShadowInstance.Visible = shadows;
			_plantShadowLayer.Visible = shadows && !_near;
		}
	}

	private float _zoom = 1f;

	/// <summary>Shows or hides plants and creatures (the data layers of the map hide them).</summary>
	public void SetLifeVisible(bool on) => Visible = on;

	private void ClearDrawing()
	{
		_buildingSprites.Clear();
		_speciesFrames = Array.Empty<(Vector2, Rect2, Color)[]>();
		_peopleFrames = Array.Empty<(Vector2, Rect2, Color)[][]>();
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
		// Up close the plants are drawn with the creatures: the strips wait until the camera is far.
		for (int k = 0; k < _stripDirty.Length && !_near; k++)
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
	/// `sway` is the wind phase of a plant (0.05..0.95, from its position), 0 for what never sways;
	/// it rides in the fractional part of the height (whole world pixels) so the shader gets both.
	private static void WriteSprite(float[] buf, int o, float sx, float sy, float ox, float oy, Rect2 rect, Color avg, float heightPx, float sway = 0f)
	{
		// Transform2D rows: (x.x, y.x, 0, origin.x), (x.y, y.y, 0, origin.y).
		buf[o] = sx; buf[o + 1] = 0f; buf[o + 2] = 0f; buf[o + 3] = ox;
		buf[o + 4] = 0f; buf[o + 5] = sy; buf[o + 6] = 0f; buf[o + 7] = oy;
		// Colour: average colour (the far-away dot) and height in world pixels / 256.
		buf[o + 8] = avg.R; buf[o + 9] = avg.G; buf[o + 10] = avg.B; buf[o + 11] = (MathF.Max(1f, MathF.Round(heightPx)) + sway) / 256f;
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
		// Ties broken by index: the same order at every rebuild (no flicker between overlapping plants).
		list.Sort((a, b) => _pY[a] != _pY[b] ? _pY[a].CompareTo(_pY[b]) : _pX[a] != _pX[b] ? _pX[a].CompareTo(_pX[b]) : a.CompareTo(b));
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
			WriteSprite(buf, m * Stride, _pFlip[p] ? -w : w, h, ox, oy, rect, avg, h, SwayPhase(_pX[p], _pY[p]));
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
	/// <summary>Poses of a creature sprite (art/creatures.py), in order.</summary>
	private static readonly string[] Poses = { "idle", "walk1", "walk2", "attack", "swim", "death" };
	private const int Idle = 0, Walk1 = 1, Walk2 = 2, Attack = 3, Dead = 5;
	// Per people species, role and pose (the sprite changes with the role).
	private (Vector2 size, Rect2 rect, Color color)[][][] _peopleFrames = Array.Empty<(Vector2, Rect2, Color)[][]>();
	// Per species and pose: size in world pixels, atlas rectangle, average colour.
	private (Vector2 size, Rect2 rect, Color color)[][] _speciesFrames = Array.Empty<(Vector2, Rect2, Color)[]>();

	/// <summary>Buildings drawn in each people's style (art/buildings.py); the others are the same
	/// for every people.</summary>
	private static readonly HashSet<string> PeopleStyled = new()
	{
		"hut", "house", "stone_house", "big_house", "town_hall", "temple", "library", "barracks", "watch_tower",
	};
	private readonly Dictionary<(int, int), string> _buildingSprites = new();

	/// <summary>The sprite of a building: a site while it is first built, the bonfire and the
	/// windmill animated, homes and great buildings in their people's style.</summary>
	private string BuildingSprite(Building bld, float time)
	{
		if (!bld.Done && bld.UpgradeTo < 0)
			return "buildings/site";
		if (bld.Type == _tBonfire)
			return BonfireFrames[(int)(time * 6f + bld.X) % 3];
		if (bld.Type == _tWindmill)
			return WindmillFrames[(int)(time * 3f + bld.X) % 2];
		int species = Villages[bld.Village].Species;
		if (!_buildingSprites.TryGetValue((bld.Type, species), out var id))
		{
			string b = Assets.Buildings[bld.Type].Id;
			id = PeopleStyled.Contains(b) ? $"buildings/{b}_{Assets.Species[species].Id}" : $"buildings/{b}";
			_buildingSprites[(bld.Type, species)] = id;
		}
		return id;
	}

	private static readonly string[] BonfireFrames = { "buildings/bonfire_0", "buildings/bonfire_1", "buildings/bonfire_2" };
	private static readonly string[] WindmillFrames = { "buildings/windmill_0", "buildings/windmill_1" };

	// What a drawn item is (packed with its index into a long, sorted by feet height).
	private const long KUnit = 0, KPlant = 1, KPlantFlame = 2, KRemains = 3, KBuilding = 4, KTileFlame = 5;
	private long[] _items = Array.Empty<long>();

	/// <summary>Animation clock in real seconds: flames, walking, the bonfire and windmills move at
	/// the same pace whatever the speed of time (ultra-fast included).</summary>
	private static float AnimTime => Time.GetTicksMsec() / 1000f;

	// The camera's view in world pixels (SetView); empty = the whole map.
	private Rect2 _view;
	/// <summary>Up close (sprites bigger than dots, the view small enough), plants are drawn with
	/// the creatures and buildings in one batch sorted by feet height, so whoever stands in front
	/// covers whoever stands behind. Far away, plants are drawn by strips and creatures (dots) on top.</summary>
	private bool _near;
	public const float NearZoom = 0.5f;
	private const int NearMaxTiles = 90000;

	/// <summary>The part of the world the camera shows, in world pixels (scripts/main.gd, every frame).</summary>
	public void SetView(Vector2 center, Vector2 size)
	{
		_view = new Rect2(center - size / 2f, size);
		bool near = _zoom >= NearZoom && size.X * size.Y / (Tile * Tile) <= NearMaxTiles;
		if (near == _near)
			return;
		_near = near;
		if (_plantLayer != null)
		{
			_plantLayer.Visible = !near;
			_plantShadowLayer.Visible = !near && _zoom >= 0.6f;
		}
	}

	/// <summary>A stable sway phase for a plant at (x, y), from its position (never from its place
	/// in a buffer, which changes whenever the strip is rebuilt).</summary>
	private static float SwayPhase(float x, float y)
	{
		float h = MathF.Sin(x * 12.9898f + y * 78.233f) * 43758.547f;
		return 0.05f + 0.9f * (h - MathF.Floor(h));
	}

	private bool InView(float x, float y, float margin)
	{
		if (_view.Size.X <= 0f)
			return true;
		float px = x * Tile, py = y * Tile;
		return px >= _view.Position.X - margin && px <= _view.End.X + margin
			&& py >= _view.Position.Y - margin && py <= _view.End.Y + margin + 40f;
	}

	private void Add(ref int n, long kind, int index, float key)
	{
		if (n == _items.Length)
		{
			Array.Resize(ref _items, Math.Max(256, n * 2));
			Array.Resize(ref _keys, _items.Length);
		}
		_items[n] = (kind << 32) | (uint)index;
		_keys[n] = key;
		n++;
	}

	private void DrawUnits()
	{
		if (_keys.Length < _items.Length)
			Array.Resize(ref _keys, _items.Length);
		// Everything drawn here, sorted by feet height: creatures, buildings, remains, flames, and
		// up close the plants too. Up close, only what the camera sees.
		bool cull = _near;
		const float margin = 48f;
		int n = 0;
		for (int i = 0; i < Units.Capacity; i++)
			if (Units.Alive[i] && (!cull || InView(Units.X[i], Units.Y[i], margin)))
				Add(ref n, KUnit, i, Units.Y[i]);
		foreach (int p in _burning)
			if (_pAlive[p] && (!cull || InView(_pX[p], _pY[p], margin)))
				Add(ref n, KPlantFlame, p, _pY[p] + 0.0001f);
		for (int r = 0; r < _remains.Count; r++)
			if (!cull || InView(_remains[r].x, _remains[r].y, margin))
				Add(ref n, KRemains, r, _remains[r].y - 0.0001f);
		for (int b = 0; b < Buildings.Count; b++)
		{
			var bld = Buildings[b];
			if (!bld.Alive || cull && !InView(bld.X + 0.5f, bld.Y + 1f, margin))
				continue;
			// Standing on the lower part of their tile; a burning one has a big flame in front.
			Add(ref n, KBuilding, b, bld.Y + 0.8f);
			if (bld.Burning > 0f)
				Add(ref n, KTileFlame, World.Index(bld.X, bld.Y), bld.Y + 0.8001f);
		}
		foreach (int t in _burningTiles)
			if (!cull || InView(t % World.Width + 0.5f, t / World.Width + 0.85f, margin))
				Add(ref n, KTileFlame, t, t / World.Width + 0.85f);
		if (_near)
		{
			// The plants in view, from the tiles the camera sees.
			int x0 = Math.Max(0, (int)((_view.Position.X - margin) / Tile)), x1 = Math.Min(World.Width - 1, (int)((_view.End.X + margin) / Tile));
			int y0 = Math.Max(0, (int)((_view.Position.Y - margin) / Tile)), y1 = Math.Min(World.Height - 1, (int)((_view.End.Y + margin + 40f) / Tile));
			for (int y = y0; y <= y1; y++)
				for (int x = x0; x <= x1; x++)
					for (int p = _tileFirst[World.Index(x, y)]; p >= 0; p = _pNext[p])
						Add(ref n, KPlant, p, _pY[p]);
		}
		Array.Sort(_keys, _items, 0, n);
		// Frames of every species, looked up once (not once per creature).
		if (_speciesFrames.Length != Assets.Species.Count)
		{
			_speciesFrames = new (Vector2, Rect2, Color)[Assets.Species.Count][];
			_peopleFrames = new (Vector2, Rect2, Color)[Assets.Species.Count][][];
			for (int s = 0; s < Assets.Species.Count; s++)
			{
				var sp = Assets.Species[s];
				if (sp.IsPeople)
				{
					// creatures/<race>_<role>_<pose>
					_peopleFrames[s] = new (Vector2, Rect2, Color)[RoleNames.Length][];
					for (int r = 0; r < RoleNames.Length; r++)
					{
						_peopleFrames[s][r] = new (Vector2, Rect2, Color)[Poses.Length];
						for (int f = 0; f < Poses.Length; f++)
							_peopleFrames[s][r][f] = SpriteInfo($"{sp.Sprite}_{RoleNames[r]}_{Poses[f]}");
					}
					_speciesFrames[s] = _peopleFrames[s][0];
					continue;
				}
				_speciesFrames[s] = new (Vector2, Rect2, Color)[Poses.Length];
				for (int f = 0; f < Poses.Length; f++)
					_speciesFrames[s][f] = SpriteInfo($"{sp.Sprite}_{Poses[f]}");
			}
		}
		var fireFrames = new (Rect2 rect, Color color)[3];
		for (int f = 0; f < 3; f++)
		{
			var info = SpriteInfo($"effects/Fire_{f}");
			fireFrames[f] = (info.rect, info.color);
		}
		float time = AnimTime;

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
			long kind = _items[k] >> 32;
			int i = (int)(_items[k] & 0xffffffff);
			switch (kind)
			{
				case KPlant:
				{
					var (psize, prect, pavg) = SpriteInfo(_plantSprites[_pSprite[i]]);
					float ps = _pScale[i] * _pGrowth[i];
					float w = psize.X * ps, h = psize.Y * ps;
					float px = _pX[i] * Tile, py = _pY[i] * Tile;
					WriteSprite(_unitBuffer, k * Stride, _pFlip[i] ? -w : w, h, px, py, prect, pavg, h, SwayPhase(_pX[i], _pY[i]));
					WriteShadow(_unitShadowBuffer, k * 8, w, px, py);
					continue;
				}
				case KTileFlame:
				{
					// A burning tile: a small flame standing in the middle of it; a big one over a
					// burning building.
					int t = i;
					float life = Math.Clamp(TileBurn[t] / Math.Max(_burnTime[World.Biome[t]], 0.1f), 0f, 1f);
					float fh = 7f * (MathF.Sin(MathF.PI * life) * 0.5f + 0.5f);
					int burningBuilding = _buildingAt[t];
					if (burningBuilding >= 0 && Buildings[burningBuilding].Burning > 0f)
						fh = 12f + 2f * MathF.Sin(time * 5f + t);
					var (trect, tcolor) = fireFrames[(int)(time * 9f + t * 7) % 3];
					float fx = (t % World.Width + 0.5f) * Tile;
					float fy = (t / World.Width + 0.85f) * Tile;
					WriteSprite(_unitBuffer, k * Stride, fh * 0.75f, fh, fx, fy, trect, tcolor, fh);
					WriteShadow(_unitShadowBuffer, k * 8, 0f, 0f, 0f);
					continue;
				}
				case KBuilding:
				{
					// Bonfires flicker, houses wear their people's style, sites are frames.
					var bld = Buildings[i];
					var (bsize, brect, bcolor) = SpriteInfo(BuildingSprite(bld, time));
					float bx = (bld.X + 0.5f) * Tile, by = (bld.Y + 1f) * Tile;
					// Burning buildings darken.
					if (bld.Burning > 0f)
						bcolor = bcolor.Darkened(0.4f * (1f - bld.Health));
					WriteSprite(_unitBuffer, k * Stride, bsize.X, bsize.Y, bx, by, brect, bcolor, bsize.Y);
					bool flat = bld.Type == _tBonfire || bld.Type == _tRuin || bld.Type == _tDummy;
					WriteShadow(_unitShadowBuffer, k * 8, flat ? 0f : bsize.X * 0.9f, bx, by);
					continue;
				}
				case KRemains:
				{
					// The remains of a dead creature, lying where it fell.
					var dead = _remains[i];
					var (dsize, drect, dcolor) = _speciesFrames[dead.species][Dead];
					dsize *= dead.scale;
					WriteSprite(_unitBuffer, k * Stride, dead.left ? -dsize.X : dsize.X, dsize.Y, dead.x * Tile, dead.y * Tile, drect, dcolor, dsize.Y);
					WriteShadow(_unitShadowBuffer, k * 8, 0f, 0f, 0f);
					continue;
				}
				case KPlantFlame:
				{
					// A flame over a burning plant: as wide as the plant, rising then dying down,
					// flickering through its three frames. No shadow (a zero-size one).
					int p = i;
					var plant = PlantSize(_pSprite[p]) * _pScale[p] * _pGrowth[p];
					float life = Math.Clamp(_pBurn[p] / BurnSeconds, 0f, 1f);
					float strength = MathF.Sin(MathF.PI * life) * 0.6f + 0.4f;
					var (frect, fcolor) = fireFrames[(int)(time * 9f + p) % 3];
					float fh = plant.Y * 0.75f * strength;
					WriteSprite(_unitBuffer, k * Stride, plant.X * 0.7f, fh, _pX[p] * Tile, _pY[p] * Tile, frect, fcolor, fh);
					WriteShadow(_unitShadowBuffer, k * 8, 0f, 0f, 0f);
					continue;
				}
			}
			var sp = Assets.Species[Units.Species[i]];
			// Pose: walking cycles idle, step, idle, other step; a hunter next to its prey strikes.
			int pose = Idle;
			if (Units.Task[i] == (byte)Task.Hunt && Units.Prey[i] >= 0 && Units.Alive[Units.Prey[i]]
				&& MathF.Abs(Units.X[Units.Prey[i]] - Units.X[i]) + MathF.Abs(Units.Y[Units.Prey[i]] - Units.Y[i]) < 1.5f)
				pose = ((int)(time * 6f + i) & 1) == 0 ? Attack : Idle;
			else if (!AtTarget(i))
			{
				int step = (int)(time * (4f + sp.Speed * 4f) + (i & 7)) & 3;
				pose = step == 1 ? Walk1 : step == 3 ? Walk2 : Idle;
			}
			var frames = sp.IsPeople ? _peopleFrames[Units.Species[i]][Units.Role[i]] : _speciesFrames[Units.Species[i]];
			var (size, rect, avg) = frames[pose];
			// The young grow from 60% to full size.
			float grown = Math.Clamp(Units.Age[i] / AdultAge(sp), 0f, 1f);
			size *= 0.6f + 0.4f * grown;
			float ox = Units.X[i] * Tile;
			float oy = Units.Y[i] * Tile;
			WriteSprite(_unitBuffer, k * Stride, Units.FacingLeft[i] ? -size.X : size.X, size.Y, ox, oy, rect, avg, size.Y);
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
