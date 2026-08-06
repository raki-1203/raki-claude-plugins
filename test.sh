#!/bin/bash
# rakis plugin — 스킬 기능 통합 테스트
# 실제 외부 서비스(NotebookLM, Obsidian MCP, GitHub, repomix)를 호출하여 검증
#
# Usage:
#   ./test.sh              # 전체 테스트
#   ./test.sh source       # source-fetch enrich 계약만
#   ./test.sh wiki         # wiki 스킬만
#   ./test.sh deps         # 의존성 확인만

set -euo pipefail

# 사내망 TLS 가로채기 대응 — enrich.md 사전 조건과 동일 규칙
[ -f "$HOME/.config/rakis/corp-ca-bundle.pem" ] && \
  export SSL_CERT_FILE="$HOME/.config/rakis/corp-ca-bundle.pem"

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

  # notebooklm 인증 — 외부 서비스 상태이므로 실패해도 게이트를 막지 않는다(skip).
  # 이 CLI는 SSL·네트워크 오류까지 "쿠키 만료"로 안내하므로 문구를 믿지 말 것.
  if notebooklm auth check --test 2>&1 | grep -q "Authentication is valid"; then
    pass "notebooklm 인증 유효"
  else
    skip "notebooklm 인증/네트워크 불가 — NotebookLM 테스트 건너뜀 (notebooklm login 또는 사내망 CA 번들 확인)"
  fi

  # gh CLI — 위와 같은 이유로 skip
  if gh auth status 2>&1 | grep -q "Logged in"; then
    pass "gh CLI 인증됨"
  else
    skip "gh CLI 미인증/네트워크 불가"
  fi

  # repomix
  if command -v npx &>/dev/null; then
    pass "npx 사용 가능 (repomix용)"
  else
    fail "npx 미설치"
  fi

  echo ""
}

# ─── source-fetch enrich 계약 테스트 ───
#
# enrich.md의 실행 순서를 그대로 밟는다. 특히 `source add` → `source wait` →
# `generate` 순서를 검증한다 — 이 대기 단계가 빠져 있어 enrich가 항상
# "Report generation is unavailable"로 죽었다 (v3.13.1에서 수정).

test_source_fetch() {
  echo "🔬 source-fetch enrich 계약 테스트"

  # 1. repomix: 소규모 repo 변환
  echo "  [repomix]"
  # macOS의 /tmp 는 /private/tmp 심볼릭 링크다. notebooklm-py 0.7.3부터 심볼릭 링크
  # 경로 업로드를 기본 거부하므로("Path is a symlink; pass --follow-symlinks"),
  # 실경로를 써야 source add 가 통과한다.
  TMPROOT=$(cd /tmp && pwd -P)
  REPOMIX_OUT="$TMPROOT/test-repomix-output.txt"
  rm -f "$REPOMIX_OUT"
  REPOMIX_RESULT=$(npx repomix --remote raki-1203/raki-claude-plugins --output "$REPOMIX_OUT" 2>&1 || true)
  if echo "$REPOMIX_RESULT" | grep -q "All Done"; then
    if [ -f "$REPOMIX_OUT" ] && [ "$(wc -c < "$REPOMIX_OUT")" -gt 1000 ]; then
      pass "repomix 변환 성공 ($(wc -c < "$REPOMIX_OUT" | tr -d ' ') bytes)"
    else
      fail "repomix 출력 파일이 비정상"
    fi
  else
    # 원격 repo 클론이 필요하므로 네트워크·프록시에 막히면 여기서 걸린다.
    # 스킬 계약의 문제가 아니라 환경 문제이므로 게이트를 막지 않는다.
    skip "repomix 실행 실패 — 네트워크/프록시 확인"
  fi

  # 2. NotebookLM enrich 계약: 생성 → add → wait → generate → download → 삭제
  echo "  [NotebookLM enrich]"
  if ! command -v notebooklm &>/dev/null; then
    skip "notebooklm 미설치 — enrich 테스트 건너뜀"
  elif ! notebooklm auth check --test 2>&1 | grep -q "Authentication is valid"; then
    skip "notebooklm 인증/네트워크 불가 — enrich 테스트 건너뜀"
  else
    NB_ID=$(notebooklm create "rakis-test-$(date +%s)" --json 2>/dev/null | jq -r '.notebook.id' || true)
    if [ -n "$NB_ID" ] && [ "$NB_ID" != "null" ]; then
      pass "노트북 생성: $NB_ID"

      # repomix 가 네트워크로 skip 됐어도 enrich 계약은 독립적으로 검증한다
      ENRICH_SRC="$REPOMIX_OUT"
      if [ ! -s "$ENRICH_SRC" ]; then
        ENRICH_SRC="$TMPROOT/test-enrich-source.md"
        printf '# rakis enrich 계약 테스트\n\n%s\n' \
          "source add → source wait → generate 순서를 검증하기 위한 더미 소스." > "$ENRICH_SRC"
      fi

      # enrich.md와 동일하게 --json 으로 source id 를 받는다
      SID=$(notebooklm source add "$ENRICH_SRC" -n "$NB_ID" --json 2>/dev/null | jq -r '.source.id' || true)
      if [ -n "$SID" ] && [ "$SID" != "null" ]; then
        pass "소스 추가 (.source.id 계약 유지): $SID"

        # 핵심 회귀 방지: 이 대기가 없으면 아래 generate 가 반드시 실패한다
        if notebooklm source wait "$SID" -n "$NB_ID" --timeout 300 >/dev/null 2>&1; then
          pass "source wait — 소스 ready"
        else
          fail "source wait 실패/타임아웃"
        fi

        if notebooklm generate report --format briefing-doc --wait -n "$NB_ID" 2>&1 | grep -q "ready"; then
          pass "briefing 생성 성공"
          BRIEF_OUT="$TMPROOT/test-briefing.md"
          rm -f "$BRIEF_OUT"
          if notebooklm download report --latest -n "$NB_ID" "$BRIEF_OUT" --force >/dev/null 2>&1 \
             && [ -s "$BRIEF_OUT" ]; then
            pass "briefing 다운로드 성공 ($(wc -c < "$BRIEF_OUT" | tr -d ' ') bytes)"
          else
            fail "briefing 다운로드 실패"
          fi
          rm -f "$BRIEF_OUT"
        else
          fail "briefing 생성 실패 — source wait 누락 시 'Report generation is unavailable'"
        fi
      else
        fail "소스 추가 실패 (--json 의 .source.id 계약 확인 필요)"
      fi

      # 정리 — 실패해도 노트북이 고아로 남지 않게 항상 시도
      if notebooklm delete -n "$NB_ID" -y 2>&1 | grep -q "Deleted"; then
        pass "테스트 노트북 삭제 완료"
      else
        fail "테스트 노트북 삭제 실패 — 수동 정리 필요: $NB_ID"
      fi
    else
      skip "노트북 생성 불가 — 네트워크/인증 확인"
    fi
  fi

  # 3. gh CLI: repo 정보 수집 (네트워크 의존 — 실패해도 게이트를 막지 않음)
  echo "  [GitHub]"
  if ! gh auth status 2>&1 | grep -q "Logged in"; then
    skip "gh 미인증 — repo view 건너뜀"
  elif gh repo view raki-1203/raki-claude-plugins --json stargazerCount 2>&1 | grep -q "stargazerCount"; then
    pass "gh repo view 성공"
  else
    skip "gh repo view 실패 — 네트워크 확인"
  fi

  # 정리
  rm -f "$REPOMIX_OUT" "$TMPROOT/test-enrich-source.md"

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
    # 외부 배포용 파일은 frontmatter를 일부러 뺀다 (Confluence 등에 그대로 붙여넣는 산출물).
    # 위키 내부 규약을 강요하면 붙여넣을 때 지워야 할 잡음이 된다.
  done < <(find "$VAULT/wiki" -name "*.md" -type f -not -name "CONFLUENCE-*" 2>/dev/null)
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

# ─── 실행 ───

echo "=== rakis plugin 통합 테스트 ==="
echo "대상: $TARGET"
echo ""

case "$TARGET" in
  all)
    test_deps
    test_source_fetch
    test_wiki
    ;;
  deps)
    test_deps
    ;;
  source)
    test_deps
    test_source_fetch
    ;;
  wiki)
    test_wiki
    ;;
  smoke)
    ;;
  v3)
    ;;
  *)
    echo "Usage: ./test.sh [all|deps|source|wiki|smoke|v3]"
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
