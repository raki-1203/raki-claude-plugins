#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HOOK="$ROOT/scripts/orca-model-inherit.sh"
TMPDIR_ROOT=$(mktemp -d)
trap 'rm -rf "$TMPDIR_ROOT"' EXIT

PASS=0
FAIL=0
pass() { PASS=$((PASS + 1)); printf '  ✅ %s\n' "$1"; }
fail() { FAIL=$((FAIL + 1)); printf '  ❌ %s%s\n' "$1" "${2:+ — $2}"; }

mkdir -p "$TMPDIR_ROOT/bin-up" "$TMPDIR_ROOT/bin-no-orca"
printf '#!/bin/bash\nexit 0\n' > "$TMPDIR_ROOT/bin-up/orca"
chmod +x "$TMPDIR_ROOT/bin-up/orca"

PATH_WITH_ORCA="$TMPDIR_ROOT/bin-up:/usr/bin:/bin"
PATH_WITHOUT_ORCA="$TMPDIR_ROOT/bin-no-orca:/usr/bin:/bin"

make_payload() {
  jq -cn --arg command "$1" --arg transcript "$2" --arg tool "$3" \
    '{tool_name:$tool,tool_input:{command:$command,description:"start worker",custom_field:{keep:true}},transcript_path:$transcript}'
}

run_hook() {
  local input="$1" path="$2" hook="${3:-$HOOK}" out
  out=$(printf '%s' "$input" | PATH="$path" bash "$hook") || return 1
  printf '%s' "$out"
}

assert_rewritten() {
  local name="$1" input="$2" path="$3" model="$4" needle="${5-}" out
  if [ ! -f "$HOOK" ]; then
    fail "$name" "hook script 없음"
    return
  fi
  if ! out=$(run_hook "$input" "$path"); then
    fail "$name" "hook가 non-zero로 종료"
    return
  fi
  if printf '%s' "$out" | jq -e --arg bridge "$ROOT/scripts/orca-worktree-model-bridge.sh" \
      --arg model "$model" --arg needle "$needle" '
      .hookSpecificOutput.hookEventName == "PreToolUse" and
      (([39] | implode) as $quote |
       .hookSpecificOutput.updatedInput.command |
       startswith($quote + $bridge + $quote + " --model " + $quote + $model + $quote)) and
      (([39] | implode) as $quote |
       .hookSpecificOutput.updatedInput.command |
       contains("--model " + $quote + $model + $quote)) and
      (.hookSpecificOutput.updatedInput.command | contains("--model sonnet") | not) and
      (.hookSpecificOutput.updatedInput.description == "start worker") and
      (.hookSpecificOutput.updatedInput.custom_field.keep == true) and
      (.hookSpecificOutput.additionalContext == "Orca model override replaced with the Main session model.") and
      (if $needle == "" then true else (.hookSpecificOutput.updatedInput.command | contains($needle)) end)
    ' >/dev/null 2>&1; then
    pass "$name"
  else
    fail "$name" "rewrite 또는 출력 계약 불일치"
  fi
}

assert_rewritten_without_old_model() {
  local name="$1" input="$2" path="$3" model="$4" out
  if ! out=$(run_hook "$input" "$path"); then
    fail "$name" "hook가 non-zero로 종료"
  elif printf '%s' "$out" | jq -e --arg model "$model" '
      .hookSpecificOutput.updatedInput.command |
      (([39] | implode) as $quote |
       contains("--model " + $quote + $model + $quote)) and
      (contains("--model sonnet") | not)
    ' >/dev/null 2>&1; then
    pass "$name"
  else
    fail "$name" "현재 model만 남지 않음"
  fi
}

assert_noop() {
  local name="$1" input="$2" path="${3:-$PATH_WITH_ORCA}" hook="${4:-$HOOK}" out
  if ! out=$(run_hook "$input" "$path" "$hook"); then
    fail "$name" "no-op이 non-zero로 종료"
  elif [ -z "$out" ]; then
    pass "$name"
  else
    fail "$name" "stdout가 비어 있지 않음"
  fi
}

assert_closed_stdin() {
  local name="$1" out
  if ! out=$(PATH="$PATH_WITH_ORCA" bash "$HOOK" 0<&- 2>/dev/null); then
    fail "$name" "닫힌 stdin이 non-zero로 종료"
  elif [ -z "$out" ]; then
    pass "$name"
  else
    fail "$name" "stdout가 비어 있지 않음"
  fi
}

assert_literal_model_execution() {
  local name="$1" input="$2" path="$3" hook="$4" expected="$5"
  local out rewritten actual

  : > "$GLOB_ARGV_LOG"
  if ! out=$(run_hook "$input" "$path" "$hook"); then
    fail "$name" "hook가 non-zero로 종료"
  elif ! rewritten=$(printf '%s' "$out" | jq -er '.hookSpecificOutput.updatedInput.command' 2>/dev/null); then
    fail "$name" "rewritten command를 읽지 못함"
  elif ! (cd "$GLOB_CWD" && GLOB_ARGV_LOG="$GLOB_ARGV_LOG" bash -c "$rewritten"); then
    fail "$name" "rewritten command 실행 실패"
  elif actual=$(<"$GLOB_ARGV_LOG") && [ "$actual" = "$expected" ]; then
    pass "$name"
  else
    fail "$name" "fake bridge model argv 불일치"
  fi
}

printf '%s\n' '{"message":{"role":"assistant","model":"claude-sonnet-5"}}' \
  '{"message":{"role":"assistant","model":"<synthetic>"}}' \
  '{"message":{"role":"assistant","model":"composer-2.5"}}' \
  '{"message":{"role":"assistant","model":"claude-sonnet-5"}}' \
  > "$TMPDIR_ROOT/orca-main.jsonl"
printf '%s\n' '{"message":{"role":"assistant","model":"claude-opus-5"}}' \
  > "$TMPDIR_ROOT/orca-claude.jsonl"
printf '%s\n' '{"message":{"role":"assistant","model":"composer-2.5"}}' \
  > "$TMPDIR_ROOT/orca-unknown.jsonl"
printf '%s\n' '{"message":{"role":"assistant","model":"claude-opus-5[1m]"}}' \
  > "$TMPDIR_ROOT/orca-main-1m.jsonl"
printf '%s\n' '{not-json' > "$TMPDIR_ROOT/orca-invalid.jsonl"

MAIN="$TMPDIR_ROOT/orca-main.jsonl"
CLAUDE="$TMPDIR_ROOT/orca-claude.jsonl"
UNKNOWN="$TMPDIR_ROOT/orca-unknown.jsonl"
MAIN_1M="$TMPDIR_ROOT/orca-main-1m.jsonl"

MISSING_BRIDGE_DIR="$TMPDIR_ROOT/missing-bridge"
MISSING_BRIDGE_HOOK="$MISSING_BRIDGE_DIR/orca-model-inherit.sh"
NONEXECUTABLE_BRIDGE_DIR="$TMPDIR_ROOT/nonexecutable-bridge"
NONEXECUTABLE_BRIDGE_HOOK="$NONEXECUTABLE_BRIDGE_DIR/orca-model-inherit.sh"
GLOB_HOOK_DIR="$TMPDIR_ROOT/glob bridge"
GLOB_HOOK="$GLOB_HOOK_DIR/orca-model-inherit.sh"
GLOB_BRIDGE="$GLOB_HOOK_DIR/orca-worktree-model-bridge.sh"
GLOB_CWD="$TMPDIR_ROOT/glob-cwd"
GLOB_ARGV_LOG="$TMPDIR_ROOT/glob-bridge-argv.log"

mkdir -p "$MISSING_BRIDGE_DIR" "$NONEXECUTABLE_BRIDGE_DIR" \
  "$GLOB_HOOK_DIR" "$GLOB_CWD"
cp "$HOOK" "$MISSING_BRIDGE_HOOK"
cp "$HOOK" "$NONEXECUTABLE_BRIDGE_HOOK"
cp "$HOOK" "$GLOB_HOOK"
printf '#!/bin/bash\nexit 0\n' > "$NONEXECUTABLE_BRIDGE_DIR/orca-worktree-model-bridge.sh"
printf '%s\n' '#!/bin/bash' 'printf "%s\n" "$@" > "$GLOB_ARGV_LOG"' > "$GLOB_BRIDGE"
chmod 644 "$NONEXECUTABLE_BRIDGE_DIR/orca-worktree-model-bridge.sh"
chmod +x "$GLOB_BRIDGE"
: > "$GLOB_CWD/claude-sonnet-51"
: > "$GLOB_CWD/claude-sonnet-5m"

printf '=== orca-model-inherit unit tests ===\n'

assert_rewritten "worker-start model 교체" \
  "$(make_payload 'orca orchestration worker-start --task task-1 --agent claude --model sonnet' "$MAIN" Bash)" \
  "$PATH_WITH_ORCA" "claude-sonnet-5"
assert_rewritten "worker-start 기존 model 없음" \
  "$(make_payload 'orca orchestration worker-start --task task-1 --agent claude' "$MAIN" Bash)" \
  "$PATH_WITH_ORCA" "claude-sonnet-5"
assert_rewritten_without_old_model "worker-start --model= 교체" \
  "$(make_payload 'orca orchestration worker-start --task task-1 --agent=claude --model=sonnet' "$MAIN" Bash)" \
  "$PATH_WITH_ORCA" "claude-sonnet-5"
assert_rewritten "worktree create 기본 경로" \
  "$(make_payload "orca worktree create --name task-1 --agent claude --prompt 'read only'" "$MAIN" Bash)" \
  "$PATH_WITH_ORCA" "claude-sonnet-5" "'read only'"
assert_rewritten "worktree create --agent=claude" \
  "$(make_payload 'orca worktree create --name task-1 --agent=claude' "$MAIN" Bash)" \
  "$PATH_WITH_ORCA" "claude-sonnet-5"
assert_rewritten "quoted prompt 특수문자 보존" \
  "$(make_payload "orca worktree create --name task-1 --agent claude --prompt 'read only: \$HOME && do not edit'" "$MAIN" Bash)" \
  "$PATH_WITH_ORCA" "claude-sonnet-5" "'read only: \$HOME && do not edit'"
assert_rewritten "quoted command substitution prompt 보존" \
  "$(make_payload "orca worktree create --name task-1 --agent claude --prompt 'literal: \$(printf no)'" "$MAIN" Bash)" \
  "$PATH_WITH_ORCA" "claude-sonnet-5" "'literal: \$(printf no)'"
assert_rewritten "double quoted prompt 특수문자 보존" \
  "$(make_payload 'orca worktree create --name task-1 --agent claude --prompt "read only: $HOME && do not edit"' "$MAIN" Bash)" \
  "$PATH_WITH_ORCA" "claude-sonnet-5" '"read only: $HOME && do not edit"'
assert_rewritten "escaped double quoted command substitution 보존" \
  "$(make_payload 'orca worktree create --name task-1 --agent claude --prompt "literal: \$(printf no)"' "$MAIN" Bash)" \
  "$PATH_WITH_ORCA" "claude-sonnet-5" '"literal: \$(printf no)"'
assert_rewritten "escaped double quoted backtick 보존" \
  "$(make_payload 'orca worktree create --name task-1 --agent claude --prompt "literal: \`printf no\`"' "$MAIN" Bash)" \
  "$PATH_WITH_ORCA" "claude-sonnet-5" '"literal: \`printf no\`"'
assert_rewritten "Claude model worktree" \
  "$(make_payload 'orca worktree create --name task-1 --agent claude --prompt "read only"' "$CLAUDE" Bash)" \
  "$PATH_WITH_ORCA" "claude-opus-5"

assert_noop "worker-start --terminal" \
  "$(make_payload 'orca orchestration worker-start --task task-1 --terminal term_1' "$MAIN" Bash)"
assert_noop "worktree non-Claude agent" \
  "$(make_payload 'orca worktree create --name task-1 --agent codex' "$MAIN" Bash)"
assert_noop "worktree Claude와 다른 agent 중복" \
  "$(make_payload 'orca worktree create --name task-1 --agent claude --agent codex' "$MAIN" Bash)"
assert_noop "worktree Claude agent 중복" \
  "$(make_payload 'orca worktree create --name task-1 --agent claude --agent=claude' "$MAIN" Bash)"
assert_noop "compound command" \
  "$(make_payload 'orca worktree create --name task-1 --agent claude && rm -rf /tmp/x' "$MAIN" Bash)"
assert_noop "semicolon command" \
  "$(make_payload 'orca worktree create --name task-1 --agent claude; rm -rf /tmp/x' "$MAIN" Bash)"
assert_noop "pipeline command" \
  "$(make_payload 'orca worktree create --name task-1 --agent claude | cat' "$MAIN" Bash)"
assert_noop "redirection command" \
  "$(make_payload 'orca worktree create --name task-1 --agent claude > /tmp/x' "$MAIN" Bash)"
assert_noop "unquoted command substitution" \
  "$(make_payload 'orca worktree create --name task-1 --agent claude $(touch /tmp/x)' "$MAIN" Bash)"
assert_noop "double quoted command substitution" \
  "$(make_payload 'orca worktree create --name task-1 --agent claude --prompt "literal: $(touch /tmp/x)"' "$MAIN" Bash)"
assert_noop "double quoted backtick substitution" \
  "$(make_payload 'orca worktree create --name task-1 --agent claude --prompt "literal: `touch /tmp/x`"' "$MAIN" Bash)"
assert_noop "double quoted non-Claude agent escape" \
  "$(make_payload 'orca worktree create --name task-1 --agent "clau\de"' "$MAIN" Bash)"
assert_noop "일반 Read tool" \
  "$(make_payload 'orca worktree create --name task-1 --agent claude' "$MAIN" Read)"
assert_noop "일반 Bash command" \
  "$(make_payload 'printf ready' "$MAIN" Bash)"
assert_noop "지원하지 않는 provider model" \
  "$(make_payload 'orca worktree create --name task-1 --agent claude' "$UNKNOWN" Bash)"
assert_noop "orca executable missing" \
  "$(make_payload 'orca worktree create --name task-1 --agent claude' "$MAIN" Bash)" "$PATH_WITHOUT_ORCA"
assert_noop "bridge missing" \
  "$(make_payload 'orca worktree create --name task-1 --agent claude' "$MAIN" Bash)" \
  "$PATH_WITH_ORCA" "$MISSING_BRIDGE_HOOK"
assert_noop "bridge non-executable" \
  "$(make_payload 'orca worktree create --name task-1 --agent claude' "$MAIN" Bash)" \
  "$PATH_WITH_ORCA" "$NONEXECUTABLE_BRIDGE_HOOK"
assert_noop "transcript 누락" \
  "$(make_payload 'orca worktree create --name task-1 --agent claude' "$TMPDIR_ROOT/missing.jsonl" Bash)"
assert_noop "transcript 잘못된 JSON" \
  "$(make_payload 'orca worktree create --name task-1 --agent claude' "$TMPDIR_ROOT/orca-invalid.jsonl" Bash)"
assert_noop "잘못된 stdin JSON" '{not-json'
assert_closed_stdin "닫힌 stdin"
assert_noop "앞 공백 command" \
  "$(make_payload ' orca worktree create --name task-1 --agent claude' "$MAIN" Bash)"
assert_rewritten "모델 [1m] suffix 보존" \
  "$(make_payload 'orca worktree create --name task-1 --agent claude' "$MAIN_1M" Bash)" \
  "$PATH_WITH_ORCA" "claude-opus-5[1m]"
assert_literal_model_execution "quoted bridge/model executes literal [1m]" \
  "$(make_payload 'orca worktree create --name task-1 --agent claude' "$MAIN_1M" Bash)" \
  "$PATH_WITH_ORCA" "$GLOB_HOOK" \
  $'--model\nclaude-opus-5[1m]\nworktree\ncreate\n--name\ntask-1\n--agent\nclaude'

printf '\n=== %s passed, %s failed ===\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
