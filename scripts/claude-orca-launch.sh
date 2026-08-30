#!/bin/bash
set -u

ORIGINAL_ARGS=("$@")

if [ -n "${CLAUDE_ORCA_REAL_BIN-}" ]; then
  REAL_CLAUDE="$CLAUDE_ORCA_REAL_BIN"
else
  REAL_CLAUDE="$(command -v claude 2>/dev/null)"
fi
[ -n "$REAL_CLAUDE" ] || exit 127

MODEL=''
ARG_COUNT="${#ORIGINAL_ARGS[@]}"
i=0
while [ "$i" -lt "$ARG_COUNT" ]; do
  token="${ORIGINAL_ARGS[$i]}"
  case "$token" in
    --model)
      next=$((i + 1))
      if [ "$next" -lt "$ARG_COUNT" ]; then
        MODEL="${ORIGINAL_ARGS[$next]}"
        i=$((i + 2))
      else
        i=$((i + 1))
      fi
      ;;
    --model=*)
      MODEL="${token#--model=}"
      i=$((i + 1))
      ;;
    *)
      i=$((i + 1))
      ;;
  esac
done

if [ -n "${ORCA_AGENT_LAUNCH_TOKEN-}" ] || [ -n "${ORCA_WORKTREE_ID-}" ]; then
  MODEL_FAMILY="$MODEL"
  case "$MODEL_FAMILY" in
    *'[1m]') MODEL_FAMILY="${MODEL_FAMILY%\[1m\]}" ;;
  esac

  case "$MODEL_FAMILY" in
    gpt-*)
      if command -v nc >/dev/null 2>&1 && nc -z 127.0.0.1 18765 >/dev/null 2>&1; then
        ANTHROPIC_BASE_URL='http://127.0.0.1:18765' \
        CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 \
          exec "$REAL_CLAUDE" "${ORIGINAL_ARGS[@]}"
      fi
      ;;
  esac
fi

exec "$REAL_CLAUDE" "${ORIGINAL_ARGS[@]}"
