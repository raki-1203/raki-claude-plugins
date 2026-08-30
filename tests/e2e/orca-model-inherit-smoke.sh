#!/bin/bash
# Orca model inheritance mock integration smoke test.
# Only uses a throwaway Git repository under /private/tmp; no real daemon/network.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ORIGINAL_PATH="$PATH"
# Keep the fixture independent from the caller's provider environment.
unset ANTHROPIC_BASE_URL CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC
SMOKE_ROOT="$(mktemp -d /private/tmp/orca-model-inherit-smoke.XXXXXX)"
REPO="$SMOKE_ROOT/repo"
WORKTREE_PATH="$SMOKE_ROOT/worktrees/task-1"
FAKE_ORCA_WORKTREE_PATH="$WORKTREE_PATH"
FAKE_BIN="$SMOKE_ROOT/bin"
LOG_DIR="$SMOKE_ROOT/logs"
FAKE_ORCA="$FAKE_BIN/orca"
FAKE_NC="$FAKE_BIN/nc"
FAKE_CLAUDE="$FAKE_BIN/claude"
FAKE_LAUNCHER="$ROOT/scripts/claude-orca-launch.sh"
FAKE_ORCA_LOG="$LOG_DIR/orca.log"
FAKE_TERMINAL_COMMAND="$LOG_DIR/terminal-command"
FAKE_CLAUDE_LOG="$LOG_DIR/claude.log"
FAKE_WORKER_LAUNCH_COMMAND="$LOG_DIR/worker-launch-command"
FAKE_WORKER_CLAUDE_LOG="$LOG_DIR/worker-claude.log"
EXPECTED_LOG="$LOG_DIR/expected.log"
CREATE_LOG="$LOG_DIR/create.log"
WORKER_EXPECTED_LOG="$LOG_DIR/worker-expected.log"
TRANSCRIPT="$LOG_DIR/transcript.jsonl"
PAYLOAD="$LOG_DIR/hook-payload.json"
HOOK_JSON="$LOG_DIR/hook.json"
WORKER_PAYLOAD="$LOG_DIR/worker-hook-payload.json"
WORKER_HOOK_JSON="$LOG_DIR/worker-hook.json"
BRIDGE_STDOUT="$LOG_DIR/bridge.stdout"
BRIDGE_STDERR="$LOG_DIR/bridge.stderr"
WORKER_STDOUT="$LOG_DIR/worker.stdout"
WORKER_STDERR="$LOG_DIR/worker.stderr"
LOOPBACK_URL='http://127.0.0.1:18765'
TERMINAL_HANDLE=''

path_is_inside_smoke_root() {
  case "$1" in
    "$SMOKE_ROOT"|"$SMOKE_ROOT"/*) return 0 ;;
    *) return 1 ;;
  esac
}

safe_remove() {
  local target="$1"
  path_is_inside_smoke_root "$target" || {
    printf 'cleanup refused outside smoke root: %s\n' "$target" >&2
    return 1
  }
  if [ -e "$target" ] || [ -L "$target" ]; then
    rm -rf -- "$target"
  fi
}

cleanup() {
  local exit_code=$?
  set +e

  if [ -n "$TERMINAL_HANDLE" ] && [ -x "$FAKE_ORCA" ]; then
    FAKE_ORCA_LOG="$FAKE_ORCA_LOG" \
      "$FAKE_ORCA" terminal stop --handle "$TERMINAL_HANDLE" --json \
      >/dev/null 2>&1
  fi

  if [ -n "${WORKTREE_PATH-}" ] && path_is_inside_smoke_root "$WORKTREE_PATH"; then
    safe_remove "$WORKTREE_PATH"
  fi
  if [ -n "${SMOKE_ROOT-}" ] && path_is_inside_smoke_root "$SMOKE_ROOT"; then
    safe_remove "$SMOKE_ROOT"
  fi

  exit "$exit_code"
}
trap cleanup EXIT

mkdir -p "$REPO" "$FAKE_BIN" "$LOG_DIR"
git -C "$REPO" init -q
printf '# Orca model inheritance smoke\n' > "$REPO/README.md"
git -C "$REPO" add README.md
git -C "$REPO" -c user.name=smoke -c user.email=smoke@example.invalid commit -qm initial

# The fake nc never probes the network. It only models a listening loopback proxy.
printf '%s\n' \
  '#!/bin/bash' \
  'if [ "$#" -eq 3 ] && [ "$1" = "-z" ] && [ "$2" = "127.0.0.1" ] && [ "$3" = "18765" ]; then' \
  '  exit 0' \
  'fi' \
  'exit 1' > "$FAKE_NC"
chmod +x "$FAKE_NC"

# The fake Claude records argv/environment and never contacts a provider.
printf '%s\n' \
  '#!/bin/bash' \
  'printf "args:" > "$FAKE_CLAUDE_LOG"' \
  'printf " %s" "$@" >> "$FAKE_CLAUDE_LOG"' \
  'printf "\\nANTHROPIC_BASE_URL=%s\\n" "${ANTHROPIC_BASE_URL-<unset>}" >> "$FAKE_CLAUDE_LOG"' \
  'printf "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=%s\\n" "${CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC-<unset>}" >> "$FAKE_CLAUDE_LOG"' \
  'exit 0' > "$FAKE_CLAUDE"
chmod +x "$FAKE_CLAUDE"

# The fake Orca records argv, creates only the throwaway worktree, and runs the
# generated terminal command against the fake Claude binary.
printf '%s\n' \
  '#!/bin/bash' \
  'set -euo pipefail' \
  'printf "CALL\\n" >> "$FAKE_ORCA_LOG"' \
  'printf "%s\\n" "$@" >> "$FAKE_ORCA_LOG"' \
  'case "${1-} ${2-}" in' \
  '  "worktree create")' \
  '    shift 2' \
  '    name=""' \
  '    while [ "$#" -gt 0 ]; do' \
  '      case "$1" in' \
  '        --name) name="$2"; shift 2 ;;' \
  '        --name=*) name="${1#--name=}"; shift ;;' \
  '        *) shift ;;' \
  '      esac' \
  '    done' \
  '    [ "$name" = "task-1" ]' \
  '    mkdir -p "$FAKE_ORCA_WORKTREE_PATH"' \
  '    printf "{\"result\":{\"worktree\":{\"id\":\"wt-smoke\",\"path\":\"%s\"}}}\n" "$FAKE_ORCA_WORKTREE_PATH"' \
  '    ;;' \
  '  "terminal create")' \
  '    shift 2' \
  '    command_text=""' \
  '    while [ "$#" -gt 0 ]; do' \
  '      case "$1" in' \
  '        --command) command_text="$2"; shift 2 ;;' \
  '        *) shift ;;' \
  '      esac' \
  '    done' \
  '    [ -n "$command_text" ]' \
  '    printf "%s\\n" "$command_text" > "$FAKE_TERMINAL_COMMAND"' \
  '    bash -c "$command_text"' \
  '    printf "%s\n" "{\"result\":{\"terminal\":{\"handle\":\"term-smoke\"}}}"' \
  '    ;;' \
  '  "orchestration worker-start")' \
  '    shift 2' \
  '    task=""' \
  '    agent=""' \
  '    model=""' \
  '    worktree=""' \
  '    while [ "$#" -gt 0 ]; do' \
  '      case "$1" in' \
  '        --task) task="$2"; shift 2 ;;' \
  '        --agent) agent="$2"; shift 2 ;;' \
  '        --model) model="$2"; shift 2 ;;' \
  '        --worktree) worktree="$2"; shift 2 ;;' \
  '        --json) shift ;;' \
  '        *) shift ;;' \
  '      esac' \
  '    done' \
  '    [ "$task" = "task-1" ]' \
  '    [ "$agent" = "claude" ]' \
  '    [ "$model" = "gpt-5.6-luna" ]' \
  '    [ "$worktree" = "path:$FAKE_ORCA_WORKTREE_PATH" ]' \
  '    launch_command="ORCA_WORKTREE_ID=wt-smoke FAKE_CLAUDE_LOG=$FAKE_WORKER_CLAUDE_LOG CLAUDE_ORCA_REAL_BIN=$FAKE_CLAUDE bash $FAKE_LAUNCHER --model $model"' \
  '    printf "%s\\n" "$launch_command" > "$FAKE_WORKER_LAUNCH_COMMAND"' \
  '    bash -c "$launch_command"' \
  '    printf "%s\n" "{\"result\":{\"worker\":{\"id\":\"worker-smoke\",\"status\":\"ready\"}}}"' \
  '    ;;' \
  '  "terminal stop")' \
  '    printf "%s\n" "{\"result\":{\"stopped\":true}}"' \
  '    ;;' \
  '  *)' \
  '    exit 64' \
  '    ;;' \
  'esac' > "$FAKE_ORCA"
chmod +x "$FAKE_ORCA"

export FAKE_ORCA_LOG FAKE_ORCA_WORKTREE_PATH FAKE_TERMINAL_COMMAND FAKE_CLAUDE_LOG \
  FAKE_WORKER_LAUNCH_COMMAND FAKE_WORKER_CLAUDE_LOG FAKE_LAUNCHER FAKE_CLAUDE
: > "$FAKE_ORCA_LOG"
: > "$FAKE_TERMINAL_COMMAND"
: > "$FAKE_CLAUDE_LOG"
: > "$FAKE_WORKER_LAUNCH_COMMAND"
: > "$FAKE_WORKER_CLAUDE_LOG"

printf '%s\n' '{"message":{"role":"assistant","model":"gpt-5.6-luna"}}' > "$TRANSCRIPT"
jq -cn --arg transcript "$TRANSCRIPT" --arg command \
  "orca worktree create --name task-1 --repo path:$REPO --agent claude --prompt 'read only' --json" \
  '{tool_name:"Bash",tool_input:{command:$command},transcript_path:$transcript}' > "$PAYLOAD"

# Hook rewrite: the payload is synthetic, and the bridge is the only command
# executed. PATH and the explicit bridge seam ensure no real Orca/nc is used.
PATH="$FAKE_BIN:$ORIGINAL_PATH" \
  bash "$ROOT/scripts/orca-model-inherit.sh" < "$PAYLOAD" > "$HOOK_JSON"

if jq -e --arg model 'gpt-5.6-luna' --arg bridge "$ROOT/scripts/orca-worktree-model-bridge.sh" '
    .hookSpecificOutput.hookEventName == "PreToolUse" and
    (([39] | implode) as $quote |
     .hookSpecificOutput.updatedInput.command |
     startswith($quote + $bridge + $quote + " --model " + $quote + $model + $quote)) and
    (.hookSpecificOutput.updatedInput.command | contains("--prompt '\''read only'\''"))
  ' "$HOOK_JSON" >/dev/null; then
  printf '  ✅ hook rewrote worktree command\n'
else
  printf '  ❌ hook rewrite assertion failed\n' >&2
  exit 1
fi

REWRITTEN_COMMAND=$(jq -er '.hookSpecificOutput.updatedInput.command' "$HOOK_JSON")
if ORCA_MODEL_BRIDGE_ORCA_BIN="$FAKE_ORCA" \
    PATH="$FAKE_BIN:$ORIGINAL_PATH" \
    bash -c "$REWRITTEN_COMMAND" > "$BRIDGE_STDOUT" 2> "$BRIDGE_STDERR"; then
  printf '  ✅ bridge completed fake worktree/terminal sequence\n'
else
  printf '  ❌ bridge failed\n' >&2
  if [ -s "$BRIDGE_STDERR" ]; then
    printf '%s\n' '--- bridge stderr ---' >&2
    while IFS= read -r line; do printf '%s\n' "$line" >&2; done < "$BRIDGE_STDERR"
  fi
  if [ -s "$FAKE_ORCA_LOG" ]; then
    printf '%s\n' '--- fake Orca log ---' >&2
    while IFS= read -r line; do printf '%s\n' "$line" >&2; done < "$FAKE_ORCA_LOG"
  fi
  exit 1
fi

# Save the handle before any later assertion can fail, so EXIT cleanup can stop it.
TERMINAL_HANDLE=$(jq -er '.terminal.result.terminal.handle // .terminal.handle // empty' \
  "$BRIDGE_STDOUT" 2>/dev/null || true)
if [ -n "$TERMINAL_HANDLE" ]; then
  printf '  ✅ terminal handle captured for cleanup: %s\n' "$TERMINAL_HANDLE"
else
  printf '  ❌ terminal handle missing from bridge JSON\n' >&2
  exit 1
fi

EXPECTED_COMMAND="env ANTHROPIC_BASE_URL=http://127.0.0.1:18765 CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 claude --model 'gpt-5.6-luna' --prefill 'read only'"
printf 'CALL\nworktree\ncreate\n--name\ntask-1\n--repo\npath:%s\n--json\nCALL\nterminal\ncreate\n--worktree\npath:%s\n--command\n%s\n--json\n' \
  "$REPO" "$WORKTREE_PATH" "$EXPECTED_COMMAND" > "$EXPECTED_LOG"

# The cleanup stop call is intentionally made after all two-phase assertions,
# so this comparison covers exactly worktree create then terminal create.
if cmp -s "$EXPECTED_LOG" "$FAKE_ORCA_LOG"; then
  printf '  ✅ fake Orca argv preserved create flags and terminal path\n'
else
  printf '  ❌ fake Orca argv mismatch\n' >&2
  diff -u "$EXPECTED_LOG" "$FAKE_ORCA_LOG" >&2 || true
  exit 1
fi
cp "$FAKE_ORCA_LOG" "$CREATE_LOG"

if jq -e --arg path "$WORKTREE_PATH" '
    .worktree.result.worktree.path == $path and
    .terminal.result.terminal.handle == "term-smoke"
  ' "$BRIDGE_STDOUT" >/dev/null; then
  printf '  ✅ bridge JSON envelope contains worktree and terminal\n'
else
  printf '  ❌ bridge JSON envelope mismatch\n' >&2
  printf '%s\n' '--- bridge stdout ---' >&2
  while IFS= read -r line; do printf '%s\n' "$line" >&2; done < "$BRIDGE_STDOUT"
  exit 1
fi

if [ "$(grep -oF "$LOOPBACK_URL" "$FAKE_TERMINAL_COMMAND" | wc -l | tr -d ' ')" -eq 1 ] && \
   grep -Fx "ANTHROPIC_BASE_URL=$LOOPBACK_URL" "$FAKE_CLAUDE_LOG" >/dev/null; then
  printf '  ✅ GPT launch keeps loopback base URL exactly once\n'
else
  printf '  ❌ GPT loopback URL assertion failed\n' >&2
  exit 1
fi

if grep -Fx 'args: --model gpt-5.6-luna --prefill read only' "$FAKE_CLAUDE_LOG" >/dev/null && \
   grep -Fx 'CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1' "$FAKE_CLAUDE_LOG" >/dev/null; then
  printf '  ✅ fake Claude received literal GPT model and prefill\n'
else
  printf '  ❌ fake Claude argv/environment mismatch\n' >&2
  exit 1
fi

# Worker-start coverage uses the same fake Orca/Claude/nc seam. The fake Orca
# hands its launch command to the real launcher shim, then the fake Claude
# records the inherited model and proxy environment without a provider call.
jq -cn --arg transcript "$TRANSCRIPT" --arg worktree "$WORKTREE_PATH" --arg command \
  "orca orchestration worker-start --task task-1 --agent claude --worktree path:$WORKTREE_PATH --model claude-opus-5 --json" \
  '{tool_name:"Bash",tool_input:{command:$command},transcript_path:$transcript}' > "$WORKER_PAYLOAD"
PATH="$FAKE_BIN:$ORIGINAL_PATH" \
  bash "$ROOT/scripts/orca-model-inherit.sh" < "$WORKER_PAYLOAD" > "$WORKER_HOOK_JSON"

if jq -e --arg model 'gpt-5.6-luna' --arg bridge "$ROOT/scripts/orca-worktree-model-bridge.sh" --arg worktree "$WORKTREE_PATH" '
    .hookSpecificOutput.hookEventName == "PreToolUse" and
    (([39] | implode) as $quote |
     .hookSpecificOutput.updatedInput.command |
     startswith($quote + $bridge + $quote + " --model " + $quote + $model + $quote)) and
    (.hookSpecificOutput.updatedInput.command | contains("orchestration worker-start")) and
    (.hookSpecificOutput.updatedInput.command | contains("--task task-1")) and
    (.hookSpecificOutput.updatedInput.command | contains("--agent claude")) and
    (.hookSpecificOutput.updatedInput.command | contains("--worktree path:" + $worktree))
  ' "$WORKER_HOOK_JSON" >/dev/null; then
  printf '  ✅ hook rewrote worker-start command\n'
else
  printf '  ❌ worker-start hook rewrite assertion failed\n' >&2
  exit 1
fi

WORKER_REWRITTEN_COMMAND=$(jq -er '.hookSpecificOutput.updatedInput.command' "$WORKER_HOOK_JSON")
if ORCA_MODEL_BRIDGE_ORCA_BIN="$FAKE_ORCA" \
    PATH="$FAKE_BIN:$ORIGINAL_PATH" \
    bash -c "$WORKER_REWRITTEN_COMMAND" > "$WORKER_STDOUT" 2> "$WORKER_STDERR"; then
  printf '  ✅ bridge completed fake worker-start launch\n'
else
  printf '  ❌ worker-start bridge failed\n' >&2
  if [ -s "$WORKER_STDERR" ]; then
    printf '%s\n' '--- worker bridge stderr ---' >&2
    while IFS= read -r line; do printf '%s\n' "$line" >&2; done < "$WORKER_STDERR"
  fi
  exit 1
fi

cp "$CREATE_LOG" "$WORKER_EXPECTED_LOG"
printf 'CALL\norchestration\nworker-start\n--task\ntask-1\n--agent\nclaude\n--worktree\npath:%s\n--json\n--model\ngpt-5.6-luna\n' \
  "$WORKTREE_PATH" >> "$WORKER_EXPECTED_LOG"
if cmp -s "$WORKER_EXPECTED_LOG" "$FAKE_ORCA_LOG" && \
   ! grep -Fx 'claude-opus-5' "$FAKE_ORCA_LOG" >/dev/null; then
  printf '  ✅ worker-start preserved task/agent/current worktree and replaced model\n'
else
  printf '  ❌ worker-start fake Orca argv mismatch\n' >&2
  diff -u "$WORKER_EXPECTED_LOG" "$FAKE_ORCA_LOG" >&2 || true
  exit 1
fi

if jq -e '.result.worker.id == "worker-smoke" and .result.worker.status == "ready"' \
    "$WORKER_STDOUT" >/dev/null && \
   grep -F -- "$FAKE_LAUNCHER --model gpt-5.6-luna" "$FAKE_WORKER_LAUNCH_COMMAND" >/dev/null; then
  printf '  ✅ worker-start launch command reached claude-orca-launch.sh\n'
else
  printf '  ❌ worker-start launch command assertion failed\n' >&2
  exit 1
fi

if grep -Fx 'args: --model gpt-5.6-luna' "$FAKE_WORKER_CLAUDE_LOG" >/dev/null && \
   grep -Fx "ANTHROPIC_BASE_URL=$LOOPBACK_URL" "$FAKE_WORKER_CLAUDE_LOG" >/dev/null && \
   grep -Fx 'CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1' "$FAKE_WORKER_CLAUDE_LOG" >/dev/null; then
  printf '  ✅ worker-start inherited GPT model and loopback/disable environment\n'
else
  printf '  ❌ worker-start launcher argv/environment mismatch\n' >&2
  exit 1
fi

# Claude provider coverage is fixture-only: no Claude quota or network request.
if (
  unset ANTHROPIC_BASE_URL CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC
  ORCA_WORKTREE_ID='fixture-claude-direct' \
    CLAUDE_ORCA_REAL_BIN="$FAKE_CLAUDE" \
    PATH="$FAKE_BIN:$ORIGINAL_PATH" \
    bash "$ROOT/scripts/claude-orca-launch.sh" --model claude-opus-5
) && \
   grep -Fx 'args: --model claude-opus-5' "$FAKE_CLAUDE_LOG" >/dev/null && \
   grep -Fx 'ANTHROPIC_BASE_URL=<unset>' "$FAKE_CLAUDE_LOG" >/dev/null; then
  printf '  ✅ Claude fixture keeps direct Anthropic base URL absent\n'
else
  printf '  ❌ Claude direct-provider fixture mismatch\n' >&2
  exit 1
fi

if (
  unset CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC
  ANTHROPIC_BASE_URL="$LOOPBACK_URL" \
    ORCA_WORKTREE_ID='fixture-claude-loopback' \
    CLAUDE_ORCA_REAL_BIN="$FAKE_CLAUDE" \
    PATH="$FAKE_BIN:$ORIGINAL_PATH" \
    bash "$ROOT/scripts/claude-orca-launch.sh" --model claude-opus-5
) && \
   grep -Fx 'args: --model claude-opus-5' "$FAKE_CLAUDE_LOG" >/dev/null && \
   grep -Fx "ANTHROPIC_BASE_URL=$LOOPBACK_URL" "$FAKE_CLAUDE_LOG" >/dev/null; then
  printf '  ✅ Claude fixture preserves loopback parent base URL\n'
else
  printf '  ❌ Claude loopback-provider fixture mismatch\n' >&2
  exit 1
fi

if path_is_inside_smoke_root "$WORKTREE_PATH" && [ -d "$WORKTREE_PATH" ]; then
  TERMINAL_HANDLE='term-smoke'
  printf '  ✅ generated worktree is inside throwaway smoke root\n'
else
  printf '  ❌ generated worktree escaped smoke root\n' >&2
  exit 1
fi

printf '✅ Orca model inheritance mock smoke passed (%s)\n' "$SMOKE_ROOT"
