#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROMPTS_FILE="$SCRIPT_DIR/../references/task-router-prompts.json"

noop() { exit 0; }

command -v jq >/dev/null 2>&1 || noop
[ -r "$PROMPTS_FILE" ] || noop

{ true >&0; } 2>/dev/null || noop
INPUT=$(cat) || noop
PROMPT=$(printf '%s' "$INPUT" | jq -er '.prompt // empty' 2>/dev/null) || noop
[ -n "$PROMPT" ] || noop

case "$PROMPT" in
  /*) noop ;;
esac

has() {
  printf '%s' "$PROMPT" | tr '\n' ' ' | grep -Eiq "$1"
}

if has '멀티[[:space:]]*에이전트|multi[- ]agent|agent[[:space:]]+team|병렬[[:space:]]*에이전트|협업[[:space:]]*에이전트'; then
  MODE='multi-agent'
else
  MODES=()

  if has '((에러|오류|버그|예외|실패|traceback|stack[[:space:]]+trace|crash).*(고쳐|수정|원인|분석|디버그|debug))|((고쳐|수정).*(에러|오류|버그|예외|실패))|((^|[[:space:][:punct:]])(함수|메서드|메소드|스크립트|명령어|앱|애플리케이션|모듈|API|클라이언트|빌드|배포|컴포넌트|쿼리|터미널|라이브러리|의존성|로직|구현|코드베이스|소스[[:space:]]+코드).{0,10}왜[[:space:]]*안[[:space:]]*(되|돼|돌아가|작동|실행|열리|먹히))|(^왜[[:space:]]*안[[:space:]]*돌아가는지[[:space:]]*봐줘)'; then
    MODES+=(debug)
  fi
  if has '성능[[:space:]]*(최적화|개선|문제)|느려|병목|메모리[[:space:]]*(최적화|사용량|누수)|(^|[^[:alnum:]])OOM([^[:alnum:]]|$)|out[- ]of[- ]memory|latency|throughput|불필요한[[:space:]]*렌더링'; then
    MODES+=(performance)
  fi
  if has 'UI[[:space:]]*(컴포넌트|구현|설계)|화면[[:space:]]*컴포넌트|프론트엔드[[:space:]]*(UI|화면|컴포넌트|구현|개발|설계|빌드|만들|구축)|접근성(을|를)?[[:space:]]*(준수|고려|대응|개선)[[:space:]]*(하는|한)?[[:space:]]*(UI|컴포넌트|화면|웹|프론트엔드)|접근성[[:space:]]*(UI|컴포넌트|화면|웹|프론트엔드)|(UI|컴포넌트|화면|웹|프론트엔드)[[:space:]]*접근성|반응형[[:space:]]*(UI|디자인)|Props[[:space:]]*설계'; then
    MODES+=(ui)
  fi
  if has '리팩터링|리팩토링|refactor|코드베이스[[:space:]]*(이해|구조[[:space:]]*개선)|중복[[:space:]]*코드|유지보수성?[[:space:]]*개선'; then
    MODES+=(codebase-refactor)
  fi
  if has '제로베이스|처음부터[[:space:]]*(앱|애플리케이션)|완성형[[:space:]]*앱|프로덕션[[:space:]]*(레디|ready)[[:space:]]*(앱|애플리케이션)|프로덕션[[:space:]]*(앱|애플리케이션)[[:space:]]*(을|를)?[[:space:]]*만들|전체[[:space:]]*(앱|애플리케이션)[[:space:]]*(만들|개발)'; then
    MODES+=(app-build)
  fi
  if has '시스템(을|를)?[[:space:]]*설계|아키텍처[[:space:]]*설계|확장[[:space:]]*가능한[[:space:]]*(시스템|아키텍처)|API[[:space:]]*설계|데이터[[:space:]]*흐름[[:space:]]*설계'; then
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
