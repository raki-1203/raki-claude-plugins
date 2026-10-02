#!/bin/bash
set -uo pipefail
source "$(dirname "$0")/../fixtures/eli5/lib.sh"

py() { python3 - "$ELI5_BIN" <<PY
import sys; sys.path.insert(0, sys.argv[1])
import plain
$1
PY
}
check() { if out=$(py "$1" 2>&1); then pass "$2"; else fail "$2" "$out"; fi; }

echo "🔧 plain — 칸 수"
check 'assert plain.text_units("abc") == 3' "ASCII 1칸"
check 'assert plain.text_units("요청") == 4' "한글 2칸"
check 'assert plain.text_units("API 서버") == 8' "섞임"
check 'assert plain.text_units("") == 0 and plain.text_units(None) == 0' "빈 값"

echo "🔧 plain — 코드 이름 탐지"
check 'assert plain.code_tokens("collect_population 단계") == [("snake_case", "collect_population")]' "snake_case"
check 'assert plain.code_tokens("resolveMartSize 호출") == [("camelCase", "resolveMartSize")]' "camelCase"
check 'assert plain.code_tokens("turn.py 에서") == [("파일 이름", "turn.py")]' "파일 이름"
check 'assert plain.code_tokens("src/api 아래") == [("경로", "src/api")]' "경로"
check 'assert plain.code_tokens("POST /run 요청") == [("경로", "/run")]' "엔드포인트 경로"
check 'assert plain.code_tokens("handle( 를 부른다") == [("함수 호출", "handle(")]' "함수 호출"
check 'assert plain.code_tokens("graph.astream 실행") == [("속성 접근", "graph.astream")]' "속성 접근"
check 'assert plain.code_tokens("parser#LLMSlotParser") != []' "심볼 표기"
check 'r = plain.code_tokens("graph.astream을 돌리고 collect_population으로 간다"); assert [t for _, t in r] == ["graph.astream", "collect_population"], r' "조사 붙은 코드 이름"
check 'r = plain.code_tokens("버전 2.0 · 5분 30초 · L0 · 실행 단위 · S3 · 화면/서버"); assert r == [], r' "숫자 오탐 없음"
check 'assert plain.code_tokens("Node.js 서버", {"Node.js": "자바스크립트 실행기"}) == []' "glossary 에 있으면 통과"

echo "🔧 plain — 풀이 없는 용어"
check 'assert plain.unexplained_terms("PostgreSQL 에 쓴다") == ["PostgreSQL"]' "대소문자 섞인 고유명사"
check 'assert plain.unexplained_terms("API로 넘긴다") == ["API"]' "약어 + 조사"
check 'assert plain.unexplained_terms("API 와 APIs", {"API": "x"}) == []' "glossary + 복수형 s"
check 'assert plain.unexplained_terms("LangGraph", {"LangGraph": "x"}) == []' "glossary 통과"
check 'assert plain.unexplained_terms("L0 · S3 저장") == []' "한 글자 대문자는 용어 아님"

echo "🔧 plain — 필드 오류"
check 'e = plain.check_plain("L0/api.say", "graph.astream 을 부른다", {}); assert len(e) == 1 and "graph.astream" in e[0] and "—" in e[0], e' "코드 이름 오류 한 줄"
check 'e = plain.check_plain("L0/api.title", "가" * 13, {}, plain.TITLE_MAX); assert len(e) == 1 and "26칸, 상한 24" in e[0], e' "길이 초과"
check 'assert plain.check_plain("L0/api.title", "가" * 12, {}, plain.TITLE_MAX) == []' "길이 경계 통과"
check 'e = plain.check_plain("x", "PostgreSQL", {}); assert len(e) == 1 and "glossary" in e[0], e' "용어 오류"

echo "🔧 plain — glossary 키"
check 'assert plain.glossary_key_errors({"PostgreSQL": "a", "API": "b", "Node.js": "c"}) == []' "고유명사 키 허용"
check 'e = plain.glossary_key_errors({"graph.astream": "x", "run_job": "y", "resolveSize": "z", "src/api": "w"}); assert len(e) == 4, e' "코드 이름 키 거부"
finish
