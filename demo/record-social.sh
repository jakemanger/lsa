#!/usr/bin/env bash
# A short Claude Code -> Codex scene using record.sh's asciinema/agg pipeline.
# Run from anywhere: bash demo/record-social.sh [output directory]
# The raw cast, timing marks and demo sessions are retained for review/re-render.
set -eu
unset NO_COLOR
while read -r var; do unset "$var"; done < <(compgen -e | grep -E '^(CLAUDE|CODEX_|PI_|GEMINI_|QWEN_)' || :)
cd "$(dirname "$0")/.."
repo=$PWD
out=${1:-.tools/launch-2026-09-27/claude-codex-take}
mkdir -p "$out"
out=$(cd "$out" && pwd)
export DEMO_HOME DEMO_COLS=80 DEMO_MARKERS
DEMO_HOME=$(mktemp -d /tmp/lsa-social.XXXXXX)
DEMO_MARKERS=$out/timing.tsv
printf '%s\n' "$DEMO_HOME" > "$out/demo-home.txt"
mkdir -p "$DEMO_HOME/code/wren" "$DEMO_HOME/code/lantern"
demo_cwd=$(cd "$DEMO_HOME/code/wren" && pwd -P)
session=$(uuidgen | tr '[:upper:]' '[:lower:]')
printf '%s\n' "$session" > "$out/claude-session-id.txt"
project=$(printf '%s' "$demo_cwd" | sed 's/[^A-Za-z0-9]/-/g')

# Make an actual saved Claude conversation first, rather than mock an answer.
(
  cd "$demo_cwd"
  claude --setting-sources '' --strict-mcp-config --tools '' --model sonnet \
    --effort low --permission-mode manual --prompt-suggestions false \
    --session-id "$session" -p \
    'Write one short sentence describing lsa: a Bash CLI that lists coding-agent sessions, resumes them, and hands conversations between Claude Code and Codex. No heading, no tools.'
) > "$out/seed-answer.txt"
mkdir -p "$DEMO_HOME/.claude/projects/$project"
mv "$HOME/.claude/projects/$project/$session.jsonl" "$DEMO_HOME/.claude/projects/$project/"

# Two clearly separate sample rows make the purpose of the list visible.
python3 - "$DEMO_HOME" <<'PY'
import json, os, sys, time, uuid
from pathlib import Path
home=Path(sys.argv[1]); cwd=(home/'code/wren').resolve()
sid=str(uuid.uuid4()); d=home/'.codex/sessions/2026/09/27'; d.mkdir(parents=True)
f=d/f'rollout-2026-09-27T00-00-00-{sid}.jsonl'
rows=[{'type':'session_meta','payload':{'id':sid,'cwd':str(cwd),'timestamp':'2026-09-27T00:00:00Z','cli_version':'0.156.1','source':'cli'}},
 {'type':'response_item','payload':{'type':'message','role':'user','content':[{'type':'input_text','text':'fix the failing login test'}]}}]
f.write_text(''.join(json.dumps(r)+'\n' for r in rows)); os.utime(f,(time.time()-7200,)*2)
d=home/'.pi/agent/sessions/demo'; d.mkdir(parents=True)
f=d/'demo.jsonl'; sid=str(uuid.uuid4())
rows=[{'type':'session','version':3,'id':sid,'cwd':str(cwd)},
 {'type':'message','message':{'role':'user','content':[{'type':'text','text':'why is the Docker build slow?'}]}}]
f.write_text(''.join(json.dumps(r)+'\n' for r in rows)); os.utime(f,(time.time()-86400,)*2)
PY
( cd "$demo_cwd" && env HOME="$DEMO_HOME" XDG_CACHE_HOME="$DEMO_HOME/.cache" "$repo/lsa" ) > "$out/session-list.txt"
: > "$DEMO_MARKERS"
asciinema rec --return --overwrite --window-size 80x24 --idle-time-limit 1.2 \
  -c 'bash demo/play.sh claude-codex' "$out/raw.cast"
agg --theme github-dark --font-size 30 \
  --font-family 'JuliaMono,JetBrains Mono,Menlo,DejaVu Sans Mono' \
  --font-dir .tools/demo-fonts --idle-time-limit 1.2 --last-frame-duration 0.8 \
  "$out/raw.cast" "$out/raw.gif"
python3 demo/render-social.py "$out/raw.cast" "$out/claude-code-to-codex"
printf 'Recorded: %s\nDemo sessions retained in: %s\n' "$out/raw.gif" "$DEMO_HOME"
