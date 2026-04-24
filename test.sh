#!/bin/bash
# rakis plugin — 스킬 기능 통합 테스트
# 실제 외부 서비스(NotebookLM, Obsidian MCP, GitHub, repomix, graphify)를 호출하여 검증
#
# Usage:
#   ./test.sh              # 전체 테스트
#   ./test.sh source       # source-analyze만
#   ./test.sh wiki         # wiki 스킬만
#   ./test.sh graphify     # graphify CLI만
#   ./test.sh deps         # 의존성 확인만

set -euo pipefail

PASS=0
FAIL=0
SKIP=0

pass() { PASS=$((PASS + 1)); echo "  ✅ $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  ❌ $1"; }
skip() { SKIP=$((SKIP + 1)); echo "  ⏭️  $1"; }

TARGET="${1:-all}"

# ─── 의존성 확인 ───

test_deps() {
  echo "📋 의존성 확인"

  # notebooklm CLI
  if command -v notebooklm &>/dev/null; then
    pass "notebooklm CLI 설치됨 ($(notebooklm --help 2>&1 | head -1 || echo 'OK'))"
  else
    fail "notebooklm CLI 미설치 — uv tool install notebooklm-py --with playwright"
  fi

  # notebooklm 인증
  if notebooklm auth check --test 2>&1 | grep -q "Authentication is valid"; then
    pass "notebooklm 인증 유효"
  else
    fail "notebooklm 인증 만료 — notebooklm login 필요"
  fi

  # gh CLI
  if gh auth status 2>&1 | grep -q "Logged in"; then
    pass "gh CLI 인증됨"
  else
    fail "gh CLI 미인증"
  fi

  # repomix
  if command -v npx &>/dev/null; then
    pass "npx 사용 가능 (repomix용)"
  else
    fail "npx 미설치"
  fi

  # graphify
  if command -v graphify &>/dev/null; then
    pass "graphify CLI 설치됨"
  else
    fail "graphify 미설치 — uv tool install graphifyy --python 3.13 (또는 /rakis:setup 으로 일괄 설치)"
  fi

  echo ""
}

# ─── source-analyze 테스트 ───

test_source_analyze() {
  echo "🔬 source-analyze 스킬 테스트"

  # 1. repomix: 소규모 repo 변환
  echo "  [repomix]"
  REPOMIX_OUT="/tmp/test-repomix-output.txt"
  rm -f "$REPOMIX_OUT"
  REPOMIX_RESULT=$(npx repomix --remote raki-1203/raki-claude-plugins --output "$REPOMIX_OUT" 2>&1 || true)
  if echo "$REPOMIX_RESULT" | grep -q "All Done"; then
    if [ -f "$REPOMIX_OUT" ] && [ "$(wc -c < "$REPOMIX_OUT")" -gt 1000 ]; then
      pass "repomix 변환 성공 ($(wc -c < "$REPOMIX_OUT" | tr -d ' ') bytes)"
    else
      fail "repomix 출력 파일이 비정상"
    fi
  else
    fail "repomix 실행 실패"
  fi

  # 2. NotebookLM: 노트북 생성 → 소스 추가 → 질의 → 삭제
  echo "  [NotebookLM]"
  if ! command -v notebooklm &>/dev/null; then
    skip "notebooklm 미설치 — NotebookLM 테스트 건너뜀"
  else
    # 생성
    NB_OUTPUT=$(notebooklm create "테스트 노트북 $(date +%s)" 2>&1)
    NB_ID=$(echo "$NB_OUTPUT" | grep -oE '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}')
    if [ -n "$NB_ID" ]; then
      pass "노트북 생성: $NB_ID"
    else
      fail "노트북 생성 실패: $NB_OUTPUT"
      echo ""
      return
    fi

    # 소스 추가 (URL)
    notebooklm use "$NB_ID" &>/dev/null
    if notebooklm source add "https://github.com/raki-1203/raki-claude-plugins" 2>&1 | grep -q "Added source"; then
      pass "URL 소스 추가 성공"
    else
      fail "URL 소스 추가 실패"
    fi

    # 소스 추가 (텍스트)
    if [ -f "$REPOMIX_OUT" ]; then
      if notebooklm source add "$REPOMIX_OUT" 2>&1 | grep -q "Added source"; then
        pass "텍스트 소스 추가 성공"
      else
        fail "텍스트 소스 추가 실패"
      fi
    fi

    # 질의
    ASK_RESULT=$(notebooklm ask "이 프로젝트가 뭔지 한 줄로 설명해줘" 2>&1)
    if echo "$ASK_RESULT" | grep -q "Answer:"; then
      pass "NotebookLM 질의 성공"
    else
      fail "NotebookLM 질의 실패: $ASK_RESULT"
    fi

    # 요약
    SUMMARY_RESULT=$(notebooklm summary 2>&1 || true)
    if echo "$SUMMARY_RESULT" | grep -q "Summary:"; then
      pass "NotebookLM 요약 수집 성공"
    else
      fail "NotebookLM 요약 실패"
    fi

    # 리포트 생성
    REPORT_RESULT=$(notebooklm generate report --format study-guide --wait 2>&1 || true)
    if echo "$REPORT_RESULT" | grep -q "ready\|Study Guide"; then
      pass "NotebookLM 리포트 생성 성공"
    else
      fail "NotebookLM 리포트 생성 실패"
    fi

    # 마인드맵 생성
    MINDMAP_RESULT=$(notebooklm generate mind-map 2>&1 || true)
    if echo "$MINDMAP_RESULT" | grep -q "Mind map generated"; then
      pass "NotebookLM 마인드맵 생성 성공"
    else
      fail "NotebookLM 마인드맵 생성 실패"
    fi

    # 삭제 (정리)
    DELETE_RESULT=$(notebooklm delete -n "$NB_ID" -y 2>&1 || true)
    if echo "$DELETE_RESULT" | grep -q "Deleted"; then
      pass "테스트 노트북 삭제 완료"
    else
      fail "테스트 노트북 삭제 실패 — 수동 정리 필요: $NB_ID"
    fi
  fi

  # 3. gh CLI: repo 정보 수집
  echo "  [GitHub]"
  if gh repo view raki-1203/raki-claude-plugins --json stargazerCount 2>&1 | grep -q "stargazerCount"; then
    pass "gh repo view 성공"
  else
    fail "gh repo view 실패"
  fi

  # 정리
  rm -f "$REPOMIX_OUT"

  echo ""
}

# ─── wiki 스킬 테스트 ───

test_wiki() {
  echo "🔬 wiki 스킬 테스트 (ingest/query/lint)"

  if [ -z "$OBSIDIAN_VAULT_PATH" ]; then
    fail "OBSIDIAN_VAULT_PATH 환경변수가 설정되지 않았습니다. ~/.zshrc 에 export OBSIDIAN_VAULT_PATH=\"\$HOME/path/to/your/Vault\" 추가 후 source ~/.zshrc"
    return 1
  fi
  VAULT="$OBSIDIAN_VAULT_PATH"

  # Vault 접근 확인
  if [ -d "$VAULT" ]; then
    pass "Vault 접근 가능: $VAULT"
  else
    fail "Vault 접근 불가: $VAULT"
    echo ""
    return
  fi

  # index.md 존재
  if [ -f "$VAULT/index.md" ]; then
    pass "index.md 존재"
  else
    fail "index.md 없음"
  fi

  # log.md 존재
  if [ -f "$VAULT/log.md" ]; then
    pass "log.md 존재"
  else
    fail "log.md 없음"
  fi

  # wiki/ 디렉토리 구조
  for dir in wiki/concepts wiki/entities wiki/sources; do
    if [ -d "$VAULT/$dir" ]; then
      COUNT=$(ls "$VAULT/$dir/"*.md 2>/dev/null | wc -l | tr -d ' ')
      pass "$dir/ 존재 (${COUNT}개 페이지)"
    else
      fail "$dir/ 없음"
    fi
  done

  # raw/ 디렉토리 구조
  if [ -d "$VAULT/raw" ]; then
    pass "raw/ 존재"
  else
    fail "raw/ 없음"
  fi

  # wiki 페이지 frontmatter 검증 (전체)
  echo "  [frontmatter 검증]"
  FAIL_FM=0
  PASS_FM=0
  while IFS= read -r wf; do
    fname=$(basename "$wf")
    if head -1 "$wf" | grep -q "^---"; then
      if grep -q "^title:" "$wf" && grep -q "^type:" "$wf"; then
        PASS_FM=$((PASS_FM + 1))
      else
        fail "$fname: title 또는 type 누락"
        FAIL_FM=$((FAIL_FM + 1))
      fi
    else
      fail "$fname: frontmatter 없음"
      FAIL_FM=$((FAIL_FM + 1))
    fi
  done < <(find "$VAULT/wiki" -name "*.md" -type f 2>/dev/null)
  if [ "$FAIL_FM" -eq 0 ]; then
    pass "전체 wiki 페이지 frontmatter OK (${PASS_FM}개)"
  fi

  # index.md에 wiki/sources 페이지가 등록되어 있는지
  echo "  [index.md 일관성]"
  IDX_FAIL=0
  while IFS= read -r sp; do
    PAGE_NAME=$(basename "$sp" .md)
    if ! grep -q "$PAGE_NAME" "$VAULT/index.md"; then
      fail "index.md에 [[$PAGE_NAME]] 미등록"
      ((IDX_FAIL++))
    fi
  done < <(find "$VAULT/wiki/sources" -name "*.md" -type f 2>/dev/null)
  if [ "$IDX_FAIL" -eq 0 ]; then
    pass "index.md에 모든 sources 페이지 등록됨"
  fi

  echo ""
}

# ─── graphify CLI 테스트 ───

test_graphify() {
  echo "🔬 graphify CLI 테스트"

  if ! command -v graphify &>/dev/null; then
    skip "graphify 미설치 — 전체 건너뜀"
    echo ""
    return
  fi

  # graphify CLI 동작
  if graphify --help 2>&1 | grep -q "Commands:"; then
    pass "graphify CLI 동작"
  else
    fail "graphify CLI 오류"
  fi

  # hook install/status/uninstall (현재 프로젝트에서)
  if graphify hook install 2>&1 | grep -q "installed"; then
    pass "graphify hook install 성공"
  else
    fail "graphify hook install 실패"
  fi

  if graphify hook status 2>&1 | grep -q "installed"; then
    pass "graphify hook status 확인"
  else
    fail "graphify hook status 실패"
  fi

  if graphify hook uninstall 2>&1 | grep -q "removed"; then
    pass "graphify hook uninstall 성공"
  else
    fail "graphify hook uninstall 실패"
  fi

  echo ""
}

# ─── 실행 ───

echo "=== rakis plugin 통합 테스트 ==="
echo "대상: $TARGET"
echo ""

case "$TARGET" in
  all)
    test_deps
    test_source_analyze
    test_wiki
    test_graphify
    ;;
  deps)
    test_deps
    ;;
  source)
    test_deps
    test_source_analyze
    ;;
  wiki)
    test_wiki
    ;;
  graphify)
    test_graphify
    ;;
  smoke)
    ;;
  v3)
    ;;
  *)
    echo "Usage: ./test.sh [all|deps|source|wiki|graphify|smoke|v3]"
    exit 1
    ;;
esac

# ─── v3 단절 검증 ───
if [ "$TARGET" = "all" ] || [ "$TARGET" = "v3" ]; then
  echo ""
  echo "🔎 v3 단절 검증"
  if [ -d skills/source-analyze ]; then
    fail "source-analyze 스킬이 남아있음 — v3에서는 제거되어야 함"
  else
    pass "source-analyze 제거됨"
  fi
  for s in source-fetch migrate-v3; do
    if [ -d "skills/$s" ]; then
      pass "v3 스킬 존재: $s"
    else
      fail "v3 스킬 누락: $s"
    fi
  done
fi

# ─── v3 smoke E2E ───
if [ "$TARGET" = "all" ] || [ "$TARGET" = "smoke" ]; then
  echo ""
  echo "🧪 v3 Smoke E2E"
  if bash tests/e2e/smoke.sh >/dev/null; then
    pass "smoke E2E"
  else
    fail "smoke E2E — bash tests/e2e/smoke.sh"
  fi
fi

# ─── 결과 ───

echo "=== 결과 ==="
echo "  ✅ PASS: $PASS"
echo "  ❌ FAIL: $FAIL"
echo "  ⏭️  SKIP: $SKIP"
echo ""

if [ "$FAIL" -gt 0 ]; then
  echo "❌ 테스트 실패"
  exit 1
else
  echo "✅ 모든 테스트 통과"
  exit 0
fi
