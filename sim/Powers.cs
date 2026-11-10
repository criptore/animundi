using System;
using System.Collections.Generic;
using Godot;

namespace Animundi.Sim;

/// <summary>
/// The god powers (0.9): what the player does to the world. Each power is one call with a place
/// in tiles, and returns how much it did (0 when there was nothing to act on: the sea, outside
/// the map). The interface (scripts/ui/power_bar.gd) only chooses the power and the brush.
/// </summary>
public partial class Simulation
{
	private readonly List<int> _powerFound = new();

	/// <summary>Living units within `radius` tiles of (x, y), whatever moved since the last step.</summary>
	private List<int> UnitsWithin(float x, float y, float radius)
	{
		_powerFound.Clear();
		if (World == null || radius <= 0f)
			return _powerFound;
		Zones.Rebuild(Units);
		Zones.Query(Units, x, y, radius, _powerFound);
		_powerFound.RemoveAll(i => !Units.Alive[i]);
		return _powerFound;
	}

	/// <summary>Calls `act` for every tile of the map whose centre is within `radius` of (x, y).</summary>
	private void TilesWithin(float x, float y, float radius, Action<int> act)
	{
		if (World == null)
			return;
		for (int ty = (int)MathF.Floor(y - radius); ty <= (int)MathF.Floor(y + radius); ty++)
			for (int tx = (int)MathF.Floor(x - radius); tx <= (int)MathF.Floor(x + radius); tx++)
			{
				float dx = tx + 0.5f - x, dy = ty + 0.5f - y;
				if (World.InBounds(tx, ty) && dx * dx + dy * dy <= radius * radius)
					act(World.Index(tx, ty));
			}
	}

	private bool OnLand(float x, float y) => World != null && World.IsLandAt(x, y);

	// ------------------------------------------------------------------ fire and water

	/// <summary>Sets the land alight under the brush. Returns the tiles that caught fire.</summary>
	public int PowerFire(float x, float y, float radius) => World == null ? 0 : Ignite(x, y, radius);

	/// <summary>A bolt of lightning: kills what stands there and lights the land. Returns the
	/// creatures killed.</summary>
	public int PowerLightning(float x, float y)
	{
		if (!OnLand(x, y))
			return 0;
		int killed = 0;
		foreach (int i in UnitsWithin(x, y, 1.5f).ToArray())
		{
			KillUnit(i, Death.Other);
			killed++;
		}
		Ignite(x, y, 1.5f);
		LogEvent($"lightning strikes near ({(int)x}, {(int)y}).", "disasters");
		return killed;
	}

	/// <summary>Rain: puts out the fires under the brush (land and plants; burning buildings too)
	/// and makes the grass grow back. Returns the burning tiles put out.</summary>
	public int PowerRain(float x, float y, float radius)
	{
		int doused = 0;
		TilesWithin(x, y, radius, t =>
		{
			if (World.Water[t] != SimWorld.WaterLand)
				return;
			if (TileBurn[t] > 0f)
			{
				TileBurn[t] = 0f;
				doused++;
			}
			for (int p = _tileFirst[t]; p >= 0; p = _pNext[p])
				if (_pBurn[p] > 0f)
				{
					_pBurn[p] = 0f;
					MarkStrip((int)_pY[p]);
				}
			int b = _buildingAt.Length > t ? _buildingAt[t] : -1;
			if (b >= 0 && Buildings[b].Burning > 0f)
				Buildings[b].Burning = 0f;
			if (Scorch[t] <= 64)
				Grass[t] = Math.Max(Grass[t], _fertility[World.Biome[t]]);
		});
		_burningTiles.RemoveAll(t => TileBurn[t] == 0f);
		_burning.RemoveAll(p => !_pAlive[p] || _pBurn[p] == 0f);
		return doused;
	}

	// ------------------------------------------------------------------ destruction and mercy

	/// <summary>A meteor: kills everything under it, flattens the plants, scorches the ground,
	/// sets buildings and the land around alight. Returns the creatures killed.</summary>
	public int PowerMeteor(float x, float y, float radius)
	{
		if (!OnLand(x, y))
			return 0;
		int killed = PowerSmite(x, y, radius);
		TilesWithin(x, y, radius, t =>
		{
			if (World.Water[t] != SimWorld.WaterLand)
				return;
			while (_tileFirst[t] >= 0)
			{
				MarkStrip((int)_pY[_tileFirst[t]]);
				RemovePlant(_tileFirst[t]);
			}
			TileBurn[t] = 0f;
			Grass[t] = 0f;
			Scorch[t] = 255;
			_scorchChanged.Add(t);
			int b = _buildingAt.Length > t ? _buildingAt[t] : -1;
			if (b >= 0 && Buildings[b].Alive && Buildings[b].Burning == 0f && Buildings[b].Type != _tRuin)
				SetBuildingOnFire(b);
		});
		_burningTiles.RemoveAll(t => TileBurn[t] == 0f);
		_burning.RemoveAll(p => !_pAlive[p] || _pBurn[p] == 0f);
		Ignite(x, y, radius + 1.5f);
		LogEvent($"a meteor falls near ({(int)x}, {(int)y}).", "disasters");
		return killed;
	}

	/// <summary>Kills every creature under the brush. Returns how many.</summary>
	public int PowerSmite(float x, float y, float radius)
	{
		int killed = 0;
		foreach (int i in UnitsWithin(x, y, radius).ToArray())
		{
			KillUnit(i, Death.Other);
			killed++;
		}
		return killed;
	}

	/// <summary>Heals, feeds and waters every creature under the brush. Returns how many.</summary>
	public int PowerBless(float x, float y, float radius)
	{
		int blessed = 0;
		foreach (int i in UnitsWithin(x, y, radius))
		{
			Units.Health[i] = Math.Max(Units.Health[i], MaxHealth(i));
			Units.Hunger[i] = 0f;
			Units.Thirst[i] = 0f;
			blessed++;
		}
		return blessed;
	}
}
