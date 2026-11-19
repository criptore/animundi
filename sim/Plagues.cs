using System;
using System.Collections.Generic;

namespace Animundi.Sim;

/// <summary>
/// Generated diseases and plagues (0.7, docs/NATURE.md). A disease is drawn the day it breaks
/// out (data/diseases.json): a symptom, a name ("the Red Cough"), who carries it (people, beasts
/// or all), how easily it passes, how many it kills, how long it lasts, and its cure.
///
/// It passes from the sick to those standing close. The sick die of it or get over it, and
/// those who got over it never catch it again: a disease burns through a village, then dies
/// out for want of anyone to take; after five years it weakens anyway. Carts and boats of trade carry it to other villages.
///
/// Cures: "herbs" (a village with a shaman loses far fewer and heals faster), "quarantine"
/// (a village with many sick shuts its gates: it passes far less there), or none. The player
/// can start one (Plague) and cure the sick (Heal).
///
/// A disease that kills ten people is a plague: the chronicle counts its dead, and the
/// kingdoms it struck remember it and make myths of it.
/// </summary>
public partial class Simulation
{
	public sealed class Disease
	{
		public int Index;
		public string Name = "", Symptom = "", SymptomText = "", Carrier = "people", Cure = "none", Origin = "", Cause = "nature";
		public float Contagion, Lethality, Seconds;
		/// <summary>How easily it passed when it broke out, and when it last did: after five
		/// years a sickness weakens, and dies out.</summary>
		public float BaseContagion;
		public double Since;
		public int Year, EndYear = -1;
		/// <summary>Sick now; dead of it (people among them); got over it; ever caught it.</summary>
		public int Sick, Dead, PeopleDead, Recovered, Caught;
		/// <summary>How many of its milestones (10, 50, 200 dead) the chronicle has told.</summary>
		public int Told;
		public double QuietSince = -1;
		public readonly HashSet<int> Struck = new();
		public bool Over => EndYear >= 0;
	}

	public static readonly string[] Cures = { "herbs", "quarantine", "none" };
	private static readonly int[] PlagueMilestones = { 10, 50, 200 };

	public readonly List<Disease> Diseases = new();
	private Random _plagueRng = new(1);
	private double _nextPlague, _nextPlagueCount;
	private readonly List<int> _plagueFound = new();
	// Per village: its sick, the disease most of them have, and whether its gates are shut.
	private int[] _villageSick = Array.Empty<int>();
	private int[] _villageDisease = Array.Empty<int>();
	private readonly HashSet<int> _quarantined = new();
	private int _sickTotal;

	private void SetupPlagues(int seed)
	{
		Diseases.Clear();
		_quarantined.Clear();
		_villageSick = Array.Empty<int>();
		_villageDisease = Array.Empty<int>();
		_sickTotal = 0;
		_plagueRng = new Random(seed ^ 0x51c4);
		_nextPlague = YearSeconds * (6.0 + 8.0 * _plagueRng.NextDouble());
		_nextPlagueCount = 0;
	}

	// ------------------------------------------------------------------ a disease is born

	/// <summary>Draws a new disease. `carrier`: people, beasts or all (null: drawn).</summary>
	private Disease NewDisease(string origin, string cause, string carrier = null, string name = null)
	{
		var symptoms = Assets.Symptoms;
		var s = symptoms.Count > 0 ? symptoms[_plagueRng.Next(symptoms.Count)] : new SymptomRecord { Id = "fever", Nouns = { "Fever" }, Text = "a fever" };
		float Between(List<float> range) => range.Count >= 2 ? range[0] + (range[1] - range[0]) * (float)_plagueRng.NextDouble() : range.Count == 1 ? range[0] : 0.1f;
		var d = new Disease
		{
			Index = Diseases.Count, Symptom = s.Id, SymptomText = s.Text, Origin = origin, Cause = cause, Year = Year(),
			Contagion = Between(s.Contagion), Lethality = Between(s.Lethality), Seconds = Between(s.Seconds),
			Carrier = carrier ?? (_plagueRng.NextDouble() < 0.8 ? "people" : "all"),
			Cure = Cures[_plagueRng.Next(Cures.Length)],
		};
		if (name == null)
		{
			// A name no other disease of this world has.
			var adjectives = Assets.DiseaseAdjectives;
			for (int tries = 0; tries < 12; tries++)
			{
				string adjective = adjectives.Count > 0 ? adjectives[_plagueRng.Next(adjectives.Count)] : "Grey";
				string noun = s.Nouns.Count > 0 ? s.Nouns[_plagueRng.Next(s.Nouns.Count)] : "Sickness";
				name = $"the {adjective} {noun}";
				if (!Diseases.Exists(o => o.Name == name))
					break;
			}
		}
		d.Name = name;
		d.BaseContagion = d.Contagion;
		d.Since = Scheduler.Time;
		Diseases.Add(d);
		return d;
	}

	/// <summary>A sickness that had died out breaks out again, as strong as it first was.</summary>
	private void Reawaken(Disease d)
	{
		d.EndYear = -1;
		d.QuietSince = -1;
		d.Contagion = d.BaseContagion;
		d.Since = Scheduler.Time;
	}

	/// <summary>Whether unit i can catch disease d: alive, of flesh (the undead, golems and
	/// legends never sicken), a carrier, not already sick, never had it.</summary>
	private bool CanCatch(int i, Disease d)
	{
		if (!Units.Alive[i] || Units.Sick[i] != 0 || (Units.Immune[i] & (1UL << (d.Index & 63))) != 0)
			return false;
		var sp = Assets.Species[Units.Species[i]];
		if (sp.IsLegend || !sp.Eats)
			return false;
		return d.Carrier == "all" || (d.Carrier == "people") == sp.IsPeople;
	}

	private bool Infect(int i, Disease d)
	{
		if (d == null || d.Over || !CanCatch(i, d))
			return false;
		Units.Sick[i] = d.Index + 1;
		Units.SickFor[i] = 0f;
		d.Sick++;
		d.Caught++;
		d.QuietSince = -1;
		_sickTotal++;
		return true;
	}

	private void Recover(int i, bool immune)
	{
		int k = Units.Sick[i] - 1;
		if (k < 0)
			return;
		Units.Sick[i] = 0;
		_sickTotal--;
		if (k >= Diseases.Count)
			return;
		var d = Diseases[k];
		d.Sick--;
		if (immune)
		{
			Units.Immune[i] |= 1UL << (d.Index & 63);
			d.Recovered++;
		}
	}

	/// <summary>A sick unit dies (KillUnit), of its sickness or of anything else.</summary>
	private void SickDied(int i, Death cause)
	{
		int k = Units.Sick[i] - 1;
		Units.Sick[i] = 0;
		_sickTotal--;
		if (k < 0 || k >= Diseases.Count)
			return;
		var d = Diseases[k];
		d.Sick--;
		if (cause != Death.Plague)
			return;
		d.Dead++;
		var sp = Assets.Species[Units.Species[i]];
		if (!sp.IsPeople)
			return;
		d.PeopleDead++;
		int kingdom = KingdomOfUnit(i);
		if (kingdom >= 0)
			d.Struck.Add(kingdom);
		// The rot: some of its dead do not stay down.
		int zombie = Assets.SpeciesIndex("zombie");
		if (d.Symptom == "rot" && zombie >= 0 && Law("monsters") && _plagueRng.NextDouble() < 0.25 && Population[zombie] < 40)
			SpawnUnit(zombie, Units.X[i], Units.Y[i], false);
	}

	// ------------------------------------------------------------------ the sick (1 / s, in batches)

	private bool HasShaman(int v)
	{
		if (v < 0 || v >= _villageShaman.Length)
			return false;
		return _villageShaman[v];
	}

	private bool[] _villageShaman = Array.Empty<bool>();

	private void PlagueStep(int a, int b, float dt)
	{
		if (_sickTotal <= 0)
			return;
		for (int i = a; i < b; i++)
		{
			if (!Units.Alive[i] || Units.Sick[i] == 0)
				continue;
			int k = Units.Sick[i] - 1;
			if (k >= Diseases.Count)
			{
				Units.Sick[i] = 0;
				continue;
			}
			var d = Diseases[k];
			var sp = Assets.Species[Units.Species[i]];
			int v = Units.Village[i];
			Units.SickFor[i] += dt;
			switch (d.Symptom)
			{
				case "fever":
					Units.Thirst[i] = Math.Min(1f, Units.Thirst[i] + dt / ThirstSeconds);
					break;
				case "wasting":
					Units.Hunger[i] = Math.Min(1f, Units.Hunger[i] + dt / HungerSeconds);
					break;
				case "shakes":
					if (sp.IsPeople)
						Units.Health[i] = Math.Min(Units.Health[i], MaxHealth(i) * 0.5f);
					break;
			}
			// It passes to those who stand close (a shut village passes it far less).
			bool shut = v >= 0 && _quarantined.Contains(v);
			float reach = d.Symptom == "cough" ? 2.4f : 1.6f;
			_plagueFound.Clear();
			Zones.Query(Units, Units.X[i], Units.Y[i], reach, _plagueFound);
			int passed = 0;
			foreach (int j in _plagueFound)
			{
				if (j == i || passed >= 3)
					continue;
				if (_plagueRng.NextDouble() < d.Contagion * dt * (shut ? 0.25 : 1.0) && Infect(j, d))
					passed++;
			}
			// A shaman's herbs: far fewer die, and they are on their feet sooner.
			bool tended = d.Cure == "herbs" && sp.IsPeople && HasShaman(v);
			float lethality = d.Lethality * (tended ? 0.35f : 1f);
			float seconds = d.Seconds * (tended ? 0.6f : 1f);
			if (_plagueRng.NextDouble() < lethality * dt / seconds)
			{
				KillUnit(i, Death.Plague);
				continue;
			}
			if (Units.SickFor[i] >= seconds)
				Recover(i, immune: true);
		}
	}

	// ------------------------------------------------------------------ watching them (the disasters' system)

	/// <summary>Counts the sick of each village, shuts and opens gates, tells the chronicle of
	/// the plagues' dead and their end, and lets new diseases break out (law "plagues").</summary>
	private void PlagueWatch(float dt)
	{
		if (Scheduler.Time >= _nextPlague)
		{
			_nextPlague = Scheduler.Time + YearSeconds * (10.0 + 12.0 * _plagueRng.NextDouble()) / EraDisaster("plague");
			if (Law("plagues"))
				NaturalOutbreak();
		}
		if (Scheduler.Time < _nextPlagueCount)
			return;
		_nextPlagueCount = Scheduler.Time + 2.0;
		if (_villageSick.Length != Villages.Count)
		{
			_villageSick = new int[Villages.Count];
			_villageDisease = new int[Villages.Count];
			_villageShaman = new bool[Villages.Count];
		}
		Array.Clear(_villageSick);
		Array.Clear(_villageShaman);
		Array.Fill(_villageDisease, -1);
		bool any = _sickTotal > 0;
		for (int i = 0; i < Units.Capacity; i++)
		{
			if (!Units.Alive[i])
				continue;
			int v = Units.Village[i];
			if (v < 0 || v >= _villageSick.Length)
				continue;
			if (Units.Role[i] == (byte)Role.Shaman)
				_villageShaman[v] = true;
			if (any && Units.Sick[i] > 0)
			{
				_villageSick[v]++;
				_villageDisease[v] = Units.Sick[i] - 1;
			}
		}
		for (int v = 0; v < Villages.Count; v++)
		{
			var village = Villages[v];
			if (!village.Alive)
			{
				_quarantined.Remove(v);
				continue;
			}
			int sick = _villageSick[v];
			var d = _villageDisease[v] >= 0 && _villageDisease[v] < Diseases.Count ? Diseases[_villageDisease[v]] : null;
			if (!_quarantined.Contains(v) && d != null && d.Cure == "quarantine" && sick >= Math.Max(3, village.Population / 5))
			{
				_quarantined.Add(v);
				LogEvent($"{village.Name} shuts its gates against {d.Name}.", "disasters");
			}
			else if (_quarantined.Contains(v) && sick == 0)
			{
				_quarantined.Remove(v);
				LogEvent($"{village.Name} opens its gates again.", "disasters");
			}
		}
		foreach (var d in Diseases)
		{
			if (d.Over)
				continue;
			while (d.Told < PlagueMilestones.Length && d.PeopleDead >= PlagueMilestones[d.Told])
			{
				LogEvent(d.Told == 0 ? $"{d.Name} is a plague now: {d.PeopleDead} have died of it."
					: $"{d.Name} has taken {d.PeopleDead} lives.", "disasters");
				foreach (int k in d.Struck)
					Remember(k, "plague", $"{d.Name} took {d.PeopleDead} lives", 2f + d.Told);
				d.Told++;
			}
			// Five years on, it weakens: fewer and fewer catch it.
			if (Scheduler.Time - d.Since > YearSeconds * 5.0)
				d.Contagion *= 0.97f;
			if (d.Sick > 0)
			{
				d.QuietSince = -1;
				continue;
			}
			if (d.QuietSince < 0)
				d.QuietSince = Scheduler.Time;
			else if (Scheduler.Time - d.QuietSince >= 8.0)
			{
				d.EndYear = Year();
				if (d.Dead > 0)
					LogEvent($"{d.Name} burns out: {d.PeopleDead} people and {d.Dead - d.PeopleDead} beasts died of it, {d.Recovered} got over it.", "disasters");
			}
		}
	}

	/// <summary>A sickness breaks out on its own: in a crowded village, or among the beasts of
	/// a thriving species. Now and then an old one comes back.</summary>
	private void NaturalOutbreak()
	{
		var crowded = new List<int>();
		for (int v = 0; v < Villages.Count; v++)
			if (Villages[v].Alive && Villages[v].Population >= 12)
				crowded.Add(v);
		if (crowded.Count > 0 && _plagueRng.NextDouble() < 0.7)
		{
			// The more crowded, the likelier.
			int total = 0;
			foreach (int v in crowded)
				total += Villages[v].Population;
			int r = _plagueRng.Next(total), at = crowded[0];
			foreach (int v in crowded)
			{
				r -= Villages[v].Population;
				if (r < 0)
				{
					at = v;
					break;
				}
			}
			var old = Diseases.FindAll(o => o.Over && o.Carrier != "beasts" && o.PeopleDead > 0);
			Disease d = null;
			if (old.Count > 0 && _plagueRng.NextDouble() < 0.25)
			{
				d = old[_plagueRng.Next(old.Count)];
				Reawaken(d);
			}
			bool back = d != null;
			d ??= NewDisease(Villages[at].Name, "nature");
			int caught = InfectVillage(at, d, 3);
			if (caught > 0)
				LogEvent(back ? $"{d.Name} comes back, in {Villages[at].Name}." : $"a sickness breaks out in {Villages[at].Name}: {d.Name}, {d.SymptomText}.", "disasters");
			else if (!back)
				d.EndYear = Year();
			return;
		}
		// Among the beasts.
		int best = -1;
		for (int s = 0; s < Assets.Species.Count; s++)
		{
			var sp = Assets.Species[s];
			if (!sp.IsPeople && !sp.IsLegend && sp.Eats && Population[s] >= 15 && (best < 0 || _plagueRng.NextDouble() < 0.4))
				best = s;
		}
		if (best < 0)
			return;
		int first = -1;
		int skip = _plagueRng.Next(Population[best]);
		for (int i = 0; i < Units.Capacity; i++)
			if (Units.Alive[i] && Units.Species[i] == best && skip-- <= 0)
			{
				first = i;
				break;
			}
		if (first < 0)
			return;
		string name = Assets.Species[best].Name.ToLower();
		var beast = NewDisease($"the {name}s", "nature", _plagueRng.NextDouble() < 0.7 ? "beasts" : "all");
		int n = InfectAround(Units.X[first], Units.Y[first], 6f, beast, 4);
		if (n > 0)
			LogEvent($"a sickness spreads among the {name}s {PlaceNear(Units.X[first], Units.Y[first])}: {beast.Name}.", "disasters");
		else
			beast.EndYear = Year();
	}

	/// <summary>Up to `count` people of village v catch disease d. Returns how many.</summary>
	private int InfectVillage(int v, Disease d, int count)
	{
		int caught = 0;
		for (int i = 0; i < Units.Capacity && caught < count; i++)
			if (Units.Alive[i] && Units.Village[i] == v && Infect(i, d))
				caught++;
		return caught;
	}

	/// <summary>Up to `count` creatures within `radius` of (x, y) catch disease d.</summary>
	private int InfectAround(float x, float y, float radius, Disease d, int count)
	{
		int caught = 0;
		foreach (int i in UnitsWithin(x, y, radius).ToArray())
		{
			if (caught >= count)
				break;
			if (Infect(i, d))
				caught++;
		}
		return caught;
	}

	/// <summary>Trade carries sickness (Trade.cs): a cart or a boat from a village with sick
	/// people may leave one sick person where it unloads, unless that village's gates are shut.</summary>
	private void TradeCarriesSickness(int from, int to)
	{
		if (from >= _villageSick.Length || to >= _villageSick.Length || _villageSick[from] < 2 || _quarantined.Contains(to) || _quarantined.Contains(from))
			return;
		int k = _villageDisease[from];
		if (k < 0 || k >= Diseases.Count || Diseases[k].Over || _plagueRng.NextDouble() > 0.5)
			return;
		bool known = _villageSick[to] > 0;
		if (InfectVillage(to, Diseases[k], 1) > 0 && !known)
			LogEvent($"traders from {Villages[from].Name} bring {Diseases[k].Name} to {Villages[to].Name}.", "disasters");
	}

	/// <summary>The line the inspector adds for a sick unit, or "".</summary>
	private string SickInfo(int i)
	{
		int k = Units.Sick[i] - 1;
		return k >= 0 && k < Diseases.Count ? $" · sick with {Diseases[k].Name}" : "";
	}

	// ------------------------------------------------------------------ the player

	/// <summary>The player's plague: the creatures under the brush catch a new sickness, which
	/// all can carry. Returns how many caught it.</summary>
	public int PowerPlague(float x, float y, float radius)
	{
		if (World == null)
			return 0;
		var candidates = UnitsWithin(x, y, radius).ToArray();
		if (candidates.Length == 0)
			return 0;
		var d = NewDisease(PlaceNear(x, y), "player", "all");
		int caught = 0;
		foreach (int i in candidates)
			if (Infect(i, d))
				caught++;
		if (caught == 0)
		{
			Diseases.Remove(d);
			return 0;
		}
		LogEvent($"a sickness falls from the sky {d.Origin}: {d.Name}, {d.SymptomText}.", "disasters");
		GodActs("plague", x, y, radius, caught);
		return caught;
	}

	/// <summary>Heal: cures the sick under the brush (they will not catch it again) and closes
	/// wounds. Returns how many were sick or wounded.</summary>
	public int PowerHeal(float x, float y, float radius)
	{
		int healed = 0, people = 0;
		foreach (int i in UnitsWithin(x, y, radius))
		{
			bool was = Units.Sick[i] > 0 || Units.Health[i] < MaxHealth(i) - 0.5f;
			if (Units.Sick[i] > 0)
				Recover(i, immune: true);
			Units.Health[i] = Math.Max(Units.Health[i], MaxHealth(i));
			if (!was)
				continue;
			healed++;
			if (Assets.Species[Units.Species[i]].IsPeople)
				people++;
		}
		GodActs("heal", x, y, radius, people);
		return healed;
	}

	// ------------------------------------------------------------------ queries (HUD, tests)

	/// <summary>The diseases of this world, the newest first: name, symptom, carrier, cure,
	/// origin, cause, year, ended (-1 while it lasts), sick, dead, people_dead, recovered, caught,
	/// contagion, lethality, seconds, plague (ten people dead).</summary>
	public Godot.Collections.Array DiseaseTable()
	{
		var list = new Godot.Collections.Array();
		for (int k = Diseases.Count - 1; k >= 0; k--)
		{
			var d = Diseases[k];
			list.Add(new Godot.Collections.Dictionary
			{
				["index"] = d.Index, ["name"] = d.Name, ["symptom"] = d.Symptom, ["text"] = d.SymptomText, ["carrier"] = d.Carrier, ["cure"] = d.Cure,
				["origin"] = d.Origin, ["cause"] = d.Cause, ["year"] = d.Year, ["ended"] = d.EndYear, ["sick"] = d.Sick, ["dead"] = d.Dead,
				["people_dead"] = d.PeopleDead, ["recovered"] = d.Recovered, ["caught"] = d.Caught, ["contagion"] = d.Contagion,
				["lethality"] = d.Lethality, ["seconds"] = d.Seconds, ["plague"] = d.PeopleDead >= PlagueMilestones[0],
			});
		}
		return list;
	}

	public int SickCount() => _sickTotal;

	public bool UnitSick(int i) => i >= 0 && i < Units.Capacity && Units.Alive[i] && Units.Sick[i] > 0;

	/// <summary>Whether village v has shut its gates against a sickness.</summary>
	public bool VillageQuarantined(int v) => _quarantined.Contains(v);

	/// <summary>Makes a sickness break out now, by itself (tests and tools).</summary>
	public void OutbreakNow() => NaturalOutbreak();

	/// <summary>Starts a disease with the numbers given in village v (tests): its index, or -1.</summary>
	public int StartDisease(int v, string symptom, string cure, float contagion, float lethality, float seconds, int count)
	{
		if (v < 0 || v >= Villages.Count || !Villages[v].Alive)
			return -1;
		var d = NewDisease(Villages[v].Name, "nature", "people");
		d.Symptom = symptom;
		d.Cure = cure;
		d.Contagion = d.BaseContagion = contagion;
		d.Lethality = lethality;
		d.Seconds = seconds;
		return InfectVillage(v, d, count) > 0 ? d.Index : -1;
	}
}
