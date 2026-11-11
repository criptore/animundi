using System;
using System.Collections.Generic;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace Animundi.Sim;

/// <summary>
/// The chronicle written by a mind (0.6, docs/CULTURES.md). The event log records everything;
/// the chronicler keeps the weightiest events (annals) and, every five years, writes a page of
/// history about them, with the local model when one is running, else procedurally. History is
/// cut into named ages ("the Age of Swords", "the Golden Age"…): a new age begins when the mood
/// of the years changes. Warriors who win many fights become heroes, sung in their culture's
/// legends; the chronicle remembers them when they fall.
/// </summary>
public partial class Simulation
{
	public sealed class Page
	{
		public int From, To;
		public string Title, Text, Mind, Mood;
		public int Age = -1;
	}

	public sealed class Age
	{
		public string Name, Mood, Mind;
		public int From, To = -1;
	}

	public sealed class Hero
	{
		public string Name, Epithet;
		public int Unit, Kingdom, Species, Year, Kills;
		public bool Alive = true;
		public int Died = -1;
	}

	/// <summary>A page as written by a mind (JSON), before validation.</summary>
	public sealed class PageDraft
	{
		[JsonPropertyName("title")] public string Title { get; set; } = "";
		[JsonPropertyName("text")] public string Text { get; set; } = "";
		[JsonPropertyName("age")] public string Age { get; set; } = "";
	}

	public readonly List<Page> Pages = new();
	public readonly List<Age> Ages = new();
	public readonly List<Hero> Heroes = new();
	/// <summary>The weightiest events: year, category, text, weight.</summary>
	private readonly List<(int year, string cat, string text, int weight)> _annals = new();
	private readonly Dictionary<int, int> _kills = new();
	private int _chronicledTo = 1;
	/// <summary>A page of the chronicle covers this many years.</summary>
	public const int ChronicleYears = 5;
	/// <summary>An age lasts at least this many years.</summary>
	public const int MinAgeYears = 10;
	/// <summary>Fights a warrior must win to be a hero.</summary>
	public const int HeroKills = 5;
	public int PagesRejected { get; private set; }

	private static readonly string[] Epithets = { "the Bold", "the Red", "Ironhand", "the Unbroken", "Wolfheart", "the Fearless", "Spearstorm", "the Grim", "Shieldbreaker", "the Swift" };

	private void SetupChronicle()
	{
		Pages.Clear();
		Ages.Clear();
		Heroes.Clear();
		_annals.Clear();
		_kills.Clear();
		_chronicledTo = 1;
	}

	// ------------------------------------------------------------------ annals

	/// <summary>How much an event weighs in history (0: not kept), from its category and words.</summary>
	private static int Weight(string cat, string text)
	{
		if (cat == "life")
			return text.Contains("extinct") ? 2 : 0;
		int w = cat switch { "wars" => 2, "kings" => 1, "cities" => 1, "disasters" => 1, "faith" => 2, "culture" => 1, "inventions" => 0, _ => 0 };
		if (text.Contains("has fallen") || text.Contains("breaks away") || text.Contains("schism"))
			w += 4;
		else if (text.Contains("declares war") || text.Contains(" takes ") || text.Contains("new god") || text.Contains("hero"))
			w += 3;
		else if (text.Contains("dynasty begins") || text.Contains("becomes a city") || text.Contains("peace between") || text.Contains("meteor") || text.Contains("have seen you") || text.Contains("turns from"))
			w += 2;
		else if (text.Contains("allies") || text.Contains("becomes a town") || text.Contains("invent the") || text.Contains("adopt a") || text.Contains("now hold"))
			w += 1;
		else if (text.Contains("plots") || text.Contains("seeks peace") || text.Contains("courts") || text.Contains("copies") || text.Contains("builds a") || text.Contains("marches") || text.Contains("sets sail"))
			w = 0;
		return w;
	}

	/// <summary>Keeps an event in the annals if it weighs anything (with LogEvent).</summary>
	private void NoteAnnal(string cat, string text)
	{
		int w = Weight(cat, text);
		if (w <= 0)
			return;
		_annals.Add((Year(), cat, text, w));
		if (_annals.Count > 600)
			_annals.RemoveRange(0, 200);
	}

	// ------------------------------------------------------------------ heroes

	/// <summary>Person i struck down person j in a fight: five victories make a hero.</summary>
	private void CountKill(int i, int j)
	{
		if (i < 0 || !Units.Alive[i] || !Assets.Species[Units.Species[i]].IsPeople)
			return;
		int kills = (_kills.TryGetValue(i, out int n) ? n : 0) + 1;
		_kills[i] = kills;
		var hero = Heroes.Find(h => h.Alive && h.Unit == i);
		if (hero != null)
		{
			hero.Kills = kills;
			return;
		}
		if (kills < HeroKills)
			return;
		int k = KingdomOfUnit(i);
		hero = new Hero
		{
			Name = NameOf(i), Epithet = Epithets[_rng.Next(Epithets.Length)], Unit = i, Kingdom = k,
			Species = Units.Species[i], Year = Year(), Kills = kills,
		};
		Heroes.Add(hero);
		string of = k >= 0 ? $" of {Kingdoms[k].Name}" : "";
		LogEvent($"{hero.Name}{of} is hailed as a hero after {kills} victories: {hero.Name} {hero.Epithet}.", "wars");
		AddLegend(k, $"the Song of {hero.Name} {hero.Epithet}");
	}

	/// <summary>When a person dies (PersonDied): a hero is mourned, the count of victories forgotten.</summary>
	private void HeroDied(int i)
	{
		_kills.Remove(i);
		var hero = Heroes.Find(h => h.Alive && h.Unit == i);
		if (hero == null)
			return;
		hero.Alive = false;
		hero.Died = Year();
		LogEvent($"the hero {hero.Name} {hero.Epithet} has died, after {hero.Kills} victories.", "wars");
	}

	// ------------------------------------------------------------------ the chronicler

	/// <summary>Every 2 s with the kingdoms: once five years have passed, a page is written.</summary>
	private void ChronicleStep()
	{
		if (Year() - _chronicledTo < ChronicleYears)
			return;
		WritePage(_chronicledTo, Year());
		_chronicledTo = Year();
	}

	/// <summary>The mood of years from-to by what weighed most in them: war, ruin, disaster,
	/// faith, wonder, growth or quiet.</summary>
	private string Mood(List<(int year, string cat, string text, int weight)> events)
	{
		var score = new Dictionary<string, int>();
		bool fell = false;
		foreach (var e in events)
		{
			string mood = e.cat switch
			{
				"wars" => "war", "disasters" => "disaster", "faith" => "faith", "culture" => "faith",
				"inventions" => "wonder", "cities" => "growth", "kings" => "growth", _ => "quiet",
			};
			score[mood] = (score.TryGetValue(mood, out int s) ? s : 0) + e.weight;
			fell |= e.text.Contains("has fallen");
		}
		if (fell && score.TryGetValue("war", out int war) && war >= 8)
			return "ruin";
		string best = "quiet";
		int most = 4;
		foreach (var (mood, s) in score)
			if (s > most)
			{
				most = s;
				best = mood;
			}
		return best;
	}

	private static readonly Dictionary<string, string[]> AgeNames = new()
	{
		["war"] = new[] { "the Age of Swords", "the Age of Spears", "the Age of Banners", "the Red Age", "the Age of Iron Rain" },
		["ruin"] = new[] { "the Age of Ruins", "the Age of Fallen Crowns", "the Ashen Age" },
		["disaster"] = new[] { "the Age of Ash", "the Age of Storms", "the Burning Age", "the Age of Omens" },
		["faith"] = new[] { "the Age of Prophets", "the Age of Temples", "the Age of Gods" },
		["wonder"] = new[] { "the Age of Wonders", "the Age of Craft", "the Age of Tools" },
		["growth"] = new[] { "the Age of Towns", "the Age of Plenty", "the Golden Age", "the Age of Crowns" },
		["quiet"] = new[] { "the Quiet Age", "the Age of Long Summers", "the Still Age" },
	};

	private static readonly Dictionary<string, string[]> PageOpenings = new()
	{
		["war"] = new[] { "Steel decided the fate of these years.", "These were years of war.", "Drums did not fall silent in these years." },
		["ruin"] = new[] { "Crowns fell in these years, and the land remembers.", "These were years of ruin." },
		["disaster"] = new[] { "The world itself turned against its peoples.", "Fire and sky ruled these years." },
		["faith"] = new[] { "The gods were close in these years.", "These were years of prayer and of new ways." },
		["wonder"] = new[] { "Clever hands changed the world in these years.", "These were years of new things." },
		["growth"] = new[] { "The peoples grew and prospered.", "These were years of building." },
		["quiet"] = new[] { "Little troubled the world in these years.", "These were quiet years." },
	};

	private static readonly Dictionary<string, string> PageTitles = new()
	{
		["war"] = "Years of War", ["ruin"] = "Years of Ruin", ["disaster"] = "The Burning Years", ["faith"] = "Years of Faith",
		["wonder"] = "Years of Wonders", ["growth"] = "Years of Growth", ["quiet"] = "Quiet Years",
	};

	/// <summary>Writes the page of years from-to: picks its events and its mood, opens a new age
	/// when the mood has changed (and the age is old enough), then asks the model for the text,
	/// or writes it procedurally.</summary>
	private void WritePage(int from, int to)
	{
		var events = _annals.FindAll(e => e.year >= from && e.year < to);
		string mood = Mood(events);
		// Ages: the first begins with the world; a new one when the mood changes.
		bool newAge = false;
		if (Ages.Count == 0)
		{
			Ages.Add(new Age { Name = "the Age of Beginnings", Mood = "growth", Mind = "procedural", From = 1 });
		}
		var age = Ages[^1];
		if (mood != age.Mood && mood != "quiet" && to - age.From >= MinAgeYears || to - age.From >= 60)
		{
			age.To = from;
			string name = AgeNames[mood][_rng.Next(AgeNames[mood].Length)];
			int again = Ages.FindAll(a => a.Name.EndsWith(name[4..])).Count;
			if (again > 0)
				name = $"the {(again == 1 ? "Second" : again == 2 ? "Third" : "Last")} {name[4..]}";
			Ages.Add(new Age { Name = name, Mood = mood, Mind = "procedural", From = from });
			newAge = true;
			LogEvent($"{Capital(name)} begins.", "culture");
		}
		var page = new Page { From = from, To = to, Mood = mood, Age = Ages.Count - 1, Mind = "procedural" };
		ProceduralPage(page, events);
		Pages.Add(page);
		if (Pages.Count > 200)
			Pages.RemoveAt(0);
		if (events.Count == 0)
			return;
		// The model may write it better (and name the new age); the procedural page stands meanwhile.
		int ageIndex = Ages.Count - 1;
		Ponder("chronicle", ChroniclePrompt(from, to, events, newAge ? Ages[ageIndex] : null), ChronicleGrammar(), ChronicleSchema(),
			"You are the chronicler of a world simulation. Answer with one JSON record.", 420,
			json => SubmitPageJson(page, json, newAge ? ageIndex : -1),
			() => { });
	}

	private static string Capital(string s) => s.Length > 0 ? char.ToUpperInvariant(s[0]) + s[1..] : s;

	/// <summary>"Year 12, spring: X." → "X" with its first letter as it should be mid-sentence.</summary>
	private static string Bare(string line)
	{
		int colon = line.IndexOf(": ");
		string s = colon >= 0 && line.StartsWith("Year ") ? line[(colon + 2)..] : line;
		if (s.StartsWith("The "))
			s = "the " + s[4..];
		return s.TrimEnd('.', '!', ' ');
	}

	/// <summary>A page written from the annals: an opening by mood, the weightiest events in
	/// order, the heroes and myths of those years.</summary>
	private void ProceduralPage(Page page, List<(int year, string cat, string text, int weight)> events)
	{
		page.Title = PageTitles[page.Mood];
		var sb = new StringBuilder();
		var open = PageOpenings[page.Mood];
		sb.Append(open[_rng.Next(open.Length)]);
		if (events.Count == 0)
			sb.Append(" Nothing worth a song happened.");
		var top = new List<(int year, string cat, string text, int weight)>(events);
		top.Sort((a, b) => b.weight != a.weight ? b.weight.CompareTo(a.weight) : a.year.CompareTo(b.year));
		if (top.Count > 5)
			top.RemoveRange(5, top.Count - 5);
		top.Sort((a, b) => a.year.CompareTo(b.year));
		string[] links = { "In year {0}, ", "Then, in year {0}, ", "In year {0}, ", "Later, in year {0}, ", "At last, in year {0}, " };
		for (int n = 0; n < top.Count; n++)
		{
			string bare = Bare(top[n].text);
			sb.Append(' ').Append(string.Format(links[n], top[n].year)).Append(bare).Append('.');
		}
		foreach (var h in Heroes)
			if (h.Year >= page.From && h.Year < page.To)
			{
				sb.Append($" Songs began to be sung of {h.Name} {h.Epithet}.");
				break;
			}
		page.Text = sb.ToString();
	}

	/// <summary>A mind's page (JSON) for the years of `page`: replaces the procedural text; when
	/// `age` is set, it names the age that began. Returns null or why it was rejected.</summary>
	private string SubmitPageJson(Page page, string json, int age)
	{
		PageDraft d;
		try
		{
			d = JsonSerializer.Deserialize<PageDraft>(json);
		}
		catch (Exception e)
		{
			PagesRejected++;
			return "not valid JSON: " + e.Message;
		}
		string error = d == null ? "empty"
			: !PlainName(d.Title, 48) ? "title must be 2-48 letters"
			: !PlainText(d.Text, 700) || d.Text.Trim().Length < 40 ? "text must be 40-700 plain characters"
			: age >= 0 && !string.IsNullOrEmpty(d.Age) && !PlainName(d.Age, 40) ? "age must be 2-40 letters"
			: null;
		if (error != null)
		{
			PagesRejected++;
			return error;
		}
		page.Title = d.Title.Trim();
		page.Text = d.Text.Trim();
		page.Mind = "model";
		if (age >= 0 && age < Ages.Count && !string.IsNullOrWhiteSpace(d.Age))
		{
			string name = d.Age.Trim();
			Ages[age].Name = name.StartsWith("The ") ? "t" + name[1..] : name;
			Ages[age].Mind = "model";
		}
		return null;
	}

	/// <summary>Writes a page the usual way, from a mind's JSON (tests): the last page's years.</summary>
	public string SubmitChronicleJson(string json)
	{
		if (Pages.Count == 0)
			return "no page yet";
		return SubmitPageJson(Pages[^1], json, -1);
	}

	private string ChroniclePrompt(int from, int to, List<(int year, string cat, string text, int weight)> events, Age newAge)
	{
		var sb = new StringBuilder();
		sb.Append($"Write the page of the chronicle for the years {from} to {to} of this world, as a chronicler of old would: ");
		sb.Append("two to five sentences of history, in the past tense, naming the kingdoms, rulers, heroes and gods involved. Only tell what happened.\n");
		sb.Append("The kingdoms: ");
		foreach (var k in Kingdoms)
			if (k.Alive)
				sb.Append($"{k.Name} ({Assets.Species[k.Species].Name}); ");
		sb.Append("\nWhat happened:\n");
		var top = new List<(int year, string cat, string text, int weight)>(events);
		top.Sort((a, b) => b.weight.CompareTo(a.weight));
		for (int n = 0; n < top.Count && n < 12; n++)
			sb.Append($"- year {top[n].year}: {Bare(top[n].text)}\n");
		if (newAge != null)
			sb.Append($"A new age begins with these years (its mood: {newAge.Mood}). Give it a name of 2-40 letters in \"age\", like \"the Age of Swords\".\n");
		else
			sb.Append("Leave \"age\" empty.\n");
		sb.Append("A title of 2-48 letters. Answer with the JSON record only.\n");
		return sb.ToString();
	}

	public static string ChronicleGrammar() => string.Join("\n", new[]
	{
		$"root ::= \"{{\" ws {GbnfKey("title")} name \",\" ws {GbnfKey("text")} text \",\" ws {GbnfKey("age")} (name | \"\\\"\\\"\") ws \"}}\"",
	}) + "\n" + GbnfCommon(600);

	public static string ChronicleSchema() => SchemaJson(new Dictionary<string, object>
	{
		["type"] = "object", ["required"] = new[] { "title", "text", "age" },
		["properties"] = new Dictionary<string, object> { ["title"] = StringSchema(48), ["text"] = StringSchema(700), ["age"] = StringSchema(40) },
	});

	// ------------------------------------------------------------------ queries (HUD, tests)

	/// <summary>The written chronicle, newest page first: years, title, text, age, mind.</summary>
	public Godot.Collections.Array ChronicleTable()
	{
		var list = new Godot.Collections.Array();
		for (int n = Pages.Count - 1; n >= 0; n--)
		{
			var p = Pages[n];
			list.Add(new Godot.Collections.Dictionary
			{
				["from"] = p.From, ["to"] = p.To, ["title"] = p.Title, ["text"] = p.Text, ["mood"] = p.Mood, ["mind"] = p.Mind,
				["age"] = p.Age >= 0 && p.Age < Ages.Count ? Ages[p.Age].Name : "",
			});
		}
		return list;
	}

	/// <summary>The ages of the world, oldest first: name, from, to (-1 for the current one), mood.</summary>
	public Godot.Collections.Array AgeTable()
	{
		var list = new Godot.Collections.Array();
		foreach (var a in Ages)
			list.Add(new Godot.Collections.Dictionary { ["name"] = a.Name, ["from"] = a.From, ["to"] = a.To, ["mood"] = a.Mood, ["mind"] = a.Mind });
		return list;
	}

	/// <summary>The current age's name ("" before the first page).</summary>
	public string CurrentAge() => Ages.Count > 0 ? Capital(Ages[^1].Name) : "";

	/// <summary>Heroes, newest first: name, epithet, kingdom, victories, alive, years.</summary>
	public Godot.Collections.Array HeroTable()
	{
		var list = new Godot.Collections.Array();
		for (int n = Heroes.Count - 1; n >= 0; n--)
		{
			var h = Heroes[n];
			list.Add(new Godot.Collections.Dictionary
			{
				["name"] = $"{h.Name} {h.Epithet}", ["kingdom"] = h.Kingdom >= 0 ? Kingdoms[h.Kingdom].Name : "",
				["people"] = Assets.Species[h.Species].Name, ["kills"] = h.Kills, ["alive"] = h.Alive, ["year"] = h.Year, ["died"] = h.Died,
				["unit"] = h.Alive ? h.Unit : -1,
			});
		}
		return list;
	}

	/// <summary>Writes the chronicle's page now for the years not yet written (tests).</summary>
	public void ChronicleNow()
	{
		if (Year() > _chronicledTo)
		{
			WritePage(_chronicledTo, Year());
			_chronicledTo = Year();
		}
	}

	/// <summary>Counts a victory for person i over j (tests: making a hero).</summary>
	public void CountKillNow(int i, int j) => CountKill(i, j);
}
