#!/usr/bin/env bash
# Build a fake HOME full of invented sessions for the demo recordings.
# Nothing here is real work: the prompts, projects and ids are made up so
# the gifs on the README show no one's actual sessions. The one exception
# is a Goose session, run for real against a local ollama model, so the
# demo can end with an honest `lsa resume`.
#
#   demo/fixtures.sh <dir>     -> populates <dir> as $HOME
set -eu
H=$1
mkdir -p "$H"
P="$H/code"   # the fake projects live here
mkdir -p "$P/wren" "$P/lantern" "$P/tidepool" "$P/quill"
mkdir -p "$H/.config/goose"
printf 'extensions: {}\n' > "$H/.config/goose/config.yaml"

# age in seconds -> touch -t stamp (portable to BSD and GNU touch)
stamp() { date -r $(( $(date +%s) - $1 )) +%Y%m%d%H%M.%S 2>/dev/null || date -d "@$(( $(date +%s) - $1 ))" +%Y%m%d%H%M.%S; }
age() { touch -t "$(stamp "$2")" "$1"; }
iso() { TZ=UTC date -r $(( $(date +%s) - $1 )) +%Y-%m-%dT%H:%M:%S.000Z 2>/dev/null || TZ=UTC date -u -d "@$(( $(date +%s) - $1 ))" +%Y-%m-%dT%H:%M:%S.000Z; }
ago_ms() { echo $(( ($(date +%s) - $1) * 1000 )); }

claude() { # id cwd age prompt
  local d="$H/.claude/projects/$(printf '%s' "$2" | sed 's/[^A-Za-z0-9]/-/g')"
  mkdir -p "$d"
  printf '{"type":"user","timestamp":"%s","message":{"role":"user","content":[{"type":"text","text":"%s"}]},"cwd":"%s","sessionId":"%s"}\n' "$(iso "$3")" "$4" "$2" "$1" > "$d/$1.jsonl"
  printf '{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"On it. Let me look at the code first."},{"type":"tool_use","name":"Read","input":{"file_path":"src/app.ts"}}]},"cwd":"%s"}\n' "$2" >> "$d/$1.jsonl"
  printf '{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Done: two files changed, tests pass."}]},"cwd":"%s"}\n' "$2" >> "$d/$1.jsonl"
  age "$d/$1.jsonl" "$3"
}
codex() { # id cwd age prompt
  local d="$H/.codex/sessions/2026/09/21" f
  mkdir -p "$d"; f="$d/rollout-2026-09-21T10-00-00-$1.jsonl"
  printf '{"type":"session_meta","payload":{"session_id":"%s","cwd":"%s","source":"cli","thread_source":"user"}}\n' "$1" "$2" > "$f"
  printf '{"type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"<environment_context>cwd=%s</environment_context>"}]}}\n' "$2" >> "$f"
  printf '{"type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"%s"}]}}\n' "$4" >> "$f"
  printf '{"type":"response_item","payload":{"type":"message","role":"assistant","content":[{"type":"output_text","text":"Sure. I will start with the failing test and work back from there."}]}}\n' >> "$f"
  age "$f" "$3"
}
pi() { # id cwd age prompt
  local d="$H/.pi/agent/sessions/--$(printf '%s' "$2" | sed 's|/|-|g')--" f
  mkdir -p "$d"; f="$d/2026-09-21T10-00-00-000Z_$1.jsonl"
  printf '{"type":"session","version":3,"id":"%s","cwd":"%s"}\n' "$1" "$2" > "$f"
  printf '{"type":"message","message":{"role":"user","content":[{"type":"text","text":"%s"}]}}\n' "$4" >> "$f"
  printf '{"type":"message","message":{"role":"assistant","content":[{"type":"text","text":"Happy to. Here is the plan."}]}}\n' >> "$f"
  age "$f" "$3"
}
qwen() { # id cwd age prompt
  local d="$H/.qwen/projects/$(printf '%s' "$2" | sed 's/[^A-Za-z0-9]/-/g')/chats"
  mkdir -p "$d"
  printf '{"uuid":"u1","sessionId":"%s","type":"user","cwd":"%s","message":{"role":"user","parts":[{"text":"%s"}]}}\n{"uuid":"u2","sessionId":"%s","type":"assistant","cwd":"%s","message":{"role":"model","parts":[{"text":"Starting with the tests."}]}}\n' "$1" "$2" "$4" "$1" "$2" > "$d/$1.jsonl"
  age "$d/$1.jsonl" "$3"
}
muse() { # id cwd age prompt
  mkdir -p "$H/.local/share/muse"
  sqlite3 "$H/.local/share/muse/session-index.db" "
    create table if not exists sessions (session_id text primary key, session_log_path text, workspace_root text, title text, first_user_prompt text, created_at_us integer, updated_at_us integer, status text);
    insert into sessions values ('$1', '', '$2', '$4', '$4', $(( ($(date +%s) - $3) * 1000000 )), $(( ($(date +%s) - $3) * 1000000 )), 'valid');"
}
opencode() { # id cwd age title
  mkdir -p "$H/.local/share/opencode"
  sqlite3 "$H/.local/share/opencode/opencode.db" "
    create table if not exists session (id text primary key, project_id text, parent_id text, directory text, title text, time_created integer, time_updated integer, time_archived integer);
    insert into session values ('$1', 'p1', null, '$2', '$4', $(ago_ms "$3"), $(ago_ms "$3"), null);"
}
openclaw() { # id key age prompt
  mkdir -p "$H/.openclaw/agents/main/agent"
  sqlite3 "$H/.openclaw/agents/main/agent/openclaw-agent.sqlite" "
    create table if not exists session_windows (session_id text primary key, session_key text, updated_at integer, display_name text, channel text);
    create table if not exists transcript_events (session_id text, seq integer, event_json text, created_at integer);
    insert into session_windows values ('$1', 'agent:main:$2', $(ago_ms "$3"), '', '');
    insert into transcript_events values ('$1', 1, '{\"type\":\"message\",\"message\":{\"role\":\"user\",\"content\":\"$4\"}}', 1);"
}
goose_real() { # cwd age prompt -> a real session, so the demo can resume it
  ( cd "$1" && HOME=$H GOOSE_PROVIDER=ollama GOOSE_MODEL=${DEMO_MODEL:-qwen2.5:3b} GOOSE_TELEMETRY_ENABLED=false \
      goose run --no-profile --system 'Write brief release notes in plain text. Do not call tools or edit files.' -t "$3" >/dev/null 2>&1 ) || { echo "demo: goose run failed (is ollama running with ${DEMO_MODEL:-qwen2.5:3b}?)" >&2; return 1; }
  sqlite3 "$H/.local/share/goose/sessions/sessions.db" "update sessions set updated_at = datetime('now', '-$2 seconds')"
}

claude   3e1f9c2a-7b44-4d0e-9a1c-0f5e6d7c8b9a "$P/wren"     120     "add a --dry-run flag to the deploy script"
codex    01a0c7d2-9e1b-7c3a-8f2d-4b6a5c7d8e9f "$P/wren"     900     "the flaky test in api/test_auth.py: find out why and fix it"
pi       01a0c7b8-1234-7abc-9def-0123456789ab "$P/lantern"  3600    "rename Widget to Panel across the codebase and update the docs"
goose_real                                    "$P/wren"     5400    "draft a release note for lsa: it lists coding agent sessions and can print or resume a conversation"
claude   9b2d4e6f-1a3c-4b5d-8e7f-6a5b4c3d2e1f "$P/lantern"  7200    "why does the build take 4 minutes? profile it"
muse     01a0c9aa-4b3c-7d2e-8f1a-2b3c4d5e6f7a "$P/tidepool" 9000    "add retries to the upload client"
opencode ses_4f7a2c9e1b3d                     "$P/tidepool" 10800   "Migrate the settings page to the new form component"
qwen     5e6f7a8b-9c0d-4e1f-8a2b-3c4d5e6f7a8b "$P/quill"    14400   "translate the error messages into Japanese"
openclaw 8a9b0c1d-2e3f-4a5b-8c6d-7e8f9a0b1c2d main          21600   "remind me to call the dentist tomorrow at 9"
codex    01a0b3e4-5f6a-7b8c-9d0e-1f2a3b4c5d6e "$P/quill"    86400   "set up GitHub Actions to run the tests on every PR"
claude   7c8d9e0f-1a2b-4c3d-8e4f-5a6b7c8d9e0f "$P/quill"    172800  "there is an off-by-one in the pagination, page 2 repeats the last item of page 1"
pi       01a0a1b2-c3d4-7e5f-8a6b-7c8d9e0f1a2b "$P/wren"     259200  "draft the README for this project"
claude   5d6e7f8a-9b0c-4d1e-8f2a-3b4c5d6e7f8a "$P/tidepool" 432000  "convert the callbacks in sync.js to async/await"
echo "fixtures in $H"
