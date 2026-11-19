using System;
using System.Collections.Generic;
using Godot;

namespace Animundi.Sim;

/// <summary>
/// Moods of the world (0.8, docs/AGES.md): eras of a few decades (data/eras.json) that change
/// the weather, growth, harvests, fire, disasters, monsters, spirits and how fast peoples learn,
/// and the light over the map. Calm, bright, dark, rainy, cold, scorching, magical...
///
/// When an era ends the next is drawn by its weight; a warming world (Ages.cs) leans to scorching
/// eras, and the same mood seldom comes twice in a row. The player can bring an era on (the Ages
/// powers): it starts at once and lasts its decades. With the law "eras" off, the world stays calm.
/// </summary>
public partial class Simulation
{
	public sealed class Era
	{
		public EraRecord Rec;
		public int From;
		public double Until;
		public bool ByPlayer;
	}

	public Era CurrentEra { get; private set; }
	public readonly List<(string name, int from, int to, bool player)> PastEras = new();
	private Random _eraRng = new(1);
	private static readonly EraRecord CalmEra = new() { Id = "calm", Name = "Calm Era" };

	private void SetupEras(int seed)
	{
		_eraRng = new Random(seed ^ 0xe7a5);
		PastEras.Clear();
		// A world begins calm, for a while.
		var calm = Assets.Eras.Find(e => e.Id == "calm") ?? CalmEra;
		CurrentEra = new Era { Rec = calm, From = 1, Until = YearSeconds * (15.0 + 15.0 * _eraRng.NextDouble()) };
	}

	/// <summary>Every second with the spirits: an era that has run its course gives way.</summary>
	private void EraStep()
	{
		if (CurrentEra == null || Scheduler.Time < CurrentEra.Until)
			return;
		NextEra(null, false);
	}

	/// <summary>Brings era `id` on now (null: drawn by weight, the warming world leaning to the
	/// scorching ones). Returns the new era, or null for an unknown id.</summary>
	private Era NextEra(string id, bool byPlayer)
	{
		EraRecord rec = null;
		if (id != null)
			rec = Assets.Eras.Find(e => e.Id == id);
		else if (!Law("eras"))
			rec = Assets.Eras.Find(e => e.Id == "calm") ?? CalmEra;
		else
		{
			float total = 0f;
			var weights = new List<(EraRecord rec, float w)>();
			foreach (var e in Assets.Eras)
			{
				float w = e.Weight;
				if (CurrentEra != null && e.Id == CurrentEra.Rec.Id)
					w *= 0.15f;
				if (e.Id == "scorching")
					w *= 1f + Warming;
				if (e.Id == "cold")
					w /= 1f + Warming * 0.5f;
				weights.Add((e, w));
				total += w;
			}
			double r = _eraRng.NextDouble() * total;
			foreach (var (e, w) in weights)
			{
				rec = e;
				if ((r -= w) <= 0)
					break;
			}
		}
		if (rec == null)
			return null;
		if (CurrentEra != null)
		{
			PastEras.Add((CurrentEra.Rec.Name, CurrentEra.From, Year(), CurrentEra.ByPlayer));
			if (PastEras.Count > 12)
				PastEras.RemoveAt(0);
		}
		CurrentEra = new Era { Rec = rec, From = Year(), Until = Scheduler.Time + YearSeconds * (20.0 + 20.0 * _eraRng.NextDouble()), ByPlayer = byPlayer };
		string words = rec.Lore.TrimEnd('.').ToLower();
		LogEvent(byPlayer ? $"by your will, a {rec.Name.ToLower()} begins: {words}." : $"a {rec.Name.ToLower()} begins: {words}.", "nature");
		return CurrentEra;
	}

	private EraRecord EraNow => CurrentEra?.Rec ?? CalmEra;

	// What the era changes (Nature.cs, Disasters.cs, Monsters.cs, Spirits.cs, Ages.cs, Villages.cs).
	private float EraGrowth() => EraNow.Growth * (NuclearWinter >= 2f ? 0.4f : 1f);
	private float EraCold() => EraNow.Cold;
	private float EraFire() => EraNow.Fire * (1f + Math.Min(1f, Warming * 0.25f));
	private float EraMonsters() => Math.Max(0.2f, EraNow.Monsters);
	private float EraSpirits() => EraNow.Spirits;
	private float EraKnowledge() => EraNow.Knowledge;
	private float EraHarvest() => EraNow.Harvest * (NuclearWinter >= 2f ? 0.35f : 1f);

	/// <summary>How much likelier a kind of disaster is now: the era, and the warmer world for
	/// droughts, wildfires and floods.</summary>
	private float EraDisaster(string kind)
	{
		float w = EraNow.DisasterWeight(kind);
		if (kind == "drought" || kind == "wildfire")
			w *= 1f + Warming * 0.35f;
		else if (kind == "flood")
			w *= 1f + Warming * 0.2f;
		return w;
	}

	// ------------------------------------------------------------------ powers and queries

	/// <summary>The player brings era `id` on now. False for an unknown era.</summary>
	public bool PowerEra(string id)
	{
		var era = NextEra(id, true);
		if (era == null)
			return false;
		// The peoples feel the world turn.
		foreach (var k in Kingdoms)
			if (k.Alive && k.Capital >= 0)
			{
				var v = Villages[k.Capital];
				GodActs(era.Rec.Id is "dark" or "scorching" or "cold" ? "wrath" : "bless", v.X, v.Y, 2f, 2);
			}
		return true;
	}

	/// <summary>The ids and names of the eras of data/eras.json (power bar, tests).</summary>
	public string[] EraIds()
	{
		var ids = new string[Assets.Eras.Count];
		for (int k = 0; k < ids.Length; k++)
			ids[k] = Assets.Eras[k].Id;
		return ids;
	}

	public string EraName() => EraNow.Name;

	public string EraId() => EraNow.Id;

	/// <summary>The light over the world: the era's tint, greyed and darkened under the ash of a
	/// nuclear winter, a little brown under a warmer sky.</summary>
	public Color EraTint()
	{
		var t = EraNow.Tint;
		var c = new Color(t.Count > 0 ? t[0] : 1f, t.Count > 1 ? t[1] : 1f, t.Count > 2 ? t[2] : 1f);
		if (NuclearWinter > 0f)
		{
			float ash = Math.Min(1f, NuclearWinter / 4f);
			c = c.Lerp(new Color(0.62f, 0.62f, 0.66f), ash * 0.7f);
		}
		if (Warming > 1f)
			c = c.Lerp(new Color(1.04f, 0.96f, 0.86f), Math.Min(0.5f, (Warming - 1f) * 0.15f));
		return c;
	}

	/// <summary>The era now: id, name, lore, since (year), years_left, by_player, and its effects;
	/// with the past eras.</summary>
	public Godot.Collections.Dictionary EraTable()
	{
		var e = EraNow;
		var past = new Godot.Collections.Array();
		for (int n = PastEras.Count - 1; n >= 0; n--)
			past.Add($"{PastEras[n].name}, years {PastEras[n].from}-{PastEras[n].to}{(PastEras[n].player ? " (by your will)" : "")}");
		return new Godot.Collections.Dictionary
		{
			["id"] = e.Id, ["name"] = e.Name, ["lore"] = e.Lore, ["since"] = CurrentEra?.From ?? 1,
			["years_left"] = CurrentEra != null ? Math.Max(0, (int)Math.Ceiling((CurrentEra.Until - Scheduler.Time) / YearSeconds)) : 0,
			["by_player"] = CurrentEra?.ByPlayer ?? false, ["growth"] = EraGrowth(), ["cold"] = EraCold(), ["fire"] = EraFire(),
			["monsters"] = EraMonsters(), ["knowledge"] = EraKnowledge(), ["harvest"] = EraHarvest(), ["past"] = past,
		};
	}

	/// <summary>Brings era `id` on, as nature would (scenarios). False for an unknown era.</summary>
	public bool SetEra(string id) => NextEra(id, false) != null;

	/// <summary>Ends the era now: the next one comes (tests).</summary>
	public void EraNextNow() => NextEra(null, false);
}
