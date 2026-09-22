#!/usr/bin/env bash
# Types and runs a scripted demo inside the recorder. Usage: demo/play.sh <scene>
set -u
LSA=$(cd "$(dirname "$0")/.." && pwd)/lsa
export PATH="$(dirname "$LSA"):$PATH"
export HOME=${DEMO_HOME:?}
export XDG_CACHE_HOME="$HOME/.cache"
export COLUMNS=${DEMO_COLS:-100}   # the recorder is headless, so tput cannot know the window size
export GOOSE_PROVIDER=ollama GOOSE_MODEL=${DEMO_MODEL:-qwen2.5:3b} GOOSE_TELEMETRY_ENABLED=false
cd "$HOME/code/wren"

PS="\033[1;32m❯\033[0m "
say() { # a dim comment line, typed
  printf '\033[2m# '; type_out "$1"; printf '\033[0m\n'; sleep 0.9
}
type_out() {
  local s=$1 i
  for ((i = 0; i < ${#s}; i++)); do printf '%s' "${s:i:1}"; sleep 0.035; done
}
run() { # type a command, then run it
  printf "$PS"; type_out "$1"; sleep 0.5; printf '\n'
  eval "$1"
  sleep "${2:-2.2}"
}

clear
case ${1:-list} in
  list)
    say "ls, but for your agent sessions"
    run "lsa"
    say "every project, every agent, newest first"
    run "lsa -a" 3
    say "pick one up where you left it"
    printf "$PS"; type_out "lsa resume 3"; sleep 0.6; printf '\n'
    # drive the resumed Goose session: one follow-up, then leave
    expect -c '
      set timeout 120
      spawn -noecho lsa resume 3
      expect -re {Enter to send}
      sleep 1.5
      send "thanks, now make them shorter\r"
      expect -re {[0-9]+\.[0-9]+s}          ;# goose prints the elapsed time when a reply is complete
      expect -timeout 20 -re {Enter to send}
      sleep 4
      send "/exit\r"
      expect -timeout 20 eof'
    sleep 1.5
    ;;
  pick)
    say "0 is the newest. pick by index or by id, like git"
    run "lsa -a -n 6" 2
    run "lsa show 1 | head -12" 3
    run "lsa path 2"
    say "-l adds the working directory and transcript path"
    run "lsa -a -l -n 3" 3
    ;;
esac
printf "$PS"; sleep 1.5
