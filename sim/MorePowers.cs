using System;
using System.Collections.Generic;

namespace Animundi.Sim;

/// <summary>
/// More god powers (0.9, docs/POWERS.md): the fire's sparks, seeds, blizzards, curses, madness,
/// the dead raised, and the powers that act on minds (a rebellion stirred, an idea given, a
/// culture or a faith forgotten, traits rained on people).
/// </summary>
public partial class Simulation
{
	/// <summary>A spark thrown by the fire power: it flies, falls, and lights what it lands on.</summary>
	private struct Spark
	{
		public float X, Y, Z, Vx, Vy, Vz;
	}

	private readonly List<Spark> _sparks = new();
	/// <summary>Frost laid by a blizzard on each tile: seconds left (ground code 9 on the map).</summary>
	public float[] Frost = Array.Empty<float>();
	private readonly HashSet<int> _frosted = new();
	public const float FrostSeconds = YearSeconds * 0.5f;
	public const float CurseSeconds = YearSeconds * 1.5f;
	public const float MadSeconds = 25f;

	/// <summary>Resets the powers' state for a new world (Simulation.Start).</summary>
	private void SetupMorePowers()
	{
		_sparks.Clear();
		_frosted.Clear();
		Frost = new float[World.Width * World.Height];
	}

	// ------------------------------------------------------------------ sparks

	/// <summary>The fire power throws sparks around the brush, as in WorldBox: they arc out and
	/// light the land they fall on, if it burns.</summary>
	private void ThrowSparks(float x, float y, float radius, int count)
	{
		for (int n = 0; n < count && _sparks.Count < 400; n++)
		{
			double a = _rng.NextDouble() * Math.PI * 2;
			float speed = 1.5f + 3f * (float)_rng.NextDouble();
			_sparks.Add(new Spark
			{
				X = x + (float)Math.Cos(a) * radius * 0.5f, Y = y + (float)Math.Sin(a) * radius * 0.5f, Z = 0.4f,
				Vx = (float)Math.Cos(a) * speed + WindX * (WindSeconds > 0f ? 3f : 0f), Vy = (float)Math.Sin(a) * speed + WindY * (WindSeconds > 0f ? 3f : 0f),
				Vz = 2.5f + 2f * (float)_rng.NextDouble(),
			});
		}
	}

	/// <summary>Every step: sparks fly and fall; one that lands on land that can burn lights it.</summary>
	private void SparkStep(float dt)
	{
		for (int k = _sparks.Count - 1; k >= 0; k--)
		{
			var s = _sparks[k];
			s.X += s.Vx * dt;
			s.Y += s.Vy * dt;
			s.Z += s.Vz * dt;
			s.Vz -= 9f * dt;
			if (s.Z > 0f)
			{
				_sparks[k] = s;
				continue;
			}
			_sparks.RemoveAt(k);
			if (World.InBounds((int)s.X, (int)s.Y) && World.IsLandAt(s.X, s.Y) && _rng.NextDouble() < 0.6)
				IgniteTile(World.Index((int)s.X, (int)s.Y));
		}
	}

	public int SparkCount() => _sparks.Count;

	// ------------------------------------------------------------------ the land

	/// <summary>Sows the plants of each tile's biome under the brush. Returns the plants sown.</summary>
	public int PowerSeeds(float x, float y, float radius)
	{
		int sown = 0;
		TilesWithin(x, y, radius, t =>
		{
			if (World.Water[t] != SimWorld.WaterLand || _buildingAt[t] >= 0 || _ground[t] != 0 || _tileCount[t] > 1 || TileBurn[t] > 0f)
				return;
			var list = _biomePlants[World.Biome[t]];
			if (list == null || list.Count == 0 || _rng.NextDouble() > 0.6)
				return;
			int sprite = list[_rng.Next(list.Count)].sprite;
			float px = t % World.Width + 0.1f + (float)_rng.NextDouble() * 0.8f, py = t / World.Width + 0.2f + (float)_rng.NextDouble() * 0.75f;
			if (OnLandFootprint(sprite, px, py) && AddPlant(sprite, px, py, _rng.Next(2) == 0, 0.7f + (float)_rng.NextDouble() * 0.4f) >= 0)
			{
				MarkStrip((int)py);
				sown++;
			}
			Grass[t] = Math.Max(Grass[t], _fertility[World.Biome[t]] * 0.8f);
			if (Scorch[t] > 0)
			{
				Scorch[t] = 0;
				_scorchChanged.Add(t);
			}
		});
		if (sown > 0)
			GodActs("bless", x, y, radius, 1);
		return sown;
	}

	/// <summary>A blizzard under the brush: frost lies on the land for half a year (nothing grows
	/// under it), fires go out, lakes freeze at their edges, and the cold kills some of the beasts
	/// and people caught in it. Returns the creatures killed.</summary>
	public int PowerBlizzard(float x, float y, float radius)
	{
		if (World == null)
			return 0;
		int ice = Array.IndexOf(_biomeNames, "Ice");
		TilesWithin(x, y, radius, t =>
		{
			TileBurn[t] = 0f;
			if (World.Water[t] == SimWorld.WaterLand)
			{
				Frost[t] = FrostSeconds;
				if (_frosted.Add(t))
					_overlayChanged.Add(t);
				Grass[t] *= 0.3f;
				int b = _buildingAt[t];
				if (b >= 0 && Buildings[b].Burning > 0f)
					Buildings[b].Burning = 0f;
			}
			else if (ice >= 0 && World.Water[t] == WaterLake && _rng.NextDouble() < 0.5)
			{
				World.Biome[t] = (byte)ice;
				_biomeChanged.Add(t);
			}
		});
		_burningTiles.RemoveAll(t => TileBurn[t] == 0f);
		int killed = 0;
		foreach (int i in UnitsWithin(x, y, radius).ToArray())
		{
			var sp = Assets.Species[Units.Species[i]];
			if (sp.IsLegend || sp.Natural.ContainsKey("Snow") || sp.Natural.ContainsKey("Tundra"))
				continue;
			if (_rng.NextDouble() < (sp.IsPeople ? 0.25 : 0.4))
			{
				KillUnit(i, Death.Disaster);
				killed++;
			}
			else
				Units.Energy[i] = 0f;
		}
		LogEvent($"a blizzard howls {PlaceNear(x, y)}.", "disasters");
		GodActs("blizzard", x, y, radius, Math.Max(1, killed));
		return killed;
	}

	/// <summary>Twice a second with the fires: frost melts away.</summary>
	private void FrostStep(float dt)
	{
		if (_frosted.Count == 0)
			return;
		var gone = new List<int>();
		foreach (int t in _frosted)
		{
			Frost[t] -= dt;
			Grass[t] = Math.Min(Grass[t], 0.1f);
			if (Frost[t] <= 0f)
			{
				Frost[t] = 0f;
				gone.Add(t);
			}
		}
		foreach (int t in gone)
		{
			_frosted.Remove(t);
			_overlayChanged.Add(t);
		}
	}

	public bool FrostAt(int x, int y) => World.InBounds(x, y) && Frost[World.Index(x, y)] > 0f;

	// ------------------------------------------------------------------ creatures

	/// <summary>Curses every creature under the brush for a year and a half: it hungers and thirsts
	/// faster and strikes weaker; peoples who see it fear the hand that did it. Returns how many.</summary>
	public int PowerCurse(float x, float y, float radius)
	{
		int cursed = 0, people = 0;
		foreach (int i in UnitsWithin(x, y, radius))
		{
			if (Assets.Species[Units.Species[i]].IsLegend)
				continue;
			Units.Cursed[i] = CurseSeconds;
			cursed++;
			if (Assets.Species[Units.Species[i]].IsPeople)
				people++;
		}
		GodActs("wrath", x, y, radius, Math.Max(people, cursed > 0 ? 1 : 0));
		return cursed;
	}

	public bool IsCursed(int i) => i >= 0 && i < Units.Capacity && Units.Alive[i] && Units.Cursed[i] > 0f;

	/// <summary>Creatures under the brush go mad and turn on the nearest creature they see, kin or
	/// not. Returns how many went mad.</summary>
	public int PowerMadness(float x, float y, float radius)
	{
		var mad = UnitsWithin(x, y, radius).ToArray();
		int turned = 0;
		foreach (int i in mad)
		{
			if (!Units.Alive[i] || Assets.Species[Units.Species[i]].IsLegend)
				continue;
			_found.Clear();
			Zones.Query(Units, Units.X[i], Units.Y[i], 6f, _found);
			int best = -1;
			float bestD = float.MaxValue;
			foreach (int j in _found)
			{
				if (j == i || !Units.Alive[j] || Assets.Species[Units.Species[j]].IsLegend)
					continue;
				float d = (Units.X[j] - Units.X[i]) * (Units.X[j] - Units.X[i]) + (Units.Y[j] - Units.Y[i]) * (Units.Y[j] - Units.Y[i]);
				if (d < bestD)
				{
					bestD = d;
					best = j;
				}
			}
			if (best < 0)
				continue;
			Units.Task[i] = (byte)Task.Hunt;
			Units.Prey[i] = best;
			Units.Mad[i] = MadSeconds;
			turned++;
		}
		if (turned > 0)
			GodActs("wrath", x, y, radius, turned);
		return turned;
	}

	/// <summary>The dead still lying under the brush rise: beasts as they were, people as the
	/// undead (zombies). Returns how many rose.</summary>
	public int PowerResurrect(float x, float y, float radius)
	{
		int zombie = Assets.SpeciesIndex("zombie");
		int risen = 0;
		for (int r = _remains.Count - 1; r >= 0; r--)
		{
			var rem = _remains[r];
			float dx = rem.x - x, dy = rem.y - y;
			if (dx * dx + dy * dy > radius * radius || !World.IsLandAt(rem.x, rem.y))
				continue;
			var sp = Assets.Species[rem.species];
			int species = sp.IsPeople ? zombie : rem.species;
			if (species < 0 || sp.IsLegend)
				continue;
			SpawnUnit(species, rem.x, rem.y, false);
			_remains.RemoveAt(r);
			risen++;
		}
		if (risen > 0)
		{
			Zones.Rebuild(Units);
			LogEvent($"the dead rise {PlaceNear(x, y)}: {risen} walk again.", "disasters");
			GodActs("wrath", x, y, radius, risen);
		}
		return risen;
	}

	/// <summary>Every second with the plagues: curses and madness wear off; the mad keep hunting.</summary>
	private void CurseStep(int a, int b, float dt)
	{
		for (int i = a; i < b; i++)
		{
			if (!Units.Alive[i])
				continue;
			if (Units.Cursed[i] > 0f)
				Units.Cursed[i] = Math.Max(0f, Units.Cursed[i] - dt);
			if (Units.Mad[i] > 0f)
			{
				Units.Mad[i] = Math.Max(0f, Units.Mad[i] - dt);
				if (Units.Task[i] != (byte)Task.Hunt && Units.Mad[i] > 0f)
				{
					_found.Clear();
					Zones.Query(Units, Units.X[i], Units.Y[i], 6f, _found);
					foreach (int j in _found)
						if (j != i && Units.Alive[j] && !Assets.Species[Units.Species[j]].IsLegend)
						{
							Units.Task[i] = (byte)Task.Hunt;
							Units.Prey[i] = j;
							break;
						}
				}
			}
		}
	}

	// ------------------------------------------------------------------ minds

	/// <summary>Stirs a village to break away from its kingdom (not a capital). False when it can't.</summary>
	public bool PowerRebellion(float x, float y)
	{
		int v = VillageAt(x, y);
		if (v < 0 || !Villages[v].Alive || Villages[v].Kingdom < 0 || Kingdoms[Villages[v].Kingdom].Capital == v)
			return false;
		int before = Kingdoms.Count;
		Secede(v);
		return Kingdoms.Count > before;
	}

	/// <summary>Gives a kingdom's mind an idea: it invents at once (the model if there is one).</summary>
	public bool PowerInspire(float x, float y)
	{
		int k = KingdomAt(x, y);
		if (k < 0 || !Kingdoms[k].Alive || Kingdoms[k].Capital < 0)
			return false;
		AskMind(k);
		GodActs("bless", x, y, 4f, 3);
		return true;
	}

	/// <summary>Makes a kingdom forget its culture: its customs, myths and memories go, and its
	/// values drift back to the middle.</summary>
	public bool PowerForgetCulture(float x, float y)
	{
		int k = KingdomAt(x, y);
		if (k < 0 || !Kingdoms[k].Alive)
			return false;
		var c = Kingdoms[k].Culture;
		c.Customs.Clear();
		c.Myths.Clear();
		c.Memories.Clear();
		for (int n = 0; n < c.Values.Length; n++)
			c.Values[n] = 0.5f + (c.Values[n] - 0.5f) * 0.3f;
		c.AggressionBonus = c.FaithBonus = 0f;
		foreach (var v in Villages)
			if (v.Alive && v.Kingdom == k)
				v.ModsDirty = true;
		LogEvent($"the people of {Kingdoms[k].Name} wake up having forgotten their customs and their tales.", "culture");
		GodActs("wrath", x, y, 4f, 3);
		return true;
	}

	/// <summary>Makes a kingdom forget its faith: its gods and myths are gone, a new faith is born.</summary>
	public bool PowerForgetFaith(float x, float y)
	{
		int k = KingdomAt(x, y);
		if (k < 0 || !Kingdoms[k].Alive)
			return false;
		var c = Kingdoms[k].Culture;
		string old = c.Creed;
		c.Gods.Clear();
		c.Myths.Clear();
		c.Faith = 10f;
		c.FaithYears = 0;
		FoundReligion(c, Kingdoms[k].Species);
		LogEvent($"{Kingdoms[k].Name} forgets {old}: a new faith is born there, {c.Creed}.", "culture");
		GodActs("wrath", x, y, 4f, 3);
		return true;
	}

	public static readonly string[] TraitNames = { "brave", "lazy", "kind", "greedy", "wise", "strong" };

	/// <summary>Rains a trait on the people under the brush (they take it if they lack it, else
	/// lose it). Returns how many changed.</summary>
	public int PowerTrait(string trait, float x, float y, float radius)
	{
		int n = Array.IndexOf(TraitNames, trait);
		if (n < 0)
			return 0;
		int bit = 1 << n;
		int changed = 0;
		foreach (int i in UnitsWithin(x, y, radius))
		{
			if (!Assets.Species[Units.Species[i]].IsPeople)
				continue;
			Units.Traits[i] |= bit;
			changed++;
		}
		return changed;
	}

	public bool HasTrait(int i, string trait)
	{
		int n = Array.IndexOf(TraitNames, trait);
		return n >= 0 && i >= 0 && i < Units.Capacity && (Units.Traits[i] & (1 << n)) != 0;
	}
}
