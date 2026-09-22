#!/usr/bin/env bash
# als - ls for agent sessions.
# Lists every coding-agent transcript on the machine, newest first.
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
  -t, --agent NAME    only this agent (repeatable): claude codex pi gemini
                      qwen opencode goose cline
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

# ---------- where each agent keeps its sessions ----------
# One line per agent: name, root directory. Files under a root are that
# agent's. Override a root with the agent's own environment variable.
XDG_DATA="${XDG_DATA_HOME:-$HOME/.local/share}"
case $(uname -s) in
  Darwin) VSCODE_STORAGE="$HOME/Library/Application Support/Code/User/globalStorage";;
  *)      VSCODE_STORAGE="${XDG_CONFIG_HOME:-$HOME/.config}/Code/User/globalStorage";;
esac
ROOTS="claude	${CLAUDE_CONFIG_DIR:-$HOME/.claude}/projects
codex	${CODEX_HOME:-$HOME/.codex}/sessions
pi	${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}/sessions
gemini	$HOME/.gemini/tmp
qwen	$HOME/.qwen/tmp
opencode	$XDG_DATA/opencode/storage/session
goose	$XDG_DATA/goose/sessions
cline	$VSCODE_STORAGE/saoudrizwan.claude-dev/tasks"

color_of() { # agent -> sets COLOR
  case $1 in
    claude) COLOR=$'\033[38;5;208m';; codex) COLOR=$'\033[38;5;39m';;
    pi) COLOR=$'\033[38;5;141m';;     gemini) COLOR=$'\033[38;5;75m';;
    qwen) COLOR=$'\033[38;5;135m';;   opencode) COLOR=$'\033[38;5;114m';;
    goose) COLOR=$'\033[38;5;220m';;  cline) COLOR=$'\033[38;5;45m';;
    *) COLOR='';;
  esac
  [ "$USE_COLOR" = 1 ] || COLOR=''
}
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then USE_COLOR=1 C_DIM=$'\033[2m' C_RESET=$'\033[0m'
else USE_COLOR=0 C_DIM='' C_RESET=''; fi

resume_cmd() { # agent id file -> sets RESUME ("" when the agent has no resume command)
  case $1 in
    claude)   RESUME="claude --resume $2";;
    codex)    RESUME="codex resume $2";;
    pi)       RESUME="pi --session $3";;
    gemini)   RESUME="gemini --resume $2";;
    qwen)     RESUME="qwen --resume $2";;
    opencode) RESUME="opencode --session $2";;
    goose)    RESUME="goose session --resume --name $2";;
    *)        RESUME="";;
  esac
}

# ---------- portable helpers ----------
NOW=$(date +%s)
ago() { # seconds since epoch -> sets AGO to "3m ago" (no subshell: called per row)
  local d=$(( NOW - $1 ))
  if   [ "$d" -lt 60 ];     then AGO="${d}s ago"
  elif [ "$d" -lt 3600 ];   then AGO="$((d/60))m ago"
  elif [ "$d" -lt 86400 ];  then AGO="$((d/3600))h ago"
  elif [ "$d" -lt 2592000 ]; then AGO="$((d/86400))d ago"
  else AGO="$((d/2592000))mo ago"; fi
}

# stdin: NUL-separated paths -> "mtime<TAB>path" per line, one stat call
mtimes() {
  if stat -f %m / >/dev/null 2>&1; then xargs -0 stat -f "%m"$'\t'"%N" 2>/dev/null
  else xargs -0 stat -c "%Y"$'\t'"%n" 2>/dev/null; fi
  return 0
}

HIDDEN='[als:hidden]'   # title sentinel for files that are not sessions
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/als"
CACHE="$CACHE_DIR/index-$VERSION.tsv"

# ---------- the parser: "agent<TAB>path<TAB>mtime" in, "path<TAB>cwd<TAB>title" out ----------
# One awk for every file. It reads the head of each transcript and stops as
# soon as it has the directory and the first real prompt, so multi-megabyte
# sessions cost the same as tiny ones. A session with no prompt yet is only
# cached once it is ten minutes old, so a session being typed into stays fresh.
parse() {
  awk -F '\t' -v now="$NOW" -v HIDDEN="$HIDDEN" '
    # the JSON string that starts right after the opening quote, unescaped, capped
    function jstr(s,   out) {
      match(s, /^([^"\\]|\\.)*/); out = substr(s, 1, RLENGTH)
      gsub(/\\[ntr]/, " ", out); gsub(/\\"/, "\"", out); gsub(/\\\\/, "\\", out)
      return substr(out, 1, 300) }
    # "key": "value" on this line, minified or pretty-printed
    function val(line, key) {
      if (match(line, "\"" key "\"[ \t]*:[ \t]*\"")) return jstr(substr(line, RSTART + RLENGTH, 2000))
      return "" }
    function has(line, key, value) { return match(line, "\"" key "\"[ \t]*:[ \t]*\"" value "\"") }
    function text_of(line,   t) { t = val(line, "text"); if (t == "") t = val(line, "content"); return t }
    { agent = $1; f = $2; cwd = ""; title = ""; n = 0; cont = 0; pend = 0
      while ((getline line < f) > 0) {
        if (++n > 60) break   # the prompt is in the first dozen records of every format
        if (agent == "claude") {
          if (cwd == "") cwd = val(line, "cwd")
          if (title == "" && has(line, "type", "user")) title = text_of(line) }
        else if (agent == "codex") {
          # Codex Desktop keeps its internal reviewer threads next to real sessions; not yours to resume
          if (n == 1 && has(line, "thread_source", "guardian_review")) { title = HIDDEN; break }
          if (cwd == "") cwd = val(line, "cwd")
          if (has(line, "type", "compacted")) cont = 1
          if (title == "" && has(line, "role", "user")) { t = text_of(line)
            # Codex injects AGENTS.md, <environment_context> and, after compaction, history summaries
            if (t !~ /^(<|# AGENTS\.md|The following is the Codex agent history)/) title = t } }
        else if (agent == "pi" || agent == "goose") {
          if (cwd == "") { cwd = val(line, "cwd"); if (cwd == "") cwd = val(line, "working_dir") }
          if (title == "" && has(line, "role", "user")) title = text_of(line) }
        else if (agent == "gemini" || agent == "qwen") {   # pretty JSON: "type" on one line, "content" later
          if (has(line, "type", "user")) pend = 1
          if (title == "" && pend) title = text_of(line) }
        else if (agent == "opencode") {                    # one object per session, title made by opencode
          if (cwd == "") cwd = val(line, "directory")
          if (title == "") title = val(line, "title") }
        else if (agent == "cline") {                       # pretty JSON: "role" on one line, "text" later
          if (has(line, "role", "user")) pend = 1
          if (title == "" && pend) { title = text_of(line); sub(/^<task> */, "", title); sub(/ *<\/task>.*$/, "", title) } }
        if (title != "" && (cwd != "" || agent == "gemini" || agent == "qwen" || agent == "cline")) break }
      close(f)
      if (title == "" && cont) title = "(continued after compaction)"
      if (title != "" || now - $3 > 600) { gsub(/\t/, " ", title); print f "\t" cwd "\t" title } }'
}

# ---------- every session: "mtime agent path id shortlen cwd title", newest first ----------
# One find, one stat, one awk. The awk tags each file with its agent, takes
# the id from the file name, shortens ids git-style (shortest unique prefix,
# minimum 4) and joins the cache. Files missing from the cache are parsed
# once and appended, then the join runs again.
find_files() {
  local roots=() root agent
  while IFS=$'\t' read -r agent root; do [ -d "$root" ] && roots+=("$root"); done <<< "$ROOTS"
  [ ${#roots[@]} -gt 0 ] || return 0
  find "${roots[@]}" -type f \( -name '*.jsonl' -o -name 'session-*.json' -o -name 'ses_*.json' \
    -o -name 'api_conversation_history.json' \) ! -name 'agent-*' -print0 2>/dev/null | mtimes
}

join_cache() { # missfile
  # awk -v expands \n, and BSD awk rejects a literal newline, so escape them
  awk -F '\t' -v OFS='\t' -v c="$CACHE" -v roots="${ROOTS//$'\n'/\\n}" -v miss="$1" '
    BEGIN { nr = split(roots, r, "\n"); for (i = 1; i <= nr; i++) { split(r[i], p, "\t"); ra[i] = p[1]; rp[i] = p[2] "/" } }
    FILENAME == c { cwd[$1] = $2; title[$1] = $3; next }
    { f = $2; agent = ""
      for (i = 1; i <= nr; i++) if (index(f, rp[i]) == 1) { agent = ra[i]; break }
      if (agent == "") next
      base = f; sub(/.*\//, "", base)
      if (agent == "codex") sub(/^rollout-[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}-[0-9]{2}-[0-9]{2}-/, "", base)
      else if (agent == "pi") sub(/^[^_]*_/, "", base)
      else if (agent == "gemini" || agent == "qwen") { sub(/\.json$/, "", base); sub(/.*-/, "", base) }   # session-<date>-<id>
      else if (agent == "cline") { base = f; sub(/\/[^\/]*$/, "", base); sub(/.*\//, "", base) }
      sub(/\.jsonl?$/, "", base)
      k++; ts[k] = $1; ag[k] = agent; path[k] = f; id[k] = base
      for (L = 4; L <= length(base); L++) seen[substr(base, 1, L)]++ }
    END {
      for (i = 1; i <= k; i++) {
        for (L = 4; L < length(id[i]) && seen[substr(id[i], 1, L)] > 1; L++) ;
        # "-" stands for an empty field: bash read collapses adjacent tabs
        if (path[i] in title) print ts[i], ag[i], path[i], id[i], L, (cwd[path[i]] == "" ? "-" : cwd[path[i]]), (title[path[i]] == "" ? "-" : title[path[i]])
        else { print ts[i], ag[i], path[i], id[i], L, "-", "-"; print ag[i] "\t" path[i] "\t" ts[i] > miss } } }' "$CACHE" -
}

sessions() {
  local files rows miss
  files=$(find_files)
  [ -n "$files" ] || return 0
  mkdir -p "$CACHE_DIR"; [ -f "$CACHE" ] || : > "$CACHE"
  miss="$CACHE_DIR/miss.$$"
  rows=$(printf '%s\n' "$files" | join_cache "$miss")
  if [ -s "$miss" ]; then   # first sight of some files: parse them once, then join again
    parse < "$miss" >> "$CACHE"
    rows=$(printf '%s\n' "$files" | join_cache /dev/null)
  fi
  rm -f "$miss"
  printf '%s\n' "$rows" | sort -rn | awk -F '\t' -v h="$HIDDEN" '$7 != h'
}

want_agent() { # agent
  [ -z "$AGENTS" ] && return 0
  case " $AGENTS " in *" $1 "*) return 0;; esac
  return 1
}

# ---------- list ----------
list_rows() { # dir cols
  local dir=$1 cols=$2 shown=0 i=-1 width ts agent f cwd id short n title when proj
  sessions | while IFS=$'\t' read -r ts agent f id n cwd title; do
    i=$((i+1))
    want_agent "$agent" || continue
    [ "$cwd" = - ] && cwd=''; [ "$title" = - ] && title=''
    short=${id:0:$n}
    if [ "$ALL" = 0 ] && [ "$cwd" != "$dir" ] && [ "$cwd" != "$DIRP" ]; then continue; fi
    [ -z "$title" ] && title="${C_DIM}(empty)${C_RESET}"
    color_of "$agent"
    ago "$ts"; when=$AGO
    proj=${cwd##*/}; [ -n "$proj" ] || proj='?'
    width=$(( cols - 4 - 9 - 9 - 22 - 10 - 4 ))
    [ "$width" -lt 20 ] && width=20
    if [ "$ALL" = 1 ]; then
      printf '%3d %s%-8s%s %-8s %-20.20s %s%-9s%s %.*s\n' \
        "$i" "$COLOR" "$agent" "$C_RESET" "$when" "$proj" "$C_DIM" "$short" "$C_RESET" "$width" "$title"
    else
      printf '%3d %s%-8s%s %-8s %s%-9s%s %.*s\n' \
        "$i" "$COLOR" "$agent" "$C_RESET" "$when" "$C_DIM" "$short" "$C_RESET" "$((width+21))" "$title"
    fi
    if [ "$LONG" = 1 ]; then
      resume_cmd "$agent" "$id" "$f"
      if [ -n "$RESUME" ]; then printf '             %s$ %s%s\n' "$C_DIM" "$RESUME" "$C_RESET"
      else printf '             %s(no resume command: open it in the app)%s\n' "$C_DIM" "$C_RESET"; fi
    fi
    if [ "$PATHS" = 1 ]; then
      printf '             %s%s%s\n' "$C_DIM" "$f" "$C_RESET"
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

# ---------- find one session by index or id prefix -> "agent<TAB>id<TAB>path" ----------
find_one() { # index-or-prefix
  local prefix=$1 hits n
  case $prefix in
    [0-9]|[0-9][0-9]|[0-9][0-9][0-9])   # an index: nth row of the newest-first list
      hits=$(sessions | awk -F '\t' -v OFS='\t' -v n="$((prefix+1))" 'NR == n { print $2, $4, $3 }')
      [ -n "$hits" ] || { echo "als: no session at index $prefix" >&2; return 1; }
      printf '%s\n' "$hits"; return 0;;
  esac
  hits=$(sessions | awk -F '\t' -v OFS='\t' -v p="$prefix" 'index($4, p) == 1 { print $2, $4, $3 }')
  n=$(printf '%s' "$hits" | grep -c .)
  case $n in
    0) echo "als: no session starts with '$prefix'" >&2; return 1;;
    1) printf '%s\n' "$hits";;
    *) echo "als: '$prefix' is ambiguous:" >&2; printf '%s\n' "$hits" | cut -f2 >&2; return 1;;
  esac
}

# ---------- show: transcript as plain text ----------
# shellcheck disable=SC2016  # the jq filters are meant to stay single-quoted
cmd_show() {
  local agent id f filter
  IFS=$'\t' read -r agent id f < <(find_one "$1")
  case $agent in
    claude) filter='
      select(.type=="user" or .type=="assistant") | .message as $m
      | ($m.content | if type=="string" then [.] else map(
          if .type=="text" then .text
          elif .type=="tool_use" then "[tool: " + .name + "] " + (.input|tostring)
          elif .type=="tool_result" then "[result] " + (.content|tostring)
          else empty end) end) as $parts
      | select($parts|length>0)
      | "\n## " + $m.role + "\n" + ($parts|join("\n"))';;
    codex) filter='
      select(.type=="response_item" and .payload.type=="message")
      | .payload as $m
      | select($m.role!="developer")
      | ($m.content|map(.text // empty)|join("\n")) as $t
      | select($t|length>0)
      | select($t|test("^(<|# AGENTS.md)")|not)
      | "\n## " + $m.role + "\n" + $t';;
    pi) filter='
      select(.type=="message") | .message as $m
      | ($m.content | if type=="string" then [.] else map(
          if .type=="text" then .text
          elif .type=="toolCall" then "[tool: " + .name + "] " + (.arguments|tostring)
          elif .type=="toolResult" then "[result] " + (.content|tostring)
          else empty end) end) as $parts
      | select($parts|length>0)
      | "\n## " + $m.role + "\n" + ($parts|join("\n"))';;
    goose) filter='
      select(.role) | "\n## " + .role + "\n" + (.content|map(.text // empty)|join("\n"))';;
    gemini|qwen) filter='
      .messages[] | "\n## " + .type + "\n" + (.content | if type=="string" then . else map(.text // empty)|join("\n") end)';;
    cline) filter='
      .[] | "\n## " + .role + "\n" + (.content | if type=="string" then . else map(.text // empty)|join("\n") end)';;
    *) echo "als: show does not know the $agent format yet; the transcript is at" >&2; echo "$f" >&2; exit 1;;
  esac
  command -v jq >/dev/null || { echo "als: 'show' needs jq (brew install jq / apt install jq)" >&2; exit 1; }
  jq -r "$filter" "$f"
}

cmd_path()   { local hit; hit=$(find_one "$1") || exit 1; printf '%s\n' "${hit##*	}"; }
cmd_resume() {
  local agent id f
  IFS=$'\t' read -r agent id f < <(find_one "$1")
  resume_cmd "$agent" "$id" "$f"
  [ -n "$RESUME" ] || { echo "als: $agent has no resume command; the transcript is at" >&2; echo "$f" >&2; exit 1; }
  # shellcheck disable=SC2086
  exec $RESUME
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
