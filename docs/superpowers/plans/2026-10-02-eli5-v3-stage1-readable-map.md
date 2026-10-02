# eli5 v3 1단계 — 지도 가독성 + 패널 제거 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 코드를 읽지 않는 사람이 eli5 지도 한 장만 보고 구조를 이해할 수 있게 한다 — 박스·화살표에서 코드 이름을 없애고(검증기가 강제), 설명은 오른쪽 박스 카드로 내리고, 질문 패널과 서버를 걷어낸다.

**Architecture:** 쉬운 말 검사는 새 모듈 `bin/plain.py` 의 순수 함수로 두고 `validate.py` 가 무결성 검사의 일부로 부른다(실패 = exit 1). `render.py` 는 v3 모델만 받고 원자적으로 쓴다. `assets/map.html` 은 박스에 `title`+`say` 만 그리고 상세·근거는 오른쪽 `<aside>` 카드에 둔다. 서버(`server.py`) 대신 `bin/open.py` 가 파일을 Orca 탭이나 브라우저로 열고 신선도를 판정한다.

**Tech Stack:** Python 3 표준 라이브러리만(`python3` 직접 실행, uv 아님 — 플러그인 레포에 pyproject 없음), 바닐라 JS/SVG 단일 HTML, bash 단위 테스트(`tests/unit/test_eli5_*.sh` + `tests/fixtures/eli5/lib.sh` 의 `pass`/`fail`/`finish`), `jq`.

**Spec:** `docs/superpowers/specs/2026-10-02-eli5-v3-readable-map-design.md` — 이 plan 은 "1단계 — 지도 가독성" 절(1.1~1.6)만 구현한다. 2~4단계는 범위 밖.

## Global Constraints

- 브랜치 `feat/eli5-v3` 에서 작업한다. main 에 직접 커밋하지 않는다
- Python 은 표준 라이브러리만. 외부 패키지 금지
- 모델 `meta.version` 은 정확히 `3`. 다른 값이면 validate·render 모두 거부한다 (v2 호환 코드 없음)
- `kind` 허용값: `person` · `external` · `service` · `module` · `store` · `job`
- 길이 상한(전각 2칸·그 외 1칸): node `title` ≤ 24, node `say` ≤ 30, edge `label` ≤ 18. 자르지 않고 실패시킨다
- 쉬운 말 검사 대상: `meta.summary`, view `title`·`hint`, node `title`·`say`, edge `label`. `detail`·`rules[].text`·`ifaces` 는 검사하지 않는다
- 오류 문자열 형식: `<위치> … — <고칠 방법>` 한 줄
- 차용 코드 파일 머리에 출처 주석: archify `textUnits` → "archify (MIT, Copyright (c) 2026 tt-a1i, 2025 Cocoon AI)", deadhd `open.sh` → "deadhd (MIT, Copyright (c) 2026 lcalmsky)"
- 대상 레포의 추적 파일을 바꾸지 않는다 (v2 원칙 유지)
- 커밋 메시지는 conventional commit(`feat(eli5):`, `test(eli5):`, `docs(eli5):`, `refactor(eli5):`), 본문 끝에 `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`
- push 는 이 plan 범위 밖 (사용자 확인 후)

## Review Focus

1. **한글 조사가 바로 붙은 코드 이름** — `graph.astream을`, `collect_population으로`, `API로`. Python `\b` 는 한글도 단어 문자로 봐서 경계가 안 생긴다. 기대: 잡힌다 → Task 1 테스트 `조사 붙은 코드 이름`
2. **숫자·버전 표기의 오탐** — `버전 2.0`, `5분 30초`, `L0 · 실행 단위`, `S3`. 기대: 통과 → Task 1 테스트 `숫자 오탐 없음`
3. **glossary 로 검사를 우회** — `{"graph.astream": "..."}` 를 넣어 통과시키기. 기대: glossary 키 자체가 코드 이름이면 실패 → Task 2 테스트 `glossary 우회 금지`
4. **사람 글에 든 HTML 특수문자·주석 표기** — `say` 에 `<b>`, hint 에 `<!--`. 기대: 화면에 글자 그대로, 스크립트 블록 안 깨짐 → Task 3·5 테스트
5. **공백·한글이 든 경로를 Orca/브라우저로 열기** — `저장소 a:1/.eli5/app.html`. 기대: `file://` URL 이 퍼센트 인코딩돼 Orca 에 전달 → Task 4 테스트 `한글·공백 경로 인코딩`

---

## File Structure

| 파일 | 상태 | 책임 |
|---|---|---|
| `skills/eli5/bin/plain.py` | 신규 | 글자 칸 수, 코드 이름·풀이 없는 용어 탐지, 필드 검사 오류 문자열 |
| `skills/eli5/bin/validate.py` | 수정 | `v3_errors()` 추가 — 버전·summary·glossary·kind·say·쉬운 말·길이 |
| `skills/eli5/bin/render.py` | 수정 | v3 버전 확인, 원자적 쓰기, `<!--` 이스케이프 |
| `skills/eli5/bin/open.py` | 신규 | `open`(Orca 탭 → 브라우저) · `status`(fresh/stale/unknown/missing) |
| `skills/eli5/assets/map.html` | 재작성 | 박스 = 색 띠 + title + say, 오른쪽 카드, 근거 토글, 접힌 리포트 |
| `skills/eli5/SKILL.md` | 재작성 | v3 절차 (패널 없음, 문체 규칙, 재검토, open.py) |
| `skills/eli5/bin/server.py`, `assets/panel.html`, `assets/answer-rules.md` | 삭제 | — |
| `tests/unit/test_eli5_plain.sh` · `test_eli5_open.sh` | 신규 | — |
| `tests/unit/test_eli5_validate.sh` · `test_eli5_render.sh` | 수정 | v3 fixture 기준 |
| `tests/unit/test_eli5_server.sh`, `tests/fixtures/eli5/bin/claude` | 삭제 | — |
| `tests/fixtures/eli5/model.json` | 재작성 | v3 모델 |
| `tests/fixtures/eli5/lib.sh` | 수정 | `ELI5_CLAUDE_BIN` 제거 |
| `lint.sh`, `test.sh` | 수정 | eli5 테스트 목록 |
| `commands/help.md`, `README.md`, `CHANGELOG.md` | 수정 | v3 안내 |

---

### Task 1: 쉬운 말 검사 모듈 `plain.py`

**Files:**
- Create: `skills/eli5/bin/plain.py`
- Test: `tests/unit/test_eli5_plain.sh`

**Interfaces:**
- Consumes: 없음
- Produces (Task 2 가 import 해서 쓴다):
  - 상수 `TITLE_MAX = 24`, `SAY_MAX = 30`, `LABEL_MAX = 18`, `KINDS = ("person", "external", "service", "module", "store", "job")`
  - `text_units(text: str) -> int`
  - `code_tokens(text: str, glossary: dict | None = None) -> list[tuple[str, str]]` — `(종류, 토큰)` 목록, 글 순서, 겹치는 구간은 먼저 잡힌 것만
  - `unexplained_terms(text: str, glossary: dict | None = None) -> list[str]`
  - `check_plain(where: str, text: str, glossary: dict, limit: int | None = None) -> list[str]` — 오류 문자열 목록
  - `glossary_key_errors(glossary: dict) -> list[str]`

- [ ] **Step 1: 실패하는 테스트 작성**

`tests/unit/test_eli5_plain.sh`:

```bash
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
```

- [ ] **Step 2: 실패 확인**

Run: `bash tests/unit/test_eli5_plain.sh`
Expected: 모든 항목 ❌ (`ModuleNotFoundError: No module named 'plain'`), 마지막 줄 `=== 0 passed, 2x failed ===`

- [ ] **Step 3: 구현**

`skills/eli5/bin/plain.py`:

```python
#!/usr/bin/env python3
"""eli5 쉬운 말 검사 — 사람이 읽는 글에서 코드 이름과 풀이 없는 용어를 찾는다.

text_units 는 archify (MIT, Copyright (c) 2026 tt-a1i, 2025 Cocoon AI)
renderers/shared/utils.mjs 의 textUnits 를 옮긴 것이다 — 전각 글자는 2칸, 나머지는 1칸.
"""
import re

TITLE_MAX, SAY_MAX, LABEL_MAX = 24, 30, 18
KINDS = ("person", "external", "service", "module", "store", "job")

FULLWIDTH_RE = re.compile(
    "[ᄀ-ᅟ⺀-꓏가-힣豈-﫿︰-﹏"
    "＀-｠￠-￦\U0001F000-\U0001FAFF\U00020000-\U0003FFFD]")

# \b 는 한글도 단어 문자로 봐서 "API로" 같은 조사 결합에서 경계가 생기지 않는다. ASCII 기준 경계를 쓴다.
A = r"(?<![A-Za-z0-9_])"
Z = r"(?![A-Za-z0-9_])"
CODE = (
    ("snake_case", re.compile(A + r"[A-Za-z0-9]+_[A-Za-z0-9_]+" + Z)),
    ("camelCase", re.compile(A + r"[a-z][a-z0-9]*[A-Z][A-Za-z0-9]*" + Z)),
    ("파일 이름", re.compile(A + r"[A-Za-z0-9_-]+\.(?:py|js|ts|tsx|jsx|json|md|ya?ml|toml|sh|go|rs|java|kt|sql|html|css)" + Z)),
    ("경로", re.compile(r"[A-Za-z0-9_.-]*/[A-Za-z0-9_./{}-]*[A-Za-z][A-Za-z0-9_./{}-]*")),
    ("함수 호출", re.compile(A + r"[A-Za-z_][A-Za-z0-9_]*\(")),
    ("속성 접근", re.compile(A + r"[A-Za-z_][A-Za-z0-9_]*\.[A-Za-z_][A-Za-z0-9_]*")),
    ("심볼 표기", re.compile(r"(?:#|::)[A-Za-z_][A-Za-z0-9_]*")),
)
TERM_RE = re.compile(A + r"(?:[A-Z]{2,}[A-Za-z0-9]*|[A-Z][a-z0-9]+[A-Z][A-Za-z0-9]*)" + Z)
# glossary 키로 들어오면 안 되는 종류 — 이걸 허용하면 코드 이름을 glossary 에 넣어 검사를 피할 수 있다
KEY_FORBIDDEN = ("snake_case", "camelCase", "경로", "함수 호출", "심볼 표기")


def text_units(text):
    return sum(2 if FULLWIDTH_RE.match(ch) else 1 for ch in str(text or ""))


def _known(tok, glossary):
    return tok in glossary or (tok.endswith("s") and tok[:-1] in glossary)


def _scan(text, glossary):
    """(시작, 끝, 종류, 토큰) 을 글 순서로. 겹치는 구간은 먼저 잡힌 것만 남긴다."""
    found = []
    for kind, rx in CODE:
        for m in rx.finditer(text):
            s, e, tok = m.start(), m.end(), m.group(0)
            if any(s < fe and fs < e for fs, fe, _, _ in found):
                continue
            found.append((s, e, kind, tok))
    return sorted((f for f in found if not _known(f[3], glossary)), key=lambda f: f[0])


def code_tokens(text, glossary=None):
    return [(k, t) for _, _, k, t in _scan(str(text or ""), glossary or {})]


def unexplained_terms(text, glossary=None):
    text, glossary = str(text or ""), glossary or {}
    spans = [(s, e) for s, e, _, _ in _scan(text, glossary)]
    out = []
    for m in TERM_RE.finditer(text):
        if any(m.start() < e and s < m.end() for s, e in spans):
            continue
        if not _known(m.group(0), glossary) and m.group(0) not in out:
            out.append(m.group(0))
    return out


def check_plain(where, text, glossary, limit=None):
    errs = [f"{where} 에 '{tok}' ({kind}) — 코드 이름은 code[]·인터페이스 카드로 옮기고 하는 일을 쉬운 말로 쓴다"
            for kind, tok in code_tokens(text, glossary)]
    errs += [f"{where} 에 '{tok}' — meta.glossary 에 풀이를 추가하거나 쉬운 말로 바꾼다"
             for tok in unexplained_terms(text, glossary)]
    if limit is not None:
        u = text_units(text)
        if u > limit:
            errs.append(f"{where} 가 {u}칸, 상한 {limit} — {u - limit}칸 줄이거나 자세한 내용은 카드(detail)로 옮긴다")
    return errs


def glossary_key_errors(glossary):
    errs = []
    for key in glossary:
        kinds = [k for k, _ in code_tokens(key, {})]
        bad = any(k in KEY_FORBIDDEN for k in kinds) or (
            any(k in ("속성 접근", "파일 이름") for k in kinds) and key[:1].islower())
        if bad:
            errs.append(f"meta.glossary 키 '{key}' 는 코드 이름이다 — glossary 는 제품·기술 용어만. 코드 이름은 글에서 빼고 code[] 로 옮긴다")
    return errs
```

- [ ] **Step 4: 통과 확인**

Run: `bash tests/unit/test_eli5_plain.sh`
Expected: 마지막 줄 `=== 26 passed, 0 failed ===` (실패가 있으면 해당 정규식만 고친다. 테스트 기대값을 바꾸지 않는다)

- [ ] **Step 5: 커밋**

```bash
git add skills/eli5/bin/plain.py tests/unit/test_eli5_plain.sh
git commit -m "feat(eli5): 쉬운 말 검사 모듈 — 코드 이름·풀이 없는 용어·글자 칸 수

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: `validate.py` v3 검사 + v3 fixture

**Files:**
- Modify: `skills/eli5/bin/validate.py` (상단 import, `integrity_errors` 호출부 `main()` 의 `errs = integrity_errors(model)` 줄, 새 함수 `v3_errors`)
- Rewrite: `tests/fixtures/eli5/model.json`
- Modify: `tests/unit/test_eli5_validate.sh` (무결성 오류 절에 v3 항목 추가)

**Interfaces:**
- Consumes: Task 1 의 `plain.check_plain`, `plain.glossary_key_errors`, `plain.KINDS`, `plain.TITLE_MAX`, `plain.SAY_MAX`, `plain.LABEL_MAX`
- Produces: `v3_errors(model: dict) -> list[str]`. `main()` 은 `integrity_errors(model) + v3_errors(model)` 가 비어 있지 않으면 `{"integrity_errors": [...]}` 출력 후 exit 1, 모델 파일 무변경 (v2 동작 유지). fixture `model.json` 은 이후 모든 eli5 테스트가 쓰는 v3 모델

- [ ] **Step 1: fixture 를 v3 로 재작성**

`tests/fixtures/eli5/model.json` (노드 id·edge 순서·등급·evidence 는 v2 와 같게 유지 — 기존 강등 테스트가 인덱스로 참조한다):

```json
{
  "meta": {
    "version": 3,
    "target": "fixture 앱",
    "summary": "요청을 받아 작업을 실행하고, 실행 결과를 에이전트 서비스에 넘긴다.",
    "glossary": {"API": "다른 프로그램이 부를 수 있게 열어 둔 입구", "HTTP": "웹에서 요청을 주고받는 약속"},
    "scope": ["src/"],
    "graft_version": "0.16.0"
  },
  "views": {
    "L0": {
      "title": "L0 · 실행 단위",
      "hint": "API 가 엔진을 부르고 엔진이 에이전트를 HTTP 로 부른다",
      "parent": null,
      "rules": [
        {"text": "엔진은 HTTP 로 에이전트를 부른다", "grade": "record", "evidence": {"ref": "docs/adr-1.md"}}
      ],
      "nodes": [
        {"id": "api", "kind": "service", "title": "요청 받는 곳", "say": "들어온 요청을 엔진에 넘긴다",
         "code": ["src/api/server.py", "handle"], "row": 0, "col": 0, "paths": ["src/api/"]},
        {"id": "core", "kind": "module", "title": "작업 엔진", "say": "작업 하나를 실행한다",
         "detail": "작업 번호를 받아 실행하고 결과를 에이전트에 보낸다.",
         "code": ["src/core/engine.py", "run_job"], "row": 0, "col": 1, "paths": ["src/core/"], "drill": "L1-core"},
        {"id": "agent", "kind": "external", "title": "에이전트 서비스", "say": "바깥에서 작업을 받아 처리한다",
         "row": 1, "col": 1, "paths": []}
      ],
      "edges": [
        {"from": "api", "to": "core", "label": "작업 실행", "iface": "run_job", "grade": "graft",
         "evidence": {"from_sym": "src/api/server.py#handle", "to_sym": "src/core/engine.py#run_job"}},
        {"from": "core", "to": "agent", "label": "작업 전달", "iface": "agent-http", "grade": "code",
         "evidence": {"ref": "src/core/engine.py:5", "quote": "requests.post"}},
        {"from": "agent", "to": "api", "label": "결과 콜백?", "grade": "unknown", "evidence": {}}
      ],
      "ifaces": [
        {"id": "run_job", "title": "작업 실행", "from": "api", "to": "core", "transport": "python call",
         "items": [{"sig": "run_job(job_id)", "desc": "작업 하나를 실행한다", "ref": "src/core/engine.py:4"}]},
        {"id": "agent-http", "title": "에이전트 호출", "from": "core", "to": "agent", "transport": "http",
         "items": [{"sig": "POST http://agent/run", "desc": "작업 id 전달", "ref": "src/core/engine.py:5"}]}
      ]
    },
    "L1-core": {
      "title": "L1 · 작업 엔진",
      "hint": "엔진 안쪽",
      "parent": "L0",
      "rules": [],
      "nodes": [
        {"id": "engine", "kind": "module", "title": "작업 실행기", "say": "작업을 실행하고 결과를 보낸다",
         "code": ["src/core/engine.py"], "row": 0, "col": 0, "paths": ["src/core/engine.py"]}
      ],
      "edges": [],
      "ifaces": []
    }
  },
  "unknowns": []
}
```

- [ ] **Step 2: v3 실패 테스트 추가**

`tests/unit/test_eli5_validate.sh` — 기존 `integrity '…' "규칙은" "규칙 graft 등급"` 줄 바로 아래에 추가:

```bash
integrity 'm["meta"]["version"]=2' "v3 지도만" "v2 모델 거부"
integrity 'm["meta"].pop("version")' "v3 지도만" "version 없음 거부"
integrity 'm["meta"]["summary"]=""' "summary 가 비었다" "summary 필수"
integrity 'm["views"]["L0"]["nodes"][0]["lines"]=["handle(req)"]' "lines 는 v3" "lines 잔존 거부"
integrity 'm["views"]["L0"]["nodes"][0]["kind"]="server"' "kind .server." "kind 허용값"
integrity 'm["views"]["L0"]["nodes"][0].pop("say")' "say 가 비었다" "say 필수"
integrity 'm["views"]["L0"]["nodes"][0]["say"]="graph.astream을 부른다"' "graph.astream" "say 에 코드 이름(조사 결합)"
integrity 'm["views"]["L0"]["nodes"][0]["title"]="요청을 받아서 검사하는 곳입니다"' "칸, 상한 24" "title 길이"
integrity 'm["views"]["L0"]["edges"][0]["label"]="run_job"' "run_job" "edge label 코드 이름"
integrity 'del m["meta"]["glossary"]["HTTP"]' "HTTP" "glossary 없는 용어"
integrity 'm["meta"]["glossary"]["graph.astream"]="그래프 실행"' "코드 이름이다" "glossary 우회 금지"
integrity 'm["meta"]["glossary"]["API"]=""' "풀이가 비었다" "glossary 빈 풀이"
fresh; edit 'm["views"]["L0"]["nodes"][0]["detail"]="handle(req) 가 run_job 을 부른다"'
out=$(run); [ $? -eq 0 ] && pass "detail 은 쉬운 말 검사 대상 아님" || fail "detail 검사 제외" "$out"
```

- [ ] **Step 3: 실패 확인**

Run: `bash tests/unit/test_eli5_validate.sh`
Expected: 새 v3 항목 12개 ❌ (`rc=0`), 기존 항목은 ✅ (v3 fixture 도 v2 검증기를 통과한다)

- [ ] **Step 4: 구현**

`skills/eli5/bin/validate.py` — `from pathlib import Path` 다음 줄에:

```python
sys.path.insert(0, str(Path(__file__).resolve().parent))
import plain  # noqa: E402
```

`def under(path, prefixes):` 바로 위에 새 함수:

```python
def v3_errors(model):
    """v3 지도 규칙 — 사람이 읽는 글에 코드 이름이 없고, 낯선 용어에 풀이가 있다."""
    meta = model.get("meta") or {}
    if meta.get("version") != 3:
        return [f"meta.version 이 {meta.get('version')!r} — v3 지도만 검증한다. v2 지도는 다시 만든다"]
    errs = []
    g = meta.get("glossary") or {}
    if not isinstance(g, dict):
        errs.append("meta.glossary 는 {용어: 풀이} 객체여야 한다")
        g = {}
    for k, v in g.items():
        if not isinstance(v, str) or not v.strip():
            errs.append(f"meta.glossary['{k}'] 풀이가 비었다 — 한 문장으로 쓴다")
    errs += plain.glossary_key_errors(g)
    s = meta.get("summary")
    if not isinstance(s, str) or not s.strip():
        errs.append("meta.summary 가 비었다 — 이 시스템이 무엇을 하는지 1~2문장으로 쓴다")
    else:
        errs += plain.check_plain("meta.summary", s, g)
    for vid, v in (model.get("views") or {}).items():
        errs += plain.check_plain(f"{vid}.title", v.get("title") or "", g)
        errs += plain.check_plain(f"{vid}.hint", v.get("hint") or "", g)
        for n in v.get("nodes", []):
            w = f"{vid}/{n.get('id')}"
            if "lines" in n:
                errs.append(f"{w}.lines 는 v3 에서 없어졌다 — 박스 한 줄은 say, 코드 이름은 code[], 긴 설명은 detail")
            if n.get("kind") not in plain.KINDS:
                errs.append(f"{w}.kind '{n.get('kind')}' — {' · '.join(plain.KINDS)} 중 하나")
            for field, limit in (("title", plain.TITLE_MAX), ("say", plain.SAY_MAX)):
                t = n.get(field)
                if not isinstance(t, str) or not t.strip():
                    errs.append(f"{w}.{field} 가 비었다 — 쉬운 말로 쓴다")
                else:
                    errs += plain.check_plain(f"{w}.{field}", t, g, limit)
            if not isinstance(n.get("code", []), list):
                errs.append(f"{w}.code 는 문자열 목록이어야 한다")
        for e in v.get("edges", []):
            if e.get("label"):
                errs += plain.check_plain(f"{vid}: {e.get('from')}→{e.get('to')} label", e["label"], g, plain.LABEL_MAX)
    return errs
```

`main()` 의 `errs = integrity_errors(model)` 를:

```python
    errs = integrity_errors(model) + v3_errors(model)
```

- [ ] **Step 5: 통과 확인**

Run: `bash tests/unit/test_eli5_validate.sh && bash tests/unit/test_eli5_prep.sh`
Expected: 두 파일 모두 `0 failed`

- [ ] **Step 6: 커밋**

```bash
git add skills/eli5/bin/validate.py tests/fixtures/eli5/model.json tests/unit/test_eli5_validate.sh
git commit -m "feat(eli5): v3 모델 검증 — 버전·summary·kind·say·glossary·쉬운 말·길이

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: `render.py` — v3 확인 · 원자적 쓰기 · `<!--` 이스케이프

**Files:**
- Modify: `skills/eli5/bin/render.py`
- Modify: `tests/unit/test_eli5_render.sh`

**Interfaces:**
- Consumes: v3 fixture (Task 2)
- Produces: `write_atomic(path: Path, text: str) -> None` (모듈 함수, Task 4 이후 재사용 가능). CLI 동작: `meta.version != 3` → stdout `{"error": "..."}` exit 1. 출력 파일 3개(html·사이드카·모델) 모두 `write_atomic` 로

- [ ] **Step 1: 실패 테스트 추가**

`tests/unit/test_eli5_render.sh` — `python3 "$ELI5_BIN/render.py" "$M" --root "$R" >/dev/null 2>&1 && fail "validate 전 render 거부" …` 줄 바로 아래에:

```bash
cp "$M" "$T/v2.model.json"
python3 - "$T/v2.model.json" <<'PY'
import json, sys
p = sys.argv[1]; m = json.load(open(p, encoding="utf-8")); m["meta"]["version"] = 2; m["validation"] = {}
json.dump(m, open(p, "w", encoding="utf-8"), ensure_ascii=False)
PY
out=$(python3 "$ELI5_BIN/render.py" "$T/v2.model.json" --root "$R"); rc=$?
[ $rc -eq 1 ] && echo "$out" | jq -e '.error|test("v3")' >/dev/null && pass "v2 모델 render 거부" || fail "v2 거부" "rc=$rc $out"
```

같은 파일의 hint 를 바꾸는 파이썬 블록에서 `m["views"]["L0"]["hint"] = "</script><b>x</b>"` 를:

```python
m["views"]["L0"]["hint"] = "</script><b>x</b><!--y-->"
```

그 아래 MODEL 파싱 확인 블록의 `assert model["views"]["L0"]["hint"] == "</script><b>x</b>"` 를:

```python
assert "<!--" not in h.split("const MODEL = ", 1)[1].split(";\n(function", 1)[0]
assert model["views"]["L0"]["hint"] == "</script><b>x</b><!--y-->"
```

`finish` 바로 위에 원자적 쓰기 테스트:

```bash
python3 - "$ELI5_BIN" "$T" <<'PY' && pass "원자적 쓰기 — 실패 시 기존 파일 보존·임시 파일 없음" || fail "원자적 쓰기"
import sys; from pathlib import Path
sys.path.insert(0, sys.argv[1]); import render
d = Path(sys.argv[2]); p = d / "a.html"; p.write_text("old", encoding="utf-8")
try:
    render.write_atomic(p, None)  # 쓰기 중 TypeError
except TypeError:
    pass
assert p.read_text(encoding="utf-8") == "old"
assert not [x for x in d.iterdir() if x.name.startswith(".a.html.")]
render.write_atomic(p, "new"); assert p.read_text(encoding="utf-8") == "new"
PY
```

- [ ] **Step 2: 실패 확인**

Run: `bash tests/unit/test_eli5_render.sh`
Expected: "v2 모델 render 거부" ❌, "MODEL 파싱 가능 + </script> 이스케이프" ❌(`<!--` 잔존), "원자적 쓰기" ❌(`write_atomic` 없음)

- [ ] **Step 3: 구현**

`skills/eli5/bin/render.py` 의 import 에 `import os`, `import tempfile` 추가. `def stem_of` 아래에:

```python
def write_atomic(path, text):
    """임시 파일에 다 쓴 뒤 교체한다 — 읽는 쪽이 반쯤 쓰인 파일을 보지 않게.
    deadhd (MIT, Copyright (c) 2026 lcalmsky) render.py 의 mkstemp → os.replace 방식."""
    path = Path(path)
    fd, tmp = tempfile.mkstemp(dir=str(path.parent), prefix="." + path.name + ".", suffix=".tmp")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            f.write(text)
        os.replace(tmp, path)
    except BaseException:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise
```

`main()` 에서 `model = json.loads(...)` 바로 다음에:

```python
    if (model.get("meta") or {}).get("version") != 3:
        print(json.dumps({"error": "v3 지도가 아니다 (meta.version != 3) — v2 지도는 다시 만든다"}, ensure_ascii=False))
        return 1
```

payload 줄을:

```python
    # 데이터 안의 문자열이 script 블록을 닫거나(</) HTML 주석을 열지(<!--) 못하게 한다. 둘 다 JS 문자열 이스케이프라 값은 그대로다.
    payload = json.dumps(model, ensure_ascii=False).replace("</", "<\\/").replace("<!--", "<\\u0021--")
```

`out.write_text(html, encoding="utf-8")` → `write_atomic(out, html)`, `sidecar.write_text(json.dumps({...}) + "\n", encoding="utf-8")` → `write_atomic(sidecar, json.dumps({...}) + "\n")`, `mp.write_text(...)` → `write_atomic(mp, json.dumps(model, ensure_ascii=False, indent=2) + "\n")`.

- [ ] **Step 4: 통과 확인**

Run: `bash tests/unit/test_eli5_render.sh`
Expected: `패널 계약(window.ELI5·이벤트)` 하나만 ❌ 로 남는다 (Task 5 에서 계약을 바꾼다). 나머지 ✅

- [ ] **Step 5: 커밋**

```bash
git add skills/eli5/bin/render.py tests/unit/test_eli5_render.sh
git commit -m "feat(eli5): render — v3 만 받고 원자적으로 쓰며 <!-- 를 이스케이프

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: `open.py` — Orca 탭/브라우저 열기 + 신선도

**Files:**
- Create: `skills/eli5/bin/open.py`
- Test: `tests/unit/test_eli5_open.sh`

**Interfaces:**
- Consumes: 렌더 산출물 `<stem>.html`, `<stem>.eli5.json` (사이드카 `{"version": 1, "commit", "scope", "dirty"}`)
- Produces:
  - `open.py open <html> [--mode auto|orca|browser|print]` → stdout 마지막 줄 `opened: orca-tab|browser|none <절대경로>`, exit 0. 파일 없으면 stderr + exit 2
  - `open.py status --model <x.model.json> [--root <repo>]` → stdout `{"map": "fresh|stale|unknown|missing"}`
  - 환경변수 `ELI5_OPEN_DRY=1` — 브라우저 명령을 실행하지 않고 `dry: <명령>` 출력 (Orca 는 dry 와 무관하게 실제 실행 — 테스트는 가짜 orca 로)

- [ ] **Step 1: 실패 테스트 작성**

`tests/unit/test_eli5_open.sh`:

```bash
#!/bin/bash
set -uo pipefail
source "$(dirname "$0")/../fixtures/eli5/lib.sh"
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
PY=$(command -v python3)
O="$ELI5_BIN/open.py"
R="$T/저장소 a:1"
bash "$ELI5_FIX/make_repo.sh" "$R"
export FAKE_GRAFT_CALLERS="$ELI5_FIX/callers.json"
mkdir -p "$R/.eli5"; M="$R/.eli5/app.model.json"; H="$R/.eli5/app.html"
cp "$ELI5_FIX/model.json" "$M"

echo "🔧 open.py status"
[ "$("$PY" "$O" status --model "$M" | jq -r .map)" = "missing" ] && pass "렌더 전 → missing" || fail "missing"
"$PY" "$ELI5_BIN/validate.py" "$M" --root "$R" >/dev/null && "$PY" "$ELI5_BIN/render.py" "$M" --root "$R" >/dev/null
[ "$("$PY" "$O" status --model "$M" | jq -r .map)" = "fresh" ] && pass "렌더 직후 → fresh" || fail "fresh" "$("$PY" "$O" status --model "$M")"
echo "# x" >> "$R/src/core/engine.py"; git -C "$R" -c user.email=t@t -c user.name=t commit -qam change
[ "$("$PY" "$O" status --model "$M" | jq -r .map)" = "stale" ] && pass "scope 코드 커밋 → stale" || fail "stale"
jq '.dirty=true' "$R/.eli5/app.eli5.json" > "$T/s" && mv "$T/s" "$R/.eli5/app.eli5.json"
[ "$("$PY" "$O" status --model "$M" | jq -r .map)" = "unknown" ] && pass "dirty 사이드카 → unknown" || fail "unknown"

echo "🔧 open.py open"
out=$("$PY" "$O" open "$H" --mode print)
[ "$out" = "opened: none $(cd "$(dirname "$H")" && pwd -P)/app.html" ] || [ "$out" = "opened: none $H" ] && pass "print 모드 → 경로만" || fail "print" "$out"
"$PY" "$O" open "$T/nope.html" >/dev/null 2>&1; [ $? -eq 2 ] && pass "없는 파일 → exit 2" || fail "없는 파일"

mkdir -p "$T/bin"
cat > "$T/bin/orca" <<'SH'
#!/bin/bash
echo "$@" >> "$FAKE_ORCA_LOG"
exit "${FAKE_ORCA_RC:-0}"
SH
chmod +x "$T/bin/orca"
export FAKE_ORCA_LOG="$T/orca.log"

out=$(env -u ORCA_WORKTREE_ID ELI5_OPEN_DRY=1 PATH="$T/bin:/usr/bin:/bin" "$PY" "$O" open "$H")
echo "$out" | grep -q '^opened: browser ' && [ ! -s "$FAKE_ORCA_LOG" ] && pass "auto · Orca 밖 → 브라우저" || fail "auto 브라우저" "$out"

out=$(ORCA_WORKTREE_ID=w1 ELI5_OPEN_DRY=1 PATH="$T/bin:/usr/bin:/bin" "$PY" "$O" open "$H")
echo "$out" | grep -q '^opened: orca-tab ' && pass "auto · Orca 안 → Orca 탭" || fail "auto orca" "$out"
grep -q -- '--url file://.*%EC%A0%80%EC%9E%A5%EC%86%8C%20a%3A1/.eli5/app.html' "$FAKE_ORCA_LOG" && pass "한글·공백 경로 인코딩" || fail "URL 인코딩" "$(cat "$FAKE_ORCA_LOG")"

out=$(FAKE_ORCA_RC=1 ORCA_WORKTREE_ID=w1 ELI5_OPEN_DRY=1 PATH="$T/bin:/usr/bin:/bin" "$PY" "$O" open "$H" 2>&1)
echo "$out" | grep -q 'skip: orca' && echo "$out" | grep -q '^opened: browser ' && pass "Orca 실패 → 브라우저로 대체" || fail "orca 실패 대체" "$out"

out=$(ELI5_OPEN_DRY=1 PATH="/usr/bin:/bin" "$PY" "$O" open "$H" --mode orca 2>&1)
echo "$out" | grep -q 'orca 명령 없음' && echo "$out" | grep -q '^opened: browser ' && pass "--mode orca · 명령 없음 → 브라우저" || fail "orca 없음" "$out"
finish
```

- [ ] **Step 2: 실패 확인**

Run: `bash tests/unit/test_eli5_open.sh`
Expected: open.py 가 없어 모든 항목 ❌

- [ ] **Step 3: 구현**

`skills/eli5/bin/open.py`:

```python
#!/usr/bin/env python3
"""eli5 지도 열기와 신선도 확인.

사용: open.py open <html> [--mode auto|orca|browser|print]
      open.py status --model <x.model.json> [--root <repo>]

열기 순서는 deadhd (MIT, Copyright (c) 2026 lcalmsky) skills/deadhd/open.sh 를 옮긴 것이다 —
Orca 안(ORCA_WORKTREE_ID)이면 Orca 탭, 실패하면 시스템 브라우저.
ELI5_OPEN_DRY=1 이면 브라우저를 실제로 띄우지 않고 명령만 출력한다 (테스트용).
"""
import argparse
import json
import os
import platform
import shutil
import subprocess
import sys
import urllib.parse
from pathlib import Path


def run(cmd):
    try:
        return subprocess.run(cmd, capture_output=True, timeout=15).returncode == 0
    except (OSError, subprocess.TimeoutExpired):
        return False


def open_browser(abs_path):
    dry = os.environ.get("ELI5_OPEN_DRY")
    cmds = []
    if platform.system() == "Darwin":
        cmds.append(["open", abs_path])
    if shutil.which("xdg-open"):
        cmds.append(["xdg-open", abs_path])
    for cmd in cmds:
        if dry:
            print("dry: " + " ".join(cmd))
            print(f"opened: browser {abs_path}")
            return
        if run(cmd):
            print(f"opened: browser {abs_path}")
            return
        print(f"skip: {cmd[0]} 실패", file=sys.stderr)
    print(f"opened: none {abs_path}")


def cmd_open(a):
    p = Path(a.html)
    if not p.is_file():
        print(f"no such file: {a.html}", file=sys.stderr)
        return 2
    abs_path = str(p.resolve())
    if a.mode == "print":
        print(f"opened: none {abs_path}")
        return 0
    if a.mode == "orca" or (a.mode == "auto" and os.environ.get("ORCA_WORKTREE_ID")):
        if not shutil.which("orca"):
            print("skip: orca 명령 없음", file=sys.stderr)
        elif run(["orca", "tab", "create", "--url", "file://" + urllib.parse.quote(abs_path), "--json"]):
            print(f"opened: orca-tab {abs_path}")
            return 0
        else:
            print("skip: orca tab create 실패", file=sys.stderr)
    open_browser(abs_path)
    return 0


def stem_of(p):
    return p.name[: -len(".model.json")] if p.name.endswith(".model.json") else p.stem


def map_status(model, root):
    html, sidecar = model.with_name(stem_of(model) + ".html"), model.with_name(stem_of(model) + ".eli5.json")
    if not html.exists():
        return "missing"
    try:
        sc = json.loads(sidecar.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return "unknown"
    if sc.get("version") != 1 or sc.get("dirty") or not sc.get("commit"):
        return "unknown"
    r = subprocess.run(["git", "-C", str(root), "diff", "--name-only", sc["commit"], "--", *(sc.get("scope") or ["."])],
                       capture_output=True, text=True)
    if r.returncode != 0:
        return "unknown"
    changed = [l for l in r.stdout.splitlines() if l and not l.startswith((".eli5/", "graft/"))]
    return "stale" if changed else "fresh"


def cmd_status(a):
    model = Path(a.model).resolve()
    if a.root:
        root = Path(a.root).resolve()
    else:
        r = subprocess.run(["git", "-C", str(model.parent), "rev-parse", "--show-toplevel"], capture_output=True, text=True)
        root = Path(r.stdout.strip()) if r.returncode == 0 else model.parent
    print(json.dumps({"map": map_status(model, root)}, ensure_ascii=False))
    return 0


def main():
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    o = sub.add_parser("open")
    o.add_argument("html")
    o.add_argument("--mode", choices=["auto", "orca", "browser", "print"], default="auto")
    s = sub.add_parser("status")
    s.add_argument("--model", required=True)
    s.add_argument("--root")
    a = ap.parse_args()
    return cmd_open(a) if a.cmd == "open" else cmd_status(a)


if __name__ == "__main__":
    sys.exit(main())
```

- [ ] **Step 4: 통과 확인**

Run: `bash tests/unit/test_eli5_open.sh`
Expected: `=== 11 passed, 0 failed ===`

- [ ] **Step 5: 커밋**

```bash
git add skills/eli5/bin/open.py tests/unit/test_eli5_open.sh
git commit -m "feat(eli5): open.py — Orca 탭 우선 열기와 지도 신선도 판정

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: 지도 템플릿 `map.html` v3

**Files:**
- Rewrite: `skills/eli5/assets/map.html`
- Modify: `tests/unit/test_eli5_render.sh` (패널 계약 줄 교체)

**Interfaces:**
- Consumes: v3 모델 (`meta.summary`, `meta.glossary`, node `kind`·`title`·`say`·`detail`·`code`·`paths`·`drill`, edge `grade`·`evidence`·`label`·`iface`, `validation.counts`·`downgrades`·`missing_edges`)
- Produces: 렌더된 HTML 의 DOM 계약 — `#title`, `#summary`, `#legend`, `#chips`, `#ev`(근거 토글 체크박스), `#svg`, `#side`(박스 카드/층 개요), `#unknowns`, `details#report` 안 `#downs`·`#missing`, 인터페이스 카드 id `card-<view>-<iface>`, `window.ELI5 = {MODEL, state, go, select}`. 2단계(시나리오)가 `#side`·`state`·`go`·`select` 를 쓴다

- [ ] **Step 1: 실패 테스트로 계약 교체**

`tests/unit/test_eli5_render.sh` 의

```bash
grep -q 'window.ELI5' "$H" && grep -q 'eli5:select' "$H" && pass "패널 계약(window.ELI5·이벤트)" || fail "패널 계약"
```

를 다음으로 바꾼다:

```bash
for id in summary legend chips ev side unknowns downs missing; do
  grep -q "id=\"$id\"" "$H" || { fail "DOM 계약 #$id"; continue; }
done && pass "DOM 계약 (summary·legend·chips·ev·side·unknowns·downs·missing)"
grep -q '<details id="report">' "$H" && pass "검증 리포트는 접힌 details" || fail "접힌 리포트"
grep -q 'window.ELI5 = {MODEL, state, go, select}' "$H" && pass "window.ELI5 계약" || fail "window.ELI5"
! grep -q 'eli5:select\|panel\|/api/ask' "$H" && pass "패널 흔적 없음" || fail "패널 흔적"
! grep -q 'n.lines' "$H" && pass "박스에 lines 를 그리지 않음" || fail "lines 잔존"
```

- [ ] **Step 2: 실패 확인**

Run: `bash tests/unit/test_eli5_render.sh`
Expected: DOM 계약·접힌 리포트·window.ELI5·lines 항목 ❌

- [ ] **Step 3: 템플릿 재작성**

`skills/eli5/assets/map.html` 전체를 다음으로 교체:

```html
<!doctype html>
<html lang="ko">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>__ELI5_TITLE__ — eli5</title>
<style>
:root{--bg:#fbfaf7;--fg:#1f2328;--muted:#656d76;--line:#d0d7de;--box:#ffffff;--accent:#0969da;--sel:#fff8c5;--edge:#8c959f;
  --graft:#1a7f37;--code:#0969da;--record:#9a6700;--unknown:#cf222e;
  --k-person:#8250df;--k-external:#6e7781;--k-service:#0969da;--k-module:#1a7f37;--k-store:#bc4c00;--k-job:#bf3989}
@media (prefers-color-scheme: dark){:root:not([data-theme="light"]){--bg:#0d1117;--fg:#e6edf3;--muted:#8d96a0;--line:#30363d;--box:#161b22;--accent:#4493f8;--sel:#3b2e00;--edge:#6e7681;
  --graft:#3fb950;--code:#4493f8;--record:#d29922;--unknown:#f85149;
  --k-person:#a371f7;--k-external:#8d96a0;--k-service:#4493f8;--k-module:#3fb950;--k-store:#f0883e;--k-job:#db61a2}}
:root[data-theme="dark"]{--bg:#0d1117;--fg:#e6edf3;--muted:#8d96a0;--line:#30363d;--box:#161b22;--accent:#4493f8;--sel:#3b2e00;--edge:#6e7681;
  --graft:#3fb950;--code:#4493f8;--record:#d29922;--unknown:#f85149;
  --k-person:#a371f7;--k-external:#8d96a0;--k-service:#4493f8;--k-module:#3fb950;--k-store:#f0883e;--k-job:#db61a2}
*{box-sizing:border-box}
body{margin:0;background:var(--bg);color:var(--fg);font:14px/1.55 -apple-system,BlinkMacSystemFont,"Apple SD Gothic Neo",sans-serif}
main{max-width:1320px;margin:0 auto;padding:16px}
h1{font-size:20px;margin:0 0 4px}
.summary{margin:0 0 10px;font-size:15px}
.meta-row{display:flex;flex-wrap:wrap;gap:6px 16px;align-items:center;font-size:12px;color:var(--muted)}
.legend .kd{margin-right:10px;white-space:nowrap}
.legend .kd i,.side .k i{display:inline-block;width:10px;height:10px;border-radius:2px;margin-right:4px;vertical-align:-1px}
.chips span{display:inline-block;padding:0 8px;border-radius:10px;border:1px solid var(--line);margin-right:4px}
.chips .warn{color:var(--unknown);border-color:currentColor}
.toggle{cursor:pointer;user-select:none}
#evlegend{font-size:12px;color:var(--muted);margin:6px 0 0}
#evlegend i{display:inline-block;width:22px;border-top:2px solid;margin:0 4px 3px 10px;vertical-align:middle}
#evlegend i.g-code,#evlegend i.g-record{border-top-style:dashed}#evlegend i.g-unknown{border-top-style:dotted}
nav{margin:12px 0 4px;font-size:13px} nav a{color:var(--accent);cursor:pointer}
.hint{color:var(--muted);margin:2px 0 8px}
ul{margin:0 0 12px;padding-left:18px}
.layout{display:grid;grid-template-columns:minmax(0,1fr) 340px;gap:16px;align-items:start}
.diagram{overflow-x:auto;border:1px solid var(--line);border-radius:8px;background:var(--box)}
aside.side{border:1px solid var(--line);border-radius:8px;background:var(--box);padding:12px 14px;position:sticky;top:12px;max-height:calc(100vh - 24px);overflow:auto}
@media (max-width:900px){.layout{grid-template-columns:1fr}aside.side{position:static;max-height:none}}
svg text{fill:var(--fg);font-size:12px}
.node{cursor:pointer}
.node rect.bg{fill:var(--box);stroke:var(--line);stroke-width:1.5}
.node.drill rect.bg{stroke:var(--fg);stroke-width:2.5}
.node.sel rect.bg{fill:var(--sel)}
.node .title{font-weight:600;font-size:13px}
.node .sub{fill:var(--muted);font-size:11px}
.node .go{fill:var(--accent);font-size:11px}
.k-person{fill:var(--k-person)}.k-external{fill:var(--k-external)}.k-service{fill:var(--k-service)}
.k-module{fill:var(--k-module)}.k-store{fill:var(--k-store)}.k-job{fill:var(--k-job)}
.edge path{fill:none;stroke-width:1.8}
.edge.dim{opacity:.15}
.edge .lbl-bg{fill:var(--box)}
.edge text{font-size:11px;stroke:none;fill:currentColor}
.g-n{stroke:var(--edge);color:var(--muted)}
.g-graft{stroke:var(--graft);color:var(--graft)}
.g-code{stroke:var(--code);color:var(--code);stroke-dasharray:6 4}
.g-record{stroke:var(--record);color:var(--record);stroke-dasharray:4 3}
.g-unknown{stroke:var(--unknown);color:var(--unknown);stroke-dasharray:2 4}
.side h2{font-size:16px;margin:4px 0 6px}.side h3{font-size:12px;color:var(--muted);margin:14px 0 4px;font-weight:600}
.side .k{font-size:12px;color:var(--muted)}
.side .detail{color:var(--muted)}
.card{border:1px solid var(--line);border-radius:8px;padding:8px 10px;margin:6px 0;background:var(--bg)}
.card.flash{outline:2px solid var(--accent)}
.card .t{font-weight:600}.card .m{color:var(--muted);font-size:12px}
.conn{margin:4px 0}
code{font:12px ui-monospace,SFMono-Regular,Menlo,monospace}
.chip{font:11px ui-monospace,SFMono-Regular,Menlo,monospace;padding:1px 8px;border-radius:10px;border:1px solid var(--line);background:none;color:var(--muted);cursor:pointer;margin:2px 4px 2px 0}
.tag{font-size:11px;padding:0 6px;border-radius:8px;border:1px solid currentColor;margin-left:4px}
abbr{text-decoration:underline dotted;cursor:help}
button.link{background:none;border:0;color:var(--accent);cursor:pointer;padding:0;font:inherit}
h2.sec{font-size:15px;margin:20px 0 8px}
details#report{margin:20px 0;color:var(--muted)} details#report summary{cursor:pointer}
details#report h3{font-size:13px;margin:12px 0 4px}
@media (max-width:640px){main{padding:12px 16px}}
</style>
</head>
<body>
<main>
<header>
  <h1 id="title"></h1>
  <p class="summary" id="summary"></p>
  <div class="meta-row">
    <span class="legend" id="legend"></span>
    <span class="chips" id="chips"></span>
    <label class="toggle"><input type="checkbox" id="ev"> 근거 보기</label>
  </div>
  <div id="evlegend" hidden>근거: <i class="g-graft"></i>graft 증명 <i class="g-code"></i>코드 읽음 <i class="g-record"></i>기록 해석 <i class="g-unknown"></i>미확인 (미확인은 항상 표시)</div>
</header>
<nav id="crumbs"></nav>
<div class="hint" id="hint"></div>
<ul id="rules"></ul>
<div class="layout">
  <div class="diagram"><svg id="svg" role="img" aria-label="구조 지도"></svg></div>
  <aside class="side" id="side"></aside>
</div>
<h2 class="sec">확인 못 한 것</h2><ul id="unknowns"></ul>
<details id="report"><summary>검증 리포트</summary>
  <h3>검증에서 강등된 주장</h3><ul id="downs"></ul>
  <h3>그림에 없는 관계 (graft 가 찾음)</h3><ul id="missing"></ul>
</details>
</main>
<script>
const MODEL = /*__ELI5_MODEL__*/null;
(function () {
  const W = 200, H = 72, GX = 90, GY = 60, PAD = 30, NS = "http://www.w3.org/2000/svg";
  let gx = GX;  // 열 간격 — view 마다 가장 긴 화살표 라벨이 박스 사이에 들어가도록 넓힌다
  const GRADE = {graft: "graft 증명", code: "코드 읽음", record: "기록 해석", unknown: "미확인", n: "근거 숨김"};
  const KIND = {person: "사람", external: "외부 시스템", service: "서비스", module: "내부 모듈", store: "저장소", job: "작업"};
  const $ = id => document.getElementById(id);
  const esc = s => String(s ?? "").replace(/[&<>"]/g, c => ({"&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;"}[c]));
  const views = MODEL.views, meta = MODEL.meta || {}, gloss = meta.glossary || {};
  const rootView = Object.keys(views).find(k => !views[k].parent) || Object.keys(views)[0];
  const state = {view: null, node: null, ev: false};

  // 용어 풀이 — 긴 용어부터, ASCII 경계 검사 (deadhd linkify 방식)
  const TERMS = Object.keys(gloss).sort((a, b) => b.length - a.length);
  const reEsc = s => s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  const TERM_RE = TERMS.length ? new RegExp("(?<![A-Za-z0-9_])(" + TERMS.map(t => reEsc(esc(t))).join("|") + ")(?![A-Za-z0-9_])", "g") : null;
  const rich = text => { const h = esc(text); return TERM_RE ? h.replace(TERM_RE, t => `<abbr title="${esc(gloss[t] ?? gloss[t.replace(/&amp;/g, "&")] ?? "")}">${t}</abbr>`) : h; };
  const termsIn = (...texts) => TERMS.filter(t => texts.some(x => x && new RegExp("(?<![A-Za-z0-9_])" + reEsc(t) + "(?![A-Za-z0-9_])").test(x)));
  const short = s => String(s).split(" → ").map(p => p.replace(/^.*\//, "")).join(" → ");
  const chip = full => full ? `<button class="chip" type="button" data-copy="${esc(full)}" title="${esc(full)} — 누르면 복사">${esc(short(full))}</button>` : "";
  const nodeTitle = (vid, id) => ((views[vid].nodes || []).find(n => n.id === id) || {}).title || id;

  function el(tag, attrs, parent) {
    const e = document.createElementNS(NS, tag);
    for (const k in attrs) e.setAttribute(k, attrs[k]);
    if (parent) parent.appendChild(e);
    return e;
  }
  function box(n) {
    const span = n.span || 1;
    return {x: PAD + (n.col || 0) * (W + gx), y: PAD + (n.row || 0) * (H + GY), w: span * W + (span - 1) * gx, h: H};
  }
  function clip(b, tx, ty) {
    const cx = b.x + b.w / 2, cy = b.y + b.h / 2, dx = tx - cx, dy = ty - cy;
    if (!dx && !dy) return [cx, cy];
    const s = Math.min(Math.abs(b.w / 2 / (dx || 1e-9)), Math.abs(b.h / 2 / (dy || 1e-9)));
    return [cx + dx * s, cy + dy * s];
  }
  function evText(ev) {
    if (!ev) return "";
    if (ev.ref) return ev.ref;
    if (ev.from_sym) return `${ev.from_sym} → ${ev.to_sym}`;
    return "";
  }
  const shown = e => (state.ev || e.grade === "unknown") ? e.grade : "n";

  function header() {
    const val = MODEL.validation || {}, c = val.counts || {};
    $("title").textContent = meta.target || "eli5";
    $("summary").innerHTML = rich(meta.summary || "");
    const kinds = [...new Set(Object.values(views).flatMap(v => (v.nodes || []).map(n => n.kind)))].filter(k => KIND[k]);
    $("legend").innerHTML = kinds.map(k => `<span class="kd"><i style="background:var(--k-${k})"></i>${KIND[k]}</span>`).join("");
    const chips = [`<span>근거 graft ${c.graft || 0} · 코드 ${c.code || 0} · 기록 ${c.record || 0} · 미확인 ${c.unknown || 0}</span>`];
    if (val.quick) chips.push('<span class="warn">미검증 (--quick)</span>');
    if (val.graft === "absent") chips.push('<span class="warn">graft 없음 — 실선 판정 불가</span>');
    if (meta.commit) chips.push(`<span>commit ${esc(meta.commit.slice(0, 7))}</span>`);
    $("chips").innerHTML = chips.join("");
    $("ev").onchange = () => { state.ev = $("ev").checked; $("evlegend").hidden = !state.ev; draw(); side(); };
  }
  function crumbs() {
    const chain = [];
    for (let v = state.view; v; v = views[v].parent) chain.unshift(v);
    $("crumbs").innerHTML = chain.map((v, i) => i < chain.length - 1
      ? `<a data-v="${esc(v)}">${esc(views[v].title)}</a> › ` : `<b>${esc(views[v].title)}</b>`).join("");
    $("crumbs").querySelectorAll("a").forEach(a => a.onclick = () => go(a.dataset.v));
  }
  function draw() {
    const v = views[state.view], svg = $("svg");
    svg.innerHTML = "";
    gx = GX;
    for (const e of v.edges || []) {
      if (!e.label) continue;
      const m = el("text", {}, svg);
      m.textContent = e.label;
      try { gx = Math.max(gx, m.getBBox().width + 24); } catch (_) {}
      m.remove();
    }
    const nodes = Object.fromEntries((v.nodes || []).map(n => [n.id, n]));
    let mx = 0, my = 0;
    for (const n of v.nodes || []) { const b = box(n); mx = Math.max(mx, b.x + b.w); my = Math.max(my, b.y + b.h); }
    svg.setAttribute("viewBox", `0 0 ${mx + PAD} ${my + PAD}`);
    svg.setAttribute("width", mx + PAD);
    svg.setAttribute("height", my + PAD);
    const defs = el("defs", {}, svg);
    for (const g of Object.keys(GRADE)) {
      const m = el("marker", {id: "ah-" + g, viewBox: "0 0 10 10", refX: "9", refY: "5", markerWidth: "7", markerHeight: "7", orient: "auto-start-reverse"}, defs);
      el("path", {d: "M0,0 L10,5 L0,10 z", class: "g-" + g, style: "fill:currentColor;stroke:none;stroke-dasharray:none"}, m);
    }
    for (const e of v.edges || []) {
      const a = nodes[e.from], b = nodes[e.to];
      if (!a || !b) continue;
      const A = box(a), B = box(b), g2 = shown(e);
      const [x1, y1] = clip(A, B.x + B.w / 2, B.y + B.h / 2), [x2, y2] = clip(B, A.x + A.w / 2, A.y + A.h / 2);
      const dim = state.node && e.from !== state.node && e.to !== state.node;
      const g = el("g", {class: "edge" + (dim ? " dim" : "")}, svg);
      el("path", {d: `M${x1},${y1} L${x2},${y2}`, class: "g-" + g2, "marker-end": `url(#ah-${g2})`}, g);
      if (e.label) {
        const t = el("text", {x: (x1 + x2) / 2, y: (y1 + y2) / 2 - 4, "text-anchor": "middle", class: "g-" + g2}, g);
        t.textContent = e.label;
        try { const bb = t.getBBox(); g.insertBefore(el("rect", {x: bb.x - 3, y: bb.y - 1, width: bb.width + 6, height: bb.height + 2, class: "lbl-bg"}), t); } catch (_) {}
      }
      el("title", {}, g).textContent = GRADE[e.grade] + (evText(e.evidence) ? " — " + evText(e.evidence) : "");
      if (e.iface) { g.style.cursor = "pointer"; g.addEventListener("click", () => flash(state.view, e.iface)); }
    }
    for (const n of v.nodes || []) {
      const B = box(n);
      const g = el("g", {class: "node" + (n.drill ? " drill" : "") + (state.node === n.id ? " sel" : "")}, svg);
      el("rect", {x: B.x, y: B.y, width: B.w, height: B.h, rx: 6, class: "bg"}, g);
      el("rect", {x: B.x + 1, y: B.y + 1, width: 5, height: B.h - 2, rx: 2, class: "k-" + (n.kind || "module")}, g);
      el("text", {x: B.x + 16, y: B.y + 27, class: "title"}, g).textContent = n.title;
      el("text", {x: B.x + 16, y: B.y + 47, class: "sub"}, g).textContent = n.say || "";
      const terms = termsIn(n.title, n.say);
      el("title", {}, g).textContent = (KIND[n.kind] || "") + terms.map(t => `\n${t}: ${gloss[t]}`).join("");
      if (n.drill) {
        const d = el("text", {x: B.x + B.w - 10, y: B.y + B.h - 8, "text-anchor": "end", class: "go"}, g);
        d.textContent = "안으로 ▸";
        d.addEventListener("click", ev => { ev.stopPropagation(); go(n.drill); });
      }
      g.addEventListener("click", () => select(state.node === n.id ? null : n.id));
    }
  }
  function ifaceCard(f) {
    return `<div class="card" id="card-${esc(state.view)}-${esc(f.id)}">
      <div class="t">${rich(f.title)}</div><div class="m">${esc(nodeTitle(state.view, f.from))} → ${esc(nodeTitle(state.view, f.to))} · ${esc(f.transport || "")}</div>
      ${(f.items || []).map(it => `<div><code>${esc(it.sig)}</code> ${rich(it.desc || "")} ${chip(it.ref)}</div>`).join("")}
    </div>`;
  }
  function side() {
    const v = views[state.view], n = state.node && (v.nodes || []).find(x => x.id === state.node);
    if (!n) {
      const list = v.ifaces || [];
      $("side").innerHTML = `<h2>${esc(v.title)}</h2><p class="detail">박스를 누르면 하는 일과 들어 있는 코드가 여기 나온다.</p>`
        + (list.length ? `<h3>이 층의 인터페이스 ${list.length}개</h3>` + list.map(ifaceCard).join("") : "");
      return;
    }
    const conns = (v.edges || []).filter(e => e.from === n.id || e.to === n.id).map(e => {
      const out = e.from === n.id, other = nodeTitle(state.view, out ? e.to : e.from);
      return `<div class="conn">${out ? "→" : "←"} ${esc(other)} — ${esc(e.label || "")} <span class="tag g-${esc(e.grade)}">${GRADE[e.grade]}</span> ${chip(evText(e.evidence))}</div>`;
    }).join("");
    const code = [...(n.code || []), ...(n.paths || [])];
    const ifs = (v.ifaces || []).filter(f => f.from === n.id || f.to === n.id);
    const terms = termsIn(n.title, n.say, n.detail);
    $("side").innerHTML = `<div class="k"><i style="background:var(--k-${esc(n.kind)})"></i>${KIND[n.kind] || ""}</div>
      <h2>${rich(n.title)}</h2><p>${rich(n.say || "")}</p>${n.detail ? `<p class="detail">${rich(n.detail)}</p>` : ""}
      ${n.drill ? `<p><button class="link" type="button" data-go="${esc(n.drill)}">안으로 들어가기 ▸</button></p>` : ""}
      ${conns ? `<h3>연결</h3>${conns}` : ""}
      ${code.length ? `<h3>들어 있는 코드</h3>${code.map(chip).join("")}` : ""}
      ${ifs.length ? `<h3>인터페이스</h3>${ifs.map(ifaceCard).join("")}` : ""}
      ${terms.length ? `<h3>용어</h3>${terms.map(t => `<div><b>${esc(t)}</b> — ${esc(gloss[t])}</div>`).join("")}` : ""}
      <p><button class="link" type="button" data-close>닫기</button></p>`;
  }
  $("side").addEventListener("click", ev => {
    const t = ev.target.closest && ev.target.closest("[data-copy],[data-go],[data-close]");
    if (!t) return;
    if (t.dataset.go) return go(t.dataset.go);
    if (t.hasAttribute("data-close")) return select(null);
    const text = t.dataset.copy, label = t.textContent;
    try { navigator.clipboard.writeText(text); } catch (_) {}
    t.textContent = "복사됨"; setTimeout(() => { t.textContent = label; }, 900);
  });
  function lists() {
    const v = views[state.view], val = MODEL.validation || {};
    $("hint").innerHTML = rich(v.hint || "");
    $("rules").innerHTML = (v.rules || []).map(r =>
      `<li>${rich(r.text)} <span class="tag g-${esc(r.grade)}">${GRADE[r.grade] || esc(r.grade)}</span> ${chip(evText(r.evidence))}</li>`).join("");
    $("unknowns").innerHTML = (MODEL.unknowns || []).map(u => `<li>${esc(u.text)} <span class="detail">— ${esc(u.why || "")}</span></li>`).join("") || "<li>없음</li>";
    const miss = val.missing_edges || [];
    $("missing").innerHTML = miss.length
      ? miss.map(m => `<li>[${esc(views[m.view] ? views[m.view].title : m.view)}] ${esc(views[m.view] ? nodeTitle(m.view, m.from) : m.from)} → ${esc(views[m.view] ? nodeTitle(m.view, m.to) : m.to)} ${chip(m.example)}</li>`).join("")
      : `<li>${esc(val.missing_edges_skipped || "없음")}</li>`;
    const d = val.downgrades || [];
    $("downs").innerHTML = d.length
      ? d.map(x => `<li>${esc(x.id)} — ${GRADE[x.claimed]} → <b>${GRADE[x.result]}</b> <span class="detail">${esc(x.reason)}</span></li>`).join("")
      : "<li>없음</li>";
  }
  function go(vid) {
    if (!views[vid]) return;
    state.view = vid; state.node = null;
    if (location.hash !== "#view=" + encodeURIComponent(vid)) history.replaceState(null, "", "#view=" + encodeURIComponent(vid));
    crumbs(); lists(); draw(); side();
  }
  function select(nid) {
    state.node = nid; draw(); side();
  }
  function flash(vid, ifaceId) {
    if (state.view !== vid) go(vid);
    if (state.node) select(null);
    const c = document.getElementById(`card-${vid}-${ifaceId}`);
    if (!c) return;
    c.scrollIntoView({behavior: "smooth", block: "center"});
    c.classList.add("flash");
    setTimeout(() => c.classList.remove("flash"), 1600);
  }
  window.addEventListener("hashchange", () => {
    const m = location.hash.match(/^#view=(.+)$/);
    if (m) { const v = decodeURIComponent(m[1]); if (v !== state.view) go(v); }
  });
  window.ELI5 = {MODEL, state, go, select};
  header();
  const m = location.hash.match(/^#view=(.+)$/);
  go(m && views[decodeURIComponent(m[1])] ? decodeURIComponent(m[1]) : rootView);
})();
</script>
</body>
</html>
```

- [ ] **Step 4: 통과 확인**

Run: `bash tests/unit/test_eli5_render.sh`
Expected: `0 failed`

- [ ] **Step 5: 브라우저로 화면 확인 (스크립트가 못 보는 결함)**

```bash
T=$(mktemp -d) && bash tests/fixtures/eli5/make_repo.sh "$T/r" && mkdir -p "$T/r/.eli5" \
 && cp tests/fixtures/eli5/model.json "$T/r/.eli5/app.model.json" \
 && FAKE_GRAFT_CALLERS=$PWD/tests/fixtures/eli5/callers.json ELI5_GRAFT_BIN=$PWD/tests/fixtures/eli5/bin/graft \
    python3 skills/eli5/bin/validate.py "$T/r/.eli5/app.model.json" --root "$T/r" >/dev/null \
 && python3 skills/eli5/bin/render.py "$T/r/.eli5/app.model.json" --root "$T/r" \
 && (cd "$T/r/.eli5" && python3 -m http.server 8799 --bind 127.0.0.1 >/dev/null 2>&1 &) && echo "http://127.0.0.1:8799/app.html"
```

Chrome 자동화(`mcp__claude-in-chrome__*`)로 연다. Chrome 확장은 `file://` 을 못 연다 — 위처럼 `http.server` 로 띄운다. 확인할 것 (각각 스크린샷):
1. `#view=L0` — 박스 3개에 색 띠·title·say 만, 코드 글자 없음. 화살표는 회색 실선, `agent → api` 만 빨간 점선
2. "근거 보기" 체크 → `api→core` 초록 실선, `core→agent` 파란 점선, 근거 범례 표시
3. `작업 엔진` 박스 클릭 → 오른쪽에 종류·title·say·detail·"안으로 들어가기"·연결(근거 칩)·들어 있는 코드 칩·인터페이스 카드. 칩 클릭 → "복사됨"
4. hint 의 `API`·`HTTP` 에 점선 밑줄, 마우스 올리면 풀이
5. 창 폭 800px — 카드가 지도 아래로
6. 검증 리포트가 접혀 있고 펼치면 강등·그림에 없는 관계

끝나면 서버를 끈다: `kill $(lsof -tiTCP:8799 -sTCP:LISTEN)`. 결함이 있으면 템플릿을 고치고 Step 4 부터 다시.

- [ ] **Step 6: 커밋**

```bash
git add skills/eli5/assets/map.html tests/unit/test_eli5_render.sh
git commit -m "feat(eli5): 지도 v3 — 박스는 쉬운 이름 한 줄, 설명·근거는 오른쪽 카드, 근거 토글

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: 질문 패널·서버 제거와 테스트 배선

**Files:**
- Delete: `skills/eli5/bin/server.py`, `skills/eli5/assets/panel.html`, `skills/eli5/assets/answer-rules.md`, `tests/unit/test_eli5_server.sh`, `tests/fixtures/eli5/bin/claude`
- Modify: `tests/fixtures/eli5/lib.sh` (마지막 줄 `export ELI5_CLAUDE_BIN=...` 삭제)
- Modify: `lint.sh` (eli5 루프 `for t in prep validate render; do` → `for t in prep plain validate render open; do`)
- Modify: `test.sh` (`test_eli5` 함수)

**Interfaces:**
- Consumes: Task 1·4 의 새 테스트 파일
- Produces: 저장소에 `server.py`·`panel.html`·`answer-rules.md`·`ELI5_CLAUDE_BIN` 참조가 0

- [ ] **Step 1: 남은 참조가 있음을 확인 (실패 상태)**

Run: `grep -rn 'server.py\|panel.html\|answer-rules\|ELI5_CLAUDE_BIN\|test_eli5_server' skills tests lint.sh test.sh`
Expected: 여러 줄 (SKILL.md, lib.sh, test.sh 등)

- [ ] **Step 2: 삭제와 배선**

```bash
git rm -q skills/eli5/bin/server.py skills/eli5/assets/panel.html skills/eli5/assets/answer-rules.md \
  tests/unit/test_eli5_server.sh tests/fixtures/eli5/bin/claude
sed -i '' '/ELI5_CLAUDE_BIN/d' tests/fixtures/eli5/lib.sh
sed -i '' 's/for t in prep validate render; do/for t in prep plain validate render open; do/' lint.sh
```

`test.sh` 의 `test_eli5()` 함수 전체를 다음으로 교체:

```bash
# ─── eli5 유닛 테스트 ───

test_eli5() {
  echo "🔬 eli5 유닛 테스트"
  local t
  for t in prep plain validate render open; do
    if bash "tests/unit/test_eli5_$t.sh"; then
      pass "eli5 $t"
    else
      fail "eli5 $t"
    fi
  done
  echo ""
}
```

(바로 위 주석 `# ─── eli5 서버 테스트 ───` 도 위 블록의 주석으로 대체된다)

- [ ] **Step 3: 확인**

Run: `grep -rn 'server.py\|panel.html\|answer-rules\|ELI5_CLAUDE_BIN\|test_eli5_server' tests lint.sh test.sh; ./test.sh eli5`
Expected: grep 결과 없음 (SKILL.md 의 참조는 Task 7 에서 정리). `./test.sh eli5` 의 5개 모두 ✅

- [ ] **Step 4: 커밋**

```bash
git add -A tests lint.sh test.sh skills/eli5
git commit -m "refactor(eli5): 질문 패널과 서버 제거 — 지도는 HTML 파일 하나로 연다

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 7: `SKILL.md` v3 와 안내 문서

**Files:**
- Rewrite: `skills/eli5/SKILL.md`
- Modify: `commands/help.md` (`### eli5` 절의 코드 블록 전체, 17·43·60행 설명은 유지)
- Modify: `README.md:58`, `README.md:108-109`
- Modify: `CHANGELOG.md` (`## [Unreleased]` → `### Added` 바로 아래 첫 항목으로)

**Interfaces:**
- Consumes: Task 1~6 의 CLI — `validate.py`, `render.py`, `open.py open|status`
- Produces: 사용자·에이전트가 읽는 v3 절차

- [ ] **Step 1: 낡은 참조 확인 (실패 상태)**

Run: `grep -n 'server.py\|패널\|panel\|lines\|stop' skills/eli5/SKILL.md | head`
Expected: 여러 줄

- [ ] **Step 2: SKILL.md 재작성**

`skills/eli5/SKILL.md` 전체:

````markdown
---
name: eli5
description: "코드베이스·시스템 구조를 코드를 읽지 않는 사람도 한눈에 이해하는 드릴다운 HTML 지도로 만든다. 박스는 쉬운 이름 한 줄, 코드 이름·근거는 박스를 누르면 펼쳐지는 카드에. 화살표마다 graft 호출 그래프·소스 인용·기록으로 근거를 기계 판정하고(토글로 표시), 박스·화살표 글에 코드 이름이 섞이거나 풀이 없는 용어가 있으면 검증기가 거부한다. '그림으로 설명해줘', '구조 좀 그려줘', '이 코드 어떻게 도는지 보여줘', '아키텍처 지도', '/rakis:eli5 <대상>' 일 때 사용. 낯선 모듈 파악·설계 검토·장애 경로 추적·구현 전 정렬 확인."
version: 3.0.0
license: MIT
---

# eli5 — 코드를 안 읽는 사람이 읽는 지도

이 지도의 1차 독자는 **코드를 직접 읽지 않는 사람**이다. 박스에는 하는 일을 쉬운 말로 쓰고, 코드 이름과 근거는 박스를 누르면 펼쳐지는 카드에 둔다.

정돈된 상자와 화살표는 정확하다는 인상을 준다. 그래서 **LLM 은 내용만 쓰고, 판정과 그리기는 스크립트가 한다.**

- 화살표의 진위는 `validate.py` 가 graft 호출 그래프·파일·git 으로 판정한다. 확인되지 않은 주장은 자동 강등된다
- 박스·화살표 글의 쉬운 말과 길이도 `validate.py` 가 검사한다. 코드 이름이 섞이거나 풀이 없는 용어가 있으면 거부한다
- HTML 은 `render.py` 가 고정 템플릿으로 만든다. LLM 은 HTML 을 쓰지 않는다

쓰임은 **구현 전에 사람과 에이전트가 같은 시스템을 보고 있는지 확인하는 것**이다. 지도를 보다 생긴 질문은 이 세션에서 바로 묻는다 — 조사 맥락이 여기 남아 있다.

## 인자

```
/rakis:eli5 <설명할 대상> [--out <dir>] [--quick] [--no-open]
/rakis:eli5 open [<model.json>]      기존 지도를 다시 연다
```

- `--out` — 출력 폴더. 기본 `<레포>/.eli5/` (`.git/info/exclude` 로 숨긴다)
- `--quick` — 인용 줄 대조(quote)와 Phase 5 렌더링 확인을 생략한다. 지도에 "미검증" 배지가 붙고, **구현·리뷰의 근거로 쓰지 않는다.** 무결성·쉬운 말 검사와 graft 판정은 생략하지 않는다
- `--no-open` — 지도만 만들고 열지 않는다

## 경로 약속

- `$SKILL` = 이 스킬의 base directory (호출 시 "Base directory for this skill" 로 주어진다). 스크립트는 `$SKILL/bin/`
- `$ROOT` = 대상 git 레포 루트. `$OUT` = `--out` 또는 `$ROOT/.eli5`
- slug = 대상을 영문 kebab-case 3~5 단어로 축약
- `$MODEL` = `$OUT/<slug>.model.json` → 지도 `$OUT/<slug>.html`, 사이드카 `$OUT/<slug>.eli5.json`

## 원칙

- 코드 실행 순서가 아니라 **사람과 시스템이 주고받는 일의 순서**로 그린다
- **모르는 것은 그리지 않는다.** 그려야 한다면 `unknown` 등급으로 그리고 `unknowns` 에 남긴다
- 박스에는 하는 일. 코드 이름은 `code[]`, 긴 설명은 `detail`, 호출 시그니처는 인터페이스 카드
- 대상 레포의 추적 파일을 바꾸지 않는다

## 문체 규칙

- `${XDG_CONFIG_HOME:-~/.config}/rakis/eli5-writing-rules.md` 가 있으면 그것을 따른다
- 없으면: 하는 일을 쓴다 · 코드 이름을 쓰지 않는다 · 시스템을 의인화하지 않는다 · 박스 이름은 명사구 · 사용자의 언어로

## Phase 0: graft 준비

```bash
git -C "$ROOT" status --short    # 출력을 기억해 둔다 — Phase 6 에서 대조
python3 "$SKILL/bin/graft_prep.py" --root "$ROOT" --out-dir "<$OUT 의 $ROOT 상대경로>"
```

출력의 `graft` 값(`ok`·`index-built`·`absent`)을 기억해 Phase 3 에 넘긴다. `absent` 면 "graft 가 없어 실선(증명) 화살표를 만들 수 없다" 고 한 줄 알리고 계속한다. `error` 면 내용을 보여주고 멈춘다.

## Phase 1: 조사 — 그림보다 먼저

읽지 않은 것은 그리지 않는다. 추적 순서: 진입점 → 호출 경로 → 데이터 저장소 → 오류·롤백 경로.

1. `graft map` — 디렉터리 클러스터·허브로 레이어 후보를 잡는다
2. `graft ask "<대상>" --source` — 흐름의 핵심 심볼과 `file:line`
3. 박스 간 관계 후보마다 `graft callers <심볼> --json` (`--direction out` 으로 callee) — **여기서 본 노드 id(`path#symbol`)를 그대로 메모한다.** 이것이 graft 등급의 증거다
4. graft 가 못 보는 관계 — HTTP·큐·subprocess·설정 기반 연결 — 는 소스를 직접 읽는다. 호출하는 줄의 `path:line` 과 그 줄의 짧은 문자열(quote)을 메모한다
5. 코드로 "왜" 가 확정되지 않으면 ADR·`docs/`·이슈·PR 본문·`git log -p --follow <file>` 을 읽는다

대상이 코드가 아니면(개념·프로토콜·외부 서비스) 조사 대상을 문서로 바꾸되 근거는 똑같이 남긴다.

## Phase 2: 모델 작성

`$MODEL` 을 쓴다.

```json
{
  "meta": {"version": 3, "target": "<대상>",
           "summary": "<이 시스템이 무엇을 하는지 1~2문장, 쉬운 말>",
           "glossary": {"PostgreSQL": "<한 문장 풀이>"},
           "scope": ["src/"], "graft_version": "<Phase 0 version>"},
  "views": {
    "L0": {
      "title": "L0 · <쉬운 말>", "hint": "<이 층을 한 문장으로>", "parent": null,
      "rules": [{"text": "<설계 규칙>", "grade": "code|record|unknown", "evidence": {}}],
      "nodes": [{"id": "api", "kind": "service", "title": "요청 받는 곳", "say": "<박스에 그리는 한 줄>",
                 "detail": "<카드에만 — 2~3문장>", "code": ["src/api/server.py", "handle"],
                 "row": 0, "col": 0, "span": 1, "paths": ["src/api/"], "drill": "L1-api"}],
      "edges": [{"from": "api", "to": "core", "label": "<쉬운 말>", "iface": "<iface id>",
                 "grade": "graft|code|record|unknown", "evidence": {}}],
      "ifaces": [{"id": "...", "title": "...", "from": "api", "to": "core", "transport": "python call|http|queue|subprocess|file",
                  "items": [{"sig": "<시그니처 — 코드 이름은 여기>", "desc": "<한 줄>", "ref": "path:line"}]}]
    }
  },
  "unknowns": [{"text": "...", "why": "..."}]
}
```

**사람이 읽는 칸** — 검증기가 쉬운 말·길이를 검사한다:

| 칸 | 규칙 |
|---|---|
| `meta.summary` | 필수. 이 시스템이 무엇을 하는지 |
| view `title`·`hint` | 쉬운 말 |
| node `title` | 쉬운 이름, 24칸 이하 (한글 2칸·영숫자 1칸) |
| node `say` | 필수. 하는 일 한 줄, 30칸 이하 |
| edge `label` | 쉬운 말, 18칸 이하 |
| node `kind` | 필수. `person`(사람) · `external`(외부 시스템) · `service`(서비스) · `module`(내부 모듈) · `store`(저장소) · `job`(작업). 박스 색과 범례가 된다 |
| `meta.glossary` | 글에 나오는 제품·기술 용어(`PostgreSQL`, `LangGraph`, `API`, `SSE`)마다 한 문장 풀이. 화면에서 점선 밑줄 + 풀이 |

검사에 걸리는 것: `snake_case`, `camelCase`, 경로(`src/api`, `/run`), 파일 이름(`turn.py`), 함수 호출(`handle(`), 속성 접근(`graph.astream`), 심볼(`#Parser`), glossary 에 없는 대문자 약어·대소문자 섞인 이름. `detail`·`code[]`·`rules`·`ifaces` 는 검사하지 않는다 — 카드에서 펼쳐 보는 2단계 정보다.

**등급과 evidence** — 검증기가 이 형식으로만 판정한다:

| 등급 | 언제 | evidence |
|---|---|---|
| `graft` | Phase 1-3 에서 `graft callers` 로 직접 본 호출 | `{"from_sym": "src/api/server.py#handle", "to_sym": "src/core/engine.py#run_job"}` — 노드 id 를 **복사**. 지어내면 검증기가 강등한다. 같은 관계를 코드로도 읽었다면 `ref`·`quote` 를 함께 넣는다 (graft 판정 실패 시 code 로 강등되는 안전망) |
| `code` | 소스에서 직접 읽은 관계 (HTTP·큐·subprocess 등) | `{"ref": "src/core/engine.py:5", "quote": "requests.post"}` — quote 는 그 줄(±2)에 실제로 있는 10~40자 (8자 미만은 검증기가 거부한다) |
| `record` | ADR·PR·커밋 메시지 기반 해석 | `{"ref": "<커밋 해시 | PR#123 | docs/adr-1.md>"}` |
| `unknown` | 근거 없음 | `{}` |

작성 규칙:

- 레이어: L0 = 프로세스·저장소·외부 시스템. 분해할 게 남은 박스는 `drill` 로 하위 view 를 만든다. view 하나에 박스 5~9 개
- 모든 박스에 `paths[]` — 그 박스가 담당하는 경로 접두사. 외부 시스템은 `[]`. graft 판정은 증거 심볼이 이 경로 안에 있는지까지 본다
- `rules[]` 는 "A 는 B 를 import 하지 않는다" 같은 설계 규칙. **`graft` 등급 금지** (부재는 callers 로 증명할 수 없다)
- 격자: 흐름 방향대로 왼→오, 위→아래. 같은 칸 금지. 화살표는 직선이므로 사이에 다른 박스가 끼지 않게 배치한다
- 모든 iface 는 최소 한 edge 가 참조해야 한다

## Phase 3: 검증

```bash
python3 "$SKILL/bin/validate.py" "$MODEL" --root "$ROOT" --graft-status <Phase 0 값> [--quick]
```

- **exit 1** — `integrity_errors` 의 각 줄 `— ` 뒤에 고칠 방법이 있다. 그대로 고치고 다시 실행한다. 3 회 연속 실패하면 멈추고 오류 목록을 보고한다
  - 쉬운 말 오류는 **글을 다시 쓴다.** 코드 이름을 `glossary` 에 넣어 통과시키지 않는다 (검증기가 코드 이름 키를 거부한다)
  - 길이 오류는 줄이거나 `detail` 로 옮긴다
- **exit 0** — 리포트를 읽는다
  - `downgrades`: **받아들인다.** 강등을 피하려고 근거를 바꾸지 않는다. 예외는 하나 — 사유가 "paths 밖" 이고 박스 `paths[]` 를 실제로 잘못 잡은 경우에만 paths 를 고쳐 재검증한다
  - `missing_edges`: graft 가 찾았는데 그림에 없는 관계. 의미 있는 관계면 graft 등급 edge 로 추가하고 재검증한다. 의도적으로 뺐다면 그대로 둔다 (접힌 검증 리포트에 남는다)

## Phase 3.5: 문체 재검토

검증을 통과한 모델의 사람이 읽는 칸(summary·hint·title·say·label·detail)을 문체 규칙에 비춰 **한 번** 다시 읽고 고친다. 스크립트가 못 잡는 것 — 의인화("엔진이 판단한다"), 번역투, 같은 말 반복, 박스끼리 이름이 헷갈리는 것. 고쳤으면 Phase 3 를 다시 돈다.

## Phase 4: 렌더

```bash
python3 "$SKILL/bin/render.py" "$MODEL" --root "$ROOT"
```

HTML 을 직접 쓰거나 고치지 않는다. 모양을 바꾸려면 모델을 고쳐 Phase 3 부터 다시.

## Phase 5: 렌더링 확인

`--quick` 이면 생략하고 출력에 "렌더링 미확인" 을 남긴다.

- Chrome 자동화(`mcp__claude-in-chrome__*`)가 있으면 `$OUT` 을 `python3 -m http.server --bind 127.0.0.1` 로 띄워(확장은 `file://` 을 못 연다) view 마다(`#view=<id>`) 스크린샷을 찍어 박스 겹침·라벨 충돌·박스를 관통하는 화살표·잘린 글자를 확인한다. 문제는 모델의 격자를 고쳐 Phase 3~4 를 다시 돈다. 끝나면 서버를 끈다
- 없으면 Phase 6 으로 연 뒤 사용자에게 확인을 요청한다. "열릴 것이다" 로 넘어가지 않는다

## Phase 6: 열기

`--no-open` 이 아니면:

```bash
python3 "$SKILL/bin/open.py" open "$OUT/<slug>.html"
```

출력 `opened: orca-tab|browser|none <path>`. `none` 이면 경로를 사용자에게 준다. 그다음 `git -C "$ROOT" status --short` 가 Phase 0 기록과 같은지 대조한다. 다르면 무엇이 생겼는지 보고한다.

## Phase 7: 출력

```
✓ <slug>.html   (<opened 결과>)
  근거: graft a · 코드 b · 기록 c · 미확인 d   (검증 강등 n건)
  그림에 없는 관계: m건
  확인 못 한 것:
    - <unknowns 항목>
```

마지막 줄로 안내한다:

> 이 지도는 코드를 대신하지 않는다. 어디부터 어떤 관점으로 읽을지 정해주는 첫 지도다. 궁금한 건 이 세션에서 바로 물어보세요.

## open

모델 경로가 없으면 `$ROOT/.eli5/*.model.json` 중 가장 최근 것. 먼저 `python3 "$SKILL/bin/open.py" status --model "$MODEL"` 로 상태를 본다.

- `stale` — "지도가 코드보다 낡았다 — 다시 만들까요, 그대로 열까요?" 를 묻는다 (기본 그대로 열기). 다시 만들기는 기존 모델을 출발점으로 Phase 1 부터
- `missing` — 렌더된 지도가 없다. Phase 3 부터
- 그 외 — `python3 "$SKILL/bin/open.py" open "<html>"`

v2 모델(`meta.version` 없음)은 `render.py` 가 거부한다. "예전 형식 지도라 다시 만든다" 고 알리고 Phase 1 부터.

## 하지 않는 것

- 보안 검토·장애 원인 보고서를 대체하지 않는다
- 그림이 틀렸다는 지적을 받기 전에 구현으로 넘어가지 않는다 — 이 스킬의 존재 이유가 그 확인 단계다
- 조사 없이 그림부터 그리지 않는다
- graft 등급을 graft 로 보지 않고 주장하지 않는다

## 출처

- 공식 `eli5` 스킬 — [anthropics/claude-plugins-community](https://github.com/anthropics/claude-plugins-community/tree/main/eli5) (Thariq Shihipar, MIT)
- 보강 조건 — [앤트로픽의 ELI5 스킬 (desty, 2026-08-23)](https://desty.github.io/blog/60-eli5-visual-explainer/)
- 그림 글과 카드 글 분리·문체 규칙 파일·Orca 탭 열기·원자적 쓰기 — [lcalmsky/deadhd](https://github.com/lcalmsky/deadhd) (MIT, Copyright (c) 2026 lcalmsky)
- 쉬운 이름과 의미 분류·글자 칸 수(`textUnits`)·고칠 방법을 담은 오류 — [tt-a1i/archify](https://github.com/tt-a1i/archify) (MIT, Copyright (c) 2026 tt-a1i, 2025 Cocoon AI)
- 레이어 드릴다운·인터페이스 카드 구조 — [robintech-seoul/agent-toolkit](https://github.com/robintech-seoul/agent-toolkit) `arch-explorer` (설계만 참고, 코드 미사용 — 라이선스 없음)
- 호출 그래프 — [graft](https://github.com/trailhq/Graft) (MIT)
- 설계 문서 — `docs/superpowers/specs/2026-10-02-eli5-v3-readable-map-design.md` (v2: `2026-10-01-eli5-graft-chat-design.md`)
````

- [ ] **Step 3: help·README·CHANGELOG**

`commands/help.md` 의 `### eli5` 아래 코드 블록 전체를:

```
# eli5 — 코드를 안 읽는 사람이 읽는 지도

## 용도
코드베이스·시스템 구조를 드릴다운 HTML 지도로 그린다. 박스는 쉬운 이름 한 줄,
코드 이름·근거는 박스를 누르면 펼쳐지는 오른쪽 카드에. 구현 전에 에이전트가
파악한 구조가 맞는지 사람이 눈으로 확인하는 단계.

## 사용법
/rakis:eli5 <설명할 대상> [--out <dir>] [--quick] [--no-open]
/rakis:eli5 open [<model.json>]     기존 지도 다시 열기 (낡았으면 다시 만들지 묻는다)

## 동작
조사(graft) → 지도 모델 JSON → validate.py(근거 판정 + 쉬운 말·길이 검사)
→ 문체 재검토 → render.py(고정 템플릿) → open.py(Orca 탭 또는 브라우저)

## 화면
- 박스: 종류 색 띠 + 쉬운 이름 + 하는 일 한 줄
- "근거 보기" 토글: graft 증명(실선)·코드 읽음(점선)·기록 해석(주황). 미확인(빨강)은 항상 표시
- 용어 점선 밑줄 = 풀이, 오른쪽 카드 = 설명·연결·들어 있는 코드·인터페이스

## 트리거
"그림으로 설명해줘", "구조 좀 그려줘", "고치기 전에 어떻게 도는지 보여줘"
```

`README.md:58` 을 `| \`eli5\` | 코드를 안 읽는 사람도 읽는 드릴다운 HTML 지도 — 근거는 graft 로 판정, 박스 글은 쉬운 말로 검증 |`, `README.md:109` 를 `/rakis:eli5 open                                   # 만들어 둔 지도를 다시 열기 (낡았으면 다시 만들지 묻는다)` 로.

`CHANGELOG.md` 의 `### Added` 바로 아래 첫 항목으로:

```markdown
- `eli5` **v3 — 코드를 안 읽는 사람이 읽는 지도.** v2 를 실제 업무 레포에 돌려 보니 박스마다 코드 이름이 들어가고(`parse → collect_population → …`), 답변 패널은 한 줄 질문에 `path:line` 25개짜리 코드 워크스루를 돌려줬다. 지도 범위도 scope 파일의 69% 만 덮었다. v3 는 독자를 코드를 직접 읽지 않는 사람으로 다시 잡았다: 박스는 종류 색 띠 + 쉬운 이름 + 하는 일 한 줄(`say`)만, 코드 이름·근거·인터페이스는 박스를 누르면 열리는 오른쪽 카드로. `validate.py` 가 사람이 읽는 칸에서 `snake_case`·`camelCase`·경로·파일 이름·호출·속성 접근을 찾아 거부하고(한글 조사가 바로 붙어도 잡도록 ASCII 경계를 쓴다), 대문자 약어·고유명사는 `meta.glossary` 에 풀이가 있어야 통과한다 — 코드 이름을 glossary 에 넣는 우회도 거부한다. 길이는 archify `textUnits`(한글 2칸)로 재서 박스 폭을 넘으면 자르지 않고 실패시킨다. 근거 등급은 "근거 보기" 토글 뒤로 보냈고 미확인만 항상 빨갛게 둔다. **질문 패널과 서버를 제거했다** — 지도는 HTML 파일 하나이고, `open.py` 가 Orca 안이면 Orca 탭, 아니면 브라우저로 연다(deadhd `open.sh` 방식). `render.py` 는 원자적으로 쓴다. 차용: [lcalmsky/deadhd](https://github.com/lcalmsky/deadhd)·[tt-a1i/archify](https://github.com/tt-a1i/archify) (둘 다 MIT). 설계: `docs/superpowers/specs/2026-10-02-eli5-v3-readable-map-design.md` (1단계 — 시나리오·커버리지·작업 진행 표시는 다음 단계)
```

- [ ] **Step 4: 확인**

Run: `grep -rn 'server.py\|panel\.html\|answer-rules\|질문 패널과 함께' skills commands README.md; ./lint.sh 2>&1 | tail -5`
Expected: grep 은 CHANGELOG 밖에서 결과 없음. `lint.sh` 실패 0

- [ ] **Step 5: 커밋**

```bash
git add skills/eli5/SKILL.md commands/help.md README.md CHANGELOG.md
git commit -m "docs(eli5): v3 절차·안내 — 쉬운 말 모델, 문체 재검토, open.py

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 8: 실측 — 업무 레포 지도를 v3 로 다시 만들고 사용자 판정

**Files:** 없음 (대상 레포 `/Users/raki-1203/workspace/KT/agent-production-profitability` 의 `.eli5/` 출력물만. 추적 파일 무변경)

**Interfaces:**
- Consumes: Task 1~7 전체. 스킬은 플러그인 캐시가 아니라 **작업 브랜치의 파일**로 돌린다 — `$SKILL=/Users/raki-1203/workspace/raki-claude-plugins/skills/eli5`
- Produces: 완료 기준 1 의 판정 기록, 오탐 목록, 길이 상한 확정값

- [ ] **Step 1: v2 지도 보존**

```bash
cd /Users/raki-1203/workspace/KT/agent-production-profitability
cp .eli5/one-turn-request-flow.html /tmp/eli5-v2-one-turn.html
git status --short > /tmp/eli5-v3-before.txt
```

- [ ] **Step 2: SKILL.md 절차대로 v3 지도 생성**

대상 "한 턴의 요청 흐름 — BFF /run 에서 SSE 응답까지", `$SKILL` 은 위 작업 브랜치 경로. 기존 v2 모델(`.eli5/one-turn-request-flow.model.json`)을 조사 출발점으로 쓰되 Phase 2 부터 v3 형식으로 새로 쓴다. Phase 3 의 쉬운 말 오류를 기록해 둔다: **오류마다 "진짜 코드 이름이었나 / 오탐이었나"** 를 표로.

- [ ] **Step 3: 나란히 비교 스크린샷**

v2(`/tmp/eli5-v2-one-turn.html`)와 v3 를 각각 `http.server` 로 띄워 `#view=L0`, `#view=L1-graph` 스크린샷을 찍는다 (v3 는 박스 하나를 선택한 상태 1장 추가). 서버는 끝나면 끈다.

- [ ] **Step 4: 대상 레포 무변경 확인**

```bash
git -C /Users/raki-1203/workspace/KT/agent-production-profitability status --short | diff /tmp/eli5-v3-before.txt -
```
Expected: 차이 없음

- [ ] **Step 5: 사용자 판정 요청**

스크린샷 4~5장과 함께 사용자에게 묻는다: "v2 와 비교해 한눈에 들어오나요?" — 이것이 1단계 완료 기준이다. 함께 보고: 쉬운 말 오류 수와 오탐 수, 길이 오류가 난 칸(상한 24/30/18 이 실제로 빡빡했는지). 오탐이 있으면 `plain.py` 규칙을 고치는 후속 커밋, 상한 조정이 필요하면 `plain.py` 상수와 `SKILL.md` 표를 함께 고친다 (스펙 1.2 "1단계 구현 중 실제 박스 폭으로 확정").

판정이 나기 전에는 1단계 완료로 보고하지 않는다.
