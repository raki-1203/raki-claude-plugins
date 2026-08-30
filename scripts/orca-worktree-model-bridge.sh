#!/bin/bash
set -u

noop() {
  exit 0
}

bridge_error() {
  printf 'orca model bridge: %s\n' "$1" >&2
  exit 1
}

# The hook puts the current model before the original Orca argv.
MODEL=''
while [ "$#" -gt 0 ]; do
  case "$1" in
    --model)
      [ "$#" -ge 2 ] || exit 1
      MODEL="$2"
      shift 2
      ;;
    --model=*)
      MODEL="${1#--model=}"
      shift
      ;;
    *)
      break
      ;;
  esac
done
[ -n "$MODEL" ] || exit 1

# Keep the optional [1m] suffix, but validate the provider and model ID.
MODEL_BASE="$MODEL"
case "$MODEL_BASE" in
  *'[1m]') MODEL_BASE="${MODEL_BASE%\[1m\]}" ;;
esac
case "$MODEL_BASE" in
  gpt-*|claude-*) ;;
  *) noop ;;
esac
case "$MODEL_BASE" in
  ''|*[!A-Za-z0-9._:-]*) noop ;;
esac

[ "$#" -ge 2 ] || noop
if [ "$1" = 'orchestration' ] && [ "$2" = 'worker-start' ]; then
  COMMAND_KIND='worker-start'
elif [ "$1" = 'worktree' ] && [ "$2" = 'create' ]; then
  COMMAND_KIND='worktree-create'
else
  noop
fi
shift 2

# A GPT launch is only safe while the local Codex proxy is listening.
case "$MODEL_BASE" in
  gpt-*)
    command -v nc >/dev/null 2>&1 || noop
    nc -z 127.0.0.1 18765 >/dev/null 2>&1 || noop
    ;;
esac

# Resolve the test seam only when it is set. Production uses command -v.
ORCA_BIN=''
resolve_orca() {
  if [ "${ORCA_MODEL_BRIDGE_ORCA_BIN+x}" = x ]; then
    [ -n "$ORCA_MODEL_BRIDGE_ORCA_BIN" ] || return 1
    ORCA_BIN="$ORCA_MODEL_BRIDGE_ORCA_BIN"
  else
    ORCA_BIN="$(command -v orca 2>/dev/null)" || return 1
  fi
  [ -n "$ORCA_BIN" ]
}

if [ "$COMMAND_KIND" = 'worker-start' ]; then
  INPUT_ARGS=("$@")
  OUTPUT_ARGS=()
  TOKEN_COUNT="${#INPUT_ARGS[@]}"
  AGENT_CLAUDE_COUNT=0
  AGENT_OTHER_COUNT=0
  TERMINAL_COUNT=0
  i=0

  while [ "$i" -lt "$TOKEN_COUNT" ]; do
    token="${INPUT_ARGS[$i]}"
    case "$token" in
      --agent)
        next=$((i + 1))
        [ "$next" -lt "$TOKEN_COUNT" ] || exit 1
        agent_value="${INPUT_ARGS[$next]}"
        if [ "$agent_value" = 'claude' ]; then
          AGENT_CLAUDE_COUNT=$((AGENT_CLAUDE_COUNT + 1))
        else
          AGENT_OTHER_COUNT=$((AGENT_OTHER_COUNT + 1))
        fi
        OUTPUT_ARGS+=("$token" "$agent_value")
        i=$((i + 2))
        ;;
      --agent=*)
        agent_value="${token#--agent=}"
        if [ "$agent_value" = 'claude' ]; then
          AGENT_CLAUDE_COUNT=$((AGENT_CLAUDE_COUNT + 1))
        else
          AGENT_OTHER_COUNT=$((AGENT_OTHER_COUNT + 1))
        fi
        OUTPUT_ARGS+=("$token")
        i=$((i + 1))
        ;;
      --terminal|--terminal=*)
        TERMINAL_COUNT=$((TERMINAL_COUNT + 1))
        OUTPUT_ARGS+=("$token")
        i=$((i + 1))
        ;;
      --model)
        next=$((i + 1))
        [ "$next" -lt "$TOKEN_COUNT" ] || exit 1
        i=$((i + 2))
        ;;
      --model=*)
        i=$((i + 1))
        ;;
      *)
        OUTPUT_ARGS+=("$token")
        i=$((i + 1))
        ;;
    esac
  done

  [ "$AGENT_CLAUDE_COUNT" -eq 1 ] || noop
  [ "$AGENT_OTHER_COUNT" -eq 0 ] || noop
  [ "$TERMINAL_COUNT" -eq 0 ] || noop
  OUTPUT_ARGS+=(--model "$MODEL")
  resolve_orca || bridge_error 'orca executable not found'
  exec "$ORCA_BIN" orchestration worker-start "${OUTPUT_ARGS[@]}"
fi

# Worktree creation is split into an Orca worktree call and a terminal call.
INPUT_ARGS=("$@")
CREATE_ARGS=(worktree create)
TOKEN_COUNT="${#INPUT_ARGS[@]}"
AGENT_CLAUDE_COUNT=0
AGENT_OTHER_COUNT=0
PROMPT_SET=0
PROMPT=''
JSON_REQUESTED=0
i=0

while [ "$i" -lt "$TOKEN_COUNT" ]; do
  token="${INPUT_ARGS[$i]}"
  case "$token" in
    --agent)
      next=$((i + 1))
      [ "$next" -lt "$TOKEN_COUNT" ] || exit 1
      agent_value="${INPUT_ARGS[$next]}"
      if [ "$agent_value" = 'claude' ]; then
        AGENT_CLAUDE_COUNT=$((AGENT_CLAUDE_COUNT + 1))
      else
        AGENT_OTHER_COUNT=$((AGENT_OTHER_COUNT + 1))
      fi
      i=$((i + 2))
      ;;
    --agent=*)
      agent_value="${token#--agent=}"
      if [ "$agent_value" = 'claude' ]; then
        AGENT_CLAUDE_COUNT=$((AGENT_CLAUDE_COUNT + 1))
      else
        AGENT_OTHER_COUNT=$((AGENT_OTHER_COUNT + 1))
      fi
      i=$((i + 1))
      ;;
    --prompt)
      next=$((i + 1))
      [ "$next" -lt "$TOKEN_COUNT" ] || exit 1
      PROMPT="${INPUT_ARGS[$next]}"
      PROMPT_SET=1
      i=$((i + 2))
      ;;
    --prompt=*)
      PROMPT="${token#--prompt=}"
      PROMPT_SET=1
      i=$((i + 1))
      ;;
    --model)
      next=$((i + 1))
      [ "$next" -lt "$TOKEN_COUNT" ] || exit 1
      i=$((i + 2))
      ;;
    --model=*)
      i=$((i + 1))
      ;;
    --json)
      JSON_REQUESTED=1
      i=$((i + 1))
      ;;
    *)
      CREATE_ARGS+=("$token")
      i=$((i + 1))
      ;;
  esac
done

[ "$AGENT_CLAUDE_COUNT" -eq 1 ] || noop
[ "$AGENT_OTHER_COUNT" -eq 0 ] || noop
CREATE_ARGS+=(--json)
resolve_orca || bridge_error 'orca executable not found'

if ! command -v jq >/dev/null 2>&1; then
  bridge_error 'jq executable not found'
fi

if ! CREATE_JSON=$("$ORCA_BIN" "${CREATE_ARGS[@]}"); then
  bridge_error 'worktree create failed'
fi

WORKTREE_PATH=$(
  printf '%s' "$CREATE_JSON" \
    | jq -er '.result.worktree.path // .worktree.path // empty' 2>/dev/null
) || bridge_error 'worktree create returned invalid JSON'

case "$WORKTREE_PATH" in
  /) bridge_error 'worktree path must not be root' ;;
  /*) ;;
  *) bridge_error 'worktree path must be absolute' ;;
esac

shell_quote() {
  local value="$1"
  local quote="'"
  local escaped="'\\''"
  value="${value//$quote/$escaped}"
  printf "'%s'" "$value"
}

MODEL_QUOTED="$(shell_quote "$MODEL")"
LAUNCH_COMMAND="claude --model $MODEL_QUOTED"
if [ "$PROMPT_SET" -eq 1 ]; then
  PROMPT_QUOTED="$(shell_quote "$PROMPT")"
  LAUNCH_COMMAND="$LAUNCH_COMMAND --prefill $PROMPT_QUOTED"
fi

LAUNCH_PREFIX=''
case "$MODEL_BASE" in
  gpt-*)
    LAUNCH_PREFIX='env ANTHROPIC_BASE_URL=http://127.0.0.1:18765 CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 '
    ;;
  claude-*)
    if [ "${ANTHROPIC_BASE_URL-}" = 'http://127.0.0.1:18765' ]; then
      LAUNCH_PREFIX='env ANTHROPIC_BASE_URL=http://127.0.0.1:18765 CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 '
    fi
    ;;
esac
LAUNCH_COMMAND="${LAUNCH_PREFIX}${LAUNCH_COMMAND}"

if ! TERMINAL_JSON=$("$ORCA_BIN" terminal create \
    --worktree "path:$WORKTREE_PATH" \
    --command "$LAUNCH_COMMAND" \
    --json
); then
  bridge_error 'terminal create failed; worktree was left in place'
fi

if ! printf '%s' "$TERMINAL_JSON" | jq -e . >/dev/null 2>&1; then
  bridge_error 'terminal create returned invalid JSON; worktree was left in place'
fi

if [ "$JSON_REQUESTED" -eq 1 ]; then
  jq -cn \
    --argjson worktree "$CREATE_JSON" \
    --argjson terminal "$TERMINAL_JSON" \
    '{worktree:$worktree,terminal:$terminal}'
else
  TERMINAL_HANDLE=$(
    printf '%s' "$TERMINAL_JSON" \
      | jq -er '.result.terminal.handle // .terminal.handle // empty' 2>/dev/null
  ) || bridge_error 'terminal create returned no handle'
  printf 'worktree: %s\nterminal: %s\n' "$WORKTREE_PATH" "$TERMINAL_HANDLE"
fi
