using System;
using System.Collections.Generic;
using Godot;

namespace Animundi.Sim;

/// <summary>
/// The god powers (0.9): what the player does to the world. Each power is one call with a place
/// in tiles, and returns how much it did (0 when there was nothing to act on: the sea, outside
/// the map). The interface (scripts/ui/power_bar.gd) only chooses the power and the brush.
/// </summary>
public partial class Simulation
{
	private readonly List<int> _powerFound = new();

	/// <summary>Living units within `radius` tiles of (x, y), whatever moved since the last step.</summary>
	private List<int> UnitsWithin(float x, float y, float radius)
	{
		_powerFound.Clear();
		if (World == null || radius <= 0f)
			return _powerFound;
		Zones.Rebuild(Units);
		Zones.Query(Units, x, y, radius, _powerFound);
		_powerFound.RemoveAll(i => !Units.Alive[i]);
		return _powerFound;
	}

	/// <summary>Calls `act` for every tile of the map whose centre is within `radius` of (x, y).</summary>
	private void TilesWithin(float x, float y, float radius, Action<int> act)
	{
		if (World == null)
			return;
		for (int ty = (int)MathF.Floor(y - radius); ty <= (int)MathF.Floor(y + radius); ty++)
			for (int tx = (int)MathF.Floor(x - radius); tx <= (int)MathF.Floor(x + radius); tx++)
			{
				float dx = tx + 0.5f - x, dy = ty + 0.5f - y;
				if (World.InBounds(tx, ty) && dx * dx + dy * dy <= radius * radius)
					act(World.Index(tx, ty));
			}
	}

	private bool OnLand(float x, float y) => World != null && World.IsLandAt(x, y);

	// ------------------------------------------------------------------ fire and water

	/// <summary>Sets the land alight under the brush. Returns the tiles that caught fire.</summary>
	public int PowerFire(float x, float y, float radius)
	{
		if (World == null)
			return 0;
		int lit = Ignite(x, y, radius);
		if (lit > 0)
			PlayerActed("fire", x, y, radius, mercy: false);
		return lit;
	}

	/// <summary>A bolt of lightning: kills what stands there and lights the land. Returns the
	/// creatures killed.</summary>
	public int PowerLightning(float x, float y)
	{
		if (!OnLand(x, y))
			return 0;
		int killed = 0;
		foreach (int i in UnitsWithin(x, y, 1.5f).ToArray())
		{
			NoteVictim(i);
			KillUnit(i, Death.Other);
			killed++;
		}
		Ignite(x, y, 1.5f);
		LogEvent($"lightning strikes near ({(int)x}, {(int)y}).", "disasters");
		PlayerActed("lightning", x, y, 1.5f, mercy: false);
		Witness("lightning", x, y, $"lightning fell from a clear sky {PlaceNear(x, y)}");
		return killed;
	}

	/// <summary>Rain: puts out the fires under the brush (land and plants; burning buildings too)
	/// and makes the grass grow back. Returns the burning tiles put out.</summary>
	public int PowerRain(float x, float y, float radius)
	{
		int doused = 0;
		TilesWithin(x, y, radius, t =>
		{
			if (World.Water[t] != SimWorld.WaterLand)
				return;
			if (TileBurn[t] > 0f)
			{
				TileBurn[t] = 0f;
				doused++;
			}
			for (int p = _tileFirst[t]; p >= 0; p = _pNext[p])
				if (_pBurn[p] > 0f)
				{
					_pBurn[p] = 0f;
					MarkStrip((int)_pY[p]);
				}
			int b = _buildingAt.Length > t ? _buildingAt[t] : -1;
			if (b >= 0 && Buildings[b].Burning > 0f)
				Buildings[b].Burning = 0f;
			if (Scorch[t] <= 64)
				Grass[t] = Math.Max(Grass[t], _fertility[World.Biome[t]]);
		});
		_burningTiles.RemoveAll(t => TileBurn[t] == 0f);
		_burning.RemoveAll(p => !_pAlive[p] || _pBurn[p] == 0f);
		if (doused > 0)
			PlayerActed("rain", x, y, radius, mercy: true);
		return doused;
	}

	// ------------------------------------------------------------------ destruction and mercy

	/// <summary>A meteor: kills everything under it, flattens the plants, scorches the ground,
	/// sets buildings and the land around alight. Returns the creatures killed.</summary>
	public int PowerMeteor(float x, float y, float radius)
	{
		if (!OnLand(x, y))
			return 0;
		int killed = Smite(x, y, radius);
		TilesWithin(x, y, radius, t =>
		{
			if (World.Water[t] != SimWorld.WaterLand)
				return;
			while (_tileFirst[t] >= 0)
			{
				MarkStrip((int)_pY[_tileFirst[t]]);
				RemovePlant(_tileFirst[t]);
			}
			TileBurn[t] = 0f;
			Grass[t] = 0f;
			Scorch[t] = 255;
			_scorchChanged.Add(t);
			int b = _buildingAt.Length > t ? _buildingAt[t] : -1;
			if (b >= 0 && Buildings[b].Alive && Buildings[b].Burning == 0f && Buildings[b].Type != _tRuin)
				SetBuildingOnFire(b);
		});
		_burningTiles.RemoveAll(t => TileBurn[t] == 0f);
		_burning.RemoveAll(p => !_pAlive[p] || _pBurn[p] == 0f);
		Ignite(x, y, radius + 1.5f);
		LogEvent($"a meteor falls near ({(int)x}, {(int)y}).", "disasters");
		PlayerActed("meteor", x, y, radius, mercy: false);
		Witness("meteor", x, y, $"a burning star fell {PlaceNear(x, y)}");
		return killed;
	}

	/// <summary>Kills every creature under the brush. Returns how many.</summary>
	public int PowerSmite(float x, float y, float radius)
	{
		int killed = Smite(x, y, radius);
		if (killed > 0)
			PlayerActed("smite", x, y, radius, mercy: false);
		return killed;
	}

	private int Smite(float x, float y, float radius)
	{
		int killed = 0;
		foreach (int i in UnitsWithin(x, y, radius).ToArray())
		{
			NoteVictim(i);
			KillUnit(i, Death.Other);
			killed++;
		}
		return killed;
	}

	/// <summary>Heals, feeds and waters every creature under the brush. Returns how many.</summary>
	public int PowerBless(float x, float y, float radius)
	{
		int blessed = 0;
		foreach (int i in UnitsWithin(x, y, radius))
		{
			Units.Health[i] = Math.Max(Units.Health[i], MaxHealth(i));
			Units.Hunger[i] = 0f;
			Units.Thirst[i] = 0f;
			blessed++;
		}
		if (blessed > 0)
			PlayerActed("bless", x, y, radius, mercy: true);
		return blessed;
	}

	/// <summary>A miracle (0.6): a sign from the sky over the brush. It heals and feeds those under
	/// it, and the villages that see it (within 20 tiles) grow in faith and love the god who sent
	/// it. Returns the creatures healed plus the villages that saw it (0 on the sea).</summary>
	public int PowerMiracle(float x, float y, float radius)
	{
		if (!OnLand(x, y))
			return 0;
		int healed = 0;
		foreach (int i in UnitsWithin(x, y, radius))
		{
			Units.Health[i] = Math.Max(Units.Health[i], MaxHealth(i));
			Units.Hunger[i] = 0f;
			Units.Thirst[i] = 0f;
			healed++;
		}
		int saw = 0;
		string where = "";
		foreach (var v in Villages)
		{
			if (!v.Alive)
				continue;
			float d = MathF.Sqrt((v.X + 0.5f - x) * (v.X + 0.5f - x) + (v.Y + 0.5f - y) * (v.Y + 0.5f - y));
			if (d > radius + 20f)
				continue;
			v.Faith = Math.Min(100f, v.Faith + 25f * (1f - d / (radius + 25f)));
			if (saw == 0)
				where = v.Name;
			saw++;
		}
		PlayerActed("miracle", x, y, radius, mercy: true);
		LogEvent(saw > 0 ? $"a miracle shines over {where}: the faithful fall to their knees." : $"a miracle shines over the wilds near ({(int)x}, {(int)y}).", "faith");
		return healed + saw;
	}

	// ------------------------------------------------------------------ life

	/// <summary>Ids of the creatures the player can bring into the world (data/species.json).</summary>
	public string[] SpawnableSpecies()
	{
		var ids = new List<string>();
		foreach (var sp in Assets.Species)
			if (!sp.IsPeople)
				ids.Add(sp.Id);
		return ids.ToArray();
	}

	/// <summary>Ids of the peoples the player can settle (data/races.json).</summary>
	public string[] RaceIds() => Assets.Races.ConvertAll(r => r.Id).ToArray();

	/// <summary>Brings `count` adult creatures of a species into the world around (x, y), on
	/// land. Returns how many came.</summary>
	public int PowerSpawn(string id, float x, float y, int count)
	{
		int s = Assets.SpeciesIndex(id ?? "");
		if (s < 0 || Assets.Species[s].IsPeople || !OnLand(x, y))
			return 0;
		int spawned = 0;
		for (int k = 0; k < count; k++)
		{
			float px = x + ((float)_rng.NextDouble() * 2f - 1f) * 1.5f, py = y + ((float)_rng.NextDouble() * 2f - 1f) * 1.5f;
			if (!World.IsLandAt(px, py))
			{
				px = x;
				py = y;
			}
			if (SpawnAt(id, px, py, false) >= 0)
				spawned++;
		}
		// Monsters from the sky frighten the peoples who see them come.
		if (spawned > 0 && !Assets.Species[s].IsNatural)
			PlayerActed("spawn", x, y, 2f, mercy: false);
		return spawned;
	}

	/// <summary>`count` people of a race found a village at (x, y), and a kingdom of their own.
	/// Refused on water, on a building and on land a village already owns. Returns the village,
	/// or -1.</summary>
	public int PowerSettle(string raceId, float x, float y, int count)
	{
		var rec = Assets.Races.Find(r => r.Id == raceId);
		if (rec == null || count < 2 || !OnLand(x, y))
			return -1;
		int tx = (int)x, ty = (int)y;
		if (OwnerAt(tx, ty) >= 0 || _buildingAt[World.Index(tx, ty)] >= 0)
			return -1;
		// A people already in this world keeps its nature; a new one gets this world's variation.
		int known = Assets.SpeciesIndex(raceId);
		int s = known >= 0 ? known : PeopleSpecies(rec.Vary(_rng));
		int v = SettleAt(s, World.Index(tx, ty), count);
		Zones.Rebuild(Units);
		return v;
	}

	// ------------------------------------------------------------------ the land

	private readonly List<int> _biomeChanged = new();

	/// <summary>Names of the biomes the brush can paint: every land biome.</summary>
	public string[] PaintableBiomes()
	{
		var names = new List<string>();
		foreach (string name in _biomeNames)
			if (!IsWaterBiome(name))
				names.Add(name);
		return names.ToArray();
	}

	private static bool IsWaterBiome(string name) => name == "Deep water" || name == "Water" || name == "Ice";

	/// <summary>Paints a land biome under the brush (land tiles only; never water). The old
	/// plants go, the new biome's own will colonise the ground. Lava kills what stands on it and
	/// lights the land around. Returns the tiles changed.</summary>
	public int PowerBiome(string biomeName, float x, float y, float radius)
	{
		int b = World == null ? -1 : Array.IndexOf(_biomeNames, biomeName);
		if (b < 0 || IsWaterBiome(biomeName))
			return 0;
		bool lava = biomeName == "Lava";
		int changed = 0;
		TilesWithin(x, y, radius, t =>
		{
			if (World.Water[t] != SimWorld.WaterLand || World.Biome[t] == b)
				return;
			World.Biome[t] = (byte)b;
			while (_tileFirst[t] >= 0)
			{
				MarkStrip((int)_pY[_tileFirst[t]]);
				RemovePlant(_tileFirst[t]);
			}
			TileBurn[t] = 0f;
			Grass[t] = Math.Min(Grass[t], _fertility[b]);
			_biomeChanged.Add(t);
			changed++;
		});
		if (changed == 0)
			return 0;
		_burningTiles.RemoveAll(t => TileBurn[t] == 0f);
		_burning.RemoveAll(p => !_pAlive[p] || _pBurn[p] == 0f);
		if (lava)
		{
			foreach (int i in UnitsWithin(x, y, radius).ToArray())
				if (World.Biome[World.Index((int)Units.X[i], (int)Units.Y[i])] == b)
				{
					NoteVictim(i);
					KillUnit(i, Death.Fire);
				}
			Ignite(x, y, radius + 1.5f);
			PlayerActed("lava", x, y, radius, mercy: false);
			Witness("lava", x, y, $"fire rose from the ground {PlaceNear(x, y)}");
		}
		return changed;
	}

	/// <summary>Biome changes since the last call, as pairs (tile, biome) for the map.</summary>
	public int[] TakeBiomeChanges()
	{
		if (World == null)
			return Array.Empty<int>();
		var pairs = new List<int>();
		var seen = new HashSet<int>();
		for (int k = _biomeChanged.Count - 1; k >= 0; k--)
			// (a tile of a world replaced since by a smaller one is dropped)
			if (_biomeChanged[k] < World.Biome.Length && seen.Add(_biomeChanged[k]))
			{
				pairs.Add(_biomeChanged[k]);
				pairs.Add(World.Biome[_biomeChanged[k]]);
			}
		_biomeChanged.Clear();
		return pairs.ToArray();
	}

	// ------------------------------------------------------------------ kingdoms and laws

	/// <summary>The village that owns the land at (x, y), or -1.</summary>
	public int VillageAt(float x, float y) => World == null ? -1 : OwnerAt((int)MathF.Floor(x), (int)MathF.Floor(y));

	/// <summary>The kingdom that owns the land at (x, y), or -1.</summary>
	public int KingdomAt(float x, float y) => KingdomOf(VillageAt(x, y));

	/// <summary>What the inspector shows about a village: its row of VillageTable (empty if none).</summary>
	public Godot.Collections.Dictionary VillageInfo(int v)
	{
		foreach (var row in VillageTable())
			if (row.AsGodotDictionary()["index"].AsInt32() == v)
				return row.AsGodotDictionary();
		return new Godot.Collections.Dictionary();
	}

	/// <summary>Whispers in a ruler's ear: kingdom a goes to "war" with b, makes "peace" or an
	/// "alliance", at once. False when it makes no sense (the same kingdom, a fallen one, war on
	/// an enemy, peace or alliance the wrong way round).</summary>
	public bool PowerWhisper(string kind, int a, int b)
	{
		if (a == b || a < 0 || b < 0 || a >= Kingdoms.Count || b >= Kingdoms.Count || !Kingdoms[a].Alive || !Kingdoms[b].Alive)
			return false;
		bool atWar = AtWar(a, b);
		if (kind == "war" ? atWar : kind == "peace" ? !atWar : kind == "alliance" ? atWar || Kingdoms[a].Allies.Contains(b) : true)
			return false;
		return ForcePlan(Plot(kind, a, b));
	}

	/// <summary>The world's laws (rules of the simulation that can be switched off): name → on.</summary>
	public Godot.Collections.Dictionary LawTable()
	{
		var table = new Godot.Collections.Dictionary();
		foreach (var (name, on) in Laws)
			table[name] = on;
		return table;
	}
}
