# Building the game (1.0)

Animundi builds into a game to share for **Linux**, **Windows** and **macOS** with Godot 4.3 .NET (`export_presets.cfg`).

## By hand

1. Godot 4.3 .NET and the [.NET 8 SDK](https://dotnet.microsoft.com/download/dotnet/8.0).
2. Godot's export templates for 4.3 .NET (Editor › Manage Export Templates, or unzip `Godot_v4.3-stable_mono_export_templates.tpz` into `~/.local/share/godot/export_templates/4.3.stable.mono/`).
3. Then:

```bash
tools/build.sh all
```

The builds land in `build/<platform>/` and are zipped as `build/Animundi-linux.zip`, `build/Animundi-windows.zip`, `build/Animundi-macos.zip` (`GODOT=/path/to/godot` if Godot is not on the path). `tools/build.sh linux` builds one platform only.

To ship the built-in mind's model with the game (else it is downloaded once, on first launch, when the player asks for it):

```bash
tools/build.sh all --with-model
```

## By GitHub

`.github/workflows/release.yml` builds the three platforms when a version tag is pushed (`git tag v1.0.0 && git push --tags`) and attaches the zips to the release; it can also be run by hand from the Actions tab (the zips are then the run's artifacts).

## What a build holds

- The game (`Animundi.x86_64` / `Animundi.exe` / the macOS app), its pack (`Animundi.pck`) and the .NET libraries (`data_Animundi_*`), llama.cpp for every CPU variant included.
- The data files (`data/*.json`) are packed with the game; tests, tools, art sources and docs are left out.
- The player's saves, stamps, achievements and mods live in Godot's user folder (`~/.local/share/godot/app_userdata/Animundi/`, `%APPDATA%\Godot\app_userdata\Animundi\`).

The Linux and Windows builds of 1.0 were made and checked this way (the Linux build started and showed its title screen). The macOS build is not signed: on a Mac, open it with a right-click › Open the first time.
