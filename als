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
  -l, --long          show the command that resumes each session
  -L, --paths         also show each transcript's path
  -h, --help          this text
  -V, --version       version

<id> is the index or the short id from the listing, or any unique prefix
of the full id. Index 0 is the newest session; indexes are global, so
als resume 3 is the same session whether you listed with -a or not.
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

NOW=$(date +%s)
ago() { # seconds since epoch -> sets AGO to "3m ago" (no subshell: called per row)
  local d=$(( NOW - $1 ))
  if   [ "$d" -lt 60 ];     then AGO="${d}s ago"
  elif [ "$d" -lt 3600 ];   then AGO="$((d/60))m ago"
  elif [ "$d" -lt 86400 ];  then AGO="$((d/3600))h ago"
  elif [ "$d" -lt 2592000 ]; then AGO="$((d/86400))d ago"
  else AGO="$((d/2592000))mo ago"; fi
}

# ---------- the parser: "agent<TAB>path<TAB>mtime" in, "path<TAB>cwd<TAB>title" out ----------
# One awk for every file. It reads the head of each transcript and stops as
# soon as it has the cwd and the first real prompt, so multi-megabyte
# sessions cost the same as tiny ones. A session with no prompt yet is only
# cached once it is ten minutes old, so a session being typed into stays fresh.
parse() {
  awk -F '\t' -v now="$NOW" -v HIDDEN="$HIDDEN" '
    # JSON string starting right after the opening quote; unescapes; capped
    function jstr(s,   out) {
      match(s, /^([^"\\]|\\.)*/); out = substr(s, 1, RLENGTH)
      gsub(/\\[ntr]/, " ", out); gsub(/\\"/, "\"", out); gsub(/\\\\/, "\\", out)
      return substr(out, 1, 300) }
    function text_of(line,   i) {
      if ((i = index(line, "\"text\":\""))) return jstr(substr(line, i + 8, 2000))
      if ((i = index(line, "\"content\":\""))) return jstr(substr(line, i + 11, 2000))
      return "" }
    { agent = $1; f = $2; cwd = ""; title = ""; n = 0; cont = 0
      while ((getline line < f) > 0) {
        if (++n > 60) break   # the prompt is in the first dozen records of every format
        # Codex Desktop keeps its internal reviewer threads next to real sessions; not yours to resume
        if (n == 1 && index(line, "\"thread_source\":\"guardian_review\"")) { title = HIDDEN; break }
        if (cwd == "" && (i = index(line, "\"cwd\":\""))) cwd = jstr(substr(line, i + 7, 2000))
        if (title == "") {
          if (agent == "claude") { if (index(line, "\"type\":\"user\"")) title = text_of(line) }
          else if (index(line, "\"role\":\"user\"")) { t = text_of(line)
            # Codex injects AGENTS.md, <environment_context> and, after compaction, history summaries
            if (agent != "codex" || t !~ /^(<|# AGENTS\.md|The following is the Codex agent history)/) title = t }
          if (agent == "codex" && index(line, "\"type\":\"compacted\"")) cont = 1 }
        if (cwd != "" && title != "") break }
      close(f)
      if (title == "" && cont) title = "(continued after compaction)"
      if (title != "" || now - $3 > 600) { gsub(/\t/, " ", title); print f "\t" cwd "\t" title } }'
}

HIDDEN='[als:hidden]'   # title sentinel for files that are not sessions

# ---------- the cache: path -> cwd, title. Immutable facts, so never invalidated ----------
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/als"
CACHE="$CACHE_DIR/index-$VERSION.tsv"

# stdin: find_all rows -> the same rows with cwd and title appended
enrich() {
  local rows misses
  rows=$(cat)
  [ -n "$rows" ] || return 0
  mkdir -p "$CACHE_DIR"; [ -f "$CACHE" ] || : > "$CACHE"
  misses=$(printf '%s\n' "$rows" | awk -F '\t' -v c="$CACHE" 'FILENAME == c { seen[$1] = 1; next } !($3 in seen) { print $2 "\t" $3 "\t" $1 }' "$CACHE" -)
  if [ -n "$misses" ]; then printf '%s\n' "$misses" | parse >> "$CACHE"; fi
  printf '%s\n' "$rows" | awk -F '\t' -v OFS='\t' -v c="$CACHE" '
    FILENAME == c { cwd[$1] = $2; title[$1] = $3; next }
    { print $0, ($3 in cwd ? cwd[$3] : ""), ($3 in title ? title[$3] : "") }' "$CACHE" -
}

# every session, newest first: "mtime agent path id shortlen cwd title"
sessions() {
  find_all | sort -rn | enrich | awk -F '\t' -v h="$HIDDEN" '$7 != h'
}

# ---------- find every transcript: "mtime<TAB>agent<TAB>path<TAB>id<TAB>shortlen" ----------
# The id comes from the file name, so nothing is opened. shortlen is the
# length of the shortest prefix unique among all ids (git-style, minimum 4).
find_all() {
  {
    [ -d "$CLAUDE_DIR" ] && find "$CLAUDE_DIR" -name '*.jsonl' ! -name 'agent-*' -print0 2>/dev/null \
      | mtimes | sed -E $'s/\t(.*\\/)([^/]*)\\.jsonl$/\tclaude\t&\t\\2/'
    [ -d "$CODEX_DIR" ] && find "$CODEX_DIR" -name 'rollout-*.jsonl' -print0 2>/dev/null \
      | mtimes | sed -E $'s/\t(.*\\/)rollout-[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}-[0-9]{2}-[0-9]{2}-([^/]*)\\.jsonl$/\tcodex\t&\t\\2/'
    [ -d "$PI_DIR" ] && find "$PI_DIR" -name '*.jsonl' -print0 2>/dev/null \
      | mtimes | sed -E $'s/\t(.*\\/)[^/_]*_([^/]*)\\.jsonl$/\tpi\t&\t\\2/'
  } | sed $'s/\t\t/\t/' | sort -t $'\t' -k4,4 | awk -F '\t' -v OFS='\t' '
    function common(a, b,   i, n) { n = length(a) < length(b) ? length(a) : length(b)
      for (i = 1; i <= n; i++) if (substr(a, i, 1) != substr(b, i, 1)) return i - 1; return n }
    { line[NR] = $0; id[NR] = $4 }
    END { for (i = 1; i <= NR; i++) { n = 4
        if (i > 1  && common(id[i], id[i-1]) + 1 > n) n = common(id[i], id[i-1]) + 1
        if (i < NR && common(id[i], id[i+1]) + 1 > n) n = common(id[i], id[i+1]) + 1
        print line[i], n } }'
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
  local dir=$1 cols=$2 shown=0 i=-1 width ts agent f cwd id short n title color when proj
  sessions | while IFS=$'\t' read -r ts agent f id n cwd title; do
    i=$((i+1))
    want_agent "$agent" || continue
    short=${id:0:$n}
    if [ "$ALL" = 0 ] && [ "$cwd" != "$dir" ] && [ "$cwd" != "$DIRP" ]; then continue; fi
    [ -z "$title" ] && title="${C_DIM}(empty)${C_RESET}"
    case $agent in claude) color=$C_CLAUDE;; codex) color=$C_CODEX;; *) color=$C_PI;; esac
    ago "$ts"; when=$AGO
    proj=${cwd##*/}; [ -n "$proj" ] || proj='?'
    width=$(( cols - 4 - 8 - 9 - 22 - 10 - 4 ))
    [ "$width" -lt 20 ] && width=20
    if [ "$ALL" = 1 ]; then
      printf '%3d %s%-7s%s %-8s %-20.20s %s%-9s%s %.*s\n' \
        "$i" "$color" "$agent" "$C_RESET" "$when" "$proj" "$C_DIM" "$short" "$C_RESET" "$width" "$title"
    else
      printf '%3d %s%-7s%s %-8s %s%-9s%s %.*s\n' \
        "$i" "$color" "$agent" "$C_RESET" "$when" "$C_DIM" "$short" "$C_RESET" "$((width+21))" "$title"
    fi
    if [ "$LONG" = 1 ]; then
      printf '            %s$ %s%s\n' "$C_DIM" "$(resume_cmd "$agent" "$id" "$f")" "$C_RESET"
    fi
    if [ "$PATHS" = 1 ]; then
      printf '            %s%s%s\n' "$C_DIM" "$f" "$C_RESET"
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
  local prefix=$1 ts agent f id n
  find_all | while IFS=$'\t' read -r ts agent f id n; do
    case $id in "$prefix"*) printf '%s\t%s\t%s\n' "$agent" "$id" "$f";; esac
  done
  return 0
}

find_one() { # index-or-prefix
  local prefix=$1 hits n ts agent f id
  case $prefix in
    [0-9]|[0-9][0-9]|[0-9][0-9][0-9])   # an index: nth row of the newest-first list
      hits=$(sessions | sed -n "$((prefix+1))p")
      [ -n "$hits" ] || { echo "als: no session at index $prefix" >&2; return 1; }
      IFS=$'\t' read -r ts agent f id n <<< "$hits"
      printf '%s\t%s\t%s\n' "$agent" "$id" "$f"; return 0;;
  esac
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
ALL=0 LONG=0 PATHS=0 LIMIT=0 AGENTS='' DIR=''
case ${1:-} in
  show|path|resume) [ $# -ge 2 ] || { usage >&2; exit 2; }; "cmd_$1" "$2"; exit;;
esac
while [ $# -gt 0 ]; do
  case $1 in
    -a|--all) ALL=1;;
    -l|--long) LONG=1;;
    -L|--paths) PATHS=1;;
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
