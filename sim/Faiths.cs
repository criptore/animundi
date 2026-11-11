using System;
using System.Collections.Generic;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace Animundi.Sim;

/// <summary>
/// Religions and gods (0.6, docs/CULTURES.md). Every kingdom keeps a faith: gods with a domain
/// (sun, sea, storm, war, death, harvest…), a temper and a demand, and myths. Myths are not
/// invented from nothing: they are drawn from what the peoples witness (lightning, meteors,
/// wildfires, wars, conquests, a kingdom's fall, a king's death, an extinction); a new kind of
/// event can give birth to a new god.
///
/// Faith lives in villages (temples, shamans, rituals, miracles): it makes them loyal; kingdoms
/// of the same faith like each other, the others are unbelievers, and faiths convert neighbours
/// and split in schisms.
///
/// The player is a god too: peoples see what the player does from the sky, and come to worship,
/// fear or hate the player, who enters their faith as a god of its own.
/// </summary>
public partial class Simulation
{
	public static readonly string[] Domains = { "sun", "moon", "sea", "sky", "storm", "fire", "earth", "harvest", "forest", "beasts", "war", "death", "wisdom", "wealth" };
	/// <summary>The domain of the god the player is to the peoples.</summary>
	public const string PlayerDomain = "the hand in the sky";
	private static readonly string[] Tempers = { "kind", "wrathful", "fickle", "distant", "jealous", "playful", "stern" };
	private static readonly string[] Demands = { "offerings of grain", "prayers at dawn", "the first-born lamb", "silence at night", "songs at every meal", "a fire that never dies", "pilgrimages to high places", "obedience" };
	/// <summary>Epithets of each domain (myths, prompts).</summary>
	private static readonly Dictionary<string, string> DomainEpithets = new()
	{
		["sun"] = "who lights the day", ["moon"] = "who watches the night", ["sea"] = "who rules the waves",
		["sky"] = "who holds up the heavens", ["storm"] = "who throws the lightning", ["fire"] = "who dwells in the flame",
		["earth"] = "who carries the land", ["harvest"] = "who ripens the grain", ["forest"] = "who sleeps in the trees",
		["beasts"] = "who herds the animals", ["war"] = "who loves the clash of arms", ["death"] = "who keeps the dead",
		["wisdom"] = "who whispers new ideas", ["wealth"] = "who guards the gold", [PlayerDomain] = "whose hand reaches down from the sky",
	};
	/// <summary>A faith hears of a new myth at most this often (except the birth of a god).</summary>
	public const float MythSeconds = YearSeconds * 2f;

	public sealed class God
	{
		public string Name, Domain, Temper, Demand;
		public int Year;
		public bool Player;
	}

	public sealed class Myth
	{
		public int Year;
		public string Title, Text, Mind, Event;
		public int God = -1;
	}

	public sealed class Faith
	{
		public int Id;
		public string Name;
		public int Species, Culture;
		public int Parent = -1;
		public int Founded;
		public bool Alive = true;
		public readonly List<God> Gods = new();
		public readonly List<Myth> Myths = new();
		public double NextMyth;
	}

	/// <summary>A myth as written by a mind (JSON), before validation.</summary>
	public sealed class MythDraft
	{
		[JsonPropertyName("god")] public string God { get; set; } = "";
		[JsonPropertyName("domain")] public string Domain { get; set; } = "";
		[JsonPropertyName("title")] public string Title { get; set; } = "";
		[JsonPropertyName("text")] public string Text { get; set; } = "";
	}

	public readonly List<Faith> Faiths = new();
	private double _nextFaithYear;
	public int MythsRejected { get; private set; }
	// The temple building type (data/buildings.json), or -1.
	private int _tTemple = -1;
	// Who the last power hurt: kingdom → people killed.
	private readonly Dictionary<int, int> _powerVictims = new();

	private void SetupFaiths()
	{
		Faiths.Clear();
		_nextFaithYear = 0;
		_powerVictims.Clear();
	}

	// ------------------------------------------------------------------ birth of a faith

	/// <summary>A new faith for a culture: one god or a small pantheon, from what the culture
	/// values and where its people live, and a myth of how the world began.</summary>
	private int CreateFaith(int ci, int capital)
	{
		var c = Cultures[ci];
		var lang = _languages[c.Species];
		var f = new Faith { Id = Faiths.Count, Species = c.Species, Culture = ci, Founded = Year() };
		f.NextMyth = Scheduler.Time + MythSeconds * _rng.NextDouble();
		var domains = new List<string>();
		string Lean(string value) => value switch
		{
			"war" => "war", "honour" => "sun", "nature" => _rng.NextDouble() < 0.5 ? "forest" : "harvest", "wealth" => "wealth",
			"knowledge" => "wisdom", "faith" => "sun", "freedom" => "sky", _ => _rng.NextDouble() < 0.5 ? "earth" : "death",
		};
		var top = TopValues(c, 2).Split(", ");
		domains.Add(Lean(top[0]));
		bool one = Val(c, "faith") > 0.7f && Val(c, "tradition") < 0.55f;
		if (!one)
		{
			string second = Lean(top[1]);
			if (capital >= 0 && NearSea(Villages[capital].X, Villages[capital].Y))
				second = "sea";
			if (second == domains[0])
				second = domains[0] == "sun" ? "moon" : "earth";
			domains.Add(second);
		}
		foreach (var d in domains)
			f.Gods.Add(NewGod(c.Species, d));
		f.Name = one ? $"the Way of {f.Gods[0].Name}" : $"the Gods of {lang.PlaceName()}";
		Faiths.Add(f);
		string people = Assets.Species[c.Species].Name;
		var g = f.Gods[0];
		string land = Assets.Species[c.Species].Race?.Biomes.Count > 0 ? Assets.Species[c.Species].Race.Biomes[0].ToLowerInvariant() : "land";
		AddMyth(f, new Myth
		{
			Year = Year(), Title = $"The Making of the {Capitalise(land)}", Mind = "procedural", Event = "creation", God = 0,
			Text = $"In the beginning {g.Name}, {DomainEpithets[g.Domain]}, shaped the {land} and set the {people} upon it.",
		});
		return f.Id;
	}

	private God NewGod(int species, string domain) => new()
	{
		Name = _languages[species].PersonName(), Domain = domain, Year = Year(),
		Temper = Tempers[_rng.Next(Tempers.Length)], Demand = Demands[_rng.Next(Demands.Length)],
	};

	/// <summary>"near Tolm" for the village closest to (x, y) within 30 tiles, else "in the wilds".</summary>
	private string PlaceNear(float x, float y)
	{
		string best = "";
		float d = 30f;
		foreach (var v in Villages)
			if (v.Alive && Math.Abs(v.X - x) + Math.Abs(v.Y - y) < d)
			{
				d = Math.Abs(v.X - x) + Math.Abs(v.Y - y);
				best = v.Name;
			}
		return best == "" ? "in the wilds" : "near " + best;
	}

	private bool NearSea(int x, int y)
	{
		for (int dy = -8; dy <= 8; dy += 2)
			for (int dx = -8; dx <= 8; dx += 2)
				if (World.InBounds(x + dx, y + dy) && World.Water[World.Index(x + dx, y + dy)] != SimWorld.WaterLand)
					return true;
		return false;
	}

	private void AddMyth(Faith f, Myth m)
	{
		f.Myths.Add(m);
		if (f.Myths.Count > 16)
			f.Myths.RemoveAt(1);  // the creation myth stays
	}

	// ------------------------------------------------------------------ what the peoples witness

	private static readonly Dictionary<string, string> WitnessDomains = new()
	{
		["lightning"] = "storm", ["wildfire"] = "fire", ["meteor"] = "sky", ["war"] = "war", ["conquest"] = "war",
		["fall"] = "death", ["king_death"] = "death", ["extinction"] = "beasts", ["famine"] = "harvest",
		["lava"] = "fire", ["invention"] = "wisdom", ["city"] = "wealth",
	};

	/// <summary>Something happened that the peoples will remember: the faiths of the kingdoms
	/// involved (k1, k2) or living within 40 tiles of (x, y) may make a myth of it, and a new kind
	/// of event may give birth to a new god. `phrase` says what happened ("a star fell near Tolm").</summary>
	private void Witness(string what, float x, float y, string phrase, int k1 = -1, int k2 = -1)
	{
		if (!WitnessDomains.TryGetValue(what, out string domain) || !Law("faiths"))
			return;
		var seen = new HashSet<int>();
		for (int k = 0; k < Kingdoms.Count; k++)
		{
			var kingdom = Kingdoms[k];
			if (!kingdom.Alive || kingdom.Faith < 0 || seen.Contains(kingdom.Faith))
				continue;
			bool involved = k == k1 || k == k2;
			if (!involved && x >= 0f && !Villages.Exists(v => v.Alive && v.Kingdom == k && Math.Abs(v.X - x) + Math.Abs(v.Y - y) < 40))
				continue;
			if (!involved && x < 0f)
				continue;
			var f = Faiths[kingdom.Faith];
			int god = f.Gods.FindIndex(g => g.Domain == domain);
			bool birth = god < 0 && f.Gods.Count < 7;
			if (!birth && Scheduler.Time < f.NextMyth)
				continue;
			if (_rng.NextDouble() > (involved ? 0.8 : 0.5))
				continue;
			seen.Add(kingdom.Faith);
			f.NextMyth = Scheduler.Time + MythSeconds * (0.7 + 0.6 * _rng.NextDouble());
			TellMyth(k, f.Id, what, domain, phrase, birth);
		}
	}

	/// <summary>Faith fi makes a myth of an event: asks the model, or the procedural mind now.
	/// A birth makes a new god of the domain.</summary>
	private void TellMyth(int k, int fi, string what, string domain, string phrase, bool birth)
	{
		int year = Year();
		void Procedural()
		{
			if (fi < Faiths.Count && Faiths[fi].Alive)
				AddProceduralMyth(fi, what, domain, phrase, birth, year);
		}
		Ponder("myth", MythPrompt(k, fi, domain, phrase, birth), MythGrammar(), MythSchema(),
			"You tell the myths of a people in a world simulation. Answer with one JSON record.", 220,
			json => fi < Faiths.Count && Faiths[fi].Alive ? SubmitMythJson(fi, json, what, birth ? domain : "", year) : null,
			Procedural);
	}

	private void AddProceduralMyth(int fi, string what, string domain, string phrase, bool birth, int year)
	{
		var f = Faiths[fi];
		string people = Assets.Species[f.Species].Name;
		int gi = f.Gods.FindIndex(g => g.Domain == domain);
		if (gi < 0)
		{
			f.Gods.Add(NewGod(f.Species, domain));
			gi = f.Gods.Count - 1;
			birth = true;
		}
		var god = f.Gods[gi];
		string title, text;
		if (birth)
		{
			title = $"The Birth of {god.Name}";
			text = $"When {phrase} in year {year}, the {people} saw {god.Name} for the first time, {DomainEpithets[domain]}.";
			LogEvent($"a new god is born to {f.Name}: {god.Name}, {DomainEpithets[domain]}.", "faith");
		}
		else
		{
			string[] nouns = { "Wrath", "Gift", "Tears", "Hunt", "Dream", "Anger", "Song" };
			title = $"The {nouns[_rng.Next(nouns.Length)]} of {god.Name}";
			string why = god.Temper switch
			{
				"wrathful" => "angered that " + god.Demand + " were forgotten",
				"kind" => "to warn the faithful",
				"fickle" => "for no reason anyone could tell",
				"jealous" => "jealous of the other gods",
				"playful" => "in play",
				"stern" => "to punish the proud",
				_ => "from far away",
			};
			text = $"The {people} say that when {phrase} in year {year}, it was {god.Name}, {why}.";
		}
		if (text.Length > 200)
			text = text[..197] + "...";
		AddMyth(f, new Myth { Year = year, Title = title, Text = text, Mind = "procedural", Event = what, God = gi });
		if (!birth)
			LogEvent($"the faithful of {f.Name} tell a new myth: {title}.", "faith");
	}

	/// <summary>A mind's myth (JSON) for faith fi: a god of the given domain (a new one when
	/// `newDomain` is set), a title and a story. Returns null or why it was rejected.</summary>
	public string SubmitMythJson(int fi, string json, string what = "", string newDomain = "", int year = -1)
	{
		if (fi < 0 || fi >= Faiths.Count || !Faiths[fi].Alive)
			return "no such faith";
		MythDraft d;
		try
		{
			d = JsonSerializer.Deserialize<MythDraft>(json);
		}
		catch (Exception e)
		{
			MythsRejected++;
			return "not valid JSON: " + e.Message;
		}
		string error = d == null ? "empty"
			: !PlainName(d.God, 32) ? "a god's name must be 2-32 letters"
			: Array.IndexOf(Domains, d.Domain) < 0 && d.Domain != PlayerDomain ? $"unknown domain '{d.Domain}'"
			: newDomain != "" && d.Domain != newDomain ? $"the god must be of {newDomain}"
			: !PlainName(d.Title, 40) ? "title must be 2-40 letters"
			: !PlainText(d.Text, 240) || d.Text.Trim().Length < 10 ? "text must be 10-240 plain characters"
			: null;
		if (error != null)
		{
			MythsRejected++;
			return error;
		}
		var f = Faiths[fi];
		int gi = f.Gods.FindIndex(g => g.Domain == d.Domain);
		if (gi < 0)
		{
			if (f.Gods.Count >= 8)
			{
				MythsRejected++;
				return "too many gods";
			}
			f.Gods.Add(new God { Name = d.God.Trim(), Domain = d.Domain, Year = Year(), Temper = Tempers[_rng.Next(Tempers.Length)], Demand = Demands[_rng.Next(Demands.Length)], Player = d.Domain == PlayerDomain });
			gi = f.Gods.Count - 1;
			LogEvent($"a new god is born to {f.Name}: {f.Gods[gi].Name}, {DomainEpithets[d.Domain]}.", "faith");
		}
		else
			LogEvent($"the faithful of {f.Name} tell a new myth: {d.Title.Trim()}.", "faith");
		AddMyth(f, new Myth { Year = year >= 0 ? year : Year(), Title = d.Title.Trim(), Text = d.Text.Trim(), Mind = "model", Event = what, God = gi });
		return null;
	}

	private string MythPrompt(int k, int fi, string domain, string phrase, bool birth)
	{
		var f = Faiths[fi];
		var sb = new StringBuilder();
		sb.Append("You are the storytellers of a people, making a myth of a real event. ");
		sb.Append(Situation(k)).Append('\n');
		sb.Append($"What happened: {phrase}, in year {Year()}.\n");
		if (birth)
			sb.Append($"They have no god of {domain} yet: a new god of {domain} is born from this event. Name the god (in the spirit of their language, like {_languages[f.Species].PersonName()}) and set \"domain\" to \"{domain}\".\n");
		else
		{
			var g = f.Gods.Find(x => x.Domain == domain);
			sb.Append($"Tell it as a deed of {g.Name}, god of {domain} ({g.Temper}, who demands {g.Demand}): \"god\" is \"{g.Name}\", \"domain\" is \"{domain}\".\n");
		}
		sb.Append("Title of 2-40 letters, story of one or two sentences. Answer with the JSON record only.\n");
		return sb.ToString();
	}

	public static string MythGrammar()
	{
		var domains = new List<string>(Domains) { PlayerDomain };
		return string.Join("\n", new[]
		{
			$"root ::= \"{{\" ws {GbnfKey("god")} name \",\" ws {GbnfKey("domain")} domain \",\" ws {GbnfKey("title")} name \",\" ws {GbnfKey("text")} text ws \"}}\"",
			$"domain ::= {GbnfWords(domains)}",
		}) + "\n" + GbnfCommon(220);
	}

	public static string MythSchema()
	{
		var domains = new List<string>(Domains) { PlayerDomain };
		return SchemaJson(new Dictionary<string, object>
		{
			["type"] = "object", ["required"] = new[] { "god", "domain", "title", "text" },
			["properties"] = new Dictionary<string, object>
			{
				["god"] = new Dictionary<string, object> { ["type"] = "string", ["minLength"] = 2, ["maxLength"] = 32 },
				["domain"] = EnumSchema(domains), ["title"] = StringSchema(40), ["text"] = StringSchema(240),
			},
		});
	}

	// ------------------------------------------------------------------ faith in the villages, once a year

	/// <summary>Every 2 s with the kingdoms: once a year faith grows or fades in each village, the
	/// god in the sky is remembered less, faiths convert their neighbours and split.</summary>
	private void FaithStep()
	{
		if (Scheduler.Time < _nextFaithYear)
			return;
		_nextFaithYear = Scheduler.Time + YearSeconds;
		for (int v = 0; v < Villages.Count; v++)
		{
			var village = Villages[v];
			if (!village.Alive || village.Kingdom < 0)
				continue;
			var kingdom = Kingdoms[village.Kingdom];
			float value = kingdom.Culture >= 0 ? Val(Cultures[kingdom.Culture], "faith") : 0.5f;
			int shamans = 0;
			for (int i = 0; i < Units.Capacity; i++)
				if (Units.Alive[i] && Units.Village[i] == v && Units.Role[i] == (byte)Role.Shaman)
					shamans++;
			float target = 15f + 30f * value + (_tTemple >= 0 ? 15f * CountOf(v, _tTemple, true) : 0f)
				+ Math.Min(shamans, 2) * 6f + village.FaithBonus * 1.5f + kingdom.Love * 0.2f - kingdom.Hate * 0.1f;
			village.Faith = Math.Clamp(village.Faith + (target - village.Faith) * 0.3f, 0f, 100f);
		}
		foreach (var kingdom in Kingdoms)
		{
			kingdom.Love *= 0.88f;
			kingdom.Fear *= 0.85f;
			kingdom.Hate *= 0.9f;
		}
		if (Law("faiths"))
		{
			Conversions();
			Schisms();
		}
		foreach (var f in Faiths)
			if (f.Alive && !Kingdoms.Exists(k => k.Alive && k.Faith == f.Id))
			{
				f.Alive = false;
				LogEvent($"no one keeps {f.Name} any more: its gods are forgotten.", "faith");
			}
	}

	/// <summary>The mean faith of a kingdom's villages, 0..100.</summary>
	public float KingdomFaith(int k)
	{
		float sum = 0f;
		int n = 0;
		foreach (var v in Villages)
			if (v.Alive && v.Kingdom == k)
			{
				sum += v.Faith;
				n++;
			}
		return n > 0 ? sum / n : 0f;
	}

	/// <summary>A kingdom of weak faith may turn to the faith of a fervent neighbour it does not
	/// hate (allies and trade partners first).</summary>
	private void Conversions()
	{
		for (int a = 0; a < Kingdoms.Count; a++)
		{
			var ka = Kingdoms[a];
			if (!ka.Alive || ka.Faith < 0)
				continue;
			float fa = KingdomFaith(a);
			for (int b = 0; b < Kingdoms.Count; b++)
			{
				var kb = Kingdoms[b];
				if (b == a || !kb.Alive || kb.Faith < 0 || kb.Faith == ka.Faith || AtWar(a, b))
					continue;
				bool close = ka.Allies.Contains(b) || _trade.Exists(r => KingdomOf(r.A) == a && KingdomOf(r.B) == b || KingdomOf(r.A) == b && KingdomOf(r.B) == a);
				if (!close && !Bordering(a, b))
					continue;
				float fb = KingdomFaith(b);
				if (fb < fa + 15f || Opinion(a, b) < -15f)
					continue;
				double chance = (close ? 0.08 : 0.04) * (fb - fa) / 40.0;
				if (_rng.NextDouble() < chance)
				{
					string old = Faiths[ka.Faith].Name;
					ka.Faith = kb.Faith;
					foreach (var v in Villages)
						if (v.Alive && v.Kingdom == a)
							v.Faith *= 0.7f;
					LogEvent($"{ka.Name} turns from {old} to {Faiths[kb.Faith].Name}, the faith of {kb.Name}.", "faith");
					break;
				}
			}
		}
	}

	/// <summary>A faith kept by several kingdoms splits when one of them has drifted far from the
	/// culture it was born in: a new faith keeps the old gods and finds a new one.</summary>
	private void Schisms()
	{
		for (int k = 0; k < Kingdoms.Count; k++)
		{
			var kingdom = Kingdoms[k];
			if (!kingdom.Alive || kingdom.Faith < 0 || kingdom.Culture < 0)
				continue;
			var f = Faiths[kingdom.Faith];
			if (f.Culture == kingdom.Culture || Kingdoms.FindAll(o => o.Alive && o.Faith == f.Id).Count < 2)
				continue;
			float distance = 0f;
			var mine = Cultures[kingdom.Culture];
			var theirs = Cultures[f.Culture];
			for (int i = 0; i < CultureValues.Length; i++)
				distance += Math.Abs(mine.Values[i] - theirs.Values[i]);
			distance /= CultureValues.Length;
			if (distance < 0.15f || _rng.NextDouble() > 0.04 + distance * 0.2)
				continue;
			var child = new Faith { Id = Faiths.Count, Species = mine.Species, Culture = mine.Id, Parent = f.Id, Founded = Year(), NextMyth = Scheduler.Time + MythSeconds };
			foreach (var g in f.Gods)
				child.Gods.Add(g);
			string domain = TopValues(mine, 1) switch { "war" => "war", "nature" => "forest", "wealth" => "wealth", "knowledge" => "wisdom", "freedom" => "sky", _ => "moon" };
			if (!child.Gods.Exists(g => g.Domain == domain))
				child.Gods.Add(NewGod(mine.Species, domain));
			var prophet = child.Gods[^1];
			child.Name = $"the Way of {prophet.Name}";
			child.Myths.Add(f.Myths[0]);
			Faiths.Add(child);
			kingdom.Faith = child.Id;
			AddMyth(child, new Myth
			{
				Year = Year(), Title = $"The Revelation of {prophet.Name}", Mind = "procedural", Event = "schism", God = child.Gods.Count - 1,
				Text = $"The {Assets.Species[mine.Species].Name} of {kingdom.Name} heard {prophet.Name}, {DomainEpithets[prophet.Domain]}, and left {f.Name}.",
			});
			LogEvent($"schism: {kingdom.Name} breaks from {f.Name} and follows {child.Name}.", "faith");
		}
	}

	/// <summary>What kingdom a's faith makes it think of b: the same faith brings them closer,
	/// the fervent despise unbelievers.</summary>
	private float FaithOpinion(int a, int b)
	{
		var ka = Kingdoms[a];
		var kb = Kingdoms[b];
		if (ka.Faith < 0 || kb.Faith < 0)
			return 0f;
		if (ka.Faith == kb.Faith)
			return 12f;
		float value = ka.Culture >= 0 ? Val(Cultures[ka.Culture], "faith") : 0.5f;
		return -14f * value;
	}

	/// <summary>Whether kingdom a would call a war on b holy: other gods, and a fervent culture.</summary>
	private bool HolyWar(int a, int b) =>
		Kingdoms[a].Faith >= 0 && Kingdoms[b].Faith >= 0 && Kingdoms[a].Faith != Kingdoms[b].Faith
		&& Kingdoms[a].Culture >= 0 && Val(Cultures[Kingdoms[a].Culture], "faith") > 0.6f;

	// ------------------------------------------------------------------ the god in the sky

	/// <summary>How a kingdom sees the player: unaware, worship, fear or hate.</summary>
	public string Attitude(int k)
	{
		var kingdom = Kingdoms[k];
		if (!kingdom.Aware)
			return "unaware";
		if (kingdom.Love >= kingdom.Fear && kingdom.Love >= kingdom.Hate)
			return "worship";
		return kingdom.Hate > kingdom.Fear ? "hate" : "fear";
	}

	/// <summary>Remembers a person a power is about to kill (so their kingdom knows it was hurt).</summary>
	private void NoteVictim(int i)
	{
		if (!Units.Alive[i] || !Assets.Species[Units.Species[i]].IsPeople)
			return;
		int k = KingdomOfUnit(i);
		if (k >= 0)
			_powerVictims[k] = (_powerVictims.TryGetValue(k, out int n) ? n : 0) + 1;
	}

	/// <summary>The peoples saw the player act at (x, y): mercy (blessings, rain on their fires,
	/// miracles) makes them love the player; wrath on them makes them fear and hate; wrath they
	/// only see from afar makes them fear. A people that has seen enough knows there is a god in
	/// the sky, and gives the player a name and a place in its faith.</summary>
	private void PlayerActed(string power, float x, float y, float radius, bool mercy)
	{
		if (World == null)
		{
			_powerVictims.Clear();
			return;
		}
		float reach = radius + 25f;
		for (int k = 0; k < Kingdoms.Count; k++)
		{
			var kingdom = Kingdoms[k];
			if (!kingdom.Alive)
				continue;
			float seen = 0f;
			int nearest = -1;
			float best = float.MaxValue;
			for (int v = 0; v < Villages.Count; v++)
			{
				var village = Villages[v];
				if (!village.Alive || village.Kingdom != k)
					continue;
				float d = MathF.Sqrt((village.X + 0.5f - x) * (village.X + 0.5f - x) + (village.Y + 0.5f - y) * (village.Y + 0.5f - y));
				if (d < best)
				{
					best = d;
					nearest = v;
				}
				seen = Math.Max(seen, 1f - d / reach);
			}
			int hurt = _powerVictims.TryGetValue(k, out int h) ? h : 0;
			if (seen <= 0f && hurt == 0)
				continue;
			if (mercy)
				kingdom.Love += 14f * seen;
			else if (hurt > 0)
			{
				kingdom.Fear += Math.Min(30f, 6f + 2f * hurt);
				kingdom.Hate += Math.Min(30f, 5f + 2.5f * hurt);
			}
			else
				kingdom.Fear += 7f * seen;
			kingdom.Love = Math.Min(kingdom.Love, 100f);
			kingdom.Fear = Math.Min(kingdom.Fear, 100f);
			kingdom.Hate = Math.Min(kingdom.Hate, 100f);
			string before = kingdom.LastAttitude;
			if (!kingdom.Aware && kingdom.Love + kingdom.Fear + kingdom.Hate >= 20f)
			{
				kingdom.Aware = true;
				SeeTheGod(k, nearest >= 0 ? Villages[nearest].Name : kingdom.Name, power);
			}
			string now = Attitude(k);
			kingdom.LastAttitude = now;
			if (before != "" && before != "unaware" && now != before)
				LogEvent($"{kingdom.Name} now {(now == "worship" ? "worships" : now == "fear" ? "fears" : "hates")} the god in the sky.", "faith");
		}
		_powerVictims.Clear();
	}

	/// <summary>Kingdom k has seen the player: its faith names the god in the sky.</summary>
	private void SeeTheGod(int k, string place, string power)
	{
		var kingdom = Kingdoms[k];
		string people = Assets.Species[kingdom.Species].Name;
		string att = Attitude(k);
		if (kingdom.Faith < 0)
			return;
		var f = Faiths[kingdom.Faith];
		int gi = f.Gods.FindIndex(g => g.Player);
		if (gi < 0)
		{
			var god = NewGod(kingdom.Species, PlayerDomain);
			god.Player = true;
			god.Temper = att == "worship" ? "kind" : att == "hate" ? "wrathful" : "stern";
			f.Gods.Add(god);
			gi = f.Gods.Count - 1;
		}
		string name = f.Gods[gi].Name;
		string deed = power switch
		{
			"bless" or "miracle" => "healed the sick with a touch",
			"rain" => "brought rain upon the fires",
			"meteor" => "threw a burning star",
			"lightning" => "struck with lightning",
			"smite" => "struck down the living where they stood",
			"fire" => "set the land alight",
			_ => "reached down",
		};
		string feeling = att == "worship" ? "and they bow in love" : att == "hate" ? "and they swear never to kneel" : "and they tremble";
		AddMyth(f, new Myth
		{
			Year = Year(), Title = $"The Hand of {name}", Mind = "procedural", Event = "player", God = gi,
			Text = $"In year {Year()} a hand came down from the sky over {place} and {deed}. The {people} call it {name}, {feeling}.",
		});
		LogEvent($"the {people} of {kingdom.Name} have seen you: they call you {name}, and they {(att == "worship" ? "worship" : att == "hate" ? "hate" : "fear")} you.", "faith");
	}

	// ------------------------------------------------------------------ queries (HUD, tests)

	/// <summary>Living faiths: name, people, kingdoms, followers, fervour, gods (name, domain,
	/// temper, demand, player) and the newest myths (year, title, text, god, mind).</summary>
	public Godot.Collections.Array FaithTable()
	{
		var list = new Godot.Collections.Array();
		foreach (var f in Faiths)
		{
			if (!f.Alive)
				continue;
			var kingdoms = new List<string>();
			int followers = 0;
			float fervour = 0f;
			int n = 0;
			for (int k = 0; k < Kingdoms.Count; k++)
				if (Kingdoms[k].Alive && Kingdoms[k].Faith == f.Id)
				{
					kingdoms.Add(Kingdoms[k].Name);
					foreach (var v in Villages)
						if (v.Alive && v.Kingdom == k)
						{
							followers += v.Population;
							fervour += v.Faith;
							n++;
						}
				}
			var gods = new Godot.Collections.Array();
			foreach (var g in f.Gods)
				gods.Add(new Godot.Collections.Dictionary
				{
					["name"] = g.Name, ["domain"] = g.Domain, ["temper"] = g.Temper, ["demand"] = g.Demand, ["player"] = g.Player, ["year"] = g.Year,
				});
			var myths = new Godot.Collections.Array();
			for (int m = f.Myths.Count - 1; m >= 0 && myths.Count < 5; m--)
			{
				var myth = f.Myths[m];
				myths.Add(new Godot.Collections.Dictionary
				{
					["year"] = myth.Year, ["title"] = myth.Title, ["text"] = myth.Text, ["mind"] = myth.Mind, ["event"] = myth.Event,
					["god"] = myth.God >= 0 && myth.God < f.Gods.Count ? f.Gods[myth.God].Name : "",
				});
			}
			list.Add(new Godot.Collections.Dictionary
			{
				["index"] = f.Id, ["name"] = f.Name, ["people"] = Assets.Species[f.Species].Name, ["kingdoms"] = string.Join(", ", kingdoms),
				["followers"] = followers, ["fervour"] = n > 0 ? Math.Round(fervour / n) : 0, ["gods"] = gods, ["myths"] = myths,
				["myth_count"] = f.Myths.Count, ["parent"] = f.Parent >= 0 ? Faiths[f.Parent].Name : "", ["founded"] = f.Founded,
			});
		}
		return list;
	}

	/// <summary>How each living kingdom sees the player: attitude, love, fear, hate, god name.</summary>
	public Godot.Collections.Array PlayerStanding()
	{
		var list = new Godot.Collections.Array();
		for (int k = 0; k < Kingdoms.Count; k++)
		{
			var kingdom = Kingdoms[k];
			if (!kingdom.Alive)
				continue;
			string name = "";
			if (kingdom.Faith >= 0)
				foreach (var g in Faiths[kingdom.Faith].Gods)
					if (g.Player)
						name = g.Name;
			list.Add(new Godot.Collections.Dictionary
			{
				["index"] = k, ["kingdom"] = kingdom.Name, ["attitude"] = Attitude(k), ["love"] = Math.Round(kingdom.Love),
				["fear"] = Math.Round(kingdom.Fear), ["hate"] = Math.Round(kingdom.Hate), ["god"] = name,
			});
		}
		return list;
	}

	/// <summary>Makes the peoples witness an event now (tests): `what` is lightning, meteor, war…</summary>
	public void WitnessNow(string what, float x, float y, string phrase, int k1, int k2) => Witness(what, x, y, phrase, k1, k2);

	/// <summary>Runs one year of faith now (tests): fervour, conversions, schisms.</summary>
	public void FaithYearNow()
	{
		_nextFaithYear = 0;
		FaithStep();
	}
}
