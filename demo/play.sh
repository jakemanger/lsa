#!/usr/bin/env bash
# Types and runs a scripted demo inside the recorder. Usage: demo/play.sh <scene>
set -eu
LSA=$(cd "$(dirname "$0")/.." && pwd)/lsa
export LSA
PATH="$(dirname "$LSA"):$PATH"
export PATH
: "${DEMO_HOME:?}"
# Only fixture readers and Goose use the demo home. The handoff launches a
# real Claude with its normal login and read-only tools for the saved context.
export DEMO_REAL_HOME=$HOME DEMO_CLAUDE
DEMO_CLAUDE=$(command -v claude)
mkdir -p "$DEMO_HOME/bin"
cat > "$DEMO_HOME/bin/claude" <<'SH'
#!/usr/bin/env bash
export HOME=$DEMO_REAL_HOME
unset XDG_CACHE_HOME
exec "$DEMO_CLAUDE" --setting-sources "" --strict-mcp-config --tools Read --allowedTools Read --model sonnet --effort low --permission-mode manual "$@"
SH
chmod +x "$DEMO_HOME/bin/claude"
PATH="$DEMO_HOME/bin:$PATH"
export PATH
lsa() { env HOME="$DEMO_HOME" XDG_CACHE_HOME="$DEMO_HOME/.cache" "$LSA" "$@"; }
export -f lsa
export COLUMNS=${DEMO_COLS:-100}   # the recorder is headless, so tput cannot know the window size
export GOOSE_PROVIDER=ollama GOOSE_MODEL=${DEMO_MODEL:-qwen2.5:3b} GOOSE_TELEMETRY_ENABLED=false
cd "$DEMO_HOME/code/wren"

PS="\033[1;32m❯\033[0m "
say() { # a dim comment line, typed
  printf '\033[2m# '; type_out "$1"; printf '\033[0m\n'; sleep 0.9
}
type_out() {
  local s=$1 i
  for ((i = 0; i < ${#s}; i++)); do printf '%s' "${s:i:1}"; sleep 0.035; done
}
run() { # type a command, then run it
  printf '%b' "$PS"; type_out "$1"; sleep 0.5; printf '\n'
  eval "$1"
  sleep "${2:-2.2}"
}

clear
case ${1:-list} in
  list)
    say "ls, but for your agent sessions"
    run "lsa"
    say "See sessions from every agent and project, starting with the most recent."
    run "lsa -a" 3
    say "pick one up where you left it"
    printf '%b' "$PS"; type_out "lsa resume 3"; sleep 0.6; printf '\n'
    # drive the resumed Goose session: one follow-up, then leave
    expect -c '
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
    sleep 1.5
    say "Continue the Goose conversation in Claude."
    printf '%b' "$PS"
    type_out 'lsa handoff 2026 claude'
    sleep 0.6; printf '\n'
    expect -f "$(dirname "$LSA")/demo/handoff.exp"
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
printf '%b' "$PS"; sleep 1.5
