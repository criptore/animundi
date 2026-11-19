using System;
using System.Collections.Generic;
using System.Text.Json;
using Godot;

namespace Animundi.Sim;

/// <summary>
/// What the interface shows about the world (0.9, docs/POWERS.md): the inspector's cards for a
/// kingdom, a species, a spirit and an invention; the political map layers (kingdoms, cultures,
/// religions, peoples, alliances, wars); and the world's statistics, a line a year.
/// </summary>
public partial class Simulation
{
	/// <summary>The political map layers: a colour per tile of owned land.</summary>
	public static readonly string[] PoliticalLayers = { "Kingdoms", "Cultures", "Religions", "Peoples", "Alliances", "Wars" };

	// ------------------------------------------------------------------ cards

	/// <summary>A kingdom's card: name, people, ruler, capital, founded, villages, population,
	/// soldiers, age, knowledge, wars, allies, faith, creed, values, culture's customs, designs,
	/// feats, opinions of the others. Empty for a fallen or unknown kingdom.</summary>
	public Godot.Collections.Dictionary KingdomInfo(int k)
	{
		if (k < 0 || k >= Kingdoms.Count || !Kingdoms[k].Alive)
			return new Godot.Collections.Dictionary();
		Godot.Collections.Dictionary row = null;
		foreach (var r in KingdomTable())
			if (r.AsGodotDictionary()["index"].AsInt32() == k)
				row = r.AsGodotDictionary();
		if (row == null)
			return new Godot.Collections.Dictionary();
		var kingdom = Kingdoms[k];
		var c = kingdom.Culture;
		var values = new List<(float v, string n)>();
		for (int n = 0; n < ValueNames.Length; n++)
			values.Add((c.Values[n], ValueNames[n]));
		values.Sort((a, b) => b.v.CompareTo(a.v));
		var opinions = new List<string>();
		foreach (var (o, m) in kingdom.Memory)
			if (o >= 0 && o < Kingdoms.Count && Kingdoms[o].Alive && Math.Abs(m) >= 10f)
				opinions.Add($"{Kingdoms[o].Name} {(m > 0 ? "liked" : "hated")} ({m:+0;-0})");
		var customs = new List<string>();
		foreach (var cu in c.Customs)
			customs.Add(cu.Name);
		row["values"] = $"{values[0].n}, {values[1].n}, {values[2].n}";
		row["creed"] = c.Creed;
		row["faith"] = c.Faith;
		row["customs"] = string.Join(", ", customs);
		row["opinions"] = string.Join("; ", opinions);
		row["designs"] = $"{KingdomDesign(k, "vehicle")}, {KingdomDesign(k, "ship")}, {KingdomDesign(k, "home")}, {KingdomDesign(k, "weapon")}";
		row["feats"] = string.Join("\n", kingdom.Feats.Count > 3 ? kingdom.Feats.GetRange(kingdom.Feats.Count - 3, 3) : kingdom.Feats);
		row["stance"] = c.Stance;
		row["god_name"] = c.GodName;
		return row;
	}

	/// <summary>A species' card: id, name, alive, habitat (biomes), diet, size, lifespan, speed,
	/// people (bool), legend, mutation (its strain's name), capacity, born and dead so far.</summary>
	public Godot.Collections.Dictionary SpeciesInfo(string nameOrId)
	{
		int s = Assets.SpeciesIndex(nameOrId);
		if (s < 0)
			s = Assets.Species.FindIndex(r => r.Name == nameOrId);
		if (s < 0)
			return new Godot.Collections.Dictionary();
		var sp = Assets.Species[s];
		var strain = StrainOf(s);
		return new Godot.Collections.Dictionary
		{
			["id"] = sp.Id, ["name"] = sp.Name, ["alive"] = Population[s], ["habitat"] = string.Join(", ", sp.Natural.Keys),
			["diet"] = sp.Diet, ["size"] = sp.Size, ["lifespan"] = sp.Lifespan, ["speed"] = sp.Speed, ["people"] = sp.IsPeople,
			["legend"] = sp.IsLegend, ["capacity"] = Capacity.Length > s && Capacity[s] < int.MaxValue ? Capacity[s] : 0,
			["strain"] = strain != null && strain.Mutations.Count > 0 ? string.Join(", ", strain.Mutations) : "", ["sprite"] = sp.Sprite ?? sp.Id,
		};
	}

	/// <summary>The spirit whose land is at (x, y): its row of SpiritTable, or empty.</summary>
	public Godot.Collections.Dictionary SpiritInfoAt(float x, float y)
	{
		int s = SpiritAt(x, y);
		return s >= 0 ? SpiritTable()[s].AsGodotDictionary() : new Godot.Collections.Dictionary();
	}

	/// <summary>An invention's card: its row of InventionTable, with its record in the invention
	/// language (script) and its lineage, eldest first.</summary>
	public Godot.Collections.Dictionary InventionInfo(int id)
	{
		if (id < 0 || id >= Inventions.Count)
			return new Godot.Collections.Dictionary();
		Godot.Collections.Dictionary row = null;
		foreach (var r in InventionTable())
			if (r.AsGodotDictionary()["id"].AsInt32() == id)
				row = r.AsGodotDictionary();
		var inv = Inventions[id];
		var cost = new Dictionary<string, float>(inv.Cost);
		var effects = new List<Dictionary<string, object>>();
		foreach (var e in inv.Effects)
		{
			var d = new Dictionary<string, object> { ["do"] = e.Do, ["amount"] = Math.Round(e.Amount, 1) };
			if (!string.IsNullOrEmpty(e.Job))
				d["job"] = e.Job;
			effects.Add(d);
		}
		row["script"] = JsonSerializer.Serialize(new Dictionary<string, object>
		{
			["name"] = inv.Name, ["kind"] = inv.Kind, ["improves"] = inv.Parent >= 0 ? Inventions[inv.Parent].Name : "",
			["cost"] = cost, ["effects"] = effects,
		}, new JsonSerializerOptions { WriteIndented = true });
		var line = new List<string>();
		for (int p = id; p >= 0 && line.Count < 12; p = Inventions[p].Parent)
			line.Insert(0, $"{Inventions[p].Name} (year {Inventions[p].Year})");
		row["lineage"] = string.Join(" → ", line);
		int children = Inventions.FindAll(x => x.Parent == id).Count;
		row["children"] = children;
		return row;
	}

	// ------------------------------------------------------------------ political layers

	/// <summary>A colour per tile for a political layer (PoliticalLayers): 0xRRGGBBAA, 0 for land no
	/// kingdom owns. Kingdoms: their colour; cultures: a colour from what they prize most;
	/// religions: one per faith; peoples: their people's colour; alliances: one per group of allies;
	/// wars: red for kingdoms at war, the front (land near a foe's) brighter.</summary>
	public int[] LayerColors(string layer)
	{
		if (World == null)
			return Array.Empty<int>();
		var byKingdom = new Dictionary<int, Color>();
		for (int k = 0; k < Kingdoms.Count; k++)
			if (Kingdoms[k].Alive)
				byKingdom[k] = KingdomLayerColor(k, layer);
		var map = new int[World.Width * World.Height];
		for (int t = 0; t < map.Length; t++)
		{
			int o = _zoneOwner[ZoneOf(t % World.Width, t / World.Width)];
			if (o < 0 || Villages[o].Kingdom < 0 || !byKingdom.TryGetValue(Villages[o].Kingdom, out var c))
				continue;
			if (layer == "Wars" && c.A > 0.5f && Front(t, Villages[o].Kingdom))
				c = c.Lightened(0.35f);
			map[t] = (int)(((uint)(c.R * 255f) << 24) | ((uint)(c.G * 255f) << 16) | ((uint)(c.B * 255f) << 8) | 255u);
		}
		return map;
	}

	private static Color Hashed(int n) => Color.FromHsv((n * 0.61803f) % 1f, 0.55f, 0.85f);

	private Color KingdomLayerColor(int k, string layer)
	{
		var kingdom = Kingdoms[k];
		switch (layer)
		{
			case "Cultures":
			{
				// The hue of what they prize most, shaded by the second.
				var v = kingdom.Culture.Values;
				int first = 0, second = 1;
				for (int n = 0; n < v.Length; n++)
					if (v[n] > v[first])
						first = n;
				second = first == 0 ? 1 : 0;
				for (int n = 0; n < v.Length; n++)
					if (n != first && v[n] > v[second])
						second = n;
				return Color.FromHsv(first / (float)v.Length, 0.45f + 0.1f * second / v.Length, 0.65f + 0.3f * second / v.Length);
			}
			case "Religions":
				return Hashed(kingdom.Culture.Religion + 3);
			case "Peoples":
				return new Color(Assets.Species[kingdom.Species].Race?.Color ?? Assets.Species[kingdom.Species].Color ?? "#ffffff");
			case "Alliances":
			{
				// The smallest index of the group of allies it belongs to.
				int root = k;
				var seen = new HashSet<int> { k };
				var stack = new Stack<int>();
				stack.Push(k);
				while (stack.Count > 0)
				{
					int a = stack.Pop();
					root = Math.Min(root, a);
					foreach (int b in Kingdoms[a].Allies)
						if (b < Kingdoms.Count && Kingdoms[b].Alive && seen.Add(b))
							stack.Push(b);
				}
				return seen.Count > 1 ? Hashed(root + 11) : new Color(0.55f, 0.55f, 0.58f);
			}
			case "Wars":
				return Wars.Exists(w => w.A == k || w.B == k) ? new Color(0.78f, 0.18f, 0.2f) : new Color(0.5f, 0.55f, 0.5f, 0.4f);
			default:
				return kingdom.Color;
		}
	}

	/// <summary>Whether tile t of kingdom k lies within 6 tiles of land of a kingdom it is at war with.</summary>
	private bool Front(int t, int k)
	{
		int x = t % World.Width, y = t / World.Width;
		for (int dy = -6; dy <= 6; dy += 3)
			for (int dx = -6; dx <= 6; dx += 3)
			{
				if (!World.InBounds(x + dx, y + dy))
					continue;
				int o = _zoneOwner[ZoneOf(x + dx, y + dy)];
				if (o >= 0 && Villages[o].Kingdom >= 0 && Villages[o].Kingdom != k && AtWar(k, Villages[o].Kingdom))
					return true;
			}
		return false;
	}

	/// <summary>Who is at war with whom, as lines between capitals for the map: [x0, y0, x1, y1, ...]
	/// in tiles.</summary>
	public float[] WarLines()
	{
		var lines = new List<float>();
		foreach (var w in Wars)
		{
			if (w.A < 0 || w.B < 0 || !Kingdoms[w.A].Alive || !Kingdoms[w.B].Alive || Kingdoms[w.A].Capital < 0 || Kingdoms[w.B].Capital < 0)
				continue;
			var a = Villages[Kingdoms[w.A].Capital];
			var b = Villages[Kingdoms[w.B].Capital];
			lines.AddRange(new[] { a.X + 0.5f, a.Y + 0.5f, b.X + 0.5f, b.Y + 0.5f });
		}
		return lines.ToArray();
	}

	// ------------------------------------------------------------------ statistics

	/// <summary>The world's numbers, once a year: year, people, villages, kingdoms, animals,
	/// plants, wars, inventions, highest age, warming.</summary>
	private readonly List<float[]> _history = new();
	public static readonly string[] HistoryColumns = { "year", "people", "villages", "kingdoms", "animals", "plants", "wars", "inventions", "age", "warming" };
	private int _historyYear;

	private void SetupHistory()
	{
		_history.Clear();
		_historyYear = 0;
	}

	/// <summary>Every second with the eras: a line of history at the turn of each year.</summary>
	private void HistoryStep()
	{
		int year = Year();
		if (year == _historyYear)
			return;
		_historyYear = year;
		RecordHistory();
	}

	private void RecordHistory()
	{
		int people = PeopleCount(), age = 0;
		foreach (var k in Kingdoms)
			if (k.Alive)
				age = Math.Max(age, k.Age);
		int inventions = Inventions.FindAll(i => !i.Lost).Count;
		_history.Add(new float[] { Year(), people, VillageCount(), KingdomCount(), Units.Count - people, PlantCount(), Wars.Count, inventions, age, Warming });
		// A long history keeps every year of the last 200, then one in five.
		if (_history.Count > 400)
			for (int n = _history.Count - 201; n >= 0; n -= 5)
				if (n % 5 != 0)
					_history.RemoveAt(n);
	}

	/// <summary>The statistics: column → its values, a value a recorded year.</summary>
	public Godot.Collections.Dictionary History()
	{
		var d = new Godot.Collections.Dictionary();
		for (int c = 0; c < HistoryColumns.Length; c++)
		{
			var col = new float[_history.Count];
			for (int r = 0; r < _history.Count; r++)
				col[r] = _history[r][c];
			d[HistoryColumns[c]] = col;
		}
		return d;
	}

	/// <summary>Records a line of history now (tests).</summary>
	public void RecordHistoryNow() => RecordHistory();
}
