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
       als path <id>                print where the transcript lives
       als resume <id>              reopen the session in its own agent

options:
  -a, --all           every directory, not just dir
  -t, --agent NAME    only this agent (repeatable): claude codex pi gemini
                      qwen cline opencode goose muse openclaw
  -n, --limit N       show at most N sessions
  -l, --long          show the command that resumes each session
  -L, --paths         also show where each transcript lives
  -h, --help          this text
  -V, --version       version

<id> is the index or the short id from the listing, or any unique prefix
of the full id. Index 0 is the newest session; indexes are global, so
als resume 3 is the same session whether you listed with -a or not.
EOF
}

# ---------- where each agent keeps its sessions ----------
# File-based agents: one line per agent, name and root directory. Every
# transcript under a root belongs to that agent.
XDG_DATA="${XDG_DATA_HOME:-$HOME/.local/share}"
GEMINI_HOME="${GEMINI_CLI_HOME:-$HOME/.gemini}"
ROOTS="claude	${CLAUDE_CONFIG_DIR:-$HOME/.claude}/projects
codex	${CODEX_HOME:-$HOME/.codex}/sessions
pi	${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}/sessions
gemini	$GEMINI_HOME/tmp
qwen	$HOME/.qwen/projects
cline	$HOME/.cline/data/sessions"
# Database-backed agents: read with the sqlite3 binary when it is present.
DB_OPENCODE="$XDG_DATA/opencode/opencode.db"
DB_GOOSE="$XDG_DATA/goose/sessions/sessions.db"
DB_MUSE="$XDG_DATA/muse/session-index.db"
DB_OPENCLAW_GLOB="$HOME/.openclaw/agents/*/agent/openclaw-agent.sqlite"

color_of() { # agent -> sets COLOR
  case $1 in
    claude) COLOR=$'\033[38;5;208m';; codex) COLOR=$'\033[38;5;39m';;
    pi) COLOR=$'\033[38;5;141m';;     gemini) COLOR=$'\033[38;5;75m';;
    qwen) COLOR=$'\033[38;5;135m';;   opencode) COLOR=$'\033[38;5;114m';;
    goose) COLOR=$'\033[38;5;220m';;  cline) COLOR=$'\033[38;5;45m';;
    muse) COLOR=$'\033[38;5;204m';;   openclaw) COLOR=$'\033[38;5;173m';;
    *) COLOR='';;
  esac
  [ "$USE_COLOR" = 1 ] || COLOR=''
}
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then USE_COLOR=1 C_DIM=$'\033[2m' C_RESET=$'\033[0m'
else USE_COLOR=0 C_DIM='' C_RESET=''; fi

resume_cmd() { # agent id file cwd -> sets RESUME ("" when the agent has no resume command)
  case $1 in
    claude)   RESUME="claude --resume $2";;
    codex)    RESUME="codex resume $2";;
    pi)       RESUME="pi --session $3";;
    gemini)   RESUME="gemini --resume $2";;
    qwen)     RESUME="qwen --resume $2";;
    cline)    RESUME="cline -i --id $2";;
    opencode) RESUME="opencode --session $2";;
    goose)    RESUME="goose session --resume --session-id $2";;
    muse)     RESUME="muse resume $2";;
    openclaw) RESUME="openclaw tui --session agent:$4";;   # the "directory" column holds the session key
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

# ---------- the parser: "agent<TAB>path<TAB>mtime" in, "path<TAB>cwd<TAB>title[<TAB>id]" out ----------
# One awk for every file. It reads the head of each transcript and stops as
# soon as it has the directory and the first real prompt, so multi-megabyte
# sessions cost the same as tiny ones. A session with no prompt yet is only
# cached once it is ten minutes old, so a session being typed into stays fresh.
# The optional fourth column replaces the id taken from the file name when
# the agent needs the full id to resume (Gemini names files by a short one).
parse() {
  awk -F '\t' -v now="$NOW" -v HIDDEN="$HIDDEN" -v gemini_projects="$GEMINI_HOME/projects.json" '
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
    BEGIN {  # Gemini names project dirs by a short id; projects.json maps paths to them
      while ((getline line < gemini_projects) > 0)
        if (match(line, /"\/[^"]*"[ \t]*:[ \t]*"[^"]+"/)) {
          split(substr(line, RSTART, RLENGTH), kv, /"[ \t]*:[ \t]*"/)
          gsub(/"/, "", kv[1]); gsub(/"/, "", kv[2]); gemini_dir[kv[2]] = kv[1] }
      close(gemini_projects) }
    { agent = $1; f = $2; cwd = ""; title = ""; id = ""; n = 0; cont = 0; pend = 0
      while ((getline line < f) > 0) {
        if (++n > 60) break   # the prompt is in the first dozen records of every format
        if (agent == "claude" || agent == "qwen") {
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
        else if (agent == "pi") {
          if (cwd == "") cwd = val(line, "cwd")
          if (title == "" && has(line, "role", "user")) title = text_of(line) }
        else if (agent == "gemini") {   # line 1 is metadata with the full session id; messages follow
          if (n == 1) { id = val(line, "sessionId")
            nparts = split(f, parts, "/"); cwd = gemini_dir[parts[nparts - 2]] }
          if (title == "" && has(line, "type", "user")) title = text_of(line) }
        else if (agent == "cline") {    # <id>.json, pretty-printed: cwd and prompt are top-level keys
          if (cwd == "") cwd = val(line, "cwd")
          if (title == "") title = val(line, "prompt") }
        if (title != "" && (cwd != "" || agent == "gemini")) break }
      close(f)
      if (title == "" && cont) title = "(continued after compaction)"
      if (title != "" || now - $3 > 600) { gsub(/\t/, " ", title); print f "\t" cwd "\t" title "\t" id } }'
}

# ---------- database-backed agents: one query each, rows in the final shape ----------
# Prints "mtime<TAB>agent<TAB>db<TAB>id<TAB>directory<TAB>title". Titles are
# the first prompt where the store has it. Skipped when sqlite3 is missing.
db_rows() {
  command -v sqlite3 >/dev/null || return 0
  local db q
  san() { printf "replace(replace(substr(%s, 1, 300), char(9), ' '), char(10), ' ')" "$1"; }
  if [ -f "$DB_OPENCODE" ]; then
    q=$(san "title")
    sqlite3 -batch -readonly -separator '	' "$DB_OPENCODE" "select time_updated/1000, 'opencode', '$DB_OPENCODE', id, directory, $q
      from session where time_archived is null and parent_id is null" 2>/dev/null
  fi
  if [ -f "$DB_GOOSE" ]; then
    q=$(san "coalesce((select json_extract(m.content_json, '\$[0].text') from messages m where m.session_id = s.id and m.role = 'user' order by m.id limit 1), nullif(s.description, ''), s.name)")
    sqlite3 -batch -readonly -separator '	' "$DB_GOOSE" "select cast(strftime('%s', updated_at) as integer), 'goose', '$DB_GOOSE', id, working_dir, $q
      from sessions s where session_type = 'user'" 2>/dev/null
  fi
  if [ -f "$DB_MUSE" ]; then
    q=$(san "coalesce(nullif(first_user_prompt, ''), title)")
    sqlite3 -batch -readonly -separator '	' "$DB_MUSE" "select updated_at_us/1000000, 'muse', '$DB_MUSE', session_id, coalesce(workspace_root, ''), $q
      from sessions where status = 'valid'" 2>/dev/null
  fi
  for db in $DB_OPENCLAW_GLOB; do   # one store per OpenClaw agent; the directory column carries the session key
    [ -f "$db" ] || continue
    q=$(san "coalesce((select coalesce(json_extract(e.event_json, '\$.message.content[0].text'), json_extract(e.event_json, '\$.message.content')) from transcript_events e where e.session_id = w.session_id and json_extract(e.event_json, '\$.type') = 'message' and json_extract(e.event_json, '\$.message.role') = 'user' order by e.seq limit 1), nullif(w.display_name, ''), '')")
    sqlite3 -batch -readonly -separator '	' "$db" "select w.updated_at/1000, 'openclaw', '$db', w.session_id, substr(w.session_key, 7), $q
      from session_windows w" 2>/dev/null
  done
  return 0
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
  find "${roots[@]}" -type f \( -name '*.jsonl' -o -name '*.json' \) ! -name 'agent-*' ! -name '*.messages.json' -print0 2>/dev/null | mtimes
}

# stdin: "mtime<TAB>path" for files, or six-column rows from db_rows.
join_cache() { # missfile
  # awk -v expands \n, and BSD awk rejects a literal newline, so escape them
  awk -F '\t' -v OFS='\t' -v c="$CACHE" -v roots="${ROOTS//$'\n'/\\n}" -v miss="$1" '
    BEGIN { nr = split(roots, r, "\n"); for (i = 1; i <= nr; i++) { split(r[i], p, "\t"); ra[i] = p[1]; rp[i] = p[2] "/" } }
    FILENAME == c { cwd[$1] = $2; title[$1] = $3; if ($4 != "") fullid[$1] = $4; next }
    NF >= 6 { k++; ts[k] = $1; ag[k] = $2; path[k] = $3; id[k] = $4; dcwd[k] = $5; dtitle[k] = $6; fromdb[k] = 1
              for (L = 4; L <= length(id[k]); L++) seen[substr(id[k], 1, L)]++; next }
    { f = $2; agent = ""
      for (i = 1; i <= nr; i++) if (index(f, rp[i]) == 1) { agent = ra[i]; break }
      if (agent == "") next
      base = f; sub(/.*\//, "", base)
      if (agent == "codex") { if (base !~ /^rollout-.*\.jsonl$/) next
        sub(/^rollout-[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}-[0-9]{2}-[0-9]{2}-/, "", base) }
      else if (agent == "pi") sub(/^[^_]*_/, "", base)
      else if (agent == "gemini") { if (f !~ /\/chats\/session-.*\.jsonl$/) next
        sub(/\.jsonl$/, "", base); sub(/.*-/, "", base) }   # session-<date>-<id>
      else if (agent == "cline") { dir = f; sub(/\/[^\/]*$/, "", dir); sub(/.*\//, "", dir)
        if (base != dir ".json") next }                     # sessions/<id>/<id>.json only
      else if (base !~ /\.jsonl$/) next
      sub(/\.jsonl?$/, "", base)
      if (f in fullid) base = fullid[f]
      k++; ts[k] = $1; ag[k] = agent; path[k] = f; id[k] = base
      for (L = 4; L <= length(base); L++) seen[substr(base, 1, L)]++ }
    END {
      for (i = 1; i <= k; i++) {
        for (L = 4; L < length(id[i]) && seen[substr(id[i], 1, L)] > 1; L++) ;
        # "-" stands for an empty field: bash read collapses adjacent tabs
        if (fromdb[i]) print ts[i], ag[i], path[i], id[i], L, (dcwd[i] == "" ? "-" : dcwd[i]), (dtitle[i] == "" ? "-" : dtitle[i])
        else if (path[i] in title) print ts[i], ag[i], path[i], id[i], L, (cwd[path[i]] == "" ? "-" : cwd[path[i]]), (title[path[i]] == "" ? "-" : title[path[i]])
        else { print ts[i], ag[i], path[i], id[i], L, "-", "-"; print ag[i] "\t" path[i] "\t" ts[i] > miss } } }' "$CACHE" -
}

sessions() {
  local files rows miss
  files=$(find_files; db_rows)
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
      resume_cmd "$agent" "$id" "$f" "$cwd"
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

# ---------- find one session by index or id prefix -> "agent<TAB>id<TAB>path<TAB>cwd" ----------
find_one() { # index-or-prefix
  local prefix=$1 hits n
  case $prefix in
    [0-9]|[0-9][0-9]|[0-9][0-9][0-9])   # an index: nth row of the newest-first list
      hits=$(sessions | awk -F '\t' -v OFS='\t' -v n="$((prefix+1))" 'NR == n { print $2, $4, $3, $6 }')
      [ -n "$hits" ] || { echo "als: no session at index $prefix" >&2; return 1; }
      printf '%s\n' "$hits"; return 0;;
  esac
  hits=$(sessions | awk -F '\t' -v OFS='\t' -v p="$prefix" 'index($4, p) == 1 { print $2, $4, $3, $6 }')
  n=$(printf '%s' "$hits" | grep -c .)
  case $n in
    0) echo "als: no session starts with '$prefix'" >&2; return 1;;
    1) printf '%s\n' "$hits";;
    *) echo "als: '$prefix' is ambiguous:" >&2; printf '%s\n' "$hits" | cut -f2 >&2; return 1;;
  esac
}

# ---------- show: transcript as plain text ----------
# turns "role<TAB>text" lines into the transcript layout
as_turns() { awk -F '\t' '{ print "\n## " $1 "\n" $2 }'; }

# shellcheck disable=SC2016  # the jq filters are meant to stay single-quoted
cmd_show() {
  local agent id f cwd filter
  IFS=$'\t' read -r agent id f cwd < <(find_one "$1")
  [ "$cwd" = - ] && cwd=''
  case $agent in
    opencode) sqlite3 -batch -readonly -separator '	' "$f" "select json_extract(m.data, '\$.role'), replace(json_extract(p.data, '\$.text'), char(10), ' ')
        from message m join part p on p.message_id = m.id where m.session_id = '$id' and json_extract(p.data, '\$.type') = 'text'
        order by m.time_created, p.time_created" | as_turns; return;;
    goose) sqlite3 -batch -readonly -separator '	' "$f" "select role, replace(json_extract(content_json, '\$[0].text'), char(10), ' ')
        from messages where session_id = '$id' and json_extract(content_json, '\$[0].text') is not null
        and json_extract(content_json, '\$[0].text') not like '<turn-context>%' order by id" | as_turns; return;;
    muse) command -v jq >/dev/null || { echo "als: 'show' needs jq (brew install jq / apt install jq)" >&2; exit 1; }
      f=$(sqlite3 -batch -readonly "$f" "select session_log_path from sessions where session_id = '$id'")
      jq -r 'select(.payload_type == "runtime.session") | .payload.event
        | if .kind == "started" and (.prompt // "") != "" then "\n## user\n" + .prompt
          elif .kind == "assistant_message_committed" then "\n## assistant\n" + .text else empty end' "$f"; return;;
    openclaw) command -v jq >/dev/null || { echo "als: 'show' needs jq (brew install jq / apt install jq)" >&2; exit 1; }
      sqlite3 -batch -readonly "$f" "select event_json from transcript_events where session_id = '$id' and json_extract(event_json, '\$.type') = 'message' order by seq" \
        | jq -r '.message as $m | ($m.content | if type=="string" then [.] else map(.text // empty) end) as $p | select($p|length>0) | "\n## " + $m.role + "\n" + ($p|join("\n"))'
      return;;
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
    qwen) filter='
      select(.type=="user" or .type=="assistant") | "\n## " + .type + "\n" + (.message.parts|map(.text // empty)|join("\n"))';;
    gemini) filter='
      select(.type=="user" or .type=="gemini") | "\n## " + .type + "\n" + (.content | if type=="string" then . else map(.text // empty)|join("\n") end)';;
    cline) f="${f%.json}.messages.json"; filter='
      .messages[] | "\n## " + .role + "\n" + (.content|map(.text // empty)|join("\n") | sub("^<user_input[^>]*>"; "") | sub("</user_input>$"; ""))';;
    *) echo "als: show does not know the $agent format yet; the session is at" >&2; echo "$f" >&2; exit 1;;
  esac
  command -v jq >/dev/null || { echo "als: 'show' needs jq (brew install jq / apt install jq)" >&2; exit 1; }
  jq -r "$filter" "$f"
}

cmd_path()   { local hit; hit=$(find_one "$1") || exit 1; printf '%s\n' "$(printf '%s' "$hit" | cut -f3)"; }
cmd_resume() {
  local agent id f cwd
  IFS=$'\t' read -r agent id f cwd < <(find_one "$1")
  [ "$cwd" = - ] && cwd=''
  resume_cmd "$agent" "$id" "$f" "$cwd"
  [ -n "$RESUME" ] || { echo "als: $agent has no resume command; the session is at" >&2; echo "$f" >&2; exit 1; }
  # most agents only find a session from the directory it was started in
  [ -d "$cwd" ] && cd "$cwd"
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
