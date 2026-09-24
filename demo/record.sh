#!/usr/bin/env bash
# Record the README gifs. Needs asciinema, agg and expect, plus goose and a
# running ollama with the demo model, and an authenticated Claude Code for
# the handoff (brew install asciinema agg block-goose-cli ollama; ollama pull qwen2.5:3b).
# JuliaMono covers Claude's UI symbols. Install it or put its fonts in .tools/demo-fonts.
#   demo/record.sh            -> demo/list.gif and demo/pick.gif
#   demo/record.sh pick       -> just one scene
set -eu
unset NO_COLOR
# record as a fresh terminal would, even when launched from inside an agent
while read -r var; do unset "$var"; done < <(compgen -e | grep -E '^(CLAUDE|CODEX_|PI_|GEMINI_|QWEN_)' || :)
cd "$(dirname "$0")/.."
export DEMO_HOME DEMO_COLS=88
DEMO_HOME=/tmp/lsa-demo   # a short, clean path: it appears in the gifs
started=$(mktemp) fake='' demo_cwd=''
setup() { # fresh fixtures for each scene, so one scene's handoffs never show in the next
  [ -z "$fake" ] || { kill "$fake" 2>/dev/null || :; wait "$fake" 2>/dev/null || :; }
  rm -rf "$DEMO_HOME"
  bash demo/fixtures.sh "$DEMO_HOME" > /dev/null
  demo_cwd=$(cd "$DEMO_HOME/code/wren" && pwd -P)
  HOME=$DEMO_HOME XDG_CACHE_HOME=$DEMO_HOME/.cache ./lsa -a > /dev/null   # warm the cache so the demo is as fast as real life
  # the newest session is "working": touch its transcript and keep a process called claude alive
  touch "$DEMO_HOME"/.claude/projects/*/3e1f9c2a-*.jsonl
  ( exec -a claude sleep 900 ) & fake=$!
}
# the handoffs run against the real stores: remove the demo's Claude sessions and
# archive its Codex ones, so neither shows up in those agents' resume lists
cleanup() {
  [ -z "$fake" ] || { kill "$fake" 2>/dev/null || :; wait "$fake" 2>/dev/null || :; }
  [ -z "$demo_cwd" ] || find "$HOME/.claude/projects/$(printf '%s' "$demo_cwd" | sed 's/[^A-Za-z0-9]/-/g')" \
    -maxdepth 1 -name '*.jsonl' -newer "$started" -delete 2>/dev/null || :
  find "$HOME/.codex/sessions" -name 'rollout-*.jsonl' -newer "$started" 2>/dev/null | while read -r f; do
    id=$(head -n 1 "$f" | jq -r --arg cwd "$demo_cwd" 'select(.payload.cwd == $cwd) | .payload.id')
    [ -z "$id" ] || codex archive "$id" >/dev/null 2>&1 || :
  done
  rm -rf "$DEMO_HOME" "$started"
}
trap cleanup EXIT

scenes=("$@"); [ ${#scenes[@]} -gt 0 ] || scenes=(list pick)
font_args=()
[ ! -d .tools/demo-fonts ] || font_args=(--font-dir .tools/demo-fonts)
for scene in "${scenes[@]}"; do
  setup
  asciinema rec --return --overwrite --window-size ${DEMO_COLS}x30 --idle-time-limit 3 \
    -c "bash demo/play.sh $scene" "demo/$scene.cast"
  agg --theme github-dark --font-size 26 --font-family "JuliaMono,JetBrains Mono,Menlo,DejaVu Sans Mono" ${font_args[@]+"${font_args[@]}"} \
    --last-frame-duration 3 "demo/$scene.cast" "demo/$scene.gif"
  echo "demo/$scene.gif"
done
