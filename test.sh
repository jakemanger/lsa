#!/usr/bin/env bash
# Fixture tests: a fake home with one session per agent, in each agent's
# real on-disk format (copied from sessions the agents wrote themselves).
set -eu
cd "$(dirname "$0")"; LSA=$PWD/lsa
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
export HOME=$tmp NO_COLOR=1
unset CLAUDE_CONFIG_DIR CODEX_HOME PI_CODING_AGENT_DIR XDG_CACHE_HOME XDG_DATA_HOME GEMINI_CLI_HOME
proj=$tmp/proj; mkdir -p "$proj"

# ---- file-based agents ----
mkdir -p "$tmp/.claude/projects/x" "$tmp/.codex/sessions/2026/09/22" "$tmp/.pi/agent/sessions/x" \
  "$tmp/.qwen/projects/x/chats" "$tmp/.gemini/tmp/quiet-otter/chats" "$tmp/.cline/data/sessions/1758500000000_ab1cd"
cat > "$tmp/.claude/projects/x/aaaa1111-0000-0000-0000-000000000000.jsonl" <<EOF
{"type":"queue-operation","sessionId":"aaaa1111-0000-0000-0000-000000000000"}
{"type":"user","message":{"role":"user","content":[{"type":"text","text":"fix the \"login\" bug\nplease"}]},"cwd":"$proj","sessionId":"aaaa1111-0000-0000-0000-000000000000"}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"On it."},{"type":"tool_use","name":"bash","input":{"command":"ls"}}]},"cwd":"$proj"}
EOF
cat > "$tmp/.claude/projects/x/agent-sidechain.jsonl" <<EOF
{"type":"user","message":{"role":"user","content":[{"type":"text","text":"SIDECHAIN"}]},"cwd":"$proj"}
EOF
cat > "$tmp/.codex/sessions/2026/09/22/rollout-2026-09-22T10-00-00-bbbb2222-0000-0000-0000-000000000000.jsonl" <<EOF
{"type":"session_meta","payload":{"session_id":"bbbb2222-0000-0000-0000-000000000000","cwd":"$proj","thread_source":"user"}}
{"type":"response_item","payload":{"type":"message","role":"developer","content":[{"type":"input_text","text":"<skills>"}]}}
{"type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"# AGENTS.md instructions\nstuff"}]}}
{"type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"<environment_context>x</environment_context>"}]}}
{"timestamp":"2026-01-01T00:00:00.000Z","type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"add subtitles"}]}}
{"type":"response_item","payload":{"type":"message","role":"assistant","content":[{"type":"output_text","text":"Done."}]}}
EOF
cat > "$tmp/.codex/sessions/2026/09/22/rollout-2026-09-22T11-00-00-dddd4444-0000-0000-0000-000000000000.jsonl" <<EOF
{"type":"session_meta","payload":{"session_id":"dddd4444-0000-0000-0000-000000000000","cwd":"$proj","thread_source":"guardian_review"}}
{"type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"REVIEWER"}]}}
EOF
cat > "$tmp/.pi/agent/sessions/x/2026-09-22T09-00-00-000Z_cccc3333-0000-0000-0000-000000000000.jsonl" <<EOF
{"type":"session","version":3,"id":"cccc3333-0000-0000-0000-000000000000","cwd":"$tmp/elsewhere"}
{"type":"message","message":{"role":"user","content":[{"type":"text","text":"hello pi"}]}}
{"type":"message","message":{"role":"assistant","content":[{"type":"text","text":"hi"}]}}
EOF
cat > "$tmp/.qwen/projects/x/chats/eeee5555-0000-0000-0000-000000000000.jsonl" <<EOF
{"uuid":"u1","parentUuid":null,"sessionId":"eeee5555-0000-0000-0000-000000000000","type":"user","cwd":"$proj","message":{"role":"user","parts":[{"text":"write a haiku about awk"}]}}
{"uuid":"u2","parentUuid":"u1","sessionId":"eeee5555-0000-0000-0000-000000000000","type":"system","subtype":"ui_telemetry","cwd":"$proj","systemPayload":{}}
{"uuid":"u3","parentUuid":"u2","sessionId":"eeee5555-0000-0000-0000-000000000000","type":"assistant","cwd":"$proj","message":{"role":"model","parts":[{"text":"fields split at dawn"}]}}
EOF
printf '{\n  "projects": {\n    "%s": "quiet-otter"\n  }\n}\n' "$proj" > "$tmp/.gemini/projects.json"
cat > "$tmp/.gemini/tmp/quiet-otter/chats/session-2026-09-22T08-00-00-ffff6666.jsonl" <<EOF
{"sessionId":"ffff6666-0000-0000-0000-000000000000","projectHash":"abc","startTime":"2026-09-22T08:00:00.000Z","lastUpdated":"2026-09-22T08:00:05.000Z"}
{"id":"m1","timestamp":"2026-09-22T08:00:01.000Z","type":"user","content":[{"text":"explain this regex"}]}
{"id":"m2","timestamp":"2026-09-22T08:00:05.000Z","type":"gemini","content":"It matches dates."}
EOF
cat > "$tmp/.cline/data/sessions/1758500000000_ab1cd/1758500000000_ab1cd.json" <<EOF
{
  "version": 1,
  "session_id": "1758500000000_ab1cd",
  "source": "cli",
  "cwd": "$proj",
  "workspace_root": "$proj",
  "prompt": "make the sidebar collapsible",
  "metadata": {
    "title": "make the sidebar collapsible"
  }
}
EOF
cat > "$tmp/.cline/data/sessions/1758500000000_ab1cd/1758500000000_ab1cd.messages.json" <<EOF
{"version":1,"messages":[{"id":"m1","role":"user","content":[{"type":"text","text":"<user_input mode=\"act\">make the sidebar collapsible</user_input>"}]},{"id":"m2","role":"assistant","content":[{"type":"text","text":"Sure."}]}]}
EOF

# ---- database-backed agents (the columns lsa reads, with the agents' own names) ----
have_sqlite=0
if command -v sqlite3 >/dev/null; then
  have_sqlite=1
  mkdir -p "$tmp/.local/share/opencode" "$tmp/.local/share/goose/sessions" "$tmp/.local/share/muse" "$tmp/.openclaw/agents/main/agent"
  sqlite3 "$tmp/.local/share/opencode/opencode.db" "
    create table session (id text primary key, project_id text, parent_id text, directory text, title text, time_created integer, time_updated integer, time_archived integer);
    create table message (id text primary key, session_id text, time_created integer, time_updated integer, data text);
    create table part (id text primary key, message_id text, session_id text, time_created integer, time_updated integer, data text);
    insert into session values ('ses_gggg7777aaaa', 'p1', null, '$proj', 'Refactor the login form', 1758500000000, 1758500005000, null);
    insert into session values ('ses_archived0000', 'p1', null, '$proj', 'old', 1758400000000, 1758400000000, 1758400001000);
    insert into message values ('msg_1', 'ses_gggg7777aaaa', 1, 1, '{\"role\":\"user\"}');
    insert into part values ('prt_1', 'msg_1', 'ses_gggg7777aaaa', 1, 1, '{\"type\":\"text\",\"text\":\"refactor the login form\"}');
    insert into message values ('msg_2', 'ses_gggg7777aaaa', 2, 2, '{\"role\":\"assistant\"}');
    insert into part values ('prt_2', 'msg_2', 'ses_gggg7777aaaa', 2, 2, '{\"type\":\"text\",\"text\":\"Done.\"}');"
  sqlite3 "$tmp/.local/share/goose/sessions/sessions.db" "
    create table sessions (id text primary key, name text, description text, session_type text, working_dir text, created_at timestamp, updated_at timestamp);
    create table messages (id integer primary key, message_id text, session_id text, role text, content_json text, created_timestamp integer);
    insert into sessions values ('20260922_7', 'honk', '', 'user', '$proj', '2026-09-22 02:28:04', '2026-09-22 02:28:09');
    insert into messages values (1, 'm1', '20260922_7', 'user', '[{\"type\":\"text\",\"text\":\"honk at the tests\"}]', 1);
    insert into messages values (2, 'm2', '20260922_7', 'user', '[{\"type\":\"text\",\"text\":\"<turn-context>now</turn-context>\"}]', 2);
    insert into messages values (3, 'm3', '20260922_7', 'assistant', '[{\"type\":\"text\",\"text\":\"HONK\"}]', 3);"
  mkdir -p "$tmp/.local/share/muse/sessions/2026/09/22/hhhh8888-0000-0000-0000-000000000000"
  cat > "$tmp/.local/share/muse/sessions/2026/09/22/hhhh8888-0000-0000-0000-000000000000/session.jsonl" <<EOF
{"payload_type":"runtime.session.metadata","payload":{"kind":"metadata","record":{"workspace_root":"$proj"}}}
{"payload_type":"runtime.session","payload":{"kind":"run","event":{"kind":"started","prompt":"rename Widget to Panel"}}}
{"payload_type":"runtime.session","payload":{"kind":"run","event":{"kind":"assistant_message_committed","text":"Renamed in 12 files."}}}
EOF
  sqlite3 "$tmp/.local/share/muse/session-index.db" "
    create table sessions (session_id text primary key, session_log_path text, workspace_root text, title text, first_user_prompt text, created_at_us integer, updated_at_us integer, status text);
    insert into sessions values ('hhhh8888-0000-0000-0000-000000000000', '$tmp/.local/share/muse/sessions/2026/09/22/hhhh8888-0000-0000-0000-000000000000/session.jsonl', '$proj', 'rename Widget to Panel', 'rename Widget to Panel', 1758500000000000, 1758500009000000, 'valid');"
  sqlite3 "$tmp/.openclaw/agents/main/agent/openclaw-agent.sqlite" "
    create table session_windows (session_id text primary key, session_key text, updated_at integer, display_name text, channel text);
    create table transcript_events (session_id text, seq integer, event_json text, created_at integer);
    insert into session_windows values ('iiii9999-0000-0000-0000-000000000000', 'agent:main:main', 1758500000000, '', '');
    insert into transcript_events values ('iiii9999-0000-0000-0000-000000000000', 1, '{\"type\":\"message\",\"message\":{\"role\":\"user\",\"content\":\"what is on my calendar\"}}', 1);
    insert into transcript_events values ('iiii9999-0000-0000-0000-000000000000', 2, '{\"type\":\"message\",\"message\":{\"role\":\"assistant\",\"content\":[{\"type\":\"text\",\"text\":\"Nothing today.\"}]}}', 2);"
fi

# fixtures are old: the working marker is only for files touched in the last two minutes
find "$tmp" -type f -exec touch -t 202601010000 {} +

fail=0
check() { # name expected actual
  if [ "$2" = "$3" ]; then echo "ok   $1"; else echo "FAIL $1"; echo "  want: $2"; echo "  got:  $3"; fail=1; fi
}
title_of() { cut -c54-; }          # the title column in -a listings
title_here() { cut -c33-; }        # the title column in a directory listing
agents_of() { awk '{print $2}' | sort | tr '\n' ' ' | sed 's/ $//'; }

out=$(cd "$proj" && bash "$LSA")
if [ $have_sqlite = 1 ]; then
  check "directory listing has every agent that recorded it" "claude cline codex gemini goose muse opencode qwen" "$(printf '%s\n' "$out" | agents_of)"
else
  check "directory listing has every agent that recorded it" "claude cline codex gemini qwen" "$(printf '%s\n' "$out" | agents_of)"
fi
check "sidechain skipped" "" "$(printf '%s\n' "$out" | grep SIDECHAIN || true)"
check "codex reviewer threads hidden" "" "$(bash "$LSA" -a | grep REVIEWER || true)"
check "claude title unescaped" 'fix the "login" bug please' "$(printf '%s\n' "$out" | grep ' claude ' | title_here)"
check "codex skips injected prompts" "add subtitles" "$(printf '%s\n' "$out" | grep ' codex ' | title_here)"
check "qwen title" "write a haiku about awk" "$(printf '%s\n' "$out" | grep ' qwen ' | title_here)"
check "cline title" "make the sidebar collapsible" "$(printf '%s\n' "$out" | grep ' cline ' | title_here)"
check "gemini title, directory via projects.json" "explain this regex" "$(printf '%s\n' "$out" | grep ' gemini ' | title_here)"
check "cache written" "1" "$([ -s "$tmp/.cache/lsa/index-$(bash "$LSA" -V | cut -d' ' -f2).tsv" ] && echo 1)"
check "second run from cache matches" "$(bash "$LSA" -a)" "$(bash "$LSA" -a)"

if [ $have_sqlite = 1 ]; then
  check "opencode title and archived hidden" "Refactor the login form" "$(bash "$LSA" -a -t opencode | title_of)"
  check "goose title is the first prompt" "honk at the tests" "$(bash "$LSA" -a -t goose | title_of)"
  check "muse title" "rename Widget to Panel" "$(bash "$LSA" -a -t muse | title_of)"
  check "openclaw title and session key" "main:main" "$(bash "$LSA" -a -t openclaw | awk '{print $5}')"
  check "openclaw first user message" "what is on my calendar" "$(bash "$LSA" -a -t openclaw | title_of)"
  check "show opencode" $'\n## user\nrefactor the login form\n\n## assistant\nDone.' "$(bash "$LSA" show ses_g)"
  check "show goose skips turn context" $'\n## user\nhonk at the tests\n\n## assistant\nHONK' "$(bash "$LSA" show 2026)"
else
  echo "skip database agents (no sqlite3)"
fi

all=$(bash "$LSA" -a)
check "short ids are 4 chars when unique" "aaaa bbbb cccc" "$(bash "$LSA" -a -t claude -t codex -t pi | awk '{print $6}' | sort | tr '\n' ' ' | sed 's/ $//')"
cp -p "$tmp/.claude/projects/x/aaaa1111-0000-0000-0000-000000000000.jsonl" "$tmp/.claude/projects/x/aaaa1199-0000-0000-0000-000000000000.jsonl"   # -p: keep it old, or a real claude on this machine makes it busy
check "short ids grow until unique" "aaaa111 aaaa119" "$(bash "$LSA" -a -t claude | awk '{print $6}' | sort | tr '\n' ' ' | sed 's/ $//')"
check "same prompt with distinct session ids stays visible" "2" "$(bash "$LSA" -a -t claude | grep -c 'fix the')"
check "short id resolves" "$tmp/.claude/projects/x/aaaa1199-0000-0000-0000-000000000000.jsonl" "$(bash "$LSA" path aaaa1199)"
rm "$tmp/.claude/projects/x/aaaa1199-0000-0000-0000-000000000000.jsonl"
check "-t pi filters" "pi" "$(bash "$LSA" -a -t pi | awk '{print $2}')"
check "-n 1 limits" "1" "$(bash "$LSA" -a -n 1 | grep -c .)"
# Long format stays one row per session, with directory and transcript columns.
long=$(bash "$LSA" -a -t claude -l)
check "-l stays on one row" "1" "$(printf '%s\n' "$long" | wc -l | tr -d ' ')"
check "-l directory and transcript columns" "$proj aaaa $tmp/.claude/projects/x/aaaa1111-0000-0000-0000-000000000000.jsonl" "$(printf '%s\n' "$long" | awk '{print $5, $6, $7}')"
check "-l retains the title" 'fix the "login" bug please' "$(printf '%s\n' "$long" | sed 's/.*[.]jsonl *//')"
check "--long is equivalent" "$long" "$(bash "$LSA" -a -t claude --long)"
check "-l in the session directory has both paths" "$long" "$(cd "$proj" && bash "$LSA" -t claude -l)"
check "-l explicit directory has both paths" "$long" "$(bash "$LSA" "$proj" -t claude -l)"
check "-l limit counts sessions" "2" "$(bash "$LSA" -a -l -n 2 | wc -l | tr -d ' ')"
check "-L is removed" "2" "$(bash "$LSA" -L >/dev/null 2>&1; echo $?)"
check "--paths is removed" "2" "$(bash "$LSA" --paths >/dev/null 2>&1; echo $?)"
check "-l pi transcript" "$tmp/.pi/agent/sessions/x/2026-09-22T09-00-00-000Z_cccc3333-0000-0000-0000-000000000000.jsonl" "$(bash "$LSA" -a -t pi -l | awk '{print $7}')"
check "-l cline points to messages" "$tmp/.cline/data/sessions/1758500000000_ab1cd/1758500000000_ab1cd.messages.json" "$(bash "$LSA" -a -t cline -l | awk '{print $7}')"
check "path cline points to messages" "$tmp/.cline/data/sessions/1758500000000_ab1cd/1758500000000_ab1cd.messages.json" "$(bash "$LSA" path 1758)"
if [ $have_sqlite = 1 ]; then
  check "-l muse points to transcript" "$tmp/.local/share/muse/sessions/2026/09/22/hhhh8888-0000-0000-0000-000000000000/session.jsonl" "$(bash "$LSA" -a -t muse -l | awk '{print $7}')"
  check "path muse points to transcript" "$tmp/.local/share/muse/sessions/2026/09/22/hhhh8888-0000-0000-0000-000000000000/session.jsonl" "$(bash "$LSA" path hhhh)"
  check "database stores labelled shared" "3" "$(bash "$LSA" -a -l | grep -c '\[shared database\]')"
  check "path goose stays a plain database path" "$tmp/.local/share/goose/sessions/sessions.db" "$(bash "$LSA" path 2026)"
  check "openclaw directory is its session key" "main:main" "$(bash "$LSA" -a -t openclaw -l | awk '{print $5}')"
fi
check "path by prefix" "$tmp/.pi/agent/sessions/x/2026-09-22T09-00-00-000Z_cccc3333-0000-0000-0000-000000000000.jsonl" "$(bash "$LSA" path cccc)"
touch -t 203001010000 "$tmp/.pi/agent/sessions/x/2026-09-22T09-00-00-000Z_cccc3333-0000-0000-0000-000000000000.jsonl"
check "index 0 is the newest" "$tmp/.pi/agent/sessions/x/2026-09-22T09-00-00-000Z_cccc3333-0000-0000-0000-000000000000.jsonl" "$(bash "$LSA" path 0)"
check "listing indexes are contiguous" "$(seq 0 $(( $(printf '%s\n' "$all" | grep -c .) - 1 )) | tr '\n' ' ' | sed 's/ $//')" "$(bash "$LSA" -a | awk '{print $1}' | tr '\n' ' ' | sed 's/ $//')"
# Control the process list: real agents running the tests must not affect it.
mkdir -p "$tmp/process-bin"
export LSA_TEST_PROCESSES="$tmp/processes"
cat > "$tmp/process-bin/ps" <<'EOF'
#!/usr/bin/env bash
cat "$LSA_TEST_PROCESSES"
EOF
chmod +x "$tmp/process-bin/ps"
printf 'codex\n' > "$LSA_TEST_PROCESSES"
busy_listing() { PATH="$tmp/process-bin:$PATH" bash "$LSA" -a -t "$1"; }
touch "$tmp/.codex/sessions/2026/09/22/rollout-2026-09-22T10-00-00-bbbb2222-0000-0000-0000-000000000000.jsonl"
check "a fresh session with a live agent is busy, no colour marker" "▶" "$(busy_listing codex | awk '{print $3}')"
check "busy shows how long the turn has run, from the last prompt" "1" "$(busy_listing codex | awk '{print $4}' | grep -cE '^[0-9]+(s|m|h[0-9]+m|h)$')"
check "busy duration counts from that prompt, not the file" "1" "$(busy_listing codex | awk '{print $4}' | grep -cE '^[0-9]+h$')"
touch "$tmp/.qwen/projects/x/chats/eeee5555-0000-0000-0000-000000000000.jsonl"
check "a fresh session without a live agent is not" "ago" "$(busy_listing qwen | awk '{print $4}')"
: > "$LSA_TEST_PROCESSES"
check "gone once the agent exits" "ago" "$(busy_listing codex | awk '{print $4}')"
touch -t 202601010000 "$tmp/.codex/sessions/2026/09/22/rollout-2026-09-22T10-00-00-bbbb2222-0000-0000-0000-000000000000.jsonl" "$tmp/.qwen/projects/x/chats/eeee5555-0000-0000-0000-000000000000.jsonl"
check "index out of range fails" "1" "$(bash "$LSA" path 99 >/dev/null 2>&1; echo $?)"
check "unknown prefix fails" "1" "$(bash "$LSA" path zzzz >/dev/null 2>&1; echo $?)"
check "empty dir hint" "lsa: no sessions in $tmp (try lsa -a)" "$(cd "$tmp" && bash "$LSA" 2>&1)"

if command -v jq >/dev/null; then
  check "show claude" $'\n## user\nfix the "login" bug\nplease\n\n## assistant\nOn it.\n[tool: bash] {"command":"ls"}' "$(bash "$LSA" show aaaa)"
  check "show codex" $'\n## user\nadd subtitles\n\n## assistant\nDone.' "$(bash "$LSA" show bbbb)"
  check "show pi" $'\n## user\nhello pi\n\n## assistant\nhi' "$(bash "$LSA" show cccc)"
  check "show qwen" $'\n## user\nwrite a haiku about awk\n\n## assistant\nfields split at dawn' "$(bash "$LSA" show eeee)"
  check "show gemini" $'\n## user\nexplain this regex\n\n## gemini\nIt matches dates.' "$(bash "$LSA" show ffff)"
  check "show cline strips the wrapper" $'\n## user\nmake the sidebar collapsible\n\n## assistant\nSure.' "$(bash "$LSA" show 1758)"
  [ $have_sqlite = 1 ] && check "show muse" $'\n## user\nrename Widget to Panel\n\n## assistant\nRenamed in 12 files.' "$(bash "$LSA" show hhhh)"
  [ $have_sqlite = 1 ] && check "show openclaw" $'\n## user\nwhat is on my calendar\n\n## assistant\nNothing today.' "$(bash "$LSA" show iiii)"
else
  echo "skip show tests (no jq)"
fi

# Resume still invokes each native agent in its directory; stubs avoid launching
# real agents or making model requests. Check argv independently of the listing.
mkdir -p "$tmp/bin" "$tmp/elsewhere"
cat > "$tmp/bin/agent" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$PWD" "${0##*/}" "$@"
EOF
chmod +x "$tmp/bin/agent"
for agent in claude codex pi gemini qwen cline opencode goose muse openclaw; do
  cp "$tmp/bin/agent" "$tmp/bin/$agent"
done
# tmux is asked whether the session is already open, so stub it here too and
# keep the pane list empty until the attach tests below.
export LSA_TEST_PANES="$tmp/panes"
: > "$LSA_TEST_PANES"
cat > "$tmp/bin/tmux" <<'EOF'
#!/usr/bin/env bash
case $1 in
  list-panes) cat "$LSA_TEST_PANES" ;;
  display-message) printf 'work\n' ;;
  *) printf 'tmux %s\n' "$*" ;;
esac
EOF
chmod +x "$tmp/bin/tmux"
resume_output() { PATH="$tmp/bin:$PATH" bash "$LSA" resume "$1"; }
check "resume claude" "$proj"$'\nclaude\n--resume\naaaa1111-0000-0000-0000-000000000000' "$(resume_output aaaa)"
check "resume codex" "$proj"$'\ncodex\nresume\nbbbb2222-0000-0000-0000-000000000000' "$(resume_output bbbb)"
check "resume pi" "$tmp/elsewhere"$'\npi\n--session\n'"$tmp/.pi/agent/sessions/x/2026-09-22T09-00-00-000Z_cccc3333-0000-0000-0000-000000000000.jsonl" "$(resume_output cccc)"
check "resume gemini uses full id" "$proj"$'\ngemini\n--resume\nffff6666-0000-0000-0000-000000000000' "$(resume_output ffff)"
check "resume qwen" "$proj"$'\nqwen\n--resume\neeee5555-0000-0000-0000-000000000000' "$(resume_output eeee)"
check "resume cline" "$proj"$'\ncline\n-i\n--id\n1758500000000_ab1cd' "$(resume_output 1758)"
if [ $have_sqlite = 1 ]; then
  check "resume opencode" "$proj"$'\nopencode\n--session\nses_gggg7777aaaa' "$(resume_output ses_g)"
  check "resume goose" "$proj"$'\ngoose\nsession\n--resume\n--session-id\n20260922_7' "$(resume_output 2026)"
  check "resume muse" "$proj"$'\nmuse\nresume\nhhhh8888-0000-0000-0000-000000000000' "$(resume_output hhhh)"
  check "resume openclaw keeps current directory" "$PWD"$'\nopenclaw\ntui\n--session\nagent:main:main' "$(resume_output iiii)"
fi

# A session still open in a tmux pane is returned to, not started a second
# time. The pane is found by walking the agent process up to the pane it
# belongs to, so the id has to match, not just the agent or the directory.
attach_output() { PATH="$tmp/bin:$tmp/process-bin:$PATH" bash "$LSA" resume "$1"; }
attached=$'tmux select-window -t %0\ntmux select-pane -t %0\ntmux attach-session -t work'
printf '\t%%0\t900\n' > "$LSA_TEST_PANES"
printf '900 1 -zsh\n901 900 claude --resume aaaa1111-0000-0000-0000-000000000000\n' > "$LSA_TEST_PROCESSES"
check "resume attaches to the pane the session is open in" "$attached" "$(attach_output aaaa)"
check "inside tmux it switches the client instead of attaching" $'tmux select-window -t %0\ntmux select-pane -t %0\ntmux switch-client -t %0' "$(TMUX=/tmp/fake,1,0 attach_output aaaa)"
check "another session in the same pane tree is not mistaken for it" "$proj"$'\ncodex\nresume\nbbbb2222-0000-0000-0000-000000000000' "$(attach_output bbbb)"
printf '901 1 claude --resume aaaa1111-0000-0000-0000-000000000000\n' > "$LSA_TEST_PROCESSES"
check "an agent running outside tmux is resumed as before" "$proj"$'\nclaude\n--resume\naaaa1111-0000-0000-0000-000000000000' "$(attach_output aaaa)"

# A pane lsa stamped is trusted only while the agent it started is alive.
: > "$LSA_TEST_PROCESSES"
printf 'aaaa1111-0000-0000-0000-000000000000 %s\t%%0\t900\n' "$$" > "$LSA_TEST_PANES"
check "a stamped pane is attached to without asking ps" "$attached" "$(attach_output aaaa)"
printf 'aaaa1111-0000-0000-0000-000000000000 999999\t%%0\t900\n' > "$LSA_TEST_PANES"
check "a stamp left by an agent that has exited is ignored" "$proj"$'\nclaude\n--resume\naaaa1111-0000-0000-0000-000000000000' "$(attach_output aaaa)"

# Claude Code records the pane it runs in, so a session started by hand and
# never opened by lsa is found too.
mkdir -p "$tmp/.claude/sessions"
printf '{"pid":901,"sessionId":"aaaa1111-0000-0000-0000-000000000000","tmux":"work:@0.%%0","status":"idle"}\n' > "$tmp/.claude/sessions/901.json"
printf '\t%%0\t900\n' > "$LSA_TEST_PANES"
check "a session claude says is in a pane is attached to" "$attached" "$(attach_output aaaa)"
printf '{"pid":901,"sessionId":"aaaa1111-0000-0000-0000-000000000000","tmux":"work:@9.%%9","status":"idle"}\n' > "$tmp/.claude/sessions/901.json"
check "a pane claude names that no longer exists is not used" "$proj"$'\nclaude\n--resume\naaaa1111-0000-0000-0000-000000000000' "$(attach_output aaaa)"
rm -rf "$tmp/.claude/sessions"
: > "$LSA_TEST_PANES"
: > "$LSA_TEST_PROCESSES"

# Neither long-format path may be cut at spaces, quotes or terminal width.
spaced="$tmp/session files"
mkdir -p "$spaced/projects/x"
cat > "$spaced/projects/x/abcd0000-0000-0000-0000-000000000000.jsonl" <<EOF
{"type":"user","message":{"content":"a separate conversation"},"cwd":"$tmp/project with 'quotes'"}
EOF
touch -t 202601010000 "$spaced/projects/x/abcd0000-0000-0000-0000-000000000000.jsonl"
long=$(CLAUDE_CONFIG_DIR="$spaced" COLUMNS=40 bash "$LSA" -a -t claude -l)
check "-l preserves directory with spaces and quotes" "1" "$(printf '%s\n' "$long" | grep -Fc "$tmp/project with 'quotes'")"
check "-l preserves transcript path with spaces" "1" "$(printf '%s\n' "$long" | grep -Fc "$spaced/projects/x/abcd0000-0000-0000-0000-000000000000.jsonl")"

exit $fail
