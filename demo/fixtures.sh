#!/usr/bin/env bash
# Build a fake HOME full of invented sessions for the demo recordings.
# Nothing here is real: the prompts, projects and ids are made up so the
# gifs on the README show no one's actual work.
#
#   demo/fixtures.sh <dir>     -> populates <dir> as $HOME
set -eu
H=$1
mkdir -p "$H"
P="$H/code"   # the fake projects live here
mkdir -p "$P/wren" "$P/lantern" "$P/tidepool" "$P/quill"

# age in seconds -> touch -t stamp (portable to BSD and GNU touch)
stamp() { date -r $(( $(date +%s) - $1 )) +%Y%m%d%H%M.%S 2>/dev/null || date -d "@$(( $(date +%s) - $1 ))" +%Y%m%d%H%M.%S; }
age() { touch -t "$(stamp "$2")" "$1"; }

claude() { # id cwd age prompt
  local d="$H/.claude/projects/$(printf '%s' "$2" | sed 's/[^A-Za-z0-9]/-/g')"
  mkdir -p "$d"
  printf '{"type":"user","message":{"role":"user","content":[{"type":"text","text":"%s"}]},"cwd":"%s","sessionId":"%s"}\n' "$4" "$2" "$1" > "$d/$1.jsonl"
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
opencode() { # id cwd age title
  local d="$H/.local/share/opencode/storage/session/p1"
  mkdir -p "$d"
  printf '{"id":"%s","projectID":"p1","directory":"%s","title":"%s","time":{"created":1758500000000}}\n' "$1" "$2" "$4" > "$d/$1.json"
  age "$d/$1.json" "$3"
}
goose() { # name cwd age prompt
  local d="$H/.local/share/goose/sessions"
  mkdir -p "$d"
  printf '{"working_dir":"%s","description":"%s"}\n{"role":"user","content":[{"type":"text","text":"%s"}]}\n{"role":"assistant","content":[{"type":"text","text":"Honk. Starting now."}]}\n' "$2" "$4" "$4" > "$d/$1.jsonl"
  age "$d/$1.jsonl" "$3"
}
gemini() { # id age prompt
  local d="$H/.gemini/tmp/7f3a/chats"
  mkdir -p "$d"
  printf '{\n  "sessionId": "%s",\n  "messages": [\n    {\n      "type": "user",\n      "content": "%s"\n    },\n    {\n      "type": "gemini",\n      "content": "Here is a first pass."\n    }\n  ]\n}\n' "$1" "$3" > "$d/session-2026-09-21T10-00-$1.json"
  age "$d/session-2026-09-21T10-00-$1.json" "$2"
}

claude   3e1f9c2a-7b44-4d0e-9a1c-0f5e6d7c8b9a "$P/wren"     120     "add a --dry-run flag to the deploy script"
codex    01a0c7d2-9e1b-7c3a-8f2d-4b6a5c7d8e9f "$P/wren"     900     "the flaky test in api/test_auth.py: find out why and fix it"
pi       01a0c7b8-1234-7abc-9def-0123456789ab "$P/lantern"  3600    "rename Widget to Panel across the codebase and update the docs"
claude   9b2d4e6f-1a3c-4b5d-8e7f-6a5b4c3d2e1f "$P/lantern"  7200    "why does the build take 4 minutes? profile it"
opencode ses_4f7a2c9e                         "$P/tidepool" 10800   "Migrate the settings page to the new form component"
goose    20260921_harbor                      "$P/tidepool" 14400   "write release notes from the last 20 commits"
gemini   c4d5e6f7                                           21600   "explain this regex and write three test cases for it"
codex    01a0b3e4-5f6a-7b8c-9d0e-1f2a3b4c5d6e "$P/quill"    86400   "set up GitHub Actions to run the tests on every PR"
claude   7c8d9e0f-1a2b-4c3d-8e4f-5a6b7c8d9e0f "$P/quill"    172800  "there is an off-by-one in the pagination, page 2 repeats the last item of page 1"
pi       01a0a1b2-c3d4-7e5f-8a6b-7c8d9e0f1a2b "$P/wren"     259200  "draft the README for this project"
claude   5d6e7f8a-9b0c-4d1e-8f2a-3b4c5d6e7f8a "$P/tidepool" 432000  "convert the callbacks in sync.js to async/await"
echo "fixtures in $H"
