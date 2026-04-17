#!/bin/bash
# tests/e2e/smoke.sh — v3 파이프라인 스모크 E2E
# 실제 wiki-ingest · wiki-query 스킬을 Claude가 실행하는 대신,
# 스킬이 내부적으로 호출할 스크립트(slug/frontmatter/migrate)와 파일 I/O만 검증한다.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP_VAULT=$(mktemp -d)
trap "rm -rf $TMP_VAULT" EXIT

# 1. v3 초기 볼트 셋업
mkdir -p "$TMP_VAULT"/{raw/articles,wiki/sources,wiki/concepts,wiki/projects,outputs}
cat > "$TMP_VAULT/CLAUDE.md" <<'EOF'
# Three-Layer Schema
raw/ wiki/ outputs/
EOF
cat > "$TMP_VAULT/log.md" <<'EOF'
# Log
EOF
cat > "$TMP_VAULT/index.md" <<'EOF'
# Index
## sources
EOF
touch "$TMP_VAULT/.rakis-v3-migrated"

# 2. source-fetch 시뮬레이션 — 로컬 파일 → raw/articles/sample-article/
SLUG=$("$SCRIPT_DIR/scripts/slug.sh" "sample-article.md")
SRC_DIR="$TMP_VAULT/raw/articles/$SLUG"
mkdir -p "$SRC_DIR"
cp "$SCRIPT_DIR/tests/fixtures/sample-article.md" "$SRC_DIR/source.md"
SIZE=$(wc -c < "$SRC_DIR/source.md" | tr -d ' ')
cat > "$SRC_DIR/meta.json" <<EOF
{"type":"article","source_url":"","captured_at":"2026-04-17","contributor":"raki-1203","slug":"$SLUG","size_bytes":$SIZE,"source_file":"source.md"}
EOF

# 3. wiki-ingest 시뮬레이션 — 미처리 소스를 wiki/sources/{slug}.md로 컴파일
WIKI="$TMP_VAULT/wiki/sources/$SLUG.md"
cat > "$WIKI" <<EOF
---
title: "Sample Article"
type: source-summary
sources: ["[[raw/articles/$SLUG]]"]
related: []
created: 2026-04-17
updated: 2026-04-17
description: "sample-topic 테스트 픽스처"
---

## 요약
sample-topic 소개.

## 원본
[[raw/articles/$SLUG/source]]
EOF

# 4. frontmatter 검증
if ! uv run python3 "$SCRIPT_DIR/scripts/frontmatter.py" validate "$WIKI"; then
  echo "❌ frontmatter invalid"
  exit 1
fi

# 5. assertions
[ -f "$SRC_DIR/source.md" ] || { echo "❌ raw/source.md 없음"; exit 1; }
[ -f "$SRC_DIR/meta.json" ] || { echo "❌ raw/meta.json 없음"; exit 1; }
[ -f "$WIKI" ] || { echo "❌ wiki/sources/{slug}.md 없음"; exit 1; }
grep -q "sample-topic" "$WIKI" || { echo "❌ wiki 내용 검증 실패"; exit 1; }
grep -q "^type: source-summary$" "$WIKI" || { echo "❌ type enum 검증 실패"; exit 1; }
grep -q "confidence:" "$WIKI" && { echo "❌ confidence 필드 잔존"; exit 1; } || true

echo "✅ smoke E2E 통과 ($TMP_VAULT)"
