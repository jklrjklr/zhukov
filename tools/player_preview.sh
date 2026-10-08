#!/bin/sh
# Renders docs/preview/player_moves_v2.{mp4,gif} and player_sheets.png (see tools/player_preview.gd).
#   sh tools/player_preview.sh
set -e
OUT=${TMPDIR:-/tmp}/player_preview
rm -rf "$OUT"
xvfb-run -a gd --path . --rendering-driver opengl3 --fixed-fps 60 --resolution 1280x720 \
  --script res://tools/player_preview.gd -- "$OUT"
mkdir -p docs/preview
FONT=/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf
VF=""
while IFS='|' read -r a b text; do
  VF="$VF,drawtext=fontfile=$FONT:text='$text':x=12:y=12:fontsize=26:fontcolor=white:box=1:boxcolor=black@0.6:boxborderw=6:enable='between(t,$a,$b)'"
done < "$OUT/captions.txt"
VF=${VF#,}
ffmpeg -y -loglevel error -framerate 30 -i "$OUT/f_%05d.png" -vf "$VF,format=yuv420p" \
  -c:v libx264 -crf 22 -preset slow -movflags +faststart docs/preview/player_moves_v2.mp4
ffmpeg -y -loglevel error -framerate 30 -i "$OUT/f_%05d.png" \
  -vf "$VF,fps=15,scale=480:-1:flags=neighbor,split[a][b];[a]palettegen=max_colors=64[p];[b][p]paletteuse=dither=none" \
  docs/preview/player_moves_v2.gif
ls -la docs/preview
