#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ROUTER="$ROOT/scripts/task-router.sh"
PROMPTS_FILE="$ROOT/references/task-router-prompts.json"

PASS=0
FAIL=0
pass() { PASS=$((PASS + 1)); echo "  ✅ $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  ❌ $1${2:+ — $2}"; }

run_router() {
  printf '%s' "$1" | bash "$ROUTER"
}

assert_selected() {
  local name="$1" input="$2" needle="$3" out
  if [ ! -f "$ROUTER" ]; then
    fail "$name" "router script 없음"
    return
  fi
  if ! out=$(run_router "$input"); then
    fail "$name" "router가 non-zero로 종료"
    return
  fi
  if printf '%s' "$out" | jq -e --arg needle "$needle" '
      .hookSpecificOutput.hookEventName == "UserPromptSubmit" and
      (.hookSpecificOutput.additionalContext | contains($needle))
    ' >/dev/null 2>&1; then
    pass "$name"
  else
    fail "$name" "선택 prompt 또는 출력 계약 불일치"
  fi
}

assert_empty() {
  local name="$1" input="$2" out
  if ! out=$(run_router "$input"); then
    fail "$name" "no-op이 non-zero로 종료"
  elif [ -z "$out" ]; then
    pass "$name"
  else
    fail "$name" "stdout가 비어 있지 않음"
  fi
}

assert_reference_noop() {
  local name="$1" input="$2" replacement="$3" out tmpdir
  if [ ! -f "$PROMPTS_FILE" ]; then
    fail "$name" "테스트 전 reference 파일 없음"
    return
  fi
  tmpdir=$(mktemp -d)
  mkdir -p "$tmpdir/scripts" "$tmpdir/references"
  cp "$ROUTER" "$tmpdir/scripts/task-router.sh"
  cp "$PROMPTS_FILE" "$tmpdir/references/task-router-prompts.json"
  case "$replacement" in
    missing) rm -f "$tmpdir/references/task-router-prompts.json" ;;
    invalid) printf '%s' '{not-json' > "$tmpdir/references/task-router-prompts.json" ;;
  esac
  if ! out=$(printf '%s' "$input" | bash "$tmpdir/scripts/task-router.sh"); then
    fail "$name" "오류 입력이 non-zero로 종료"
  elif [ -z "$out" ]; then
    pass "$name"
  else
    fail "$name" "stdout가 비어 있지 않음"
  fi
  rm -rf "$tmpdir"
}

assert_without_jq() {
  local name="$1" input="$2" out empty_path
  empty_path=$(mktemp -d)
  if ! out=$(PATH="$empty_path" /bin/bash "$ROUTER" <<< "$input"); then
    fail "$name" "jq 없음이 non-zero로 종료"
  elif [ -z "$out" ]; then
    pass "$name"
  else
    fail "$name" "stdout가 비어 있지 않음"
  fi
  rmdir "$empty_path"
}

assert_closed_stdin() {
  local name="$1" out
  if ! out=$(/bin/bash "$ROUTER" 0<&- 2>/dev/null); then
    fail "$name" "닫힌 stdin이 non-zero로 종료"
  elif [ -z "$out" ]; then
    pass "$name"
  else
    fail "$name" "stdout가 비어 있지 않음"
  fi
}

echo "=== task-router unit tests ==="

if command -v jq >/dev/null 2>&1; then
  pass "jq available"
else
  fail "jq available"
fi

assert_selected "app-build" \
  '{"prompt":"제로베이스에서 완성형 앱을 만들어줘"}' \
  "완전한 프로덕션 레디 애플리케이션"
assert_selected "app-build (프로덕션 앱, 레디 불필요)" \
  '{"prompt":"프로덕션 앱을 만들어줘"}' \
  "완전한 프로덕션 레디 애플리케이션"
assert_selected "codebase-refactor" \
  '{"prompt":"이 코드베이스를 리팩터링해줘"}' \
  "낯선 대규모 코드베이스"
assert_selected "debug" \
  '{"prompt":"이 에러의 원인을 분석하고 고쳐줘"}' \
  "프로덕션 환경의 버그"
assert_selected "debug (왜 안)" \
  '{"prompt":"이 함수가 왜 안 되지"}' \
  "프로덕션 환경의 버그"
assert_selected "debug (왜 안 돌아가)" \
  '{"prompt":"왜 안 돌아가는지 봐줘"}' \
  "프로덕션 환경의 버그"
assert_selected "debug (멀티라인 traceback)" \
  '{"prompt":"Traceback (most recent call last):\n  File app.py line 10\n\n원인 분석하고 고쳐줘"}' \
  "프로덕션 환경의 버그"
assert_selected "system-design" \
  '{"prompt":"확장 가능한 시스템을 설계하고 구현해줘"}' \
  "시니어 시스템 아키텍트"
assert_selected "performance" \
  '{"prompt":"성능 최적화와 메모리 사용량을 개선해줘"}' \
  "퍼포먼스 엔지니어"
assert_selected "multi-agent" \
  '{"prompt":"멀티 에이전트로 병렬 작업해줘"}' \
  "너는 협업하는 4명의 에이전트"
assert_selected "ui" \
  '{"prompt":"접근성을 준수하는 UI 컴포넌트를 만들어줘"}' \
  "재사용 가능한 UI 컴포넌트"

assert_empty "일반 요청" '{"prompt":"오늘 회의 내용을 정리해줘"}'
assert_empty "불명확한 요청" '{"prompt":"이거 해줘"}'
assert_empty "충돌하는 요청" '{"prompt":"시스템을 설계하고 리팩터링해줘"}'
assert_empty "잘못된 JSON" '{bad-json'
assert_empty "prompt 없는 JSON" '{}'
assert_empty "zoom 오탐 방지" '{"prompt":"zoom 회의 녹음 정리해줘"}'
assert_empty "접근성 단독 오탐 방지" '{"prompt":"접근성 개선 방안 문서로 정리해줘"}'
assert_empty "프론트엔드 단독 오탐 방지" '{"prompt":"위키에 프론트엔드 관련 정리된 거 있어?"}'
assert_empty "반응형 단독 오탐 방지" '{"prompt":"반응형"}'
assert_empty "슬래시 커맨드" '{"prompt":"/rakis:wiki-query 성능 최적화 관련 정리된 거 있어?"}'
assert_empty "왜 안 오탐 방지 (와)" '{"prompt":"오늘 왜 안 와?"}'
assert_empty "왜 안 오탐 방지 (팔리다)" '{"prompt":"이 옷 왜 안 팔리지?"}'
assert_empty "왜 안 오탐 방지 (먹다)" '{"prompt":"밥을 왜 안 먹어?"}'
assert_empty "왜 안 오탐 방지 (이해)" '{"prompt":"이해가 왜 안 되는지 모르겠어"}'
assert_empty "왜 안 오탐 방지 (냉장고)" '{"prompt":"냉장고가 왜 안 되지"}'
assert_empty "왜 안 오탐 방지 (문)" '{"prompt":"문이 왜 안 열리지"}'
assert_empty "왜 안 오탐 방지 (세탁기)" '{"prompt":"이 세탁기가 왜 안 돌아가지"}'
assert_empty "왜 안 오탐 방지 (기계)" '{"prompt":"이 기계가 왜 안 작동하지"}'
assert_empty "왜 안 오탐 방지 (약속)" '{"prompt":"약속을 왜 안 실행하지"}'
assert_empty "왜 안 오탐 방지 (개그)" '{"prompt":"이 개그가 왜 안 먹히지"}'
assert_empty "왜 안 오탐 방지 (돌아가+봐줘)" '{"prompt":"왜 안 돌아가지? 봐줘"}'
assert_empty "왜 안 오탐 방지 (bare 원인)" '{"prompt":"왜 안 되는지 원인을 모르겠어"}'
assert_empty "왜 안 오탐 방지 (자물쇠 원인)" '{"prompt":"왜 안 열리는지 원인을 모르겠어. 자물쇠 비밀번호를 제대로 눌렀는데"}'
assert_empty "왜 안 오탐 방지 (머리 원인)" '{"prompt":"왜 안 돌아가는지 원인을 모르겠어. 요즘 머리가"}'
assert_empty "왜 안 오탐 방지 (병뚜껑 분석)" '{"prompt":"왜 안 열리는지 분석 좀 해줘. 이 병뚜껑"}'
assert_empty "왜 안 오탐 방지 (냉장고 기능)" '{"prompt":"냉장고 기능이 왜 안 되지"}'
assert_empty "왜 안 오탐 방지 (세탁기 기능)" '{"prompt":"세탁기 기능이 왜 안 돌아가지"}'
assert_empty "왜 안 오탐 방지 (기계 기능)" '{"prompt":"이 기계 기능이 왜 안 작동하지"}'
assert_empty "왜 안 오탐 방지 (여행 패키지)" '{"prompt":"여행 패키지 예약이 왜 안 되지"}'
assert_empty "왜 안 오탐 방지 (채용 프로세스)" '{"prompt":"채용 프로세스가 왜 안 되지"}'
assert_empty "왜 안 오탐 방지 (연차 요청)" '{"prompt":"연차 요청이 왜 안 되지"}'
assert_empty "왜 안 오탐 방지 (카톡 응답)" '{"prompt":"카톡 응답이 왜 안 되지"}'
assert_empty "왜 안 오탐 방지 (명령 일반어)" '{"prompt":"이 명령이 왜 안 되지"}'
assert_empty "왜 안 오탐 방지 (코트 버튼)" '{"prompt":"이 코트 버튼이 왜 안 되지"}'
assert_empty "왜 안 오탐 방지 (콘테스트 substring)" '{"prompt":"이 콘테스트가 왜 안 되지"}'
assert_empty "왜 안 오탐 방지 (바코드 substring)" '{"prompt":"이 바코드가 왜 안 되지"}'
assert_empty "왜 안 오탐 방지 (자물쇠 코드)" '{"prompt":"이 자물쇠 코드가 왜 안 되지"}'
assert_empty "왜 안 오탐 방지 (서버실 compound)" '{"prompt":"서버실 문이 왜 안 열리지"}'
assert_selected "debug (API token)" \
  '{"prompt":"이 API가 왜 안 되지"}' \
  "프로덕션 환경의 버그"
assert_reference_noop "reference 누락" '{"prompt":"이 에러의 원인을 분석하고 고쳐줘"}' missing
assert_reference_noop "잘못된 reference JSON" '{"prompt":"이 에러의 원인을 분석하고 고쳐줘"}' invalid
assert_without_jq "jq 없음" '{"prompt":"이 에러의 원인을 분석하고 고쳐줘"}'
assert_closed_stdin "닫힌 stdin"

printf '\n=== %s passed, %s failed ===\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
