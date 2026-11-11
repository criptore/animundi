using System;
using System.Collections.Generic;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace Animundi.Sim;

/// <summary>
/// The chronicle (0.6, docs/CULTURE.md). Every event of the log is kept in the annals. Every
/// five years a chronicler writes a chapter from the annals of those years: the local model
/// when there is one (a JSON record: title, text, a name for the age), else a procedural
/// chronicler that picks the events that mattered most. Ages are named after what filled the
/// last ten years (wars, disasters, inventions, gods, heroes...): "The Age of Ash".
///
/// Heroes: a warrior who slays four foes in war is hailed a hero, told in the chronicle and
/// remembered by the kingdom (its myths may be about them).
/// </summary>
public partial class Simulation
{
	public sealed class Chapter
	{
		public int From, To;
		public string Title, Text, Mind, Age;
	}

	public sealed class Age
	{
		public string Name, Theme;
		public int From;
	}

	public sealed class ChapterDraft
	{
		[JsonPropertyName("title")] public string Title { get; set; } = "";
		[JsonPropertyName("text")] public string Text { get; set; } = "";
		[JsonPropertyName("age")] public string Age { get; set; } = "";
	}

	public const int ChapterYears = 5;
	public const int AgeYears = 10;
	public const int HeroKills = 4;

	private readonly List<(int year, string cat, string text)> _annals = new();
	public readonly List<Chapter> Chapters = new();
	public readonly List<Age> Ages = new();
	private readonly HashSet<int> _heroes = new();
	private double _nextChapter;
	private Question _chapterAsking;
	private (int from, int to) _chapterAsked;

	/// <summary>How much each kind of event weighs when an age is named.</summary>
	private static readonly Dictionary<string, float> ThemeWeights = new()
	{
		["wars"] = 4f, ["disasters"] = 3f, ["heroes"] = 3f, ["kings"] = 2f, ["cities"] = 2f, ["inventions"] = 1f, ["culture"] = 0.75f, ["life"] = 1f,
	};

	/// <summary>What an event weighs: its kind's weight; a wildfire far from anyone and the
	/// daily life of villages (a new building) weigh little.</summary>
	private static float EventWeight(string cat, string text)
	{
		if (text.StartsWith("lightning sets") || text.Contains(" builds "))
			return 0.5f;
		return ThemeWeights.TryGetValue(cat, out float w) ? w : 1f;
	}

	private static readonly Dictionary<string, (string[] ages, string title)> Themes = new()
	{
		["wars"] = (new[] { "Blades", "Banners", "Blood", "Iron" }, "Blades and Banners"),
		["disasters"] = (new[] { "Ash", "Storms", "Embers", "Ruin" }, "Fire and Ruin"),
		["heroes"] = (new[] { "Heroes", "Songs", "Champions" }, "Songs of the Brave"),
		["culture"] = (new[] { "Gods", "Omens", "Prayers", "Customs" }, "Gods and Customs"),
		["kings"] = (new[] { "Crowns", "Thrones", "Heirs" }, "Crowns Passing"),
		["cities"] = (new[] { "Stone", "Hearths", "Walls" }, "Walls Rising"),
		["inventions"] = (new[] { "Makers", "Wonders", "Craft" }, "The Makers' Years"),
		["life"] = (new[] { "Silence", "Beasts", "Seasons" }, "The Turning Seasons"),
		["quiet"] = (new[] { "Plenty", "Calm", "Sleep" }, "Quiet Years"),
	};

	private void SetupChronicle()
	{
		_annals.Clear();
		Chapters.Clear();
		Ages.Clear();
		_heroes.Clear();
		_chapterAsking = null;
		_nextChapter = ChapterYears * YearSeconds;
		Ages.Add(new Age { Name = "The Age of Dawn", Theme = "dawn", From = 1 });
	}

	private void Annal(string cat, string text)
	{
		_annals.Add((Year(), cat, text));
		if (_annals.Count > 6000)
			_annals.RemoveRange(0, 2000);
	}

	public string AgeName() => Ages.Count > 0 ? Ages[^1].Name : "";

	// ------------------------------------------------------------------ heroes

	/// <summary>Person i killed a foe in war: the fourth makes a hero.</summary>
	private void WarKill(int i)
	{
		if (!Units.Alive[i] || ++Units.Kills[i] != HeroKills)
			return;
		int k = KingdomOfUnit(i);
		if (k < 0 || !_heroes.Add(i))
			return;
		string from = Villages[Units.Village[i]].Name;
		LogEvent($"{NameOf(i)} of {from} is hailed a hero of {Kingdoms[k].Name}, with {HeroKills} foes slain.", "heroes");
		Remember(k, "hero", $"{NameOf(i)} of {from} slew {HeroKills} foes and was hailed a hero", 1.5f);
	}

	/// <summary>When a person dies: a hero's death is told.</summary>
	private void HeroDied(int i)
	{
		if (_heroes.Remove(i) && Units.Village[i] >= 0)
			LogEvent($"{NameOf(i)}, hero of {Villages[Units.Village[i]].Name}, has died.", "heroes");
	}

	// ------------------------------------------------------------------ chapters and ages

	private void ChronicleStep()
	{
		if (_chapterAsking != null)
		{
			if (!_chapterAsking.Take(Scheduler.Time, out string json, out string why))
				return;
			_chapterAsking = null;
			string error = json == null ? why : SubmitChapterJson(json, _chapterAsked.from, _chapterAsked.to, "model");
			LastModelAnswer = json ?? "";
			LastModelError = error ?? "";
			if (string.IsNullOrEmpty(error))
				ModelAnswers++;
			else
			{
				ModelFailures++;
				AddChapter(ProceduralChapter(_chapterAsked.from, _chapterAsked.to), _chapterAsked.from, _chapterAsked.to, "procedural");
			}
			return;
		}
		if (Scheduler.Time >= _nextChapter)
			WriteChapter(force: false);
	}

	/// <summary>The chapter of the years since the last one, up to last year (this year when
	/// forced): the model in the background, or the procedural chronicler now.</summary>
	private void WriteChapter(bool force)
	{
		_nextChapter = Scheduler.Time + ChapterYears * YearSeconds;
		int to = force ? Year() : Math.Max(1, Year() - 1);
		int from = Math.Min(to, Chapters.Count > 0 ? Chapters[^1].To + 1 : 1);
		if (!force)
		{
			var task = AskAnyMind(ChapterPrompt(from, to), ChapterGrammar(), ChapterSchema(),
				"You are the chronicler of a world simulation. Answer with one JSON record.");
			if (task != null)
			{
				_chapterAsking = new Question { Pending = task, Asked = Scheduler.Time };
				_chapterAsked = (from, to);
				return;
			}
		}
		AddChapter(ProceduralChapter(from, to), from, to, "procedural");
	}

	/// <summary>Plots are news while they brew, not history.</summary>
	private static bool IsRumour(string text) => text.Contains(" plots ") || text.Contains(" seeks peace ") || text.Contains(" courts an alliance ");

	private List<(int year, string cat, string text)> AnnalsOf(int from, int to) =>
		_annals.FindAll(a => a.year >= from && a.year <= to && !IsRumour(a.text));

	/// <summary>What filled the years from..to: the heaviest kind of event, or "quiet".</summary>
	private string ThemeOf(int from, int to)
	{
		var weights = new Dictionary<string, float>();
		foreach (var (_, cat, text) in AnnalsOf(from, to))
			weights[cat] = (weights.TryGetValue(cat, out float w) ? w : 0f) + EventWeight(cat, text);
		string best = "quiet";
		float most = 2.9f;
		foreach (var (cat, w) in weights)
			if (w > most && Themes.ContainsKey(cat))
			{
				most = w;
				best = cat;
			}
		return best;
	}

	private ChapterDraft ProceduralChapter(int from, int to)
	{
		var events = AnnalsOf(from, to);
		string theme = ThemeOf(from, to);
		// The events that mattered most, told in the order they happened.
		var ranked = new List<(float weight, int order)>();
		for (int n = 0; n < events.Count; n++)
			ranked.Add((EventWeight(events[n].cat, events[n].text), n));
		ranked.Sort((a, b) => a.weight != b.weight ? b.weight.CompareTo(a.weight) : a.order.CompareTo(b.order));
		var chosen = new List<int>();
		for (int n = 0; n < ranked.Count && chosen.Count < 4; n++)
			chosen.Add(ranked[n].order);
		chosen.Sort();
		var sb = new StringBuilder();
		foreach (int n in chosen)
		{
			string text = events[n].text;
			sb.Append($"In year {events[n].year}, {text}{(text.EndsWith('.') || text.EndsWith('!') ? "" : ".")} ");
		}
		if (chosen.Count == 0)
			sb.Append("Nothing troubled the world: the peoples lived and worked in peace. ");
		var counts = new Dictionary<string, int>();
		for (int n = 0; n < events.Count; n++)
			if (!chosen.Contains(n))
				counts[events[n].cat] = (counts.TryGetValue(events[n].cat, out int c) ? c : 0) + 1;
		if (counts.Count > 0)
		{
			var parts = new List<string>();
			foreach (var (cat, n) in counts)
				parts.Add(cat switch
				{
					"wars" => $"{n} more deeds of war", "kings" => $"{n} more affairs of crowns", "cities" => $"{n} more tidings from the villages",
					"inventions" => $"{n} more inventions and borrowings", "disasters" => $"{n} more disasters", "culture" => $"{n} more matters of gods and customs",
					"heroes" => $"{n} more tales of heroes", _ => $"{n} more things",
				});
			sb.Append($"These years also saw {string.Join(", ", parts)}.");
		}
		string title = Themes[theme].title;
		string told = sb.ToString().Trim();
		if (told.Length > 700)
			told = told[..700].TrimEnd() + "...";
		return new ChapterDraft { Title = title, Text = told, Age = "" };
	}

	public static string ValidateChapter(ChapterDraft d)
	{
		if (d == null)
			return "empty";
		string error = NameError(d.Title, 40) ?? TextError(d.Text, 20, 500);
		if (error != null)
			return error;
		if (!string.IsNullOrEmpty(d.Age) && (!d.Age.StartsWith("The Age of ") || NameError(d.Age, 32) != null || d.Age.Length < 14))
			return "an age is named 'The Age of ...'";
		return null;
	}

	/// <summary>A mind's chapter (JSON) for the years since the last chapter. Returns "" when it
	/// joins the chronicle, else why it was rejected.</summary>
	public string SubmitChapterJson(string json, string mind = "model")
	{
		int to = Year();
		return SubmitChapterJson(json, Math.Min(to, Chapters.Count > 0 ? Chapters[^1].To + 1 : 1), to, mind);
	}

	private string SubmitChapterJson(string json, int from, int to, string mind)
	{
		ChapterDraft d;
		try
		{
			d = JsonSerializer.Deserialize<ChapterDraft>(json);
		}
		catch (Exception e)
		{
			return "not valid JSON: " + e.Message;
		}
		string error = ValidateChapter(d);
		if (error != null)
			return error;
		AddChapter(d, from, to, mind);
		return "";
	}

	/// <summary>The chapter joins the chronicle. A new age begins when what filled the last ten
	/// years is no longer what the age was named after, and the age is ten years old.</summary>
	private void AddChapter(ChapterDraft d, int from, int to, string mind)
	{
		string theme = ThemeOf(Math.Max(1, to - AgeYears + 1), to);
		var age = Ages[^1];
		// (the procedural chronicler's texts are built from event texts, cut to what a text may hold)
		string text = mind == "procedural" ? d.Text : d.Text.Trim();
		if (theme != age.Theme && to - age.From + 1 >= AgeYears)
		{
			string name = d.Age;
			if (string.IsNullOrEmpty(name) || Ages.Exists(a => a.Name == name))
			{
				var names = new List<string>(Themes[theme].ages);
				names.RemoveAll(n => Ages.Exists(a => a.Name == "The Age of " + n));
				name = "The Age of " + (names.Count > 0 ? names[_cultureRng.Next(names.Count)] : Themes[theme].ages[0]);
				if (Ages.Exists(a => a.Name == name))
					name = "The Second Age of " + name["The Age of ".Length..];
			}
			string old = age.Name;
			age = new Age { Name = name, Theme = theme, From = to };
			Ages.Add(age);
			LogEvent($"{old} is over. The chroniclers call these years {name}.", "culture");
		}
		Chapters.Add(new Chapter { From = from, To = to, Title = d.Title.Trim(), Text = text, Mind = mind, Age = age.Name });
		if (Chapters.Count > 400)
			Chapters.RemoveAt(0);
	}

	public string ChapterPrompt(int from, int to)
	{
		var sb = new StringBuilder();
		sb.Append($"You are the chronicler of a world. It is {AgeName()}. Write the chapter of the years {from} to {to} from these events:\n");
		var events = AnnalsOf(from, to);
		// The newest and heaviest fit a small model's window.
		int shown = 0;
		for (int n = 0; n < events.Count && shown < 16; n++)
			if (events.Count - n <= 16 || EventWeight(events[n].cat, events[n].text) >= 2f)
			{
				sb.Append($"- year {events[n].year}: {events[n].text}\n");
				shown++;
			}
		if (shown == 0)
			sb.Append("- nothing of note happened\n");
		sb.Append("\"title\": 2-40 letters. \"text\": two to four plain sentences telling these years (under 400 characters). ");
		sb.Append("\"age\": a name for these times, as \"The Age of ...\" and one word. Answer with the JSON record only.\n");
		return sb.ToString();
	}

	public string ChapterGrammar() =>
		"root ::= \"{\" ws \"\\\"title\\\":\" ws title \",\" ws \"\\\"text\\\":\" ws text \",\" ws \"\\\"age\\\":\" ws age ws \"}\"\n"
		+ $"title ::= {LocalModel.Name(39)}\ntext ::= {LocalModel.Text(400, 20)}\n"
		+ "age ::= \"\\\"The Age of \" [A-Z] [a-z]{2,12} \"\\\"\"\nws ::= [ ]?\n";

	public string ChapterSchema() => JsonSerializer.Serialize(new Dictionary<string, object>
	{
		["type"] = "object",
		["properties"] = new Dictionary<string, object>
		{
			["title"] = new Dictionary<string, object> { ["type"] = "string", ["minLength"] = 2, ["maxLength"] = 40 },
			["text"] = new Dictionary<string, object> { ["type"] = "string", ["minLength"] = 20, ["maxLength"] = 500 },
			["age"] = new Dictionary<string, object> { ["type"] = "string", ["pattern"] = "^The Age of [A-Z][a-z]{2,12}$" },
		},
		["required"] = new[] { "title", "text", "age" },
	});

	// ------------------------------------------------------------------ queries (HUD, tests)

	/// <summary>The written chronicle, newest chapter first: years, title, text, age, mind.</summary>
	public Godot.Collections.Array ChronicleTable()
	{
		var list = new Godot.Collections.Array();
		for (int n = Chapters.Count - 1; n >= 0; n--)
		{
			var ch = Chapters[n];
			list.Add(new Godot.Collections.Dictionary
			{
				["from"] = ch.From, ["to"] = ch.To, ["title"] = ch.Title, ["text"] = ch.Text, ["age"] = ch.Age, ["mind"] = ch.Mind,
			});
		}
		return list;
	}

	/// <summary>The ages so far, oldest first: name, first year, what it was named after.</summary>
	public Godot.Collections.Array AgeTable()
	{
		var list = new Godot.Collections.Array();
		foreach (var a in Ages)
			list.Add(new Godot.Collections.Dictionary { ["name"] = a.Name, ["from"] = a.From, ["theme"] = a.Theme });
		return list;
	}

	/// <summary>Makes the procedural chronicler write the chapter of the years up to now (tests).</summary>
	public void WriteChapterNow() => WriteChapter(force: true);

	/// <summary>Asks the chronicler the usual way: the model if there is one, else procedural.</summary>
	public void AskChronicler() => WriteChapter(force: false);
}
