using System;
using System.Collections.Generic;

namespace Animundi.Sim;

/// <summary>
/// What faiths do between kingdoms (0.6, docs/CULTURE.md § Faiths between kingdoms), on top of
/// Religion.cs:
/// - holy wars: a devout kingdom is quicker to plot war on a neighbour of another faith, and its
///   priests say so;
/// - conversions: once a year, a kingdom of lukewarm faith may take up the faith of a fervent
///   neighbour, ally or trade partner it does not hate (or of the one the player whispers);
/// - heresies: a faith kept by several kingdoms splits when one of them has drifted far from the
///   others; the heretics keep the old gods and find a new one.
/// The law "faiths" switches conversions and heresies off.
/// </summary>
public partial class Simulation
{
	private double _nextFaithYear;
	/// <summary>How much more likely a devout kingdom is to plot war on unbelievers.</summary>
	public const float HolyWarLean = 1.5f;

	/// <summary>The god a heresy finds, by the value its heretics hold dearest.</summary>
	private static readonly string[] HeresyDomains = { "war", "glory", "the forest", "gold", "wisdom", "the sky", "the wind", "the ancestors" };

	/// <summary>Whether kingdom a would call a war on b holy: other gods, and a devout culture.</summary>
	public bool HolyWar(int a, int b)
	{
		if (a < 0 || b < 0 || a >= Kingdoms.Count || b >= Kingdoms.Count)
			return false;
		var ca = Kingdoms[a].Culture;
		return ca.Religion != Kingdoms[b].Culture.Religion && ca.Faith > 55f && ca.Values[5] > 0.5f;
	}

	/// <summary>Every 2 s with the cultures: once a year, conversions and heresies.</summary>
	private void FaithsStep()
	{
		if (Scheduler.Time < _nextFaithYear)
			return;
		_nextFaithYear = Scheduler.Time + YearSeconds;
		if (Law("faiths"))
			ReligionYear();
	}

	private void ReligionYear()
	{
		Conversions();
		Heresies();
	}

	/// <summary>A kingdom may take up the faith of a neighbour, ally or trade partner whose faith
	/// burns 15 points hotter than its own and that it does not hate; the closer the bond and
	/// the wider the gap, the likelier.</summary>
	private void Conversions()
	{
		for (int a = 0; a < Kingdoms.Count; a++)
		{
			var ka = Kingdoms[a];
			if (!ka.Alive)
				continue;
			for (int b = 0; b < Kingdoms.Count; b++)
			{
				var kb = Kingdoms[b];
				if (b == a || !kb.Alive || kb.Culture.Religion == ka.Culture.Religion || AtWar(a, b))
					continue;
				bool close = ka.Allies.Contains(b) || _trade.Exists(r => KingdomOf(r.A) == a && KingdomOf(r.B) == b || KingdomOf(r.A) == b && KingdomOf(r.B) == a);
				if (!close && !Bordering(a, b))
					continue;
				float gap = kb.Culture.Faith - ka.Culture.Faith;
				if (gap < 15f || Opinion(a, b) < -15f)
					continue;
				if (_cultureRng.NextDouble() < (close ? 0.1 : 0.05) * gap / 40.0)
				{
					Convert(a, b, whispered: false);
					break;
				}
			}
		}
	}

	/// <summary>Kingdom a takes up the faith of kingdom b: b's creed and gods (the god it makes
	/// of the player stays theirs), faith a little shaken. Its old myths are still told.</summary>
	private void Convert(int a, int b, bool whispered)
	{
		var ca = Kingdoms[a].Culture;
		var cb = Kingdoms[b].Culture;
		string old = ca.Creed;
		ca.Religion = cb.Religion;
		ca.Creed = cb.Creed;
		var player = ca.Gods.Find(g => g.Player);
		ca.Gods.Clear();
		ca.Gods.AddRange(cb.Gods.FindAll(g => !g.Player));
		if (player != null)
			ca.Gods.Add(player);
		ca.Faith *= 0.75f;
		foreach (var v in Villages)
			if (v.Alive && v.Kingdom == a)
				v.ModsDirty = true;
		string people = Assets.Species[Kingdoms[a].Species].Name;
		LogEvent($"the {people} of {Kingdoms[a].Name} turn from {old} to {cb.Creed}, the faith of {Kingdoms[b].Name}"
			+ (whispered ? ", as a voice in their dreams told them." : "."), "culture");
		Remember(a, "freedom", $"the {people} turned to {cb.Creed}", 1.5f);
	}

	/// <summary>A faith kept by several kingdoms splits when one of them values things far from
	/// the others and still cares for its gods: the heretics keep the old gods, find a new one
	/// in what they hold dearest, and name their faith after it.</summary>
	private void Heresies()
	{
		for (int k = 0; k < Kingdoms.Count; k++)
		{
			var kingdom = Kingdoms[k];
			if (!kingdom.Alive)
				continue;
			var c = kingdom.Culture;
			var brothers = new List<int>();
			for (int o = 0; o < Kingdoms.Count; o++)
				if (o != k && Kingdoms[o].Alive && Kingdoms[o].Culture.Religion == c.Religion)
					brothers.Add(o);
			if (brothers.Count == 0 || c.Faith < 25f)
				continue;
			float kinship = 0f;
			foreach (int o in brothers)
				kinship += Kinship(c, Kingdoms[o].Culture);
			kinship /= brothers.Count;
			if (kinship > 0.85f || _cultureRng.NextDouble() > 0.04 + (0.85f - kinship) * 0.6)
				continue;
			int dearest = 0;
			for (int n = 1; n < c.Values.Length; n++)
				if (c.Values[n] > c.Values[dearest])
					dearest = n;
			string domain = HeresyDomains[dearest];
			string old = c.Creed;
			var prophet = c.Gods.Find(g => !g.Player && g.Domain == domain);
			if (prophet == null)
			{
				prophet = new God
				{
					Name = _languages[kingdom.Species].PersonName(), Domain = domain, Year = Year(),
					Temper = Tempers[_cultureRng.Next(Tempers.Length)],
				};
				if (c.Gods.FindAll(g => !g.Player).Count >= MaxGods)
					c.Gods.Remove(c.Gods.Find(g => !g.Player));
				c.Gods.Add(prophet);
			}
			c.Religion = _nextReligion++;
			c.Creed = "the Way of " + prophet.Name;
			string people = Assets.Species[kingdom.Species].Name;
			LogEvent($"heresy: the {people} of {kingdom.Name} break from {old} and follow {c.Creed}, god of {domain}.", "culture");
			Remember(k, "freedom", $"the {people} broke from {old} for {c.Creed}", 2f);
		}
	}

	// ------------------------------------------------------------------ tests and powers

	/// <summary>Kingdom a takes up kingdom b's faith now (the Convert whisper, tests). False when
	/// it makes no sense (the same kingdom or faith, a fallen kingdom).</summary>
	public bool ConvertKingdom(int a, int b)
	{
		if (a == b || a < 0 || b < 0 || a >= Kingdoms.Count || b >= Kingdoms.Count || !Kingdoms[a].Alive || !Kingdoms[b].Alive
			|| Kingdoms[a].Culture.Religion == Kingdoms[b].Culture.Religion)
			return false;
		Convert(a, b, whispered: true);
		return true;
	}

	/// <summary>Runs a year of conversions and heresies now, whatever the law (tests).</summary>
	public void ReligionYearNow() => ReligionYear();

	/// <summary>Sets a kingdom's faith, 0..100 (tests).</summary>
	public void SetFaith(int k, float faith) => Kingdoms[k].Culture.Faith = Math.Clamp(faith, 0f, 100f);

	/// <summary>Sets one of a kingdom's values, 0..1 (tests).</summary>
	public void SetCultureValue(int k, string value, float v)
	{
		int n = Array.IndexOf(ValueNames, value);
		if (n >= 0)
			Kingdoms[k].Culture.Values[n] = Math.Clamp(v, 0f, 1f);
	}
}
