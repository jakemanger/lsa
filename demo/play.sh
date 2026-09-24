#!/usr/bin/env bash
# Types and runs a scripted demo inside the recorder. Usage: demo/play.sh <scene>
set -eu
LSA=$(cd "$(dirname "$0")/.." && pwd)/lsa
export LSA
PATH="$(dirname "$LSA"):$PATH"
export PATH
: "${DEMO_HOME:?}"
# Only fixture readers and Goose use the demo home. The handoffs launch a real
# Claude and Codex with their normal logins, so these wrappers move each
# handed-off session into the real store while it runs.
export DEMO_HOME DEMO_REAL_HOME=$HOME DEMO_CLAUDE DEMO_CODEX
DEMO_CLAUDE=$(command -v claude) DEMO_CODEX=$(command -v codex)
mkdir -p "$DEMO_HOME/bin"
cat > "$DEMO_HOME/bin/claude" <<'SH'
#!/usr/bin/env bash
# claude reads the real store; move the session there, then back so lsa can hand it on
demo=''
if [ "${1:-}" = --resume ]; then
  for demo in "$DEMO_HOME"/.claude/projects/*/"$2".jsonl; do
    real="$DEMO_REAL_HOME/.claude/projects/$(basename "$(dirname "$demo")")/$2.jsonl"
    mkdir -p "${real%/*}" && mv "$demo" "$real"
  done
fi
HOME=$DEMO_REAL_HOME XDG_CACHE_HOME='' "$DEMO_CLAUDE" --setting-sources "" --strict-mcp-config --tools "" \
  --model sonnet --effort low --permission-mode manual "$@"
status=$?
[ -z "$demo" ] || mv "$real" "$demo"
exit $status
SH
cat > "$DEMO_HOME/bin/codex" <<'SH'
#!/usr/bin/env bash
if [ "${1:-}" = resume ]; then
  for demo in "$DEMO_HOME"/.codex/sessions/*/*/*/rollout-*-"$2".jsonl; do
    real="$DEMO_REAL_HOME/.codex/${demo#"$DEMO_HOME"/.codex/}"
    mkdir -p "${real%/*}" && mv "$demo" "$real"
  done
fi
export HOME=$DEMO_REAL_HOME
unset XDG_CACHE_HOME CODEX_HOME
# typed demo input arrives fast enough to look like a paste, which turns Enter into a newline
exec "$DEMO_CODEX" "$@" -c disable_paste_burst=true
SH
chmod +x "$DEMO_HOME/bin/claude" "$DEMO_HOME/bin/codex"
PATH="$DEMO_HOME/bin:$PATH"
export PATH
lsa() { env HOME="$DEMO_HOME" XDG_CACHE_HOME="$DEMO_HOME/.cache" "$LSA" "$@"; }
export -f lsa
export COLUMNS=${DEMO_COLS:-88}   # the recorder is headless, so tput cannot know the window size
export GOOSE_PROVIDER=ollama GOOSE_MODEL=${DEMO_MODEL:-qwen2.5:3b} GOOSE_TELEMETRY_ENABLED=false
cd "$DEMO_HOME/code/wren"

PS="\033[1;32m❯\033[0m "
# like a shell: the prompt appears as soon as the last command finishes, and each
# line is typed after it
say() { # a dim comment, typed at the prompt
  printf '\033[2m# '; type_out "$1"; printf '\033[0m\n%b' "$PS"; sleep 0.9
}
type_out() {
  local s=$1 i
  for ((i = 0; i < ${#s}; i++)); do printf '%s' "${s:i:1}"; sleep 0.035; done
}
run() { # type a command, run it, then prompt
  type_out "$1"; sleep 0.5; printf '\n'
  eval "$1"
  printf '%b' "$PS"
  sleep "${2:-2.2}"
}
interactive() { # type a command whose program an expect script drives, then prompt
  type_out "$1"; sleep 0.6; printf '\n'
  shift
  expect "$@"
  printf '%b' "$PS"
  sleep 1.5
}

clear
printf '%b' "$PS"
case ${1:-list} in
  list)
    say "ls, but for your agent sessions"
    run "lsa"
    say "See sessions from every agent and project, starting with the most recent."
    run "lsa -a" 3
    say "pick one up where you left it"
    # drive the resumed Goose session: one follow-up, then leave
    interactive "lsa resume 3" -c '
      set timeout 120
      encoding system utf-8
      spawn -noecho bash -c {lsa resume 3}
      expect -re {Enter to send}
      sleep 1.5
      send "Shorten these, then note that the next step is a one-sentence version.\r"
      expect -re {[0-9]+\.[0-9]+s}          ;# goose prints the elapsed time when a reply is complete
      expect -timeout 20 -re {Enter to send}
      sleep 4
      send "/exit\r"
      expect -timeout 20 eof'
    say "Continue the Goose conversation in Claude."
    interactive "lsa handoff 2026 claude" -f "$(dirname "$LSA")/demo/handoff.exp"
    say "Now hand the Claude conversation to Codex."
    interactive "lsa handoff 0 codex" -f "$(dirname "$LSA")/demo/handoff-codex.exp"
    exit 0
    ;;
  pick)
    say "0 is the newest. pick by index or by id, like git"
    run "lsa -a -n 6" 2
    say "show includes the tool calls and results, too"
    run "lsa show 01a0c7d | tail -n 14" 4
    run "lsa path 2"
    say "-l adds the working directory and transcript path"
    run "lsa -a -l -n 3" 3
    ;;
esac
sleep 1.5
