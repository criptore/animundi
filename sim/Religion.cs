using System;
using System.Collections.Generic;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace Animundi.Sim;

/// <summary>
/// Religions (0.6, docs/CULTURE.md). Every culture has gods and tells myths, and its myths are
/// drawn from the world itself: a kingdom remembers what it lived through (a war, a king's death,
/// a fire from the sky, a hero), and its mind turns the heaviest memory into a myth. A myth about
/// something no god of theirs answers for gives birth to a new god.
///
/// The player is a god too. Peoples notice what the player's powers do near their villages:
/// healing and rain leave gratitude, lightning, fire, meteors and sudden death leave dread. They
/// give the unseen hand a name and worship, fear or hate it, which changes their faith, their
/// loyalty and their taste for war.
/// </summary>
public partial class Simulation
{
	public sealed class God
	{
		public string Name, Domain, Temper;
		public int Year;
		/// <summary>The player, as this people names them.</summary>
		public bool Player;
	}

	public sealed class Myth
	{
		public string Title, Text, God, Source, Mind;
		public int Year;
	}

	/// <summary>Something a kingdom lived through, that a myth can be made of.</summary>
	public sealed class Memory
	{
		public string Kind, Text;
		public float Weight;
		public int Year;
		public bool Told;
	}

	public sealed class MythDraft
	{
		[JsonPropertyName("title")] public string Title { get; set; } = "";
		[JsonPropertyName("text")] public string Text { get; set; } = "";
	}

	private static readonly string[] FirstDomains = { "the sun", "the sea", "the forest", "the harvest", "the hearth", "the sky", "the moon" };
	private static readonly string[] Tempers = { "kind", "stern", "fickle", "wrathful", "patient", "hungry", "silent" };
	public const int MaxGods = 5;

	/// <summary>The god a memory belongs to, by its kind, and what the god did in the myth.</summary>
	private static readonly Dictionary<string, (string domain, string deed)> MemoryDomains = new()
	{
		["war"] = ("war", "Took Up the Spear"), ["conquest"] = ("war", "Broke the Walls"), ["loss"] = ("sorrow", "Turned Away"),
		["peace"] = ("the hearth", "Stayed the Blades"), ["death"] = ("death", "Called the Crown Home"), ["city"] = ("stone", "Raised the Stones"),
		["fire"] = ("fire", "Walked in Flame"), ["storm"] = ("storms", "Threw the Bolt"), ["hero"] = ("glory", "Chose a Champion"),
		["freedom"] = ("the wind", "Cut the Rope"), ["miracle"] = ("the sky", "Healed the People"), ["wrath"] = ("the sky", "Struck the Land"),
	};

	private void FoundReligion(Culture c, int species)
	{
		var lang = _languages[species];
		c.Religion = _nextReligion++;
		var god = new God
		{
			Name = lang.PersonName(), Domain = FirstDomains[_cultureRng.Next(FirstDomains.Length)],
			Temper = Tempers[_cultureRng.Next(Tempers.Length)], Year = Year(),
		};
		c.Gods.Add(god);
		c.Creed = "the Way of " + god.Name;
	}

	// ------------------------------------------------------------------ memories

	/// <summary>Kingdom k will remember this: `text` is a clause ("war broke out with Karum").
	/// Kinds are those of MemoryDomains. Twelve memories are kept, the lightest forgotten first.</summary>
	private void Remember(int k, string kind, string text, float weight)
	{
		if (k < 0 || k >= Kingdoms.Count || !Kingdoms[k].Alive)
			return;
		var c = Kingdoms[k].Culture;
		c.Memories.Add(new Memory { Kind = kind, Text = text, Weight = weight, Year = Year() });
		if (c.Memories.Count > 12)
		{
			int drop = 0;
			for (int n = 1; n < c.Memories.Count - 1; n++)
				if (c.Memories[n].Told && !c.Memories[drop].Told || c.Memories[n].Told == c.Memories[drop].Told && c.Memories[n].Weight < c.Memories[drop].Weight)
					drop = n;
			c.Memories.RemoveAt(drop);
		}
	}

	/// <summary>The heaviest thing not yet told as a myth, or null.</summary>
	private static Memory HeaviestMemory(Culture c)
	{
		Memory best = null;
		foreach (var m in c.Memories)
			if (!m.Told && m.Weight >= 1f && (best == null || m.Weight > best.Weight))
				best = m;
		return best;
	}

	/// <summary>The living kingdom with a village within `reach` tiles of (x, y), the nearest
	/// first, or -1; `village` is that village.</summary>
	private int KingdomNear(float x, float y, float reach, out int village)
	{
		village = -1;
		float best = reach * reach;
		for (int v = 0; v < Villages.Count; v++)
		{
			var o = Villages[v];
			if (!o.Alive || o.Kingdom < 0)
				continue;
			float d = (o.X - x) * (o.X - x) + (o.Y - y) * (o.Y - y);
			if (d <= best)
			{
				best = d;
				village = v;
			}
		}
		return village < 0 ? -1 : Villages[village].Kingdom;
	}

	// ------------------------------------------------------------------ myths

	public static string ValidateMyth(MythDraft d)
	{
		if (d == null)
			return "empty";
		return NameError(d.Title, 40) ?? TextError(d.Text, 10, 240);
	}

	/// <summary>A mind's myth (JSON) for kingdom k, about the heaviest thing it remembers.
	/// Returns "" when the myth is now told, else why it was rejected.</summary>
	public string SubmitMythJson(int k, string json, string mind = "model")
	{
		if (k < 0 || k >= Kingdoms.Count || !Kingdoms[k].Alive)
			return "no such kingdom";
		return SubmitMythJson(k, json, HeaviestMemory(Kingdoms[k].Culture), mind);
	}

	private string SubmitMythJson(int k, string json, Memory memory, string mind)
	{
		MythDraft d;
		try
		{
			d = JsonSerializer.Deserialize<MythDraft>(json);
		}
		catch (Exception e)
		{
			return "not valid JSON: " + e.Message;
		}
		return SubmitMyth(k, d, memory, mind) ?? "";
	}

	/// <summary>The myth joins the kingdom's faith. The engine, not the mind, ties it to what
	/// really happened (its source) and to a god: theirs for that domain, a new one when they
	/// have none, the player when the event was the player's doing.</summary>
	private string SubmitMyth(int k, MythDraft d, Memory memory, string mind)
	{
		if (k < 0 || k >= Kingdoms.Count || !Kingdoms[k].Alive)
			return "no such kingdom";
		if (memory == null || memory.Told)
			return "nothing to tell a myth about";
		string error = ValidateMyth(d);
		if (error != null)
			return error;
		var kingdom = Kingdoms[k];
		var c = kingdom.Culture;
		string people = Assets.Species[kingdom.Species].Name;
		var god = GodFor(k, memory, out bool born);
		memory.Told = true;
		c.Myths.Add(new Myth
		{
			Title = d.Title.Trim(), Text = d.Text.Trim(), God = god.Name, Mind = mind, Year = Year(),
			Source = $"year {memory.Year}: {memory.Text}",
		});
		if (c.Myths.Count > 12)
			c.Myths.RemoveAt(0);
		c.Values[5] = Math.Min(1f, c.Values[5] + 0.03f);
		if (born)
			LogEvent($"a god is born among the {people} of {kingdom.Name}: {god.Name}, {god.Temper} god of {god.Domain}, since {memory.Text}.", "culture");
		LogEvent($"the {people} of {kingdom.Name} now tell the myth \"{d.Title.Trim()}\", of the day {memory.Text}.", "culture");
		return null;
	}

	private God GodFor(int k, Memory memory, out bool born)
	{
		var c = Kingdoms[k].Culture;
		born = false;
		if ((memory.Kind == "miracle" || memory.Kind == "wrath") && c.GodName != "")
			return c.Gods.Find(g => g.Player);
		string domain = MemoryDomains.TryGetValue(memory.Kind, out var known) ? known.domain : "fate";
		var god = c.Gods.Find(g => !g.Player && g.Domain == domain);
		if (god != null)
			return god;
		var own = c.Gods.FindAll(g => !g.Player);
		if (own.Count >= MaxGods)
			return own[_cultureRng.Next(own.Count)];
		god = new God { Name = _languages[Kingdoms[k].Species].PersonName(), Domain = domain, Temper = Tempers[_cultureRng.Next(Tempers.Length)], Year = Year() };
		c.Gods.Add(god);
		born = true;
		return god;
	}

	private MythDraft ProceduralMyth(int k, Memory memory)
	{
		var kingdom = Kingdoms[k];
		var c = kingdom.Culture;
		string people = Assets.Species[kingdom.Species].Name;
		string domain = MemoryDomains.TryGetValue(memory.Kind, out var known) ? known.domain : "fate";
		string deed = known.deed ?? "Spoke";
		bool players = (memory.Kind == "miracle" || memory.Kind == "wrath") && c.GodName != "";
		var god = players ? c.Gods.Find(g => g.Player) : c.Gods.Find(g => !g.Player && g.Domain == domain);
		// A god not yet born has no name: the myth is of "the Nameless", and the god it gives
		// birth to is named after.
		string who = Clean(god?.Name ?? "the Nameless");
		string title = $"How {who} {deed}";
		if (title.Length > 40)
			title = title[..40].TrimEnd();
		string text = $"In year {memory.Year}, {Clean(memory.Text)}. The {Clean(people)} say it was the will of {who}"
			+ (god != null ? $", {god.Temper} god of {god.Domain}." : $", and they have feared {domain} ever since.");
		if (text.Length > 240)
			text = text[..239].TrimEnd() + ".";
		return new MythDraft { Title = title, Text = text };
	}

	/// <summary>Keeps what the validators allow in names and texts (generated names may carry
	/// marks they don't).</summary>
	private static string Clean(string s)
	{
		var sb = new StringBuilder();
		foreach (char ch in s)
			if (char.IsLetterOrDigit(ch) || " ,.'!?;:-".IndexOf(ch) >= 0)
				sb.Append(ch);
		return sb.ToString();
	}

	public string MythPrompt(int k, Memory memory)
	{
		var kingdom = Kingdoms[k];
		var c = kingdom.Culture;
		var sb = new StringBuilder();
		sb.Append($"You are the storyteller of the {Assets.Species[kingdom.Species].Name} of the kingdom of {kingdom.Name}. They follow {c.Creed}.\n");
		sb.Append("Their gods: ");
		foreach (var g in c.Gods)
			sb.Append($"{g.Name}, {g.Temper} god of {g.Domain}; ");
		sb.Append($"\nIn year {memory.Year}, {memory.Text}.\n");
		sb.Append("Tell this event as a short myth of theirs: a \"title\" of 2-40 letters and a \"text\" of one to three plain sentences (under 240 characters). Answer with the JSON record only.\n");
		return sb.ToString();
	}

	public string MythGrammar() =>
		"root ::= \"{\" ws \"\\\"title\\\":\" ws title \",\" ws \"\\\"text\\\":\" ws text ws \"}\"\n"
		+ $"title ::= {LocalModel.Name(39)}\ntext ::= {LocalModel.Text(230, 10)}\nws ::= [ ]?\n";

	public string MythSchema() => JsonSerializer.Serialize(new Dictionary<string, object>
	{
		["type"] = "object",
		["properties"] = new Dictionary<string, object>
		{
			["title"] = new Dictionary<string, object> { ["type"] = "string", ["minLength"] = 2, ["maxLength"] = 40 },
			["text"] = new Dictionary<string, object> { ["type"] = "string", ["minLength"] = 10, ["maxLength"] = 240 },
		},
		["required"] = new[] { "title", "text" },
	});

	// ------------------------------------------------------------------ faith, every season

	private int _tTemple = -2;

	/// <summary>Faith moves toward what the culture values, its temples, its myths and customs,
	/// and what it makes of the player; gratitude and dread fade; the stance follows.</summary>
	private void FaithSeason(int k)
	{
		var kingdom = Kingdoms[k];
		var c = kingdom.Culture;
		if (_tTemple == -2)
			_tTemple = Assets.Buildings.FindIndex(b => b.Id == "temple");
		int temples = 0;
		if (_tTemple >= 0)
			for (int v = 0; v < Villages.Count; v++)
				if (Villages[v].Alive && Villages[v].Kingdom == k)
					temples += CountOf(v, _tTemple, true);
		float target = 15f + 45f * c.Values[5] + 6f * Math.Min(3, temples) + Math.Min(10f, 2f * c.Myths.Count) + c.FaithBonus
			+ (c.Stance == "worshipped" ? 15f : c.Stance == "feared" ? 5f : c.Stance == "hated" ? -10f : 0f);
		c.Faith = Math.Clamp(c.Faith + (Math.Clamp(target, 0f, 100f) - c.Faith) * 0.25f, 0f, 100f);
		c.Gratitude *= 0.93f;
		c.Dread *= 0.93f;
		UpdateStance(k);
	}

	/// <summary>Loyalty a village owes to its kingdom's faith and to what it makes of the player.</summary>
	private float FaithLoyalty(int k)
	{
		var c = Kingdoms[k].Culture;
		return Math.Clamp((c.Faith - 40f) / 8f, -3f, 7f) + (c.Stance == "worshipped" ? 3f : c.Stance == "hated" ? -3f : 0f);
	}

	// ------------------------------------------------------------------ the player as a god

	/// <summary>The player did something at (x, y): the kingdoms with a village within sight
	/// (the brush and 14 tiles) notice. `kind`: bless, rain, fire, lightning, meteor, smite.
	/// `amount`: people healed or killed, tiles put out or set alight. Powers are dragged, called
	/// every frame: a kingdom feels one kind of act at most every 0.4 s of the player's time
	/// (paused or not), and remembers and speaks of it once a season.</summary>
	private void GodActs(string kind, float x, float y, float radius, int amount)
	{
		if (amount <= 0 || Kingdoms.Count == 0)
			return;
		float reach = radius + 14f;
		var seen = new Dictionary<int, int>();
		for (int v = 0; v < Villages.Count; v++)
		{
			var o = Villages[v];
			if (!o.Alive || o.Kingdom < 0 || !Kingdoms[o.Kingdom].Alive)
				continue;
			float d = (o.X - x) * (o.X - x) + (o.Y - y) * (o.Y - y);
			if (d <= reach * reach && (!seen.TryGetValue(o.Kingdom, out int old) || d < (Villages[old].X - x) * (Villages[old].X - x) + (Villages[old].Y - y) * (Villages[old].Y - y)))
				seen[o.Kingdom] = v;
		}
		foreach (var (k, v) in seen)
		{
			var c = Kingdoms[k].Culture;
			string place = Villages[v].Name;
			bool kindly = kind == "bless" || kind == "rain" || kind == "miracle";
			ulong now = Godot.Time.GetTicksMsec();
			if (c.LastFelt.TryGetValue(kind, out ulong felted) && now - felted < 400)
				continue;
			c.LastFelt[kind] = now;
			float felt = kind switch
			{
				"bless" => Math.Min(12f, 2f * amount), "rain" => 6f, "miracle" => 20f, "fire" => 5f, "lightning" => 10f, "meteor" => 25f,
				_ => Math.Min(20f, 4f * amount),
			};
			if (kindly)
				c.Gratitude = Math.Min(100f, c.Gratitude + felt);
			else
				c.Dread = Math.Min(100f, c.Dread + felt);
			if (!c.LastAct.TryGetValue(kind, out double last) || Scheduler.Time - last >= YearSeconds / 4f)
			{
				c.LastAct[kind] = Scheduler.Time;
				Remember(k, kindly ? "miracle" : "wrath", kind switch
				{
					"bless" => $"a great healing came over the people of {place}",
					"rain" => $"rain fell from a clear sky and put out the fires of {place}",
					"miracle" => $"light poured from the sky over {place} and the sick rose healed",
					"fire" => $"fire sprang from nowhere near {place}",
					"lightning" => $"a bolt from a clear sky struck near {place}",
					"meteor" => $"a star fell on the land of {place}",
					_ => $"people of {place} fell dead where they stood",
				}, kind == "miracle" || kind == "meteor" ? 3f : 2f);
			}
			UpdateStance(k);
		}
	}

	/// <summary>What kingdom k makes of the player, from its gratitude and dread: unnoticed while
	/// both are faint; worshipped when gratitude wins; else feared by cultures of faith and
	/// tradition, hated by those of freedom and war. A change is told in the chronicle.</summary>
	private void UpdateStance(int k)
	{
		var kingdom = Kingdoms[k];
		var c = kingdom.Culture;
		string stance = c.Gratitude < 8f && c.Dread < 8f ? "unnoticed"
			: c.Gratitude >= c.Dread ? "worshipped"
			: c.Values[5] + c.Values[7] >= c.Values[6] + c.Values[0] ? "feared" : "hated";
		if (stance == c.Stance)
			return;
		c.Stance = stance;
		foreach (var v in Villages)
			if (v.Alive && v.Kingdom == k)
				v.ModsDirty = true;
		if (stance == "unnoticed")
			return;
		string people = Assets.Species[kingdom.Species].Name;
		if (c.GodName == "")
		{
			c.GodName = _languages[kingdom.Species].PersonName();
			c.Gods.Add(new God { Name = c.GodName, Domain = "the sky", Temper = stance == "worshipped" ? "kind" : "wrathful", Year = Year(), Player = true });
			LogEvent($"the {people} of {kingdom.Name} have felt an unseen hand over their land. They name it {c.GodName}.", "culture");
		}
		var god = c.Gods.Find(g => g.Player);
		if (god != null)
			god.Temper = stance == "worshipped" ? "kind" : "wrathful";
		LogEvent(stance switch
		{
			"worshipped" => $"the {people} of {kingdom.Name} worship {c.GodName}, who watches over them.",
			"feared" => $"the {people} of {kingdom.Name} live in fear of {c.GodName}.",
			_ => $"the {people} of {kingdom.Name} curse the name of {c.GodName}.",
		}, "culture");
	}
}
