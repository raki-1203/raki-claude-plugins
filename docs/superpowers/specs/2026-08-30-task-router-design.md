# Threads 작업 프롬프트 자동 라우터 디자인

**Date**: 2026-08-30
**Status**: Spec (Approved in chat, pre-implementation)
**Target**: `rakis` 플러그인에 추가

## 목적

Threads 게시물의 7개 작업 프롬프트를 `CLAUDE.md`에 상시 삽입하지 않고, 사용자의 요청이 특정 작업 유형에 해당할 때만 하나를 `UserPromptSubmit`의 `additionalContext`로 주입한다.

대상 프롬프트는 원문 기준으로 다음 7개를 개별 유지한다.

1. 제로베이스에서 완성형 앱 만들기
2. 코드베이스 이해 및 리팩터링
3. 시니어 디버깅 엔지니어
4. 시스템 설계 + 구현
5. 성능 최적화
6. Claude 멀티 에이전트 워크플로
7. 프로덕션급 UI 컴포넌트 빌더

## 범위

### 포함

- `rakis` 플러그인 hook에 `UserPromptSubmit` 추가
- Threads 원문 7개를 플러그인 내부 JSON reference로 보관
- 한국어·영어 작업 표현에 대한 결정론적 로컬 분류
- 고신뢰 단일 매칭 시 선택된 프롬프트 하나만 주입
- 매칭 실패·모호한 요청·실행 환경 오류 시 원래 Claude Code 동작 유지
- 라우터 분류 유닛 테스트와 README 사용 설명

### 제외

- `CLAUDE.md` 수정
- 레포별 profile·프로젝트별 추가 규칙
- Git repository 또는 worktree 식별
- 프롬프트 내용의 레포별 변형
- LLM·네트워크를 이용한 분류
- 자동 멀티 에이전트 실행
- 기존 `rakis` 스킬 동작 변경

## 아키텍처

```text
사용자 요청
   ↓ stdin(JSON)
UserPromptSubmit hook
   ↓
scripts/task-router.sh
   ├─ prompt 추출
   ├─ 고신뢰 패턴 분류
   ├─ references/task-router-prompts.json에서 하나 조회
   └─ JSON additionalContext 출력 또는 no-op
   ↓
Claude Code가 사용자 요청 + 선택된 작업 프롬프트 처리
```

`UserPromptSubmit`은 matcher를 사용하지 않는다. 이 이벤트는 matcher를 지원하지 않으므로 hook 전체가 실행되며, 실제 선택 여부는 스크립트가 결정한다.

## 컴포넌트 구조

```text
rakis/
├── hooks/
│   └── hooks.json                         # UserPromptSubmit 등록
├── scripts/
│   └── task-router.sh                     # 무상태 결정론적 분류기
├── references/
│   └── task-router-prompts.json            # Threads 원문 7개
├── tests/
│   └── unit/
│       └── test_task_router.sh             # 분류·출력 테스트
├── test.sh                                # router 테스트 진입점 추가
└── README.md                              # 자동 적용 동작 문서화
```

`CLAUDE.md`와 기존 스킬 파일은 변경하지 않는다.

## 데이터 흐름과 출력 계약

### 입력

Claude Code가 hook에 전달하는 JSON의 `prompt` 필드만 사용한다. 세션 상태, 현재 레포, 사용자 파일, 환경변수의 비밀값은 읽지 않는다.

### reference 데이터

`references/task-router-prompts.json`은 다음 키를 사용한다.

```json
{
  "app-build": "...원문 1번...",
  "codebase-refactor": "...원문 2번...",
  "debug": "...원문 3번...",
  "system-design": "...원문 4번...",
  "performance": "...원문 5번...",
  "multi-agent": "...원문 6번...",
  "ui": "...원문 7번..."
}
```

값은 Threads 게시물의 해당 프롬프트 본문을 보존한다. 분류기나 레포 정보에 맞춰 문장을 덧붙이거나 수정하지 않는다.

### 매칭 성공

선택된 본문을 다음 hook 전용 JSON으로 출력한다.

```json
{
  "hookSpecificOutput": {
    "hookEventName": "UserPromptSubmit",
    "additionalContext": "[rakis task-router]\n\n<선택된 원문 프롬프트>"
  }
}
```

고정 marker는 선택된 내용이 사용자 원문이 아니라 작업 보조 컨텍스트임을 구분하기 위한 최소 래퍼다. 프로젝트 규칙이나 추가 역할 문구는 넣지 않는다.

### 매칭 실패

stdout에 아무것도 출력하지 않고 exit code `0`으로 종료한다. Claude Code는 사용자의 원래 요청만 처리한다.

## 분류 규칙

분류기는 각 요청을 독립적으로 처리하며, 한 요청에 최대 하나의 프롬프트만 선택한다.

### 고신뢰 표현

| mode | 대표 표현 |
|---|---|
| `multi-agent` | `멀티 에이전트`, `multi-agent`, `agent team`, `병렬 에이전트`, `협업 에이전트` |
| `debug` | `에러`, `오류`, `버그`, `예외`, `실패`, `traceback`, `crash`, `왜 안`, `고쳐` + 오류 맥락 |
| `performance` | `성능 최적화`, `느려`, `병목`, `메모리 최적화`, `OOM`, `latency`, `throughput`, `불필요한 렌더링` |
| `ui` | `UI 컴포넌트`, `화면 컴포넌트`, `프론트엔드`, `접근성`, `반응형 UI`, `Props 설계` |
| `codebase-refactor` | `리팩터링`, `refactor`, `코드베이스 구조 개선`, `중복 코드 제거`, `유지보수성 개선` |
| `app-build` | `제로베이스`, `처음부터 앱`, `완성형 앱`, `프로덕션 앱 만들`, `전체 애플리케이션 만들` |
| `system-design` | `시스템 설계`, `아키텍처 설계`, `확장 가능한 시스템`, `API 설계`, `데이터 흐름 설계` |

일반적인 `해줘`, `만들어줘`, `코드 봐줘`처럼 유형이 드러나지 않는 표현은 매칭하지 않는다.

### 충돌 처리

- `multi-agent`의 명시 표현은 다른 mode보다 우선한다.
- 나머지는 강한 표현이 하나의 mode에만 있을 때 선택한다.
- 서로 다른 mode의 강한 표현이 함께 있거나 우선순위를 확정할 수 없으면 no-op한다.
- `app-build`와 `system-design`은 각각 앱 전체 제작 표현과 시스템 설계 표현을 기준으로 구분하며, 둘 다 명확하면 no-op한다.
- `multi-agent`는 요청에 명시된 경우에만 선택하며, 작업 규모를 추정해 자동 선택하지 않는다.

분류 규칙은 프롬프트 원문과 분리된 라우팅 로직이며, 원문 프롬프트를 재작성하지 않는다.

## 오류 처리와 안전성

1. stdin이 비어 있거나 JSON이 잘못되면 no-op한다.
2. `jq`가 없으면 no-op한다.
3. reference 파일이 없거나 선택 키가 없으면 no-op한다.
4. reference JSON 파싱에 실패하면 no-op한다.
5. hook은 네트워크·LLM·파일 업로드를 호출하지 않는다.
6. 사용자 prompt 전문을 로그나 별도 파일에 기록하지 않는다.
7. hook 실패가 Claude Code 실행 자체를 차단하지 않도록 모든 분류 실패를 exit code `0`으로 처리한다.

고객·프로젝트 데이터 보호는 이 라우터가 새로 담당하지 않는다. 기존 `CLAUDE.md`와 실행 환경의 정책을 그대로 따른다.

## 테스트 전략

### 유닛 테스트

`tests/unit/test_task_router.sh`에서 다음을 검증한다.

- 7개 대표 요청이 각각 올바른 mode의 marker와 원문을 출력한다.
- 일반 요청은 stdout이 비어 있다.
- 모호한 요청은 stdout이 비어 있다.
- 충돌하는 요청은 stdout이 비어 있다.
- 명시적 멀티 에이전트 요청은 `multi-agent`를 선택한다.
- 출력은 유효한 JSON이다.
- reference 파일 누락·잘못된 입력·`jq` 실패 상황에서 Claude 실행을 막지 않는다.

### 통합 검증

- `jq empty references/task-router-prompts.json`
- `bash tests/unit/test_task_router.sh`
- `bash lint.sh`
- `bash test.sh smoke` 또는 기존 네트워크 의존 테스트와 분리된 router 테스트 경로
- 실제 Claude 세션에서 일반 요청, 디버깅 요청, 모호한 요청을 각각 한 번씩 확인

성공 기준은 선택된 프롬프트가 정확히 하나만 추가되고, 선택되지 않은 요청의 기존 동작이 변하지 않는 것이다.

## 사용자 문서

README에는 다음 사실만 짧게 추가한다.

- Threads 작업 프롬프트 7개가 요청 유형에 따라 자동 적용됨
- 유형이 불명확하면 아무 프롬프트도 적용하지 않음
- 기존 `CLAUDE.md`와 스킬은 변경하지 않음
- 플러그인 업데이트 또는 새 세션에서 hook 변경사항이 반영됨

## 근거

- Threads 원문: `https://www.threads.com/share/BAb4mvSwxs/`
- Claude Code Hooks 공식 문서: `https://code.claude.com/docs/en/hooks`
- Claude Code Plugins 공식 문서: `https://code.claude.com/docs/en/plugins`
