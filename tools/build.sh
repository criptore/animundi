#!/usr/bin/env bash
# Builds a playable Animundi (1.0, docs/BUILD.md) with Godot 4.3 .NET and its export templates:
#   tools/build.sh [linux|windows|macos|all] [--with-model]
# The builds land in build/<platform>/; each is zipped as build/Animundi-<platform>.zip.
# --with-model ships the built-in mind's model next to the game (tools/bundle_model.sh), so
# players do not download it on first launch.
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
which="${1:-all}"
model="${2:-}"
platforms=(linux windows macos)
[ "$which" != "all" ] && platforms=("$which")
"$GODOT" --headless --path . --import >/dev/null 2>&1 || true
for p in "${platforms[@]}"; do
	case "$p" in
		linux) preset="Linux"; out="build/linux/Animundi.x86_64" ;;
		windows) preset="Windows"; out="build/windows/Animundi.exe" ;;
		macos) preset="macOS"; out="build/macos/Animundi.zip" ;;
		*) echo "unknown platform $p"; exit 1 ;;
	esac
	mkdir -p "$(dirname "$out")"
	"$GODOT" --headless --path . --export-release "$preset" "$out"
	if [ "$model" = "--with-model" ] && [ "$p" != "macos" ]; then
		tools/bundle_model.sh "$(dirname "$out")"
	fi
	if [ "$p" != "macos" ]; then
		(cd "$(dirname "$out")" && zip -qr "../Animundi-$p.zip" .)
	else
		cp "$out" "build/Animundi-macos.zip"
	fi
	echo "built build/Animundi-$p.zip"
done
