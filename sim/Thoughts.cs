using System;
using System.Collections.Generic;
using System.Text;
using System.Text.Json;

namespace Animundi.Sim;

/// <summary>
/// Questions to the local model other than inventions (0.6 Culture): a culture's mind writing a
/// law, a ritual or a taboo, a faith telling a myth, the chronicler writing the years. Each
/// question is asked in the background; its answer is checked by `accept` (null when taken,
/// else why it was refused), and when the model is absent, slow or wrong, `fallback` does the
/// same thing procedurally. The world never waits.
/// </summary>
public partial class Simulation
{
	private sealed class Thought
	{
		public System.Threading.Tasks.Task<string> Task;
		public double Asked;
		public Func<string, string> Accept;
		public Action Fallback;
		public string What;
	}

	private readonly List<Thought> _thoughts = new();
	/// <summary>Answers of the model to these questions (inventions count apart: ModelAnswers),
	/// the ones refused or given up, and the last answer and why it was refused ("" if taken).</summary>
	public int ThoughtAnswers { get; private set; }
	public int ThoughtFailures { get; private set; }
	public string LastThoughtAnswer { get; private set; } = "";
	public string LastThoughtError { get; private set; } = "";

	/// <summary>Questions waiting for the model.</summary>
	public int ThoughtsPending() => _thoughts.Count;
	/// <summary>At most this many questions wait for the model; more go to the procedural minds.</summary>
	public const int MaxThoughts = 6;

	/// <summary>Whether a model (a server the player runs, or the built-in one) can answer now.</summary>
	public bool ModelReady() => _llmUrl != "" || LocalModel.Status == LocalModel.State.Ready;

	/// <summary>Asks the model `prompt` (the answer forced by `grammar` for the built-in model, by
	/// `schema` for a server). Without a model, or with too many questions waiting, `fallback`
	/// runs now.</summary>
	private void Ponder(string what, string prompt, string grammar, string schema, string system, int tokens,
		Func<string, string> accept, Action fallback)
	{
		System.Threading.Tasks.Task<string> task = null;
		if (_thoughts.Count < MaxThoughts)
		{
			if (_llmUrl != "")
				task = AskModel(prompt, schema, tokens);
			else if (LocalModel.Status == LocalModel.State.Ready)
				task = LocalModel.Generate(prompt, grammar, system, tokens);
		}
		if (task == null)
		{
			fallback();
			return;
		}
		_thoughts.Add(new Thought { Task = task, Asked = Scheduler.Time, Accept = accept, Fallback = fallback, What = what });
	}

	/// <summary>Every 2 s: answers that came back are checked and taken, or replaced by the
	/// procedural minds; questions the model takes too long over are given up.</summary>
	private void ThoughtsStep()
	{
		for (int n = _thoughts.Count - 1; n >= 0; n--)
		{
			var t = _thoughts[n];
			if (t.Task.IsCompleted)
			{
				_thoughts.RemoveAt(n);
				string json = t.Task.Status == System.Threading.Tasks.TaskStatus.RanToCompletion ? t.Task.Result : null;
				string error;
				try
				{
					error = json == null ? "no answer: " + t.Task.Exception?.GetBaseException().Message : t.Accept(json);
				}
				catch (Exception e)
				{
					error = e.Message;
				}
				LastThoughtAnswer = json ?? "";
				LastThoughtError = error == null ? "" : $"{t.What}: {error}";
				if (error == null)
					ThoughtAnswers++;
				else
				{
					ThoughtFailures++;
					t.Fallback();
				}
			}
			else if (Scheduler.Time - t.Asked > ModelTimeout)
			{
				_thoughts.RemoveAt(n);
				ThoughtFailures++;
				t.Fallback();
			}
		}
	}

	// ------------------------------------------------------------------ helpers for the languages

	/// <summary>Letters, digits and plain punctuation only: what the grammars let through, and
	/// what a text written by a mind may hold.</summary>
	public static bool PlainText(string s, int max)
	{
		if (s == null || s.Length > max)
			return false;
		foreach (char c in s)
			if (!char.IsLetterOrDigit(c) && " ,.'!?-:;()".IndexOf(c) < 0)
				return false;
		return true;
	}

	/// <summary>A name: 2..max letters, spaces, hyphens or apostrophes.</summary>
	public static bool PlainName(string s, int max)
	{
		if (string.IsNullOrWhiteSpace(s) || s.Trim().Length < 2 || s.Length > max)
			return false;
		foreach (char c in s)
			if (!char.IsLetter(c) && c != ' ' && c != '-' && c != '\'')
				return false;
		return true;
	}

	/// <summary>GBNF alternatives of quoted words.</summary>
	private static string GbnfWords(IEnumerable<string> words)
	{
		var parts = new List<string>();
		foreach (var w in words)
			parts.Add($"\"\\\"{w}\\\"\"");
		return string.Join(" | ", parts);
	}

	/// <summary>A GBNF key: `"key":` with an optional space after it.</summary>
	private static string GbnfKey(string key) => $"\"\\\"{key}\\\":\" ws";

	/// <summary>GBNF for a whole number from 1 to max (max under 100).</summary>
	private static string GbnfUpTo(int max)
	{
		var parts = new List<string> { "[1-9]" };
		int tens = max / 10, units = max % 10;
		if (tens >= 2)
			parts.Add($"[1-{tens - 1}] [0-9]");
		if (tens >= 1)
			parts.Add($"\"{tens}\" [0-{units}]");
		return string.Join(" | ", parts);
	}

	/// <summary>The rules every grammar of 0.6 shares: names, texts of a given length, spaces.</summary>
	private static string GbnfCommon(int textMax) => string.Join("\n", new[]
	{
		"name ::= \"\\\"\" [A-Z] [a-zA-Z' -]{1,30} \"\\\"\"",
		$"text ::= \"\\\"\" [A-Z] [a-zA-Z0-9 ,.'!?-]{{0,{textMax}}} \"\\\"\"",
		"ws ::= [ ]?",
	}) + "\n";

	private static Dictionary<string, object> StringSchema(int max) => new() { ["type"] = "string", ["maxLength"] = max };

	private static Dictionary<string, object> EnumSchema(IEnumerable<string> words) => new() { ["enum"] = new List<string>(words) };

	private static string SchemaJson(object schema) => JsonSerializer.Serialize(schema);

	/// <summary>A short summary of a kingdom for the minds: who, where, how they fare.</summary>
	private string Situation(int k)
	{
		var kingdom = Kingdoms[k];
		var village = Villages[kingdom.Capital];
		var sb = new StringBuilder();
		string people = Assets.Species[kingdom.Species].Name;
		sb.Append($"The {people} of the kingdom of {kingdom.Name}, year {Year()} of their world. ");
		sb.Append($"Capital {village.Name}: {village.Population} people, food {village.Food:0}, gold {village.Gold:0}. ");
		var enemies = new List<string>();
		foreach (var w in Wars)
			if (w.A == k || w.B == k)
				enemies.Add(Kingdoms[w.A == k ? w.B : w.A].Name);
		sb.Append(enemies.Count > 0 ? $"At war with {string.Join(", ", enemies)}. " : "At peace. ");
		if (kingdom.Culture >= 0)
		{
			var c = Cultures[kingdom.Culture];
			sb.Append($"Their culture, the {c.Name} ways: a {c.Society}; they value {TopValues(c, 3)}; they {c.NatureWay} nature. ");
		}
		if (kingdom.Faith >= 0)
		{
			var f = Faiths[kingdom.Faith];
			var gods = new List<string>();
			foreach (var g in f.Gods)
				gods.Add($"{g.Name} ({g.Domain})");
			sb.Append($"Their faith, {f.Name}: {string.Join(", ", gods)}. ");
		}
		string att = Attitude(k);
		if (att != "unaware")
			sb.Append($"They {(att == "worship" ? "worship" : att == "fear" ? "fear" : "hate")} the god who acts from the sky. ");
		return sb.ToString();
	}
}
