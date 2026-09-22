#!/usr/bin/env bash
# Record the README gifs. Needs asciinema, agg and expect, plus goose and a
# running ollama with the demo model for the resume at the end of the list
# scene (brew install asciinema agg block-goose-cli ollama; ollama pull qwen2.5:3b).
#   demo/record.sh            -> demo/list.gif and demo/pick.gif
#   demo/record.sh pick       -> just one scene
set -eu
cd "$(dirname "$0")/.."
export DEMO_HOME DEMO_COLS=100
DEMO_HOME=/tmp/lsa-demo   # a short, clean path: it appears in the gifs
rm -rf "$DEMO_HOME"; trap 'rm -rf "$DEMO_HOME"' EXIT
bash demo/fixtures.sh "$DEMO_HOME" > /dev/null
HOME=$DEMO_HOME XDG_CACHE_HOME=$DEMO_HOME/.cache ./lsa -a > /dev/null   # warm the cache so the demo is as fast as real life
# the newest session is "working": touch its transcript and keep a process called claude alive
touch "$DEMO_HOME"/.claude/projects/*/3e1f9c2a-*.jsonl
( exec -a claude sleep 900 ) & fake=$!
trap 'kill $fake 2>/dev/null; wait $fake 2>/dev/null; rm -rf "$DEMO_HOME"' EXIT

scenes=("$@"); [ ${#scenes[@]} -gt 0 ] || scenes=(list pick)
for scene in "${scenes[@]}"; do
  asciinema rec --overwrite --window-size ${DEMO_COLS}x30 --idle-time-limit 3 \
    -c "bash demo/play.sh $scene" "demo/$scene.cast"
  agg --theme github-dark --font-size 22 --font-family "JetBrains Mono,Menlo,DejaVu Sans Mono" \
    --last-frame-duration 3 "demo/$scene.cast" "demo/$scene.gif"
  echo "demo/$scene.gif"
done
