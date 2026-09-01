#!/bin/bash
set -u

ORIGINAL_ARGS=("$@")

if [ -n "${CLAUDE_ORCA_REAL_BIN-}" ]; then
  REAL_CLAUDE="$CLAUDE_ORCA_REAL_BIN"
else
  REAL_CLAUDE="$(command -v claude 2>/dev/null)"
fi
[ -n "$REAL_CLAUDE" ] || exit 127

exec "$REAL_CLAUDE" "${ORIGINAL_ARGS[@]}"
