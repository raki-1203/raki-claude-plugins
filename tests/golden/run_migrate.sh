#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP=$(mktemp -d)
trap "rm -rf $TMP" EXIT

cp -R "$SCRIPT_DIR/tests/fixtures/vault-v2-sample/." "$TMP/"

export RAKIS_MIGRATION_DATE=2026-04-17
uv run python3 "$SCRIPT_DIR/scripts/migrate_v3.py" "$TMP"

# 비교: 날짜 플레이스홀더 치환
EXPECTED=$(mktemp -d)
trap "rm -rf $TMP $EXPECTED" EXIT
cp -R "$SCRIPT_DIR/tests/fixtures/vault-v3-expected/." "$EXPECTED/"
find "$EXPECTED" -type f -exec sed -i.bak "s/MIGRATION_DATE/2026-04-17/g" {} \;
find "$EXPECTED" -name "*.bak" -delete

# diff (marker 파일은 무시)
if diff -r --exclude=".rakis-v3-migrated" "$TMP" "$EXPECTED"; then
  echo "✅ golden diff empty"
  exit 0
else
  echo "❌ golden diff above"
  exit 1
fi
