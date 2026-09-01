#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SHIM="$ROOT/scripts/claude-orca-launch.sh"
TMPDIR_ROOT=$(mktemp -d)
trap 'rm -rf "$TMPDIR_ROOT"' EXIT

PASS=0
FAIL=0
ORIGINAL_PATH="$PATH"
FAKE_BIN_DIR="$TMPDIR_ROOT/bin"
FAKE_CLAUDE="$TMPDIR_ROOT/fake-claude.sh"
FAKE_CLAUDE_LOG="$TMPDIR_ROOT/claude.log"
FAKE_STDOUT="$TMPDIR_ROOT/stdout"
FAKE_STDERR="$TMPDIR_ROOT/stderr"

pass() { PASS=$((PASS + 1)); printf '  ✅ %s\n' "$1"; }
fail() { FAIL=$((FAIL + 1)); printf '  ❌ %s%s\n' "$1" "${2:+ — $2}"; }

mkdir -p "$FAKE_BIN_DIR"
printf '%s\n' \
  '#!/bin/bash' \
  'printf "args:" >> "$FAKE_CLAUDE_LOG"' \
  'printf " %s" "$@" >> "$FAKE_CLAUDE_LOG"' \
  'printf "\\nANTHROPIC_BASE_URL=%s\\n" "${ANTHROPIC_BASE_URL-<unset>}" >> "$FAKE_CLAUDE_LOG"' \
  'printf "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=%s\\n" "${CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC-<unset>}" >> "$FAKE_CLAUDE_LOG"' \
  > "$FAKE_CLAUDE"
chmod +x "$FAKE_CLAUDE"

run_launch() {
  local marker="$1" base_url="$2" disable="$3"
  shift 3
  : > "$FAKE_CLAUDE_LOG"
  : > "$FAKE_STDOUT"
  : > "$FAKE_STDERR"
  set +e
  (
    export PATH="$FAKE_BIN_DIR:$ORIGINAL_PATH"
    export FAKE_CLAUDE_LOG
    export CLAUDE_ORCA_REAL_BIN="$FAKE_CLAUDE"
    case "$marker" in
      token) export ORCA_AGENT_LAUNCH_TOKEN=token-1; unset ORCA_WORKTREE_ID ;;
      worktree) export ORCA_WORKTREE_ID=wt-1; unset ORCA_AGENT_LAUNCH_TOKEN ;;
      none) unset ORCA_AGENT_LAUNCH_TOKEN ORCA_WORKTREE_ID ;;
    esac
    case "$base_url" in
      unset) unset ANTHROPIC_BASE_URL ;;
      *) export ANTHROPIC_BASE_URL="$base_url" ;;
    esac
    case "$disable" in
      unset) unset CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC ;;
      *) export CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC="$disable" ;;
    esac
    bash "$SHIM" "$@" > "$FAKE_STDOUT" 2> "$FAKE_STDERR"
  )
  LAST_STATUS=$?
  set -e
}

assert_record() {
  local name="$1" expected_args="$2" expected_base="$3" expected_disable="$4"
  if [ "$LAST_STATUS" -eq 0 ] && \
     grep -Fx "args: $expected_args" "$FAKE_CLAUDE_LOG" >/dev/null 2>&1 && \
     grep -Fx "ANTHROPIC_BASE_URL=$expected_base" "$FAKE_CLAUDE_LOG" >/dev/null 2>&1 && \
     grep -Fx "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=$expected_disable" "$FAKE_CLAUDE_LOG" >/dev/null 2>&1; then
    pass "$name"
  else
    fail "$name" "fake Claude 기록 또는 status 불일치"
  fi
}

printf '=== claude-orca-launch unit tests ===\n'

run_launch token unset unset \
  --model claude-sonnet-5 --dangerously-skip-permissions
assert_record "Orca token launch is a pass-through" \
  "--model claude-sonnet-5 --dangerously-skip-permissions" \
  "<unset>" "<unset>"

run_launch worktree unset unset \
  --model=claude-opus-5[1m] --dangerously-skip-permissions
assert_record "ORCA_WORKTREE_ID and --model= with [1m]" \
  "--model=claude-opus-5[1m] --dangerously-skip-permissions" \
  "<unset>" "<unset>"

run_launch token existing 0 \
  --model claude-opus-5
assert_record "Claude model preserves environment" \
  "--model claude-opus-5" "existing" "0"

run_launch token existing 0 \
  --model composer-2.5
assert_record "Unknown model preserves environment" \
  "--model composer-2.5" "existing" "0"

run_launch token existing 0 \
  --dangerously-skip-permissions
assert_record "Missing model preserves environment" \
  "--dangerously-skip-permissions" "existing" "0"

run_launch none existing 0 \
  --model claude-sonnet-5 --dangerously-skip-permissions
assert_record "No Orca marker is a pass-through" \
  "--model claude-sonnet-5 --dangerously-skip-permissions" "existing" "0"

printf '\n=== %s passed, %s failed ===\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
