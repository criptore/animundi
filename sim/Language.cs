using System;
using System.Collections.Generic;
using System.Text;

namespace Animundi.Sim;

/// <summary>
/// A generated language (docs/GAME_DESIGN.md section 9): a people's sounds (data/races.json) narrowed
/// and reweighted by the world's seed, so the Elves of one world don't speak like those of the
/// next. It makes names for people, families and places from syllables and a small lexicon of
/// roots ("home", "river", "fire"...) that settlement names combine.
/// </summary>
public sealed class Language
{
	private readonly string[] _consonants;
	private readonly string[] _vowels;
	private readonly string[] _patterns;
	private readonly string[] _endings;
	private readonly Dictionary<string, string> _lexicon = new();
	private readonly Random _rng;

	public static readonly string[] Roots = { "home", "river", "fire", "stone", "tree", "hill", "sun", "star", "wolf", "king" };

	public Language(LanguageRecord rec, Random worldRng)
	{
		_rng = new Random(worldRng.Next());
		// Keep most of the people's sounds, drop a few: each world's dialect differs.
		_consonants = Pick(rec.Consonants.Split(' ', StringSplitOptions.RemoveEmptyEntries), 0.75);
		_vowels = Pick(rec.Vowels.Split(' ', StringSplitOptions.RemoveEmptyEntries), 0.8);
		_patterns = rec.Patterns.Count > 0 ? rec.Patterns.ToArray() : new[] { "CV" };
		_endings = Pick(rec.Endings.ToArray(), 0.7);
		foreach (var root in Roots)
			_lexicon[root] = Tidy(Syllable());
	}

	private string[] Pick(string[] all, double keep)
	{
		var kept = new List<string>();
		foreach (var s in all)
			if (_rng.NextDouble() < keep)
				kept.Add(s);
		if (kept.Count == 0 && all.Length > 0)
			kept.Add(all[_rng.Next(all.Length)]);
		return kept.Count > 0 ? kept.ToArray() : new[] { "a" };
	}

	private string Syllable()
	{
		var sb = new StringBuilder();
		foreach (char c in _patterns[_rng.Next(_patterns.Length)])
			sb.Append(c == 'C' ? _consonants[_rng.Next(_consonants.Length)] : _vowels[_rng.Next(_vowels.Length)]);
		return sb.ToString();
	}

	private string Syllables(int n)
	{
		var sb = new StringBuilder();
		for (int k = 0; k < n; k++)
			sb.Append(Syllable());
		return sb.ToString();
	}

	private static string Capital(string s) => s.Length == 0 ? s : char.ToUpperInvariant(s[0]) + s[1..];

	/// <summary>Smooths a word: no more than two vowels or two equal letters in a row.</summary>
	private static string Tidy(string s)
	{
		var sb = new StringBuilder();
		int vowels = 0;
		foreach (char c in s)
		{
			bool vowel = "aeiouy".IndexOf(c) >= 0;
			vowels = vowel ? vowels + 1 : 0;
			int n = sb.Length;
			if (vowels > 2 || (n >= 2 && sb[n - 1] == c && sb[n - 2] == c))
				continue;
			sb.Append(c);
		}
		return sb.ToString();
	}

	/// <summary>A word of the lexicon ("home", "river"...).</summary>
	public string Word(string root) => _lexicon.TryGetValue(root, out var w) ? w : Syllables(2);

	/// <summary>A given name: one or two syllables and, often, a typical ending.</summary>
	public string PersonName()
	{
		string name = Syllables(1 + _rng.Next(2));
		if (_rng.NextDouble() < 0.6)
			name += _endings[_rng.Next(_endings.Length)];
		name = Tidy(name);
		return Capital(name.Length > 9 ? name[..9] : name);
	}

	/// <summary>A settlement name: a root of the lexicon and an ending, or two roots.</summary>
	public string PlaceName()
	{
		string a = Word(Roots[_rng.Next(Roots.Length)]);
		string b = _rng.NextDouble() < 0.5 ? _endings[_rng.Next(_endings.Length)] : Word(Roots[_rng.Next(Roots.Length)]);
		string name = Tidy(a + b);
		return Capital(name.Length > 10 ? name[..10] : name);
	}
}
