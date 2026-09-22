#!/usr/bin/env bash
# Fixture tests: a fake home with one session per agent.
set -eu
cd "$(dirname "$0")"; ALS=$PWD/als
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
export HOME=$tmp NO_COLOR=1
unset CLAUDE_CONFIG_DIR CODEX_HOME PI_CODING_AGENT_DIR
proj=$tmp/proj; mkdir -p "$proj"

mkdir -p "$tmp/.claude/projects/x" "$tmp/.codex/sessions/2026/09/22" "$tmp/.pi/agent/sessions/x"
cat > "$tmp/.claude/projects/x/aaaa1111-0000-0000-0000-000000000000.jsonl" <<EOF
{"type":"queue-operation","sessionId":"aaaa1111-0000-0000-0000-000000000000"}
{"type":"user","message":{"role":"user","content":[{"type":"text","text":"fix the \"login\" bug\nplease"}]},"cwd":"$proj","sessionId":"aaaa1111-0000-0000-0000-000000000000"}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"On it."},{"type":"tool_use","name":"bash","input":{"command":"ls"}}]},"cwd":"$proj"}
EOF
cat > "$tmp/.claude/projects/x/agent-sidechain.jsonl" <<EOF
{"type":"user","message":{"role":"user","content":[{"type":"text","text":"SIDECHAIN"}]},"cwd":"$proj"}
EOF
cat > "$tmp/.codex/sessions/2026/09/22/rollout-2026-09-22T10-00-00-bbbb2222-0000-0000-0000-000000000000.jsonl" <<EOF
{"type":"session_meta","payload":{"session_id":"bbbb2222-0000-0000-0000-000000000000","cwd":"$proj"}}
{"type":"response_item","payload":{"type":"message","role":"developer","content":[{"type":"input_text","text":"<skills>"}]}}
{"type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"# AGENTS.md instructions\nstuff"}]}}
{"type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"<environment_context>x</environment_context>"}]}}
{"type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"add subtitles"}]}}
{"type":"response_item","payload":{"type":"message","role":"assistant","content":[{"type":"output_text","text":"Done."}]}}
EOF
cat > "$tmp/.pi/agent/sessions/x/2026-09-22T09-00-00-000Z_cccc3333-0000-0000-0000-000000000000.jsonl" <<EOF
{"type":"session","version":3,"id":"cccc3333-0000-0000-0000-000000000000","cwd":"$tmp/elsewhere"}
{"type":"message","message":{"role":"user","content":[{"type":"text","text":"hello pi"}]}}
{"type":"message","message":{"role":"assistant","content":[{"type":"text","text":"hi"}]}}
EOF

fail=0
check() { # name expected actual
  if [ "$2" = "$3" ]; then echo "ok   $1"; else echo "FAIL $1"; echo "  want: $2"; echo "  got:  $3"; fail=1; fi
}

out=$(cd "$proj" && bash "$ALS")
check "cwd listing has claude and codex only" "claude codex" "$(printf '%s\n' "$out" | awk '{print $1}' | sort | tr '\n' ' ' | sed 's/ $//')"
check "sidechain skipped" "" "$(printf '%s\n' "$out" | grep SIDECHAIN || true)"
check "claude title unescaped" 'fix the "login" bug please' "$(printf '%s\n' "$out" | grep claude | sed 's/.*aaaa1111  //')"
check "codex skips injected prompts" "add subtitles" "$(printf '%s\n' "$out" | grep codex | sed 's/.*bbbb2222  //')"

all=$(bash "$ALS" -a)
check "-a lists three" "3" "$(printf '%s\n' "$all" | grep -c .)"
check "-t pi filters" "pi" "$(bash "$ALS" -a -t pi | awk '{print $1}')"
check "-n 1 limits" "1" "$(bash "$ALS" -a -n 1 | grep -c .)"
check "-l prints resume" "$ codex resume bbbb2222-0000-0000-0000-000000000000" "$(bash "$ALS" -a -t codex -l | sed -n 2p | sed 's/^ *//')"
check "-L prints path" "$tmp/.claude/projects/x/aaaa1111-0000-0000-0000-000000000000.jsonl" "$(bash "$ALS" -a -t claude -L | sed -n 2p | sed 's/^ *//')"
check "-l for pi uses the file" "$ pi --session $tmp/.pi/agent/sessions/x/2026-09-22T09-00-00-000Z_cccc3333-0000-0000-0000-000000000000.jsonl" "$(bash "$ALS" -a -t pi -l | sed -n 2p | sed 's/^ *//')"
check "fg is a subcommand" "0" "$(bash "$ALS" fg 2>/dev/null; [ $? = 2 ] && echo 0)"
check "path by prefix" "$tmp/.pi/agent/sessions/x/2026-09-22T09-00-00-000Z_cccc3333-0000-0000-0000-000000000000.jsonl" "$(bash "$ALS" path cccc)"
check "unknown prefix fails" "1" "$(bash "$ALS" path zzzz >/dev/null 2>&1; echo $?)"
check "empty dir hint" "als: no sessions in $tmp (try als -a)" "$(cd "$tmp" && bash "$ALS" 2>&1)"

if command -v jq >/dev/null; then
  check "show claude" $'\n## user\nfix the "login" bug\nplease\n\n## assistant\nOn it.\n[tool: bash] {"command":"ls"}' "$(bash "$ALS" show aaaa)"
  check "show codex" $'\n## user\nadd subtitles\n\n## assistant\nDone.' "$(bash "$ALS" show bbbb)"
  check "show pi" $'\n## user\nhello pi\n\n## assistant\nhi' "$(bash "$ALS" show cccc)"
else
  echo "skip show tests (no jq)"
fi

exit $fail
