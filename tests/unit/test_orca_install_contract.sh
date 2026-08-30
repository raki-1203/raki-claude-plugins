#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SETTINGS="/Users/raki-1203/.claude/settings.json"
SYNCED_ROOT="/Users/raki-1203/workspace/raki-claude-plugins"

PASS=0
FAIL=0
pass() { PASS=$((PASS + 1)); printf '  ✅ %s\n' "$1"; }
fail() { FAIL=$((FAIL + 1)); printf '  ❌ %s%s\n' "$1" "${2:+ — $2}"; }

assert_jq() {
  local name="$1" filter="$2"
  if jq -e "$filter" "$SETTINGS" >/dev/null 2>&1; then
    pass "$name"
  else
    fail "$name" "settings assertion failed"
  fi
}

assert_executable() {
  local name="$1" path="$2"
  if test -x "$path"; then
    pass "$name"
  else
    fail "$name" "executable file 없음: $path"
  fi
}

assert_same_file() {
  local name="$1" source="$2" synced="$3"
  if cmp -s "$source" "$synced"; then
    pass "$name"
  else
    fail "$name" "source와 synced copy 불일치"
  fi
}

printf '%s\n' '=== orca install contract tests ==='

if command -v jq >/dev/null 2>&1; then
  pass 'jq available'
else
  fail 'jq available'
fi

if jq empty "$SETTINGS" >/dev/null 2>&1; then
  pass 'settings JSON parse'
else
  fail 'settings JSON parse'
fi

assert_jq 'Orca Bash hook 등록' \
  '.hooks.PreToolUse | any(.[]; .matcher == "Bash" and any(.hooks[]?; .type == "command" and (.command | contains("orca-model-inherit.sh")) and .command == "${HOME}/workspace/raki-claude-plugins/scripts/orca-model-inherit.sh" and .timeout == 5))'

assert_jq 'Orca hook가 Python lint와 wildcard 사이' \
  '[.hooks.PreToolUse | to_entries[]] as $entries
   | ($entries[] | select(.value.matcher == "Bash" and any(.value.hooks[]?; .command == "~/.claude/hooks/python-lint.sh")) | .key) as $python
   | ($entries[] | select(.value.matcher == "Bash" and any(.value.hooks[]?; (.command? // "") | contains("orca-model-inherit.sh"))) | .key) as $orca
   | ($entries[] | select(.value.matcher == "*") | .key) as $wildcard
   | $python < $orca and $orca < $wildcard'

assert_jq '기존 Agent model hook 보존' \
  '.hooks.PreToolUse | any(.[]; .matcher == "Agent" and any(.hooks[]?; .command == "${HOME}/.claude/hooks/agent-model-inherit.sh"))'
assert_jq '기존 Python lint hook 보존' \
  '.hooks.PreToolUse | any(.[]; .matcher == "Bash" and any(.hooks[]?; .command == "~/.claude/hooks/python-lint.sh"))'
assert_jq '기존 wildcard Orca hook 보존' \
  '.hooks.PreToolUse | any(.[]; .matcher == "*" and any(.hooks[]?; (.command? // "") | contains(".orca/agent-hooks/claude-hook")))'
assert_jq '기존 UserPromptSubmit hook 보존' \
  '.hooks.UserPromptSubmit | any(.[]; any(.hooks[]?; (.command? // "") | contains("오늘 날짜: %Y-%m-%d (%a) %H:%M KST"))) and any(.[]; any(.hooks[]?; (.command? // "") | contains(".orca/agent-hooks/claude-hook")))'
assert_jq '기존 SessionStart hook 보존' \
  '.hooks.SessionStart | any(.[]; any(.hooks[]?; (.command? // "") | contains(".orca/agent-hooks/claude-hook")))'

for script in orca-model-inherit.sh orca-worktree-model-bridge.sh claude-orca-launch.sh; do
  assert_executable "source $script executable" "$ROOT/scripts/$script"
  assert_executable "synced $script executable" "$SYNCED_ROOT/scripts/$script"
  assert_same_file "$script synced path" "$ROOT/scripts/$script" "$SYNCED_ROOT/scripts/$script"
done

printf '\n=== %s passed, %s failed ===\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
