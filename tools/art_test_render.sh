#!/usr/bin/env bash
# Renders scenes/art_test/art_test.tscn to docs/art_test/:
#   art_test_v2.mp4 / art_test_v2.gif   full scripted timeline (1080p, 30 fps)
#   charger_gait_v2.mp4                 0.5x slow-motion close-up following the Charger (walk + pivot), rendered at 60 fps
#   still_1..3.png                      (kept from the first pass; not regenerated)
# Usage: tools/art_test_render.sh [main|gait|all]   (needs gd, xvfb-run, ffmpeg, python3+Pillow)
set -euo pipefail
cd "$(dirname "$0")/.."
MODE="${1:-all}"
TMP=/tmp/art_test
OUT=docs/art_test
TOTAL_T=14.8
python3 tools/art_test_gen.py
gd --headless --path . --import >/dev/null 2>&1 || true
mkdir -p "$OUT"
trap 'rm -f override.cfg' EXIT

# render <w> <h> <fps> <dir> [extra user args]
render() {
  local w=$1 h=$2 fps=$3 dir=$4; shift 4
  rm -rf "$dir"; mkdir -p "$dir"
  # Movie Maker records at the project's base viewport size, so force it for the run only.
  printf '[display]\nwindow/size/viewport_width=%s\nwindow/size/viewport_height=%s\n' "$w" "$h" > override.cfg
  local frames
  frames=$(python3 -c "print(int(round($TOTAL_T*$fps))+1)")
  xvfb-run -a -s "-screen 0 ${w}x${h}x24" gd --path . res://scenes/art_test/art_test.tscn \
    --write-movie "$dir/frame.png" --fixed-fps "$fps" --quit-after "$frames" --resolution "${w}x${h}" -- "$@" 2>&1 \
    | grep -E "ERROR|SCRIPT ERROR|Parse Error" || true
  rm -f override.cfg
}

if [[ "$MODE" == main || "$MODE" == all ]]; then
  render 1920 1080 30 "$TMP/main"
  ffmpeg -y -loglevel error -framerate 30 -i "$TMP/main/frame%08d.png" -c:v libx264 -preset slow -crf 24 -pix_fmt yuv420p -r 30 -movflags +faststart "$OUT/art_test_v2.mp4"
  ffmpeg -y -loglevel error -framerate 30 -i "$TMP/main/frame%08d.png" -vf "fps=15,scale=960:-1:flags=lanczos,split[a][b];[a]palettegen=max_colors=128:stats_mode=diff[p];[b][p]paletteuse=dither=bayer:bayer_scale=5:diff_mode=rectangle" "$OUT/art_test_v2.gif"
fi

if [[ "$MODE" == gait || "$MODE" == all ]]; then
  # 60 fps sim/render, then play 3 s of sim time at 0.5x (-> ~6 s at 30 fps): 5.2-7.4 s walk, 10.15-11.0 s pivot
  render 1280 720 60 "$TMP/gait" --follow-charger
  ffmpeg -y -loglevel error -framerate 60 -i "$TMP/gait/frame%08d.png" -filter_complex \
    "[0:v]trim=start=5.2:end=7.4,setpts=(PTS-STARTPTS)*2[a];[0:v]trim=start=10.15:end=11.0,setpts=(PTS-STARTPTS)*2[b];[a][b]concat=n=2:v=1:a=0,fps=30,format=yuv420p" \
    -c:v libx264 -preset slow -crf 22 -movflags +faststart "$OUT/charger_gait_v2.mp4"
fi
ls -l "$OUT"
