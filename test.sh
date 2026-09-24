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
{"type":"user","uuid":"u1","parentUuid":null,"timestamp":"2026-09-22T10:00:00.000Z","message":{"role":"user","content":[{"type":"text","text":"fix the \"login\" bug\nplease"}]},"cwd":"$proj","sessionId":"aaaa1111-0000-0000-0000-000000000000"}
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
  check "show goose retains turn context" $'\n## user\nhonk at the tests\n\n## user\n<turn-context>now</turn-context>\n\n## assistant\nHONK' "$(bash "$LSA" show 2026)"
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
  check "show codex keeps recorded instructions" $'\n## session context\n'"{\"cwd\":\"$proj\"}"$'\n\n## developer\n<skills>\n\n## user\n# AGENTS.md instructions\nstuff\n\n## user\n<environment_context>x</environment_context>\n\n## user\nadd subtitles\n\n## assistant\nDone.' "$(bash "$LSA" show bbbb)"
  check "show pi keeps project context" $'\n## session context\n'"{\"cwd\":\"$tmp/elsewhere\"}"$'\n\n## user\nhello pi\n\n## assistant\nhi' "$(bash "$LSA" show cccc)"
  check "show qwen" $'\n## user\nwrite a haiku about awk\n\n## assistant\nfields split at dawn' "$(bash "$LSA" show eeee)"
  check "show gemini" $'\n## user\nexplain this regex\n\n## gemini\nIt matches dates.' "$(bash "$LSA" show ffff)"
  check "show cline strips the wrapper" $'\n## user\nmake the sidebar collapsible\n\n## assistant\nSure.' "$(bash "$LSA" show 1758)"
  [ $have_sqlite = 1 ] && check "show muse" $'\n## user\nrename Widget to Panel\n\n## assistant\nRenamed in 12 files.' "$(bash "$LSA" show hhhh)"
  [ $have_sqlite = 1 ] && check "show openclaw" $'\n## user\nwhat is on my calendar\n\n## assistant\nNothing today.' "$(bash "$LSA" show iiii)"
else
  echo "skip show tests (no jq)"
fi

# Regression fixtures for information that text-only readers used to discard.
# Check the saved evidence, including multiline output and non-text markers.
contains() { case $2 in *"$1"*) printf yes;; *) printf no;; esac; }
if command -v jq >/dev/null; then
  cat >> "$tmp/.claude/projects/x/aaaa1111-0000-0000-0000-000000000000.jsonl" <<'JSON'
{"type":"attachment","attachment":{"type":"file","path":"src/app.ts"},"rendered":[{"content":"Read src/app.ts:\nconst port = 8123;"}]}
{"type":"attachment","attachment":{"type":"prompt_snapshot","systemPrompt":["Project rule: run the unit tests."]}}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"tool-1","name":"Read","input":{"file_path":"src/app.ts"}}]}}
{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"tool-1","is_error":true,"content":[{"type":"text","text":"line one\nline two\tindent"}]},{"type":"image","source":{"type":"base64","media_type":"image/png","data":"DO_NOT_DUMP_BINARY"}}]}}
{"type":"system","subtype":"compact_boundary","compactMetadata":{"trigger":"auto"}}
{"type":"summary","summary":"Pending: change port 8123 to 9000."}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"thinking","thinking":"","signature":"sig"},{"type":"text","text":"after hidden thinking"}]}}
JSON
  shown=$(bash "$LSA" show aaaa)
  check "show renders attachment content" yes "$(contains $'Read src/app.ts:\nconst port = 8123;' "$shown")"
  check "show keeps recorded system prompt" yes "$(contains 'Project rule: run the unit tests.' "$shown")"
  check "show pairs tool results and preserves whitespace" yes "$(contains $'[result id=tool-1 error]\nline one\nline two\tindent' "$shown")"
  check "show marks images without dumping base64" yes "$(contains '[binary data omitted]' "$shown")"
  check "show does not dump binary" no "$(contains DO_NOT_DUMP_BINARY "$shown")"
  check "show includes compaction summaries" yes "$(contains 'Pending: change port 8123 to 9000.' "$shown")"
  check "show skips thinking with no recorded text" no "$(contains $'[thinking]\nafter hidden thinking' "$shown")"
  check "show keeps the text after it" yes "$(contains 'after hidden thinking' "$shown")"

  cat >> "$tmp/.codex/sessions/2026/09/22/rollout-2026-09-22T10-00-00-bbbb2222-0000-0000-0000-000000000000.jsonl" <<'JSON'
{"type":"response_item","payload":{"type":"function_call","name":"exec_command","call_id":"call-1","arguments":"{\"cmd\":\"git diff\"}"}}
{"type":"response_item","payload":{"type":"function_call_output","call_id":"call-1","output":"diff --git a/app b/app\n-old\n+new"}}
{"type":"response_item","payload":{"type":"custom_tool_call","name":"apply_patch","call_id":"call-2","input":"*** Begin Patch\n*** End Patch"}}
{"type":"response_item","payload":{"type":"custom_tool_call_output","call_id":"call-2","output":[{"type":"text","text":"Patch applied."},{"type":"input_image","image_url":"data:image/png;base64,DO_NOT_DUMP_BINARY"}]}}
{"type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"<request>Keep XML prompts too.</request>"}]}}
{"type":"world_state","payload":{"full":true,"state":{"agents_md":"Use pnpm here."}}}
{"type":"turn_context","payload":{"cwd":"/project/subdir","model":"test-model"}}
{"type":"compacted","payload":{"message":"Tests still failing.","replacement_history":[{"type":"message","role":"user","content":[{"type":"input_text","text":"Keep the migration backwards compatible."}]},{"type":"compaction","encrypted_content":"DO_NOT_DUMP_ENCRYPTED"}],"retained_context":{"verified_answers":["API contract confirmed."]}}}
{"type":"event_msg","payload":{"type":"turn_aborted","reason":"interrupted"}}
JSON
  shown=$(bash "$LSA" show bbbb)
  check "show codex includes function calls" yes "$(contains '[tool: exec_command id=call-1]' "$shown")"
  check "show codex preserves diffs" yes "$(contains $'[result id=call-1]\ndiff --git a/app b/app\n-old\n+new' "$shown")"
  check "show codex includes custom tools" yes "$(contains $'[tool: apply_patch id=call-2]\n*** Begin Patch' "$shown")"
  check "show codex includes structured tool output" yes "$(contains 'Patch applied.' "$shown")"
  check "show keeps XML user prompts" yes "$(contains '<request>Keep XML prompts too.</request>' "$shown")"
  check "show keeps world state" yes "$(contains 'Use pnpm here.' "$shown")"
  check "show keeps per-turn project" yes "$(contains '/project/subdir' "$shown")"
  check "show keeps compaction replacement text" yes "$(contains 'Keep the migration backwards compatible.' "$shown")"
  check "show keeps retained context" yes "$(contains 'API contract confirmed.' "$shown")"
  check "show marks interruption" yes "$(contains '## turn_aborted' "$shown")"
  check "show omits encrypted state" no "$(contains DO_NOT_DUMP_ENCRYPTED "$shown")"
  check "show omits embedded image data" no "$(contains DO_NOT_DUMP_BINARY "$shown")"

  cat >> "$tmp/.pi/agent/sessions/x/2026-09-22T09-00-00-000Z_cccc3333-0000-0000-0000-000000000000.jsonl" <<'JSON'
{"type":"message","message":{"role":"assistant","content":[{"type":"toolCall","id":"pi-1","name":"read","arguments":{"path":"app.ts"}}]}}
{"type":"message","message":{"role":"toolResult","toolCallId":"pi-1","toolName":"read","isError":false,"content":[{"type":"text","text":"pi line one\npi line two"}]}}
{"type":"compaction","summary":"Remember the database migration."}
{"type":"branch_summary","summary":"The previous branch ruled out a cache bug."}
{"type":"custom_message","customType":"project-rule","display":false,"content":"Use pnpm, not npm."}
JSON
  shown=$(bash "$LSA" show cccc)
  check "show pi pairs result with tool" yes "$(contains $'[result: read id=pi-1]\npi line one\npi line two' "$shown")"
  check "show pi keeps compaction" yes "$(contains 'Remember the database migration.' "$shown")"
  check "show pi keeps branch summaries" yes "$(contains 'ruled out a cache bug' "$shown")"
  check "show pi keeps invisible context messages" yes "$(contains 'Use pnpm, not npm.' "$shown")"

  cat >> "$tmp/.qwen/projects/x/chats/eeee5555-0000-0000-0000-000000000000.jsonl" <<'JSON'
{"type":"assistant","message":{"parts":[{"functionCall":{"name":"read_file","args":{"path":"config.ts"}}},{"functionResponse":{"name":"read_file","response":{"text":"qwen file content"}}}]}}
JSON
  check "show qwen keeps tool responses" yes "$(contains 'qwen file content' "$(bash "$LSA" show eeee)")"
  cat >> "$tmp/.gemini/tmp/quiet-otter/chats/session-2026-09-22T08-00-00-ffff6666.jsonl" <<'JSON'
{"type":"gemini","content":"Checking.","toolCalls":[{"id":"g1","name":"read_file","args":{"path":"config.ts"},"result":[{"functionResponse":{"name":"read_file","response":{"output":"gemini file content"}}}]}]}
JSON
  check "show gemini keeps tool results" yes "$(contains 'gemini file content' "$(bash "$LSA" show ffff)")"
  if [ $have_sqlite = 1 ]; then
    sqlite3 "$tmp/.local/share/goose/sessions/sessions.db" "insert into messages values (4,'m4','20260922_7','assistant','[{\"type\":\"text\",\"text\":\"first block\"},{\"type\":\"text\",\"text\":\"second block\\nwith a newline\\tand tab\"},{\"type\":\"toolRequest\",\"toolCall\":{\"name\":\"read\",\"arguments\":{\"path\":\"goose.ts\"}}}]',4);"
    shown=$(bash "$LSA" show 2026)
    check "show goose keeps all blocks and whitespace" yes "$(contains $'first block\nsecond block\nwith a newline\tand tab' "$shown")"
    check "show goose keeps tool request" yes "$(contains goose.ts "$shown")"
    sqlite3 "$tmp/.local/share/opencode/opencode.db" "insert into part values ('prt_3','msg_2','ses_gggg7777aaaa',3,3,'{\"type\":\"tool\",\"tool\":\"bash\",\"callID\":\"oc-1\",\"state\":{\"status\":\"completed\",\"input\":{\"command\":\"git diff\"},\"output\":\"OpenCode result\"}}');"
    check "show opencode keeps tool state and output" yes "$(contains 'OpenCode result' "$(bash "$LSA" show ses_g)")"
  fi
  check "show unknown prefix fails" 1 "$(bash "$LSA" show zzzz >/dev/null 2>&1; echo $?)"
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
  check "resume goose" "$proj"$'\ngoose\nsession\n--resume\n--session-id\n20260922_7\n--history' "$(resume_output 2026)"
  check "resume muse" "$proj"$'\nmuse\nresume\nhhhh8888-0000-0000-0000-000000000000' "$(resume_output hhhh)"
  check "resume openclaw keeps current directory" "$PWD"$'\nopenclaw\ntui\n--session\nagent:main:main' "$(resume_output iiii)"
fi

# A session still open in a tmux pane is returned to, not started a second
# time. The pane is found by walking the agent process up to the pane it
# belongs to, so the id has to match, not just the agent or the directory.
attach_output() { PATH="$tmp/bin:$tmp/process-bin:$PATH" bash "$LSA" resume "$1"; }
attached=$'tmux select-window -t %0\ntmux select-pane -t %0\ntmux attach-session -t work'
resumed_claude="$proj"$'\nclaude\n--resume\naaaa1111-0000-0000-0000-000000000000'
# lsof stands in for the one on the codex lock: the fixture puts the pid in it
cat > "$tmp/bin/lsof" <<'EOF'
#!/usr/bin/env bash
cat "${*: -1}" 2>/dev/null || :
EOF
chmod +x "$tmp/bin/lsof"

# Every resume command carries the id, so one rule covers all ten agents.
printf '\t%%0\t900\n' > "$LSA_TEST_PANES"
printf '900 1 -zsh\n901 900 claude --resume aaaa1111-0000-0000-0000-000000000000\n' > "$LSA_TEST_PROCESSES"
check "resume attaches to the pane the session is open in" "$attached" "$(attach_output aaaa)"
check "inside tmux it switches the client instead of attaching" $'tmux select-window -t %0\ntmux select-pane -t %0\ntmux switch-client -t %0' "$(TMUX=/tmp/fake,1,0 attach_output aaaa)"
check "another session in the same pane tree is not mistaken for it" "$proj"$'\ncodex\nresume\nbbbb2222-0000-0000-0000-000000000000' "$(attach_output bbbb)"
printf '900 1 -zsh\n901 900 pi --session /x/2026_cccc3333-0000-0000-0000-000000000000.jsonl\n' > "$LSA_TEST_PROCESSES"
check "an id inside a session path counts too" $'tmux select-window -t %0\ntmux select-pane -t %0\ntmux attach-session -t work' "$(attach_output cccc)"
printf '901 1 claude --resume aaaa1111-0000-0000-0000-000000000000\n' > "$LSA_TEST_PROCESSES"
check "an agent running outside tmux is resumed as before" "$resumed_claude" "$(attach_output aaaa)"

# Claude Code records the pane it runs in, so a session started by hand is
# found without its id ever appearing on a command line.
: > "$LSA_TEST_PROCESSES"
mkdir -p "$tmp/.claude/sessions"
claude_record() { printf '{"pid":901,"sessionId":"aaaa1111-0000-0000-0000-000000000000","tmux":"work:@0.%s","status":"idle"}\n' "$1" > "$tmp/.claude/sessions/901.json"; }
claude_record '%0'
check "a session claude says is in a pane is attached to" "$attached" "$(attach_output aaaa)"
claude_record '%9'
check "a pane claude names that no longer exists is not used" "$resumed_claude" "$(attach_output aaaa)"
rm -rf "$tmp/.claude/sessions"

# Codex holds its session lock open, so its hand-started sessions are found.
mkdir -p "$tmp/.codex/thread-writer-locks"
printf '901\n' > "$tmp/.codex/thread-writer-locks/bbbb2222-0000-0000-0000-000000000000.lock"
printf '900 1 -zsh\n901 900 codex\n' > "$LSA_TEST_PROCESSES"
check "a session codex holds the lock for is attached to" "$attached" "$(attach_output bbbb)"
rm -rf "$tmp/.codex/thread-writer-locks"
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

# Handoff writes each agent's own session format, then runs its resume command.
# Stubs stand in for the agents; each destination gets a fresh home.
if command -v jq >/dev/null; then
  mkdir -p "$tmp/handoff-bin"
  cat > "$tmp/handoff-bin/agent" <<'SH'
#!/usr/bin/env bash
set -eu
name=${0##*/}
case "$name ${1:-} ${2:-}" in
  "codex --version"*) echo "codex-cli 0.156.1"; exit;;
  "opencode --version"*) echo "1.18.30"; exit;;
  "opencode import"*) cp "$2" "$HOME/opencode-import.json"; exit;;
  "goose session import"*) cp "$3" "$HOME/goose-import.jsonl"; printf 'Session imported:\n20260924_1 - handoff\n'; exit;;
esac
printf '%s\n' "$PWD" "$name" "argc=$#"
printf 'arg=%s\n' "$@"
if [ "${LSA_TEST_READ_STDIN:-}" = 1 ]; then
  IFS= read -r followup
  printf 'stdin=%s\n' "$followup"
fi
SH
  chmod +x "$tmp/handoff-bin/agent"
  targets='claude codex pi gemini qwen cline opencode goose muse openclaw'
  for agent in $targets; do cp "$tmp/handoff-bin/agent" "$tmp/handoff-bin/$agent"; done
  handoff_home() { # target -> a fresh home, with the settings its writer reads
    local h="$tmp/handoff-$1"
    rm -rf "$h"; mkdir -p "$h/.cline/data/settings"
    printf '{"lastUsedProvider":"anthropic","providers":{"anthropic":{"settings":{"model":"claude-sonnet-5"}}}}\n' > "$h/.cline/data/settings/providers.json"
    printf '%s' "$h"
  }
  handoff_output() { # target [lsa args...]
    local target=$1; shift
    HOME=$HANDOFF_HOME CLAUDE_CONFIG_DIR="$tmp/.claude" XDG_CACHE_HOME="$tmp/cache with spaces" PATH="$tmp/handoff-bin:$PATH" \
      bash "$LSA" handoff "$@" 2>"$tmp/handoff-error"
  }
  arg() { sed -n "s/^arg=//p" | sed -n "${1}p"; }
  native_text() { # target handed -> the message texts in the session it wrote
    local h=$HANDOFF_HOME
    case $1 in
      claude) jq -r '.message.content | if type == "string" then . else .[].text end' "$tmp"/.claude/projects/*/"$(arg 2 <<< "$2")".jsonl;;
      codex) jq -r 'select(.type == "response_item") | .payload.content[].text' "$h"/.codex/sessions/*/*/*/rollout-*-"$(arg 2 <<< "$2")".jsonl;;
      pi) jq -r 'select(.type == "message") | .message.content[].text' "$(arg 2 <<< "$2")";;
      qwen) jq -r '.message.parts[].text' "$h"/.qwen/projects/*/chats/"$(arg 2 <<< "$2")".jsonl;;
      gemini) jq -r 'select(.type) | .content[].text' "$h"/.gemini/tmp/*/chats/session-*.jsonl;;
      cline) jq -r '.messages[].content[].text' "$h"/.cline/data/sessions/"$(arg 3 <<< "$2")"/*.messages.json;;
      opencode) jq -r '.messages[].parts[].text' "$h/opencode-import.json";;
      goose) jq -r '.message.content | if type == "string" then . else .[].text end' "$h/goose-import.jsonl";;
      muse) jq -r '.payload.event | .prompt // .text // empty' "$h"/.local/share/muse/sessions/*/*/*/"$(arg 2 <<< "$2")"/session.jsonl;;
    esac
  }
  resume_args() {
    case $1 in
      claude|qwen|gemini) echo "--resume";; codex) echo "resume";; pi) echo "--session";; cline) echo "-i";;
      opencode) echo "--session";; goose) echo "session";; muse) echo "resume";;
    esac
  }
  for target in $targets; do
    HANDOFF_HOME=$(handoff_home "$target")
    handed=$(handoff_output "$target" aaaa "$target")
    check "handoff to $target starts in source project" yes "$(contains "$proj"$'\n'"$target" "$handed")"
    if [ "$target" = openclaw ]; then
      # no openclaw database here, so it gets the conversation as its first message
      check "handoff to openclaw falls back to a first message" yes "$(contains $'line one\nline two\tindent' "$handed")"
      check "handoff says when it falls back" yes "$(contains 'sending the conversation as the first message' "$(cat "$tmp/handoff-error")")"
      continue
    fi
    check "handoff to $target resumes the new session" "$(resume_args "$target")" "$(arg 1 <<< "$handed")"
    text=$(native_text "$target" "$handed")
    check "handoff to $target writes its own session with tool evidence" yes "$(contains $'line one\nline two\tindent' "$text")"
    check "handoff to $target keeps the first prompt" yes "$(contains 'fix the "login" bug' "$text")"
    check "handoff to $target names the source session" yes "$(contains 'claude session aaaa1111-0000-0000-0000-000000000000' "$text")"
  done
  HANDOFF_HOME=$(handoff_home codex)
  text=$(native_text codex "$(handoff_output codex aaaa codex)")
  check "handoff keeps file context" yes "$(contains 'const port = 8123;' "$text")"
  check "handoff leaves the source agent's system prompt behind" no "$(contains 'Project rule: run the unit tests.' "$text")"
  if [ $have_sqlite = 1 ]; then
    HANDOFF_HOME=$(handoff_home codex)
    text=$(native_text codex "$(XDG_DATA_HOME="$tmp/.local/share" handoff_output codex 2026 codex)")
    check "handoff leaves injected turn context behind" no "$(contains 'turn-context' "$text")"
    check "handoff keeps the goose conversation" yes "$(contains 'honk at the tests' "$text")"
  fi
  HANDOFF_HOME=$(handoff_home claude)
  check "handoff to claude alternates user and assistant" yes \
    "$(jq -rs '[.[].type] | . as $t | all(range(1; length); $t[.] != $t[. - 1])' "$tmp"/.claude/projects/*/"$(arg 2 <<< "$(handoff_output claude aaaa claude)")".jsonl | sed 's/true/yes/')"
  HANDOFF_HOME=$(handoff_home gemini)
  handoff_output gemini aaaa gemini >/dev/null
  gemini_file=$(ls "$HANDOFF_HOME"/.gemini/tmp/*/chats/session-*.jsonl)
  check "gemini session file avoids the id suffix gemini's cleanup deletes" no \
    "$(contains "-$(head -n 1 "$gemini_file" | jq -r '.sessionId[0:8]').jsonl" "$gemini_file")"
  find "$tmp/.claude/projects" -name '*.jsonl' ! -name 'aaaa1111-*' ! -name 'agent-*' -newer "$tmp/.claude/projects/x/agent-sidechain.jsonl" -delete

  HANDOFF_HOME=$(handoff_home pi)
  mkdir -p "$HANDOFF_HOME/.pi/agent/sessions/x"
  printf '{"type":"session","version":99}\n' > "$HANDOFF_HOME/.pi/agent/sessions/x/newer.jsonl"
  handed=$(handoff_output pi aaaa pi)
  check "handoff falls back when an agent's format has changed" yes "$(contains 'unrecognised Pi session format' "$(cat "$tmp/handoff-error")")"
  check "the fallback sends the conversation to pi" yes "$(contains 'arg=@' "$handed")"

  HANDOFF_HOME=$(handoff_home codex)
  check "handoff forwards destination options" yes "$(contains $'arg=--model\narg=test-model' "$(handoff_output codex aaaa codex --model test-model)")"
  for target in claude codex pi; do
    HANDOFF_HOME=$(handoff_home "$target")
    check "handoff to $target preserves stdin" yes "$(contains 'stdin=follow-up' "$(printf 'follow-up\n' | LSA_TEST_READ_STDIN=1 handoff_output "$target" aaaa "$target")")"
  done
  find "$tmp/.claude/projects" -name '*.jsonl' ! -name 'aaaa1111-*' ! -name 'agent-*' -newer "$tmp/.claude/projects/x/agent-sidechain.jsonl" -delete
  HANDOFF_HOME=$(handoff_home codex)
  touch "$tmp/.claude/projects/x/aaaa1111-0000-0000-0000-000000000000.jsonl"
  check "handoff resolves index before launching destination" yes "$(contains 'claude session aaaa1111' "$(native_text codex "$(handoff_output codex 0 codex)")")"
  check "handoff rejects unknown session" 1 "$(handoff_output codex zzzz codex >/dev/null; echo $?)"
  check "handoff rejects unsupported destination" 2 "$(handoff_output codex aaaa unknown >/dev/null; echo $?)"
  check "handoff requires destination" 2 "$(bash "$LSA" handoff aaaa >/dev/null 2>&1; echo $?)"

  # full transcripts must survive OS argv limits
  awk 'BEGIN { printf "{\"type\":\"assistant\",\"message\":{\"role\":\"assistant\",\"content\":\""; for (i=0;i<300000;i++) printf "x"; print "LARGE_TRANSCRIPT_END\"}}" }' >> "$tmp/.claude/projects/x/aaaa1111-0000-0000-0000-000000000000.jsonl"
  for target in codex pi; do
    HANDOFF_HOME=$(handoff_home "$target")
    check "handoff to $target handles transcripts above argv limits" yes "$(contains LARGE_TRANSCRIPT_END "$(native_text "$target" "$(handoff_output "$target" aaaa "$target")")")"
  done

  printf '{broken json\n' >> "$tmp/.claude/projects/x/aaaa1111-0000-0000-0000-000000000000.jsonl"
  HANDOFF_HOME=$(handoff_home codex)
  check "handoff never launches with an unreadable transcript" 1 "$(handoff_output codex aaaa codex >"$tmp/failed-handoff"; echo $?)"
  check "failed handoff produced no agent output" '' "$(cat "$tmp/failed-handoff")"
  check "failed handoff wrote no session" '' "$(ls "$HANDOFF_HOME/.codex" 2>/dev/null)"
fi

exit $fail
