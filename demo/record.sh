#!/usr/bin/env bash
# Record the README gifs. Needs asciinema and agg (brew install asciinema agg).
#   demo/record.sh            -> demo/list.gif and demo/pick.gif
#   demo/record.sh pick       -> just one scene
set -eu
cd "$(dirname "$0")/.."
export DEMO_HOME
DEMO_HOME=/tmp/als-demo   # a short, clean path: it appears in the gifs
rm -rf "$DEMO_HOME"; trap 'rm -rf "$DEMO_HOME"' EXIT
bash demo/fixtures.sh "$DEMO_HOME" > /dev/null
HOME=$DEMO_HOME XDG_CACHE_HOME=$DEMO_HOME/.cache ./als -a > /dev/null   # warm the cache so the demo is as fast as real life

scenes=("$@"); [ ${#scenes[@]} -gt 0 ] || scenes=(list pick)
for scene in "${scenes[@]}"; do
  asciinema rec --overwrite --window-size 118x28 --idle-time-limit 3 \
    -c "bash demo/play.sh $scene" "demo/$scene.cast"
  agg --theme github-dark --font-size 18 --font-family "JetBrains Mono,Menlo,DejaVu Sans Mono" \
    --last-frame-duration 3 "demo/$scene.cast" "demo/$scene.gif"
  echo "demo/$scene.gif"
done
