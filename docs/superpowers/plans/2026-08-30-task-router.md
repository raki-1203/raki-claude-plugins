# Threads 작업 프롬프트 자동 라우터 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `rakis` 플러그인이 사용자 요청에 맞는 Threads 작업 프롬프트 하나만 자동으로 `UserPromptSubmit.additionalContext`에 주입하도록 만든다.

**Architecture:** 플러그인의 `UserPromptSubmit` hook이 stdin의 사용자 prompt를 로컬 정규식으로 분류하고, 매칭된 경우 `references/task-router-prompts.json`에서 원문 하나를 읽어 hook 전용 JSON으로 출력한다. 매칭 실패·모호한 요청·환경 오류는 no-op으로 처리해 기존 Claude Code 동작을 유지한다.

**Tech Stack:** Bash, `jq`, Claude Code Plugin Hooks (`hooks/hooks.json`), JSON

**Spec:** `docs/superpowers/specs/2026-08-30-task-router-design.md`

## Global Constraints

- `CLAUDE.md`와 기존 스킬 파일은 변경하지 않는다.
- 레포별 profile·프로젝트별 추가 규칙은 추가하지 않는다.
- Threads 원문 7개는 개별 mode로 유지하고 원문 문장을 변형하지 않는다.
- 한 요청에는 최대 하나의 프롬프트만 주입한다.
- 모호하거나 충돌하는 요청은 아무 프롬프트도 주입하지 않는다.
- hook은 LLM·네트워크·파일 업로드를 호출하지 않는다.
- 사용자 prompt 전문을 로그나 별도 파일에 기록하지 않는다.
- 모든 분류 실패와 실행 환경 오류는 exit code `0`의 no-op으로 처리한다.
- `multi-agent`는 명시적인 멀티 에이전트·병렬 에이전트 표현이 있을 때만 선택한다.
- 사용자 요청 전에는 git commit·push를 생성하지 않는다.
- 기존 외부 서비스 통합 테스트(`test.sh all`)는 실행하지 않고 로컬 라우터 테스트로 검증한다.

---

## File Map

| 파일 | 책임 |
|---|---|
| `references/task-router-prompts.json` | Threads 7개 원문 prompt의 mode별 저장소 |
| `scripts/task-router.sh` | hook stdin 파싱, 고신뢰 분류, 선택 prompt의 JSON 출력 |
| `hooks/hooks.json` | `UserPromptSubmit` hook 등록; 기존 `SessionStart` hook 보존 |
| `tests/unit/test_task_router.sh` | 7개 매칭·no-op·충돌·출력 계약 검증 |
| `lint.sh` | 기존 로컬 유닛 테스트 집합에 router 테스트 편입 |
| `test.sh` | `router` 선택 실행 경로와 전체 로컬 테스트 편입 |
| `README.md` | 자동 적용 동작과 no-op 정책 문서화 |
| `CHANGELOG.md` | 다음 릴리스의 기능 기록 |

---

### Task 1: 라우터 유닛 테스트 작성

**Files:**
- Create: `tests/unit/test_task_router.sh`
- Read: `docs/superpowers/specs/2026-08-30-task-router-design.md`

**Interfaces:**
- Consumes: `scripts/task-router.sh`에 stdin으로 `{ "prompt": "..." }` JSON
- Produces: 성공 시 `hookSpecificOutput.event`와 선택 prompt를 담은 JSON, 그 외 빈 stdout과 exit code `0`

- [ ] **Step 1: 실패하는 테스트 작성**

`tests/unit/test_task_router.sh`에 다음 테스트를 작성한다. `run_router`는 구현체가 아직 없어도 테스트가 결과를 집계하도록 `bash` 실행 실패를 잡는다.

```bash
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
  local name="$1" input="$2" replacement="$3" out backup
  backup="$PROMPTS_FILE.test-backup.$$"
  if [ ! -f "$PROMPTS_FILE" ]; then
    fail "$name" "테스트 전 reference 파일 없음"
    return
  fi
  mv "$PROMPTS_FILE" "$backup"
  if [ "$replacement" = "invalid" ]; then
    printf '%s' '{not-json' > "$PROMPTS_FILE"
  fi
  if ! out=$(run_router "$input"); then
    fail "$name" "오류 입력이 non-zero로 종료"
  elif [ -z "$out" ]; then
    pass "$name"
  else
    fail "$name" "stdout가 비어 있지 않음"
  fi
  rm -f "$PROMPTS_FILE"
  mv "$backup" "$PROMPTS_FILE"
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

echo "=== task-router unit tests ==="

if command -v jq >/dev/null 2>&1; then
  pass "jq available"
else
  fail "jq available"
fi

assert_selected "app-build" \
  '{"prompt":"제로베이스에서 완성형 앱을 만들어줘"}' \
  "완전한 프로덕션 레디 애플리케이션"
assert_selected "codebase-refactor" \
  '{"prompt":"이 코드베이스를 리팩터링해줘"}' \
  "낯선 대규모 코드베이스"
assert_selected "debug" \
  '{"prompt":"이 에러의 원인을 분석하고 고쳐줘"}' \
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
assert_reference_noop "reference 누락" '{"prompt":"이 에러의 원인을 분석하고 고쳐줘"}' missing
assert_reference_noop "잘못된 reference JSON" '{"prompt":"이 에러의 원인을 분석하고 고쳐줘"}' invalid
assert_without_jq "jq 없음" '{"prompt":"이 에러의 원인을 분석하고 고쳐줘"}'

printf '\n=== %s passed, %s failed ===\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
```

- [ ] **Step 2: 실패를 확인**

Run: `bash tests/unit/test_task_router.sh`

Expected: FAIL. `scripts/task-router.sh`가 아직 없다는 테스트 실패가 포함되어야 한다.

- [ ] **Step 3: 테스트 파일 문법 확인**

Run: `bash -n tests/unit/test_task_router.sh`

Expected: PASS. 라우터 부재로 기능 테스트는 실패하되 테스트 스크립트 자체의 문법 오류는 없어야 한다.

---

### Task 2: Threads 원문 reference 추가

**Files:**
- Create: `references/task-router-prompts.json`
- Test: `tests/unit/test_task_router.sh`

**Interfaces:**
- Consumes: 없음
- Produces: `jq -r --arg mode "$mode" '.[$mode] // empty'`로 조회 가능한 7개 문자열

- [ ] **Step 1: 7개 원문을 JSON으로 저장**

다음 내용을 `references/task-router-prompts.json`에 저장한다. JSON의 key는 스크립트와 테스트가 공유하는 고정 interface다.

```json
{
  "app-build": "완전한 프로덕션 레디 애플리케이션을 개발하는 시니어 풀스택 엔지니어처럼 생각하라. 먼저 시스템 아키텍처를 설계하고, 그다음 최소한이지만 확장 가능한 버전을 개발하라.\n\n결과물에 포함할 것: • 아키텍처 • 파일 구조 • 데이터베이스 스키마 • API 엔드포인트 • UI 구조 • 전체 코드\n\n실제 스타트업 MVP처럼 설계하고, 확장 가능하게 만들 것.",
  "codebase-refactor": "낯선 대규모 코드베이스에 막 합류한 시니어 엔지니어처럼 생각하라. 먼저 아키텍처와 데이터 흐름을 파악하라. 그다음 다음을 식별하라: • 구조적 문제 • 중복 코드 • 성능 병목 • 유지보수 리스크\n\n결과물: • 아키텍처 요약 • 문제 영역 • 리팩터링 전략 • 개선된 코드\n\n기능은 그대로 유지하고, 품질만 끌어올릴 것.",
  "debug": "프로덕션 환경의 버그를 조사하는 시니어 디버깅 엔지니어처럼 생각하라. • 코드를 꼼꼼히 분석하고 • 단계별로 사고하고 • 근본 원인을 찾고 • 견고한 해결책을 제안하라\n\n결과물: • 코드가 하는 일 • 무엇이 문제인지 • 왜 실패하는지 • 엣지 케이스 • 수정된 프로덕션 레디 코드",
  "system-design": "시니어 시스템 아키텍트처럼 생각하라. 해당 제품을 위한 확장 가능한 시스템을 설계한 뒤, 최소 프로덕션 버전을 개발하라. 포함할 것: • 아키텍처 • 컴포넌트 구조 • 데이터 흐름 • API 설계 • 데이터베이스 스키마 • 캐싱 전략 • 구현 코드",
  "performance": "코드를 최적화하는 퍼포먼스 엔지니어처럼 생각하라. 목표: • 속도 • 메모리 사용량 • 확장성\n\n찾을 것: • 병목 지점 • 비효율적 로직 • 불필요한 렌더링\n\n결과물: • 성능 이슈 • 최적화 전략 • 개선된 코드",
  "multi-agent": "너는 협업하는 4명의 에이전트다: • 아키텍트 • 엔지니어 • 리뷰어 • 옵티마이저\n\n역할: • 아키텍트 → 시스템 설계 • 엔지니어 → 개발 • 리뷰어 → 품질 관리 • 옵티마이저 → 성능 개선\n\n결과물: • 아키텍처 • 구현 • 리뷰 피드백 • 최종 최적화 버전",
  "ui": "시니어 프론트엔드 엔지니어처럼 생각하고 다음을 만들어라: • 재사용 가능한 UI 컴포넌트 • 접근성 준수 • 프로덕션 레디\n\n고려할 것: • 로딩 상태 • 엣지 케이스 • 반응형 디자인 • 접근성\n\n결과물: • 컴포넌트 구조 • Props 설계 • 구현 • 사용 예시"
}
```

- [ ] **Step 2: reference JSON만 검증**

Run: `jq -e 'type == "object" and (keys | sort) == ["app-build","codebase-refactor","debug","multi-agent","performance","system-design","ui"] and all(.[]; type == "string" and length > 0)' references/task-router-prompts.json`

Expected: PASS. key가 7개가 아니거나 빈 문자열이면 실패해야 한다.

- [ ] **Step 3: 원문 marker가 모두 존재하는지 확인**

Run:

```bash
for marker in \
  '완전한 프로덕션 레디 애플리케이션' \
  '낯선 대규모 코드베이스' \
  '프로덕션 환경의 버그' \
  '시니어 시스템 아키텍트' \
  '퍼포먼스 엔지니어' \
  '너는 협업하는 4명의 에이전트' \
  '재사용 가능한 UI 컴포넌트'; do
  jq -e --arg marker "$marker" 'any(.[]; contains($marker))' references/task-router-prompts.json >/dev/null
  printf 'marker OK: %s\n' "$marker"
done
```

Expected: 7개 marker 모두 `marker OK`.

---

### Task 3: 결정론적 task-router 스크립트 구현

**Files:**
- Create: `scripts/task-router.sh`
- Test: `tests/unit/test_task_router.sh`
- Depends on: `references/task-router-prompts.json`

**Interfaces:**
- Consumes: stdin JSON의 `.prompt` 문자열
- Produces: 선택 시 `{hookSpecificOutput:{hookEventName,additionalContext}}` JSON; 미선택 시 빈 stdout, exit code `0`

- [ ] **Step 1: 고신뢰 분류기 구현**

`scripts/task-router.sh`에 다음 구조를 사용한다.

```bash
#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROMPTS_FILE="$SCRIPT_DIR/../references/task-router-prompts.json"

noop() { exit 0; }

command -v jq >/dev/null 2>&1 || noop
[ -r "$PROMPTS_FILE" ] || noop

INPUT=$(< /dev/stdin)
PROMPT=$(printf '%s' "$INPUT" | jq -er '.prompt // empty' 2>/dev/null) || noop
[ -n "$PROMPT" ] || noop

has() {
  printf '%s' "$PROMPT" | grep -Eiq "$1"
}

if has '멀티[[:space:]]*에이전트|multi[- ]agent|agent[[:space:]]+team|병렬[[:space:]]*에이전트|협업[[:space:]]*에이전트'; then
  MODE='multi-agent'
else
  MODES=()

  if has '((에러|오류|버그|예외|실패|traceback|stack[[:space:]]+trace|crash).*(고쳐|수정|원인|분석|디버그|debug))|((고쳐|수정).*(에러|오류|버그|예외|실패))'; then
    MODES+=(debug)
  fi
  if has '성능[[:space:]]*(최적화|개선|문제)|느려|병목|메모리[[:space:]]*(최적화|사용량|누수)|OOM|out[- ]of[- ]memory|latency|throughput|불필요한[[:space:]]*렌더링'; then
    MODES+=(performance)
  fi
  if has 'UI[[:space:]]*(컴포넌트|구현|설계)|화면[[:space:]]*컴포넌트|프론트엔드|접근성|반응형[[:space:]]*(UI|디자인)?|Props[[:space:]]*설계'; then
    MODES+=(ui)
  fi
  if has '리팩터링|리팩토링|refactor|코드베이스[[:space:]]*(이해|구조[[:space:]]*개선)|중복[[:space:]]*코드|유지보수성?[[:space:]]*개선'; then
    MODES+=(codebase-refactor)
  fi
  if has '제로베이스|처음부터[[:space:]]*(앱|애플리케이션)|완성형[[:space:]]*앱|프로덕션[[:space:]]*(레디|ready)[[:space:]]*(앱|애플리케이션)|전체[[:space:]]*(앱|애플리케이션)[[:space:]]*(만들|개발)'; then
    MODES+=(app-build)
  fi
  if has '시스템[[:space:]]*설계|아키텍처[[:space:]]*설계|확장[[:space:]]*가능한[[:space:]]*(시스템|아키텍처)|API[[:space:]]*설계|데이터[[:space:]]*흐름[[:space:]]*설계'; then
    MODES+=(system-design)
  fi

  [ "${#MODES[@]}" -eq 1 ] || noop
  MODE="${MODES[0]}"
fi

BODY=$(jq -er --arg mode "$MODE" '.[$mode] // empty' "$PROMPTS_FILE" 2>/dev/null) || noop
[ -n "$BODY" ] || noop

CONTEXT=$(printf '[rakis task-router]\n\n%s' "$BODY")
jq -n --arg context "$CONTEXT" \
  '{hookSpecificOutput:{hookEventName:"UserPromptSubmit",additionalContext:$context}}'
```

분류 순서는 `multi-agent`만 명시 표현을 우선 처리하고, 나머지는 매칭 개수가 정확히 1개일 때만 선택한다. `grep`의 실패는 `if has ...` 조건 안에서만 사용해 `set -e`가 no-op 경로를 중단시키지 않도록 한다.

- [ ] **Step 2: 실행 권한과 문법 설정**

Run:

```bash
chmod +x scripts/task-router.sh
bash -n scripts/task-router.sh
```

Expected: 두 명령 모두 PASS.

- [ ] **Step 3: 라우터 유닛 테스트 실행**

Run: `bash tests/unit/test_task_router.sh`

Expected: 7개 mode 선택, 일반·불명확·충돌·잘못된 JSON no-op, `UserPromptSubmit` 출력 계약이 모두 PASS.

- [ ] **Step 4: 실제 hook payload를 흉내 내 출력 검증**

Run:

```bash
printf '%s' '{"prompt":"이 에러의 원인을 분석하고 고쳐줘"}' \
  | CLAUDE_PLUGIN_ROOT="$PWD" bash scripts/task-router.sh \
  | jq -e '.hookSpecificOutput.hookEventName == "UserPromptSubmit" and (.hookSpecificOutput.additionalContext | contains("프로덕션 환경의 버그"))'
```

Expected: `true`.

---

### Task 4: UserPromptSubmit plugin hook 등록

**Files:**
- Modify: `hooks/hooks.json:2-17`
- Test: `hooks/hooks.json`, `scripts/task-router.sh`

**Interfaces:**
- Consumes: Claude Code의 `UserPromptSubmit` stdin payload
- Produces: 기존 `SessionStart` 동작을 보존하면서 task-router command 실행

- [ ] **Step 1: 기존 SessionStart hook을 보존한 채 UserPromptSubmit 추가**

`hooks/hooks.json`의 최상위 `hooks` 객체에 다음 항목을 추가한다. `UserPromptSubmit`은 matcher를 지원하지 않으므로 `matcher`를 넣지 않는다.

```json
"UserPromptSubmit": [
  {
    "hooks": [
      {
        "type": "command",
        "command": "bash \"${CLAUDE_PLUGIN_ROOT}/scripts/task-router.sh\"",
        "timeout": 5
      }
    ]
  }
]
```

기존 `SessionStart` 배열과 그 command는 삭제·변경하지 않는다. 최상위 description은 `rakis 플러그인 SessionStart 안내·작업 프롬프트 자동 라우터`로 갱신한다.

- [ ] **Step 2: hook 설정 JSON 검증**

Run:

```bash
jq empty hooks/hooks.json
jq -e '
  (.hooks.SessionStart | length == 1) and
  (.hooks.UserPromptSubmit | length == 1) and
  (.hooks.UserPromptSubmit[0].hooks[0].type == "command") and
  (.hooks.UserPromptSubmit[0].hooks[0].command | contains("task-router.sh")) and
  (.hooks.UserPromptSubmit[0].hooks[0].timeout == 5)
' hooks/hooks.json
```

Expected: 두 명령 모두 PASS.

- [ ] **Step 3: command 경로를 plugin root 기준으로 검증**

Run:

```bash
printf '%s' '{"prompt":"성능 최적화가 필요해"}' \
  | CLAUDE_PLUGIN_ROOT="$PWD" bash scripts/task-router.sh \
  | jq -e '.hookSpecificOutput.additionalContext | contains("퍼포먼스 엔지니어")'
```

Expected: `true`. 현재 작업 디렉터리나 사용자의 실제 repo 경로와 무관하게 `${CLAUDE_PLUGIN_ROOT}` 아래 script가 reference를 찾는다.

---

### Task 5: 테스트 진입점·문서·최종 검증 통합

**Files:**
- Modify: `lint.sh:172-188`
- Modify: `test.sh:170-289`
- Modify: `README.md:47-59`
- Modify: `CHANGELOG.md:1-3`
- Test: `tests/unit/test_task_router.sh`, `hooks/hooks.json`

**Interfaces:**
- Consumes: 기존 `lint.sh`, `test.sh` 실행 흐름
- Produces: `./test.sh router`로 외부 서비스 없이 task-router만 검증하고, `lint.sh`가 router 회귀를 포함하는 상태

- [ ] **Step 1: lint.sh에 router 유닛 테스트 추가**

기존 `frontmatter 유닛 테스트` 블록 다음에 아래 블록을 추가한다.

```bash
if bash tests/unit/test_task_router.sh >/dev/null 2>&1; then
  pass "task-router 유닛 테스트"
else
  fail "task-router 유닛 테스트 — bash tests/unit/test_task_router.sh"
fi
```

- [ ] **Step 2: test.sh에 독립 router target 추가**

`test.sh`에 다음 함수를 추가하고, `all` 경로에서는 `test_wiki` 뒤에 호출한다.

```bash
test_router() {
  echo "🔬 task-router 테스트"
  if bash tests/unit/test_task_router.sh; then
    pass "task-router 유닛 테스트"
  else
    fail "task-router 유닛 테스트"
  fi
  echo ""
}
```

`case`에 `router)`를 추가한다.

```bash
  router)
    test_router
    ;;
```

Usage 문자열도 다음처럼 갱신한다.

```bash
echo "Usage: ./test.sh [all|source|wiki|router|deps|smoke|v3]"
```

- [ ] **Step 3: README에 자동 적용 동작을 짧게 문서화**

기존 스킬 목록 뒤에 다음 섹션을 추가한다.

```markdown
## 작업 프롬프트 자동 적용

`UserPromptSubmit` hook이 요청 유형을 로컬 규칙으로 판단해 Threads의 작업 프롬프트 7개 중 하나만 선택적으로 적용합니다.

- 앱 제작·시스템 설계·리팩터링·디버깅·성능·멀티 에이전트·UI 작업을 구분
- 요청이 일반적이거나 모호하면 아무 프롬프트도 추가하지 않음
- 기존 `CLAUDE.md`와 스킬 내용은 변경하지 않음
- hook은 LLM·네트워크를 호출하지 않음
```

- [ ] **Step 4: CHANGELOG에 기능 기록**

`CHANGELOG.md` 최상단에 다음 `Unreleased` 항목을 추가한다.

```markdown
## [Unreleased]

### Added

- **Threads 작업 프롬프트 자동 라우터** — `UserPromptSubmit` hook이 요청 유형을 결정론적으로 분류해 7개 원문 중 하나만 `additionalContext`에 주입한다. 모호한 요청은 기존 동작을 유지한다.
```

- [ ] **Step 5: 로컬 검증 실행**

Run:

```bash
jq empty references/task-router-prompts.json
jq empty hooks/hooks.json
bash -n scripts/task-router.sh
bash -n tests/unit/test_task_router.sh
bash tests/unit/test_task_router.sh
bash test.sh router
bash lint.sh
```

Expected: 모든 명령 PASS. `lint.sh`의 기존 테스트도 함께 통과해야 한다.

- [ ] **Step 6: 기존 SessionStart 동작과 변경 범위 확인**

Run:

```bash
git diff --check
git diff -- hooks/hooks.json scripts/task-router.sh references/task-router-prompts.json tests/unit/test_task_router.sh lint.sh test.sh README.md CHANGELOG.md
git status --short
```

Expected:

- whitespace 오류 없음
- `CLAUDE.md`, 기존 `skills/`, 기존 `SessionStart` command에 의도하지 않은 변경 없음
- 변경 파일이 File Map에 있는 파일로만 제한됨
- 사용자 요청 전 commit·push 없음

- [ ] **Step 7: 실제 Claude 세션에서 최종 확인**

플러그인 소스 변경을 설치된 세션에 반영한 뒤 새 세션에서 다음 세 요청을 순서대로 확인한다.

```text
이 에러의 원인을 분석하고 고쳐줘
오늘 회의 내용을 정리해줘
시스템을 설계하고 리팩터링해줘
```

Expected:

1. 첫 요청에는 debug 원문만 추가된다.
2. 두 번째 요청에는 추가 prompt가 없다.
3. 세 번째 요청은 충돌 요청이므로 추가 prompt가 없다.

이 확인은 플러그인 배포·reload 이후 수행하며, 설치된 플러그인의 변경 반영 여부는 `claude --debug`의 hook 로딩 로그로 확인한다.
