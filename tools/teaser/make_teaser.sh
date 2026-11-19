#!/bin/bash
# Films every shot of the teaser (tools/teaser.gd) and edits it (make_teaser.py).
#   tools/teaser/make_teaser.sh <work dir> [seed] [parallel jobs]
# Writes <work dir>/animundi_teaser.mp4. Needs Godot 4.3 .NET as `godot`, the C# project built
# (dotnet build), ffmpeg, python3 with numpy and fonttools[woff] (brotli), and a display: on a
# headless machine it runs under xvfb-run (a Vulkan driver such as Mesa's lavapipe works, slowly).
set -e
WORK=$(realpath -m "${1:?work dir}")
SEED=${2:-anima}
JOBS=${3:-3}
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
SHOTS="descent village nightfall shore storm meteor dragons war dawn interface"
mkdir -p "$WORK/shots" "$WORK/teaser_work/fonts"
python3 - "$ROOT" "$WORK/teaser_work/fonts" <<'PY'
import sys
from fontTools.ttLib import TTFont
for n in ("Jersey10-Regular", "Jersey15-Regular"):
    f = TTFont(f"{sys.argv[1]}/assets/fonts/{n}.woff2")
    f.flavor = None
    f.save(f"{sys.argv[2]}/{n}.ttf")
PY
film() {
	rm -rf "$WORK/shots/$1" && mkdir -p "$WORK/shots/$1"
	xvfb-run -a -s "-screen 0 1920x1080x24" godot --path "$ROOT" --resolution 1920x1080 --fixed-fps 30 \
		--write-movie "$WORK/shots/$1/f.png" --script res://tools/teaser.gd -- "$1" "$SEED" > "$WORK/shots/$1.log" 2>&1 || true
	echo "$1: $(ls "$WORK/shots/$1" | wc -l) frames"
}
export -f film
export WORK SEED ROOT
echo $SHOTS | tr ' ' '\n' | xargs -P "$JOBS" -I{} bash -c 'film {}'
python3 "$ROOT/tools/teaser/make_teaser.py" "$WORK/shots" "$WORK/animundi_teaser.mp4"
