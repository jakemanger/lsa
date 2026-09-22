#!/usr/bin/env bash
# als - ls for agent sessions.
# Lists Claude Code, Codex and pi transcripts, newest first.
# https://github.com/jakemanger/als
set -eu

VERSION="0.1.0"

usage() {
  cat <<'EOF'
als - ls for agent sessions

usage: als [options] [dir]          list sessions started in dir (default: .)
       als show <id>                print a transcript as plain text
       als path <id>                print the transcript's file path
       als resume <id>              reopen the session in its own agent

options:
  -a, --all           every directory, not just dir
  -t, --agent NAME    only claude, codex or pi (repeatable)
  -n, --limit N       show at most N sessions
  -l, --long          add the full path and the resume command
  -h, --help          this text
  -V, --version       version

<id> is any unique prefix of the session id shown in the listing.
EOF
}

# ---------- settings ----------
CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/projects"
CODEX_DIR="${CODEX_HOME:-$HOME/.codex}/sessions"
PI_DIR="${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}/sessions"

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  C_CLAUDE=$'\033[38;5;208m' C_CODEX=$'\033[38;5;39m' C_PI=$'\033[38;5;141m'
  C_DIM=$'\033[2m' C_RESET=$'\033[0m'
else
  C_CLAUDE='' C_CODEX='' C_PI='' C_DIM='' C_RESET=''
fi

# ---------- portable helpers ----------
# stdin: NUL-separated paths -> "mtime<TAB>path" per line, one stat call
mtimes() {
  if stat -f %m / >/dev/null 2>&1; then xargs -0 stat -f "%m"$'\t'"%N" 2>/dev/null
  else xargs -0 stat -c "%Y"$'\t'"%n" 2>/dev/null; fi
  return 0
}

ago() { # seconds since epoch -> "3m ago"
  local d=$(( $(date +%s) - $1 ))
  if   [ "$d" -lt 60 ];     then echo "${d}s ago"
  elif [ "$d" -lt 3600 ];   then echo "$((d/60))m ago"
  elif [ "$d" -lt 86400 ];  then echo "$((d/3600))h ago"
  elif [ "$d" -lt 2592000 ]; then echo "$((d/86400))d ago"
  else echo "$((d/2592000))mo ago"; fi
}

# first "key":"value" string on the first line that has it (JSON escapes kept)
json_first() { # file key
  grep -m1 -oE "\"$2\":\"([^\"\\\\]|\\\\.)*\"" "$1" 2>/dev/null | head -1 | sed -e "s/^\"$2\":\"//" -e 's/"$//'
}

unescape() { sed -e 's/\\n/ /g' -e 's/\\t/ /g' -e 's/\\"/"/g' -e 's/\\\\/\\/g'; }

# ---------- per-agent readers: cwd, id, title ----------
# Each reader prints three lines: cwd, id, title.

read_claude() { # file
  local f=$1 line
  printf '%s\n' "$(json_first "$f" cwd)"
  printf '%s\n' "$(basename "$f" .jsonl)"
  line=$(grep -m1 '"type":"user"' "$f" 2>/dev/null || true)
  printf '%s\n' "$line" | grep -oE '"text":"([^"\\]|\\.)*"' | head -1 | sed -e 's/^"text":"//' -e 's/"$//' | unescape
}

read_codex() { # file
  local f=$1
  printf '%s\n' "$(json_first "$f" cwd)"
  printf '%s\n' "$(json_first "$f" session_id)"
  # skip the AGENTS.md / environment_context messages Codex injects first
  grep '"role":"user"' "$f" 2>/dev/null \
    | grep -oE '"text":"([^"\\]|\\.)*"' \
    | sed -e 's/^"text":"//' -e 's/"$//' \
    | grep -vE '^(<|# AGENTS\.md)' | head -1 | unescape
}

read_pi() { # file
  local f=$1
  printf '%s\n' "$(json_first "$f" cwd)"
  printf '%s\n' "$(json_first "$f" id)"
  grep -m1 '"role":"user"' "$f" 2>/dev/null \
    | grep -oE '"text":"([^"\\]|\\.)*"' | head -1 \
    | sed -e 's/^"text":"//' -e 's/"$//' | unescape
}

# ---------- find every transcript: "mtime<TAB>agent<TAB>path" ----------
find_all() {
  [ -d "$CLAUDE_DIR" ] && find "$CLAUDE_DIR" -name '*.jsonl' ! -name 'agent-*' -print0 2>/dev/null \
    | mtimes | sed $'s/\t/\tclaude\t/'
  [ -d "$CODEX_DIR" ] && find "$CODEX_DIR" -name 'rollout-*.jsonl' -print0 2>/dev/null \
    | mtimes | sed $'s/\t/\tcodex\t/'
  [ -d "$PI_DIR" ] && find "$PI_DIR" -name '*.jsonl' -print0 2>/dev/null \
    | mtimes | sed $'s/\t/\tpi\t/'
  return 0
}

want_agent() { # agent
  [ -z "$AGENTS" ] && return 0
  case " $AGENTS " in *" $1 "*) return 0;; esac
  return 1
}

resume_cmd() { # agent id file
  case $1 in
    claude) printf 'claude --resume %s\n' "$2";;
    codex)  printf 'codex resume %s\n' "$2";;
    pi)     printf 'pi --session %s\n' "$3";;
  esac
}

# ---------- list ----------
list_rows() { # dir cols
  local dir=$1 cols=$2 shown=0 width ts agent f cwd id title color when proj
  find_all | sort -rn | while IFS=$'\t' read -r ts agent f; do
    want_agent "$agent" || continue
    { read -r cwd; read -r id; read -r title; } < <("read_$agent" "$f")
    [ -z "$id" ] && continue
    if [ "$ALL" = 0 ] && [ "$cwd" != "$dir" ] && [ "$cwd" != "$DIRP" ]; then continue; fi
    [ -z "$title" ] && title="${C_DIM}(empty)${C_RESET}"
    case $agent in claude) color=$C_CLAUDE;; codex) color=$C_CODEX;; *) color=$C_PI;; esac
    when=$(ago "$ts")
    proj=$(basename "${cwd:-?}")
    width=$(( cols - 8 - 9 - 22 - 10 - 4 ))
    [ "$width" -lt 20 ] && width=20
    if [ "$ALL" = 1 ]; then
      printf '%s%-7s%s %-8s %-20.20s %s%-9.8s%s %.*s\n' \
        "$color" "$agent" "$C_RESET" "$when" "$proj" "$C_DIM" "$id" "$C_RESET" "$width" "$title"
    else
      printf '%s%-7s%s %-8s %s%-9.8s%s %.*s\n' \
        "$color" "$agent" "$C_RESET" "$when" "$C_DIM" "$id" "$C_RESET" "$((width+21))" "$title"
    fi
    if [ "$LONG" = 1 ]; then
      printf '        %s%s\n        %s%s\n' "$C_DIM" "$f" "$(resume_cmd "$agent" "$id" "$f")" "$C_RESET"
    fi
    shown=$((shown+1))
    [ "$LIMIT" -gt 0 ] && [ "$shown" -ge "$LIMIT" ] && break
  done
  return 0
}

cmd_list() {
  local dir=$1 cols out
  if [ -t 1 ]; then cols=${COLUMNS:-$(tput cols 2>/dev/null || echo 100)}; else cols=200; fi
  out=$(list_rows "$dir" "$cols")
  if [ -n "$out" ]; then printf '%s\n' "$out"
  elif [ "$ALL" = 1 ]; then echo "als: no sessions found" >&2
  else echo "als: no sessions in $dir (try als -a)" >&2; fi
  return 0
}

# ---------- find one session by id prefix -> "agent<TAB>id<TAB>path" ----------
matching_ids() { # prefix
  local prefix=$1 ts agent f id
  find_all | while IFS=$'\t' read -r ts agent f; do
    case $agent in
      claude) id=$(basename "$f" .jsonl);;
      codex)  id=$(basename "$f" .jsonl | sed 's/^rollout-[0-9T:-]*-//');;
      pi)     id=$(basename "$f" .jsonl | sed 's/^[^_]*_//');;
    esac
    case $id in "$prefix"*) printf '%s\t%s\t%s\n' "$agent" "$id" "$f";; esac
  done
  return 0
}

find_one() { # prefix
  local prefix=$1 hits n
  hits=$(matching_ids "$prefix")
  n=$(printf '%s' "$hits" | grep -c .)
  case $n in
    0) echo "als: no session starts with '$prefix'" >&2; return 1;;
    1) printf '%s\n' "$hits";;
    *) echo "als: '$prefix' is ambiguous:" >&2; printf '%s\n' "$hits" | cut -f2 >&2; return 1;;
  esac
}

# ---------- show: transcript as plain text ----------
cmd_show() {
  local agent id f
  IFS=$'\t' read -r agent id f < <(find_one "$1")
  command -v jq >/dev/null || { echo "als: 'show' needs jq (brew install jq / apt install jq)" >&2; exit 1; }
  case $agent in
    claude) jq -r '
      select(.type=="user" or .type=="assistant") | .message as $m
      | ($m.content | if type=="string" then [.] else map(
          if .type=="text" then .text
          elif .type=="tool_use" then "[tool: " + .name + "] " + (.input|tostring)
          elif .type=="tool_result" then "[result] " + (.content|tostring)
          else empty end) end) as $parts
      | select($parts|length>0)
      | "\n## " + $m.role + "\n" + ($parts|join("\n"))' "$f";;
    codex) jq -r '
      select(.type=="response_item" and .payload.type=="message")
      | .payload as $m
      | select($m.role!="developer")
      | ($m.content|map(.text // empty)|join("\n")) as $t
      | select($t|length>0)
      | select($t|test("^(<|# AGENTS.md)")|not)
      | "\n## " + $m.role + "\n" + $t' "$f";;
    pi) jq -r '
      select(.type=="message") | .message as $m
      | ($m.content | if type=="string" then [.] else map(
          if .type=="text" then .text
          elif .type=="toolCall" then "[tool: " + .name + "] " + (.arguments|tostring)
          elif .type=="toolResult" then "[result] " + (.content|tostring)
          else empty end) end) as $parts
      | select($parts|length>0)
      | "\n## " + $m.role + "\n" + ($parts|join("\n"))' "$f";;
  esac
}

cmd_path()   { local hit; hit=$(find_one "$1") || exit 1; printf '%s\n' "${hit##*	}"; }
cmd_resume() {
  local agent id f
  IFS=$'\t' read -r agent id f < <(find_one "$1")
  exec $(resume_cmd "$agent" "$id" "$f")
}

# ---------- args ----------
ALL=0 LONG=0 LIMIT=0 AGENTS='' DIR=''
case ${1:-} in
  show|path|resume) [ $# -ge 2 ] || { usage >&2; exit 2; }; "cmd_$1" "$2"; exit;;
esac
while [ $# -gt 0 ]; do
  case $1 in
    -a|--all) ALL=1;;
    -l|--long) LONG=1;;
    -n|--limit) LIMIT=$2; shift;;
    -t|--agent) AGENTS="$AGENTS $2"; shift;;
    -h|--help) usage; exit 0;;
    -V|--version) echo "als $VERSION"; exit 0;;
    -*) echo "als: unknown option $1" >&2; usage >&2; exit 2;;
    *) DIR=$1;;
  esac
  shift
done
DIR=$(cd "${DIR:-.}" 2>/dev/null && pwd) || { echo "als: no such directory" >&2; exit 1; }
DIRP=$(cd "$DIR" && pwd -P)   # agents may record either the logical or the resolved path
cmd_list "$DIR"
