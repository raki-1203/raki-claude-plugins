#!/bin/bash
# rakis plugin skill tests
# Usage: ./test.sh

set -euo pipefail

PASS=0
FAIL=0
WARN=0

pass() { ((PASS++)); echo "  ✅ $1"; }
fail() { ((FAIL++)); echo "  ❌ $1"; }
warn() { ((WARN++)); echo "  ⚠️  $1"; }

echo "=== rakis plugin skill tests ==="
echo ""

# ─── 1. 플러그인 메타데이터 검증 ───

echo "📦 플러그인 메타데이터"

# plugin.json 존재
if [ -f .claude-plugin/plugin.json ]; then
  pass "plugin.json 존재"
else
  fail "plugin.json 없음"
fi

# package.json 존재
if [ -f package.json ]; then
  pass "package.json 존재"
else
  fail "package.json 없음"
fi

# 버전 일치
if [ -f .claude-plugin/plugin.json ] && [ -f package.json ]; then
  V_PLUGIN=$(grep '"version"' .claude-plugin/plugin.json | head -1 | sed 's/.*: *"\(.*\)".*/\1/')
  V_PACKAGE=$(grep '"version"' package.json | head -1 | sed 's/.*: *"\(.*\)".*/\1/')
  if [ "$V_PLUGIN" = "$V_PACKAGE" ]; then
    pass "버전 일치: $V_PLUGIN"
  else
    fail "버전 불일치: plugin.json=$V_PLUGIN, package.json=$V_PACKAGE"
  fi
fi

echo ""

# ─── 2. 스킬별 검증 ───

for skill_dir in skills/*/; do
  skill_name=$(basename "$skill_dir")
  echo "🔧 스킬: $skill_name"

  SKILL_FILE="$skill_dir/SKILL.md"

  # SKILL.md 존재
  if [ ! -f "$SKILL_FILE" ]; then
    fail "SKILL.md 없음"
    echo ""
    continue
  fi
  pass "SKILL.md 존재"

  # frontmatter: name 필드
  if grep -q "^name:" "$SKILL_FILE"; then
    FM_NAME=$(grep "^name:" "$SKILL_FILE" | head -1 | sed 's/name: *//')
    if [ "$FM_NAME" = "$skill_name" ]; then
      pass "name 일치: $FM_NAME"
    else
      fail "name 불일치: frontmatter=$FM_NAME, 디렉토리=$skill_name"
    fi
  else
    fail "frontmatter name 누락"
  fi

  # frontmatter: description 필드
  if grep -q "^description:" "$SKILL_FILE"; then
    DESC=$(grep "^description:" "$SKILL_FILE" | head -1)
    DESC_LEN=${#DESC}
    if [ "$DESC_LEN" -gt 50 ]; then
      pass "description 존재 (${DESC_LEN}자)"
    else
      warn "description이 너무 짧음 (${DESC_LEN}자) — pushy하게 작성 필요"
    fi
  else
    fail "frontmatter description 누락"
  fi

  # 라인 수 제한 (500줄)
  LINE_COUNT=$(wc -l < "$SKILL_FILE" | tr -d ' ')
  if [ "$LINE_COUNT" -le 500 ]; then
    pass "라인 수: ${LINE_COUNT}/500"
  else
    fail "라인 수 초과: ${LINE_COUNT}/500"
  fi

  # references/ 참조 일관성
  if [ -d "${skill_dir}references" ]; then
    REF_COUNT=$(ls "${skill_dir}references/"*.md 2>/dev/null | wc -l | tr -d ' ')
    pass "references/ 존재 (${REF_COUNT}개 파일)"

    # SKILL.md에서 references/ 언급하는 파일이 실제로 존재하는지
    MISSING_REFS=""
    while IFS= read -r ref_mention; do
      ref_file="${skill_dir}references/${ref_mention}"
      if [ ! -f "$ref_file" ]; then
        MISSING_REFS="$MISSING_REFS $ref_mention"
      fi
    done < <(grep -oP 'references/\K[a-z0-9_-]+\.md' "$SKILL_FILE" 2>/dev/null | sort -u)

    if [ -z "$MISSING_REFS" ]; then
      pass "references 참조 일관성 OK"
    else
      fail "참조하지만 없는 파일:$MISSING_REFS"
    fi

    # references/ 파일 중 SKILL.md에서 언급되지 않는 파일
    ORPHAN_REFS=""
    for ref_file in "${skill_dir}references/"*.md; do
      ref_basename=$(basename "$ref_file")
      if ! grep -q "$ref_basename" "$SKILL_FILE" 2>/dev/null; then
        ORPHAN_REFS="$ORPHAN_REFS $ref_basename"
      fi
    done

    if [ -z "$ORPHAN_REFS" ]; then
      pass "고아 references 없음"
    else
      warn "SKILL.md에서 언급 안 되는 references:$ORPHAN_REFS"
    fi
  fi

  echo ""
done

# ─── 3. 스킬 간 트리거 충돌 검사 ───

echo "🔍 트리거 충돌 검사"

# 각 스킬의 description에서 트리거 키워드 추출하여 중복 확인
TRIGGER_FILE=$(mktemp)
for skill_dir in skills/*/; do
  skill_name=$(basename "$skill_dir")
  SKILL_FILE="$skill_dir/SKILL.md"
  [ -f "$SKILL_FILE" ] || continue

  # description에서 한국어 키워드 추출
  DESC=$(grep "^description:" "$SKILL_FILE" | head -1)
  echo "$skill_name: $DESC" >> "$TRIGGER_FILE"
done

# source-analyze와 wiki-ingest의 '정리해줘' 충돌 등 수동 체크 안내
CONFLICT_FOUND=false
if grep -l "분석" skills/*/SKILL.md 2>/dev/null | wc -l | grep -q "^[2-9]"; then
  warn "'분석' 키워드가 여러 스킬에 존재 — 트리거 충돌 가능성 확인 필요"
  CONFLICT_FOUND=true
fi
if grep -l "정리" skills/*/SKILL.md 2>/dev/null | wc -l | grep -q "^[2-9]"; then
  warn "'정리' 키워드가 여러 스킬에 존재 — 트리거 충돌 가능성 확인 필요"
  CONFLICT_FOUND=true
fi

if [ "$CONFLICT_FOUND" = false ]; then
  pass "명확한 트리거 충돌 없음"
fi

rm -f "$TRIGGER_FILE"

echo ""

# ─── 결과 요약 ───

echo "=== 결과 ==="
echo "  ✅ PASS: $PASS"
echo "  ❌ FAIL: $FAIL"
echo "  ⚠️  WARN: $WARN"
echo ""

if [ "$FAIL" -gt 0 ]; then
  echo "❌ 테스트 실패"
  exit 1
else
  echo "✅ 모든 테스트 통과"
  exit 0
fi
