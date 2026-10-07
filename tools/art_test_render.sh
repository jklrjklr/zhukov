#!/usr/bin/env bash
# Renders scenes/art_test/art_test.tscn to docs/art_test/{art_test.mp4,art_test.gif,still_1..3.png}.
# Usage: tools/art_test_render.sh [frames]   (needs gd, xvfb-run, ffmpeg, python3+Pillow)
set -euo pipefail
cd "$(dirname "$0")/.."
FRAMES="${1:-444}"
TMP=/tmp/art_test
OUT=docs/art_test
python3 tools/art_test_gen.py
gd --headless --path . --import >/dev/null 2>&1 || true
rm -rf "$TMP"; mkdir -p "$TMP" "$OUT"
# Movie Maker records at the project's base viewport size, so force 1920x1080 for the run only.
printf '[display]\nwindow/size/viewport_width=1920\nwindow/size/viewport_height=1080\n' > override.cfg
trap 'rm -f override.cfg' EXIT
xvfb-run -a -s "-screen 0 1920x1080x24" gd --path . res://scenes/art_test/art_test.tscn \
  --write-movie "$TMP/frame.png" --fixed-fps 30 --quit-after "$FRAMES" --resolution 1920x1080 2>&1 | grep -E "ERROR|SCRIPT ERROR|Parse Error" || true
ffmpeg -y -loglevel error -framerate 30 -i "$TMP/frame%08d.png" -c:v libx264 -preset slow -crf 24 -pix_fmt yuv420p -r 30 -movflags +faststart "$OUT/art_test.mp4"
ffmpeg -y -loglevel error -framerate 30 -i "$TMP/frame%08d.png" -vf "fps=15,scale=960:-1:flags=lanczos,split[a][b];[a]palettegen=max_colors=128:stats_mode=diff[p];[b][p]paletteuse=dither=bayer:bayer_scale=5:diff_mode=rectangle" "$OUT/art_test.gif"
ls -l "$OUT"
