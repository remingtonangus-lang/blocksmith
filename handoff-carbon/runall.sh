#!/bin/bash
# render each shot at 2560x1440, encode to 1920x1080 mp4, keep every 15th frame for review
cd /home/user/qc
export QUEST_SKIP=landmarks
OUT=/tmp/claude-0/cine/full
for s in "$@"; do
  if [ ! -f $OUT/$s/f00000.png ]; then
    /tmp/claude-0/qc1/questcheck --cine docs/store/trailer-shots.json --out $OUT --w 2560 --h 1440 --only $s 2>&1 | grep -E 'cine:|Fatal' | grep -v 'frame ' >> $OUT/render.log
  fi
  ffmpeg -loglevel error -y -framerate 30 -i $OUT/$s/f%05d.png -vf scale=1920:1080:flags=lanczos -c:v libx264 -preset slow -crf 14 -pix_fmt yuv420p $OUT/$s.mp4 && \
  mkdir -p $OUT/keep/$s && for f in $OUT/$s/f*.png; do n=$(basename $f .png); i=$((10#${n#f})); if [ $((i % 15)) -eq 0 ]; then mv $f $OUT/keep/$s/; else rm $f; fi; done
  echo "done $s" >> $OUT/render.log
done
echo ALLDONE >> $OUT/render.log
