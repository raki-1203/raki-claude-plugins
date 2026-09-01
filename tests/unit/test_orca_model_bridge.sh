#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BRIDGE="$ROOT/scripts/orca-worktree-model-bridge.sh"
TMPDIR_ROOT=$(mktemp -d)
trap 'rm -rf "$TMPDIR_ROOT"' EXIT

PASS=0
FAIL=0
ORIGINAL_PATH="$PATH"
TEST_PATH="$TMPDIR_ROOT/bin:$ORIGINAL_PATH"
FAKE_ORCA="$TMPDIR_ROOT/fake-orca.sh"
FAKE_ORCA_LOG="$TMPDIR_ROOT/orca.log"
FAKE_ORCA_ENV_LOG="$TMPDIR_ROOT/orca.env"
FAKE_ORCA_STDOUT="$TMPDIR_ROOT/stdout"
FAKE_ORCA_STDERR="$TMPDIR_ROOT/stderr"
EXPECTED_LOG="$TMPDIR_ROOT/expected.log"
FAKE_ORCA_CREATE_MODE=valid
FAKE_ORCA_TERMINAL_FAIL=0
FAKE_ORCA_WORKTREE_PATH='/private/tmp/orca-smoke/task-1'
export FAKE_ORCA_CREATE_MODE FAKE_ORCA_TERMINAL_FAIL FAKE_ORCA_WORKTREE_PATH

pass() { PASS=$((PASS + 1)); printf '  ✅ %s\n' "$1"; }
fail() { FAIL=$((FAIL + 1)); printf '  ❌ %s%s\n' "$1" "${2:+ — $2}"; }

mkdir -p "$TMPDIR_ROOT/bin"
printf '%s\n' \
  '#!/bin/bash' \
  'printf "CALL\\n" >> "$FAKE_ORCA_LOG"' \
  'printf "%s\\n" "$@" >> "$FAKE_ORCA_LOG"' \
  'printf "ANTHROPIC_BASE_URL=%s\\n" "${ANTHROPIC_BASE_URL-<unset>}" >> "$FAKE_ORCA_ENV_LOG"' \
  'printf "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=%s\\n" "${CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC-<unset>}" >> "$FAKE_ORCA_ENV_LOG"' \
  'if [ "$1" = "worktree" ] && [ "$2" = "create" ]; then' \
  '  case "${FAKE_ORCA_CREATE_MODE:-valid}" in' \
  '    valid) printf '\''{"result":{"worktree":{"id":"wt-1","path":"%s"}}}'\'' "${FAKE_ORCA_WORKTREE_PATH:-/private/tmp/orca-smoke/task-1}" ;;' \
  '    missing-path) printf "%s" '\''{"result":{"worktree":{"id":"wt-1"}}}'\'' ;;' \
  '    relative-path) printf "%s" '\''{"result":{"worktree":{"path":"relative/task-1"}}}'\'' ;;' \
  '    root-path) printf "%s" '\''{"result":{"worktree":{"path":"/"}}}'\'' ;;' \
  '    invalid-json) printf "%s" '\''{not-json'\'' ;;' \
  '    create-fail) exit 7 ;;' \
  '  esac' \
  '  exit 0' \
  'fi' \
  'if [ "$1" = "terminal" ] && [ "$2" = "create" ]; then' \
  '  if [ "${FAKE_ORCA_TERMINAL_FAIL:-0}" -eq 1 ]; then exit 9; fi' \
  '  printf "%s" '\''{"result":{"terminal":{"handle":"term-1"}}}'\'' ' \
  '  exit 0' \
  'fi' \
  'if [ "$1" = "orchestration" ] && [ "$2" = "worker-start" ]; then exit 0; fi' \
  'exit 64' > "$FAKE_ORCA"
chmod +x "$FAKE_ORCA"

run_bridge() {
  local base_mode="$1"
  shift
  : > "$FAKE_ORCA_LOG"
  : > "$FAKE_ORCA_ENV_LOG"
  : > "$FAKE_ORCA_STDOUT"
  : > "$FAKE_ORCA_STDERR"
  set +e
  if [ "$base_mode" = "unset" ]; then
    (
      unset ANTHROPIC_BASE_URL
      unset CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC
      ORCA_MODEL_BRIDGE_ORCA_BIN="$FAKE_ORCA" \
        FAKE_ORCA_LOG="$FAKE_ORCA_LOG" \
        FAKE_ORCA_ENV_LOG="$FAKE_ORCA_ENV_LOG" \
        PATH="$TEST_PATH" \
        bash "$BRIDGE" "$@" > "$FAKE_ORCA_STDOUT" 2> "$FAKE_ORCA_STDERR"
    )
    LAST_STATUS=$?
  else
    local base_url="$base_mode"
    (
      unset CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC
      ANTHROPIC_BASE_URL="$base_url" \
        ORCA_MODEL_BRIDGE_ORCA_BIN="$FAKE_ORCA" \
        FAKE_ORCA_LOG="$FAKE_ORCA_LOG" \
        FAKE_ORCA_ENV_LOG="$FAKE_ORCA_ENV_LOG" \
        PATH="$TEST_PATH" \
        bash "$BRIDGE" "$@" > "$FAKE_ORCA_STDOUT" 2> "$FAKE_ORCA_STDERR"
    )
    LAST_STATUS=$?
  fi
  set -e
}

call_count() {
  grep -c '^CALL$' "$FAKE_ORCA_LOG" 2>/dev/null || true
}

assert_log() {
  local name="$1"
  shift
  printf 'CALL\n' > "$EXPECTED_LOG"
  printf '%s\n' "$@" >> "$EXPECTED_LOG"
  if diff -u "$EXPECTED_LOG" "$FAKE_ORCA_LOG" >/dev/null 2>&1; then
    pass "$name"
  else
    fail "$name" "fake Orca argv 불일치"
  fi
}

assert_no_calls() {
  local name="$1"
  if [ "$(call_count)" -eq 0 ]; then
    pass "$name"
  else
    fail "$name" "fake Orca가 호출됨"
  fi
}

assert_calls() {
  local name="$1" expected="$2"
  if [ "$(call_count)" -eq "$expected" ]; then
    pass "$name"
  else
    fail "$name" "호출 횟수 $(call_count), 기대값 $expected"
  fi
}

assert_json_envelope() {
  local name="$1"
  if jq -e '
      (.worktree.result.worktree.path == "/private/tmp/orca-smoke/task-1") and
      (.terminal.result.terminal.handle == "term-1")
    ' "$FAKE_ORCA_STDOUT" >/dev/null 2>&1; then
    pass "$name"
  else
    fail "$name" "JSON envelope 불일치"
  fi
}

printf '=== orca-worktree-model-bridge unit tests ===\n'

# worker-start replaces every existing model and appends the current model.
run_bridge unset --model claude-sonnet-5 \
  orchestration worker-start --task task-1 --agent claude --model sonnet
if [ "$LAST_STATUS" -eq 0 ]; then
  assert_log "worker-start model 교체" \
    orchestration worker-start --task task-1 --agent claude --model claude-sonnet-5
else
  fail "worker-start model 교체" "bridge가 non-zero로 종료"
fi
if ! grep -F -- '--model sonnet' "$FAKE_ORCA_LOG" >/dev/null 2>&1; then
  pass "worker-start 기존 model 제거"
else
  fail "worker-start 기존 model 제거" "기존 model이 남아 있음"
fi

run_bridge unset --model=claude-opus-5 \
  orchestration worker-start --task task-1 --agent=claude --model=sonnet
if [ "$LAST_STATUS" -eq 0 ] && [ "$(call_count)" -eq 1 ] && \
   grep -F -- '--model=sonnet' "$FAKE_ORCA_LOG" >/dev/null 2>&1; then
  fail "worker-start --model= 제거" "기존 model이 남아 있음"
elif [ "$LAST_STATUS" -eq 0 ] && [ "$(call_count)" -eq 1 ]; then
  pass "worker-start --model= 제거"
else
  fail "worker-start --model= 제거" "bridge 호출 계약 불일치"
fi

run_bridge unset --model claude-sonnet-5 \
  orchestration worker-start --task task-1 --agent claude --terminal term-1
if [ "$LAST_STATUS" -eq 0 ]; then
  assert_no_calls "worker-start --terminal no-op"
else
  fail "worker-start --terminal no-op" "no-op이 non-zero로 종료"
fi

run_bridge unset --model claude-sonnet-5 \
  orchestration worker-start --task task-1 --agent codex
if [ "$LAST_STATUS" -eq 0 ]; then
  assert_no_calls "worker-start non-Claude agent no-op"
else
  fail "worker-start non-Claude agent no-op" "no-op이 non-zero로 종료"
fi

# worktree create strips agent/prompt/model, preserves creation flags, then creates a terminal.
FAKE_ORCA_CREATE_MODE=valid
FAKE_ORCA_TERMINAL_FAIL=0
run_bridge unset --model claude-sonnet-5 \
  worktree create --name task-1 --repo path:/private/tmp/orca-smoke \
  --agent claude --prompt 'read only: $HOME && do not edit' --json
if [ "$LAST_STATUS" -eq 0 ]; then
  assert_json_envelope "worktree JSON envelope"
else
  fail "worktree JSON envelope" "bridge가 non-zero로 종료"
fi
if [ "$LAST_STATUS" -eq 0 ]; then
  assert_calls "worktree two-phase 호출" 2
  EXPECTED_COMMAND="claude --model 'claude-sonnet-5' --prefill 'read only: \$HOME && do not edit'"
  printf 'CALL\nworktree\ncreate\n--name\ntask-1\n--repo\npath:/private/tmp/orca-smoke\n--json\nCALL\nterminal\ncreate\n--worktree\npath:/private/tmp/orca-smoke/task-1\n--command\n%s\n--json\n' "$EXPECTED_COMMAND" > "$EXPECTED_LOG"
  if diff -u "$EXPECTED_LOG" "$FAKE_ORCA_LOG" >/dev/null 2>&1; then
    pass "worktree argv·prompt quote"
  else
    fail "worktree argv·prompt quote" "fake Orca argv 불일치"
  fi
  if grep -F -- 'ANTHROPIC_BASE_URL=<unset>' "$FAKE_ORCA_ENV_LOG" >/dev/null 2>&1 && \
     grep -F -- 'CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=<unset>' "$FAKE_ORCA_ENV_LOG" >/dev/null 2>&1; then
    pass "parent 환경 기록"
  else
    fail "parent 환경 기록" "parent 환경이 예상과 다름"
  fi
fi

# The optional [1m] suffix must stay literal even when a matching filename exists.
GLOB_WORKTREE="$TMPDIR_ROOT/worktree/task-1"
mkdir -p "$GLOB_WORKTREE"
touch "$GLOB_WORKTREE/claude-sonnet-51"
FAKE_ORCA_WORKTREE_PATH="$GLOB_WORKTREE"
run_bridge unset --model 'claude-opus-5[1m]' \
  worktree create --name task-1 --agent claude --prompt x
EXPECTED_GLOB_COMMAND="claude --model 'claude-opus-5[1m]' --prefill 'x'"
if [ "$LAST_STATUS" -eq 0 ] && [ "$(call_count)" -eq 2 ] && \
   grep -F -- "$EXPECTED_GLOB_COMMAND" "$FAKE_ORCA_LOG" >/dev/null 2>&1; then
  pass "[1m] model shell quote"
else
  fail "[1m] model shell quote" "launch command에서 model glob이 quote되지 않음"
fi
FAKE_ORCA_WORKTREE_PATH='/private/tmp/orca-smoke/task-1'

run_bridge https://api.example.test --model claude-opus-5 \
  worktree create --name task-1 --agent claude --prompt 'read only'
if [ "$LAST_STATUS" -eq 0 ] && ! grep -F -- 'ANTHROPIC_BASE_URL=' "$FAKE_ORCA_LOG" >/dev/null 2>&1; then
  pass "Claude 외부 base URL 차단"
else
  fail "Claude 외부 base URL 차단" "외부 base URL이 launch command에 전달됨"
fi

run_bridge unset --model claude-sonnet-5 \
  worktree create --name task-1 --agent claude --prompt 'read only'
if [ "$LAST_STATUS" -eq 0 ] && [ "$(call_count)" -eq 2 ]; then
  if grep -F -- 'terminal:' "$FAKE_ORCA_STDOUT" >/dev/null 2>&1 && \
     grep -F -- 'worktree:' "$FAKE_ORCA_STDOUT" >/dev/null 2>&1; then
    pass "worktree human-readable output"
  else
    fail "worktree human-readable output" "두 줄 출력 계약 불일치"
  fi
else
  fail "worktree human-readable output" "bridge 호출 계약 불일치"
fi

# Fail-open/no-cleanup cases.
run_bridge unset --model claude-sonnet-5 \
  worktree create --name task-1 --agent codex
if [ "$LAST_STATUS" -eq 0 ]; then
  assert_no_calls "worktree non-Claude agent no-op"
else
  fail "worktree non-Claude agent no-op" "no-op이 non-zero로 종료"
fi

FAKE_ORCA_CREATE_MODE=invalid-json
run_bridge unset --model claude-opus-5 \
  worktree create --name task-1 --agent claude
if [ "$LAST_STATUS" -ne 0 ] && [ "$(call_count)" -eq 1 ] && \
   ! grep -F -- 'terminal' "$FAKE_ORCA_LOG" >/dev/null 2>&1; then
  pass "invalid JSON terminal 차단"
else
  fail "invalid JSON terminal 차단" "invalid JSON 후 terminal 호출 또는 잘못된 status"
fi

FAKE_ORCA_CREATE_MODE=relative-path
run_bridge unset --model claude-opus-5 \
  worktree create --name task-1 --agent claude
if [ "$LAST_STATUS" -ne 0 ] && [ "$(call_count)" -eq 1 ]; then
  pass "relative path terminal 차단"
else
  fail "relative path terminal 차단" "invalid path 처리 불일치"
fi

FAKE_ORCA_CREATE_MODE=root-path
run_bridge unset --model claude-opus-5 \
  worktree create --name task-1 --agent claude
if [ "$LAST_STATUS" -ne 0 ] && [ "$(call_count)" -eq 1 ]; then
  pass "root path terminal 차단"
else
  fail "root path terminal 차단" "root path 처리 불일치"
fi

FAKE_ORCA_CREATE_MODE=valid
FAKE_ORCA_TERMINAL_FAIL=1
run_bridge unset --model claude-opus-5 \
  worktree create --name task-1 --agent claude
if [ "$LAST_STATUS" -ne 0 ] && [ "$(call_count)" -eq 2 ] && \
   ! grep -F -- 'rm -rf' "$FAKE_ORCA_LOG" >/dev/null 2>&1; then
  pass "terminal failure worktree 보존"
else
  fail "terminal failure worktree 보존" "terminal failure 또는 삭제 계약 불일치"
fi
FAKE_ORCA_TERMINAL_FAIL=0

FAKE_ORCA_CREATE_MODE=valid
run_bridge unset --model nonsense \
  worktree create --name task-1 --agent claude
if [ "$LAST_STATUS" -eq 0 ]; then
  assert_no_calls "지원하지 않는 model no-op"
else
  fail "지원하지 않는 model no-op" "no-op이 non-zero로 종료"
fi

printf '\n=== %s passed, %s failed ===\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
