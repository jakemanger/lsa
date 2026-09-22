#!/usr/bin/env bash
# Types and runs a scripted demo inside the recorder. Usage: demo/play.sh <scene>
set -u
ALS=$(cd "$(dirname "$0")/.." && pwd)/als
export PATH="$(dirname "$ALS"):$PATH"
export HOME=${DEMO_HOME:?}
export XDG_CACHE_HOME="$HOME/.cache"
export COLUMNS=118  # the recorder is headless, so tput cannot know the window size
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
    run "als"
    say "every project, every agent, newest first"
    run "als -a" 3
    say "just one agent"
    run "als -a -t claude" 2.5
    ;;
  pick)
    say "0 is the newest. pick by index or by id, like git"
    run "als -a -n 5" 2
    run "als show 1 | head -12" 3
    run "als path 2"
    say "-l shows the command that reopens each one"
    run "als -a -l -n 3" 3
    say "or just: als resume 1"
    sleep 1.5
    ;;
esac
printf "$PS"; sleep 1.5
