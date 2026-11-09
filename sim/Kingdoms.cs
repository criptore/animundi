using System;
using System.Collections.Generic;
using Godot;

namespace Animundi.Sim;

/// <summary>
/// Kingdoms (0.4 Civilisation): every people starts as one kingdom; its villages, the ones its
/// settlers found included, belong to it. A kingdom has a capital, a king or queen of a dynasty, a
/// colour (its villages' land and roofs, a shade per village) and a generated banner.
///
/// Kings plot: wars, alliances, peace. Every plot is a Plan that grows over months before it
/// happens, shown to the player, who can cancel or force it (god powers, 0.9). Villages far from
/// the capital, big ones and those of another people grow disloyal and may rebel: a new kingdom
/// is born and a civil war starts. War itself (armies, fights, sieges, conquest) is in War.cs.
///
/// Settlements grow through ranks: camp, village, town, city.
/// </summary>
public partial class Simulation
{
	public sealed class Kingdom
	{
		public string Name;
		public int Species;
		public int Capital = -1;
		public int King = -1;
		public string Dynasty;
		public Color Color;
		/// <summary>Banner: second colour, field division (0 plain, 1 per pale, 2 per fess, 3 bend,
		/// 4 chevron, 5 cross) and symbol (0-7).</summary>
		public Color Banner2;
		public int Division, Symbol;
		public bool Alive = true;
		public int Founded;
		public readonly HashSet<int> Allies = new();
		/// <summary>Lasting feelings about other kingdoms (wars fought, help given), -100..100.</summary>
		public readonly Dictionary<int, float> Memory = new();
		/// <summary>Tiredness of war, 0..1: grows with the dead, fades in peace.</summary>
		public float Weariness;
		public int Kings;
	}

	public sealed class KingPlan
	{
		public int Id;
		/// <summary>war, peace, alliance, rebellion.</summary>
		public string Kind;
		public int Kingdom;
		/// <summary>The other kingdom (war, peace, alliance) or the village (rebellion).</summary>
		public int Target;
		public float Progress;
		/// <summary>Seconds the plot takes.</summary>
		public float Seconds;
		public bool Alive = true;
	}

	public readonly List<Kingdom> Kingdoms = new();
	public readonly List<KingPlan> Plans = new();
	private int _nextPlan;
	public const float KingdomStepSeconds = 2f;
	/// <summary>Kings think about their neighbours every season.</summary>
	public const float DiplomacySeconds = YearSeconds / 4f;
	private double _nextDiplomacy;

	public static readonly string[] RankNames = { "camp", "village", "town", "city" };

	private void SetupKingdoms()
	{
		Kingdoms.Clear();
		Plans.Clear();
		Wars.Clear();
		_nextPlan = 0;
		_nextDiplomacy = 0;
		_trade.Clear();
		_armyPaths.Clear();
		_seaRoutes.Clear();
		_boarding.Clear();
		_vehicles.Clear();
	}

	// ------------------------------------------------------------------ founding

	/// <summary>A new kingdom with village `v` as its capital and its chief as ruler.</summary>
	private int CreateKingdom(int species, int v, Color? colour = null)
	{
		var lang = _languages[species];
		var race = Assets.Species[species].Race;
		int sameKind = Kingdoms.FindAll(k => k.Species == species).Count;
		var c = colour ?? (sameKind == 0 ? new Color(race?.Color ?? "#ffffff") : Color.FromHsv((float)_rng.NextDouble(), 0.55f, 0.8f));
		var k = new Kingdom
		{
			Name = lang.PlaceName(), Species = species, Capital = v, Color = c, Founded = Year(),
			Dynasty = lang.PersonName(), Banner2 = Color.FromHsv((float)_rng.NextDouble(), 0.35f, 0.95f),
			Division = _rng.Next(6), Symbol = _rng.Next(8),
		};
		Kingdoms.Add(k);
		int id = Kingdoms.Count - 1;
		JoinKingdom(v, id);
		CrownNewKing(id, -1);
		return id;
	}

	/// <summary>Village v now belongs to kingdom k: its colour (a shade of the kingdom's), land
	/// and roofs follow.</summary>
	private void JoinKingdom(int v, int k)
	{
		var village = Villages[v];
		village.Kingdom = k;
		var kingdom = Kingdoms[k];
		int shade = 0;
		foreach (var o in Villages)
			if (o != village && o.Alive && o.Kingdom == k)
				shade++;
		var c = kingdom.Color;
		village.Color = shade == 0 ? c : shade % 2 == 1 ? c.Lightened(0.1f * ((shade + 1) / 2 % 4)) : c.Darkened(0.1f * (shade / 2 % 4));
		foreach (int z in village.Zones)
			MarkZone(z);
	}

	public int KingdomOf(int v) => v >= 0 && v < Villages.Count ? Villages[v].Kingdom : -1;

	/// <summary>The kingdom of person i, or -1.</summary>
	private int KingdomOfUnit(int i) => Units.Village[i] >= 0 ? Villages[Units.Village[i]].Kingdom : -1;

	// ------------------------------------------------------------------ rulers

	/// <summary>A new king or queen: the eldest grown child of the old one (the dynasty goes
	/// on), else the chief of the capital (a new dynasty begins).</summary>
	private void CrownNewKing(int k, int old)
	{
		var kingdom = Kingdoms[k];
		int heir = -1;
		if (old >= 0)
			for (int i = 0; i < Units.Capacity; i++)
				if (Units.Alive[i] && i != old && (Units.Mother[i] == old || Units.Father[i] == old) && IsAdult(i)
					&& KingdomOfUnit(i) == k && (heir < 0 || Units.Age[i] > Units.Age[heir]))
					heir = i;
		bool sameDynasty = heir >= 0;
		if (heir < 0)
		{
			for (int i = 0; i < Units.Capacity; i++)
				if (Units.Alive[i] && Units.Village[i] == kingdom.Capital && IsAdult(i)
					&& (heir < 0 || Units.Role[i] == (byte)Role.Chief && Units.Role[heir] != (byte)Role.Chief
						|| Units.Role[i] == Units.Role[heir] && Units.Age[i] > Units.Age[heir]))
					heir = i;
		}
		kingdom.King = heir;
		if (heir < 0)
			return;
		kingdom.Kings++;
		if (!sameDynasty && old >= 0)
			kingdom.Dynasty = _languages[kingdom.Species].PersonName();
		string title = Units.Female[heir] ? "queen" : "king";
		if (old >= 0)
			LogEvent($"{NameOf(heir)} {kingdom.Dynasty} becomes {title} of {kingdom.Name}"
				+ (sameDynasty ? "." : $": the {kingdom.Dynasty} dynasty begins."), "kings");
	}

	/// <summary>When a person dies: a ruler is succeeded.</summary>
	private void RulerDied(int i)
	{
		for (int k = 0; k < Kingdoms.Count; k++)
			if (Kingdoms[k].Alive && Kingdoms[k].King == i)
			{
				LogEvent($"{NameOf(i)} {Kingdoms[k].Dynasty}, {(Units.Female[i] ? "queen" : "king")} of {Kingdoms[k].Name}, has died.", "kings");
				Kingdoms[k].King = -1;
				_pendingSuccession.Add((k, i));
			}
	}

	private readonly List<(int kingdom, int old)> _pendingSuccession = new();

	// ------------------------------------------------------------------ the kingdoms, every 2 s

	private void KingdomStep(int a, int b, float dt)
	{
		if (Kingdoms.Count == 0)
			return;
		foreach (var (k, old) in _pendingSuccession)
			if (Kingdoms[k].Alive)
				CrownNewKing(k, old);
		_pendingSuccession.Clear();
		for (int k = 0; k < Kingdoms.Count; k++)
		{
			var kingdom = Kingdoms[k];
			if (!kingdom.Alive)
				continue;
			// A capital lost or emptied: the biggest village left takes its place; none left, the
			// kingdom has fallen.
			if (kingdom.Capital < 0 || !Villages[kingdom.Capital].Alive || Villages[kingdom.Capital].Kingdom != k)
			{
				int best = -1;
				for (int v = 0; v < Villages.Count; v++)
					if (Villages[v].Alive && Villages[v].Kingdom == k && (best < 0 || Villages[v].Population > Villages[best].Population))
						best = v;
				if (best < 0)
				{
					Fall(k);
					continue;
				}
				kingdom.Capital = best;
				LogEvent($"{Villages[best].Name} becomes the capital of {kingdom.Name}.", "kings");
			}
			if (kingdom.King < 0 || !Units.Alive[kingdom.King] || KingdomOfUnit(kingdom.King) != k)
				CrownNewKing(k, -1);
			kingdom.Weariness = Math.Max(0f, kingdom.Weariness - dt / (YearSeconds * 3f));
		}
		RankVillages();
		PlansStep(dt);
		if (Scheduler.Time >= _nextDiplomacy)
		{
			_nextDiplomacy = Scheduler.Time + DiplomacySeconds;
			Diplomacy();
			Loyalty();
		}
		WarStep(dt);
		TradeStep(dt);
	}

	private void Fall(int k)
	{
		var kingdom = Kingdoms[k];
		kingdom.Alive = false;
		foreach (var w in Wars.ToArray())
			if (w.A == k || w.B == k)
				Wars.Remove(w);
		foreach (var o in Kingdoms)
			o.Allies.Remove(k);
		foreach (var p in Plans)
			if (p.Kingdom == k || p.Kind != "rebellion" && p.Target == k)
				p.Alive = false;
		LogEvent($"the kingdom of {kingdom.Name} has fallen.", "kings");
	}

	// ------------------------------------------------------------------ ranks

	/// <summary>camp below 10 people, village below 35, town below 90 (a town hall makes a town
	/// a city past 90), as WorldBox's settlements grow.</summary>
	private int RankOf(int v)
	{
		var village = Villages[v];
		int pop = village.Population;
		if (pop >= 90 && CountOf(v, _tTownHall, true) > 0)
			return 3;
		return pop >= 35 ? 2 : pop >= 10 ? 1 : 0;
	}

	private void RankVillages()
	{
		for (int v = 0; v < Villages.Count; v++)
		{
			var village = Villages[v];
			if (!village.Alive)
				continue;
			int rank = RankOf(v);
			if (rank > village.Rank && rank >= 2)
				LogEvent($"{village.Name} becomes a {RankNames[rank]}.", "cities");
			village.Rank = rank;
		}
	}

	// ------------------------------------------------------------------ diplomacy

	/// <summary>What kingdom a thinks of kingdom b, -100..100: kin peoples like each other,
	/// warlike rulers like no one, borders breed distrust, old wars are remembered, allies trusted.</summary>
	public float Opinion(int a, int b)
	{
		var ka = Kingdoms[a];
		var kb = Kingdoms[b];
		float aggression = Assets.Species[ka.Species].Race?.Temper("aggression") ?? 0.5f;
		float o = ka.Species == kb.Species ? 25f : 0f;
		o -= 40f * aggression;
		o += 10f;
		if (Bordering(a, b))
			o -= 15f;
		if (ka.Allies.Contains(b))
			o += 35f;
		if (AtWar(a, b))
			o -= 50f;
		if (ka.Memory.TryGetValue(b, out float m))
			o += m;
		return Math.Clamp(o, -100f, 100f);
	}

	/// <summary>Whether two kingdoms' villages lie within 45 tiles of each other.</summary>
	public bool Bordering(int a, int b)
	{
		foreach (var va in Villages)
		{
			if (!va.Alive || va.Kingdom != a)
				continue;
			foreach (var vb in Villages)
				if (vb.Alive && vb.Kingdom == b && Math.Abs(va.X - vb.X) + Math.Abs(va.Y - vb.Y) < 45)
					return true;
		}
		return false;
	}

	/// <summary>Whether kingdom a's army could walk to one of b's villages (a land road).</summary>
	public bool CanReach(int a, int b)
	{
		int target = -1;
		float best = float.MaxValue;
		for (int v = 0; v < Villages.Count; v++)
			if (Villages[v].Alive && Villages[v].Kingdom == b)
				foreach (var own in Villages)
					if (own.Alive && own.Kingdom == a && Math.Abs(own.X - Villages[v].X) + Math.Abs(own.Y - Villages[v].Y) < best)
					{
						best = Math.Abs(own.X - Villages[v].X) + Math.Abs(own.Y - Villages[v].Y);
						target = v;
					}
		return target >= 0 && (ArmyPath(a, target) != null || SeaRoute(a, target).path != null);
	}

	/// <summary>Soldiers a kingdom can field.</summary>
	public int Strength(int k)
	{
		int n = 0;
		for (int i = 0; i < Units.Capacity; i++)
			if (Units.Alive[i] && Units.Role[i] == (byte)Role.Warrior && KingdomOfUnit(i) == k)
				n++;
		return n;
	}

	private bool Plotting(string kind, int k, int target) =>
		Plans.Exists(p => p.Alive && p.Kind == kind && p.Kingdom == k && p.Target == target);

	/// <summary>Every season each ruler looks at the neighbours: plots a war against one it
	/// dislikes and is not weaker than, an alliance with one it likes, peace in a long or costly war.</summary>
	private void Diplomacy()
	{
		for (int a = 0; a < Kingdoms.Count; a++)
		{
			var ka = Kingdoms[a];
			if (!ka.Alive || ka.King < 0)
				continue;
			float aggression = Assets.Species[ka.Species].Race?.Temper("aggression") ?? 0.5f;
			bool kingKind = (Units.Traits[ka.King] & (int)Trait.Kind) != 0;
			for (int b = 0; b < Kingdoms.Count; b++)
			{
				if (a == b || !Kingdoms[b].Alive || !Bordering(a, b))
					continue;
				float o = Opinion(a, b);
				var war = WarBetween(a, b);
				if (war != null)
				{
					double years = (Scheduler.Time - war.Started) / YearSeconds;
					if (!Plotting("peace", a, b) && !Plotting("peace", b, a)
						&& (years > 8 || years > 2 && _rng.NextDouble() < 0.15 + ka.Weariness * 0.6))
						StartPlan("peace", a, b, YearSeconds * 0.5f);
					continue;
				}
				if (ka.Allies.Contains(b))
					continue;
				int wars = Wars.FindAll(w => w.A == a || w.B == a).Count;
				if (o < -20f && wars == 0 && !kingKind && !Plotting("war", a, b)
					&& Strength(a) >= Strength(b) * 0.8f && Strength(a) >= 3
					&& _rng.NextDouble() < 0.12 + 0.35 * aggression && CanReach(a, b))
					StartPlan("war", a, b, YearSeconds * (0.6f + 0.6f * (float)_rng.NextDouble()));
				else if (o > 30f && !Plotting("alliance", a, b) && !Plotting("alliance", b, a) && _rng.NextDouble() < 0.3)
					StartPlan("alliance", a, b, YearSeconds * 0.5f);
			}
		}
	}

	private void StartPlan(string kind, int k, int target, float seconds)
	{
		var plan = new KingPlan { Id = _nextPlan++, Kind = kind, Kingdom = k, Target = target, Seconds = seconds };
		Plans.Add(plan);
		var kingdom = Kingdoms[k];
		string ruler = kingdom.King >= 0 ? $"{NameOf(kingdom.King)} of {kingdom.Name}" : kingdom.Name;
		string text = kind switch
		{
			"war" => $"{ruler} plots war against {Kingdoms[target].Name}.",
			"peace" => $"{ruler} seeks peace with {Kingdoms[target].Name}.",
			"alliance" => $"{ruler} courts an alliance with {Kingdoms[target].Name}.",
			_ => $"{Villages[target].Name} plots to break away from {kingdom.Name}.",
		};
		LogEvent(text, kind == "alliance" || kind == "peace" ? "kings" : "wars");
	}

	/// <summary>Plots grow; when one is ripe it happens (unless its reason is gone).</summary>
	private void PlansStep(float dt)
	{
		foreach (var plan in Plans.ToArray())
		{
			if (!plan.Alive)
				continue;
			plan.Progress += dt / plan.Seconds;
			if (plan.Kind == "rebellion" && (!Villages[plan.Target].Alive || Villages[plan.Target].Kingdom != plan.Kingdom
				|| Villages[plan.Target].Loyalty > 15f))
			{
				plan.Alive = false;
				continue;
			}
			if (plan.Progress >= 1f)
				Fulfil(plan);
		}
		Plans.RemoveAll(p => !p.Alive);
	}

	/// <summary>A plan happens now.</summary>
	private void Fulfil(KingPlan plan)
	{
		plan.Alive = false;
		int a = plan.Kingdom, b = plan.Target;
		if (!Kingdoms[a].Alive)
			return;
		switch (plan.Kind)
		{
			case "war":
				if (Kingdoms[b].Alive && !AtWar(a, b))
					DeclareWar(a, b);
				break;
			case "peace":
				MakePeace(a, b);
				break;
			case "alliance":
				if (Kingdoms[b].Alive && !AtWar(a, b))
				{
					Kingdoms[a].Allies.Add(b);
					Kingdoms[b].Allies.Add(a);
					LogEvent($"{Kingdoms[a].Name} and {Kingdoms[b].Name} are now allies.", "kings");
				}
				break;
			case "rebellion":
				Secede(b);
				break;
		}
	}

	/// <summary>Cancels a plot (god powers, 0.9). False if there is no such plan.</summary>
	public bool CancelPlan(int id)
	{
		var plan = Plans.Find(p => p.Id == id && p.Alive);
		if (plan == null)
			return false;
		plan.Alive = false;
		return true;
	}

	/// <summary>Makes a plot happen now (god powers, 0.9).</summary>
	public bool ForcePlan(int id)
	{
		var plan = Plans.Find(p => p.Id == id && p.Alive);
		if (plan == null)
			return false;
		Fulfil(plan);
		return true;
	}

	/// <summary>Starts a plot at once (tests and, later, god powers): "war", "peace", "alliance"
	/// between kingdoms, or "rebellion" of a village. Returns the plan id.</summary>
	public int Plot(string kind, int kingdom, int target)
	{
		StartPlan(kind, kingdom, target, YearSeconds * 0.5f);
		return Plans[^1].Id;
	}

	// ------------------------------------------------------------------ loyalty and rebellions

	/// <summary>Every season: each village's loyalty to its kingdom. Far from the capital, big,
	/// of another people, tired of war, under a dead king: less loyal. Disloyal big villages plot
	/// to break away.</summary>
	private void Loyalty()
	{
		for (int v = 0; v < Villages.Count; v++)
		{
			var village = Villages[v];
			if (!village.Alive || village.Kingdom < 0)
				continue;
			var kingdom = Kingdoms[village.Kingdom];
			if (kingdom.Capital == v)
			{
				village.Loyalty = 100f;
				continue;
			}
			var capital = Villages[kingdom.Capital];
			float dist = MathF.Sqrt((capital.X - village.X) * (capital.X - village.X) + (capital.Y - village.Y) * (capital.Y - village.Y));
			float l = 50f - dist / 2.5f - village.Population / 3.5f + (village.Species == kingdom.Species ? 10f : -20f)
				- kingdom.Weariness * 35f - (kingdom.King < 0 ? 10f : 0f) - village.Conquered * 30f;
			village.Conquered = Math.Max(0f, village.Conquered - 0.05f);
			village.Loyalty = Math.Clamp(village.Loyalty * 0.5f + l * 0.5f + (float)(_rng.NextDouble() * 10 - 5), -100f, 100f);
			// Big disloyal villages plot to break away, at most once every eight years.
			if (village.Loyalty < -5f && village.Population >= 20 && Scheduler.Time >= village.CalmUntil
				&& !Plotting("rebellion", village.Kingdom, v))
				StartPlan("rebellion", village.Kingdom, v, YearSeconds * 0.8f);
		}
	}

	/// <summary>A village breaks away: a new kingdom, its chief the ruler; disloyal villages nearby
	/// join; the old kingdom goes to war to win it back (a civil war when it is the same people).</summary>
	private void Secede(int v)
	{
		var village = Villages[v];
		int old = village.Kingdom;
		if (!village.Alive || old < 0 || Kingdoms[old].Capital == v)
			return;
		village.CalmUntil = Scheduler.Time + YearSeconds * 8;
		int k = CreateKingdom(village.Species, v);
		var rebels = Kingdoms[k];
		int joined = 0;
		for (int o = 0; o < Villages.Count; o++)
		{
			var other = Villages[o];
			if (o != v && other.Alive && other.Kingdom == old && Kingdoms[old].Capital != o && other.Loyalty < 15f
				&& Math.Abs(other.X - village.X) + Math.Abs(other.Y - village.Y) < 40)
			{
				JoinKingdom(o, k);
				joined++;
			}
		}
		bool civil = Kingdoms[old].Species == village.Species;
		LogEvent($"{village.Name} breaks away from {Kingdoms[old].Name}{(joined > 0 ? $" with {joined} more villages" : "")}"
			+ $" and founds the kingdom of {rebels.Name}{(civil ? ": civil war" : "")}!", "wars");
		DeclareWar(old, k, announce: false);
	}

	// ------------------------------------------------------------------ queries (HUD, tests)

	public int KingdomCount() => Kingdoms.FindAll(k => k.Alive).Count;

	/// <summary>Living kingdoms for the HUD: name, people, ruler, dynasty, capital, villages, people,
	/// soldiers, wars, allies, colours and banner.</summary>
	public Godot.Collections.Array KingdomTable()
	{
		var list = new Godot.Collections.Array();
		for (int k = 0; k < Kingdoms.Count; k++)
		{
			var kingdom = Kingdoms[k];
			if (!kingdom.Alive)
				continue;
			int villages = 0, people = 0;
			foreach (var v in Villages)
				if (v.Alive && v.Kingdom == k)
				{
					villages++;
					people += v.Population;
				}
			var wars = new List<string>();
			foreach (var w in Wars)
				if (w.A == k || w.B == k)
					wars.Add(Kingdoms[w.A == k ? w.B : w.A].Name);
			var allies = new List<string>();
			foreach (int al in kingdom.Allies)
				if (Kingdoms[al].Alive)
					allies.Add(Kingdoms[al].Name);
			list.Add(new Godot.Collections.Dictionary
			{
				["index"] = k, ["name"] = kingdom.Name, ["people"] = Assets.Species[kingdom.Species].Name,
				["ruler"] = kingdom.King >= 0 && Units.Alive[kingdom.King] ? $"{(Units.Female[kingdom.King] ? "Queen" : "King")} {NameOf(kingdom.King)} {kingdom.Dynasty}" : "no ruler",
				["dynasty"] = kingdom.Dynasty, ["capital"] = kingdom.Capital >= 0 ? Villages[kingdom.Capital].Name : "",
				["villages"] = villages, ["population"] = people, ["soldiers"] = Strength(k), ["founded"] = kingdom.Founded,
				["wars"] = string.Join(", ", wars), ["allies"] = string.Join(", ", allies), ["color"] = kingdom.Color,
				["banner2"] = kingdom.Banner2, ["division"] = kingdom.Division, ["symbol"] = kingdom.Symbol,
				["kings"] = kingdom.Kings,
			});
		}
		return list;
	}

	/// <summary>What the map writes over each village, every frame (cheap: no counting):
	/// name, x, y, rank, capital, siege.</summary>
	public Godot.Collections.Array VillageLabels()
	{
		var list = new Godot.Collections.Array();
		for (int k = 0; k < Villages.Count; k++)
		{
			var v = Villages[k];
			if (!v.Alive)
				continue;
			list.Add(new Godot.Collections.Dictionary
			{
				["name"] = v.Name, ["x"] = v.X, ["y"] = v.Y, ["rank"] = RankNames[v.Rank],
				["capital"] = v.Kingdom >= 0 && Kingdoms[v.Kingdom].Capital == k, ["siege"] = v.Siege,
			});
		}
		return list;
	}

	/// <summary>Plots under way, for the HUD: id, kind, who, against whom, progress.</summary>
	public Godot.Collections.Array PlanTable()
	{
		var list = new Godot.Collections.Array();
		foreach (var p in Plans)
		{
			if (!p.Alive)
				continue;
			string target = p.Kind == "rebellion" ? Villages[p.Target].Name : Kingdoms[p.Target].Name;
			list.Add(new Godot.Collections.Dictionary
			{
				["id"] = p.Id, ["kind"] = p.Kind, ["kingdom"] = Kingdoms[p.Kingdom].Name, ["target"] = target,
				["progress"] = p.Progress, ["x"] = Villages[p.Kind == "rebellion" ? p.Target : Kingdoms[p.Kingdom].Capital].X,
				["y"] = Villages[p.Kind == "rebellion" ? p.Target : Kingdoms[p.Kingdom].Capital].Y,
			});
		}
		return list;
	}
}
