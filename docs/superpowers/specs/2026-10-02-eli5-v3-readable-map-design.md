# eli5 v3 — 코드를 안 읽는 사람이 읽는 지도

- **작성일**: 2026-10-02
- **상태**: 1단계 구현 중 — 1.7(한 장 지도) 2026-10-03 추가
- **영향 범위**: rakis `eli5` 스킬 (2.0.0 → 3.0.0), `hooks/hooks.json` (PostToolUse 추가). 플러그인 버전은 pre-push 훅이 자동 bump
- **이전 설계**: `2026-10-01-eli5-graft-chat-design.md` (v2 — graft 검증 지도 + 질문 패널)
- **참고 구현 (코드를 직접 읽음)**
  - [lcalmsky/deadhd](https://github.com/lcalmsky/deadhd) — MIT, Copyright (c) 2026 lcalmsky. 코드 차용 시 저작권 표기 유지
  - [tt-a1i/archify](https://github.com/tt-a1i/archify) — MIT, Copyright (c) 2026 tt-a1i + 2025 Cocoon AI. 코드 차용 시 저작권 표기 유지
  - [robintech-seoul/agent-toolkit](https://github.com/robintech-seoul/agent-toolkit) `arch-explorer` — 라이선스 없음. 설계만 참고, 코드 미사용
- **vault 근거**: `wiki/sources/lcalmsky-deadhd.md`, `raw/repos/{lcalmsky-deadhd,tt-a1i-archify,robintech-seoul-agent-toolkit}/repomix.txt`

## 배경

v2 를 실제 업무 레포(agent-production-profitability, "한 턴의 요청 흐름")에 돌려 사용자가 본 결과:

1. **지도가 한눈에 안 들어온다.** 박스 안 글이 코드 이름이다 — "조건 해석" 박스에 `parse → collect_population → usage_vintage → spend → collect_design`, "대체·여유·범위" 에 `reselect · fill · scope`. 순서 표시가 없어 "한 턴의 흐름" 인데 시작과 끝을 눈으로 찾아야 한다. 첫 시선은 근거 등급 배지·범례로 간다. L1-graph 는 화살표 8개가 전부 같은 파란 점선이라 등급도 구분을 못 준다.
2. **"그림에 없는 관계 (graft 가 찾음)" 21건이 원문 그대로 하단에 쏟아진다.** 검증기 출력이 사람에게 노출됐다.
3. **패널 답변이 읽히지 않는다.** "FE 화면을 통해서 입력이 들어오면 어떻게 되는건지" 한 줄 질문에 5섹션·`path:line` 25개. `answer-rules.md` 의 "모든 사실 주장에 근거를 단다" 가 "짧게 답한다" 를 이긴다. `panel.html` 의 `md()` 는 지도 카드에 등록된 위치만 링크해 25개 중 24개는 눌러도 아무 일 없는 글자다.
4. **일부 범위만 그린다.** 실측: scope(`src/`, `devbff/`) 소스 256개 중 L0 박스 `paths` 에 속한 파일 176개(69%). 80개가 어느 박스에도 없고(`src/agents/simulation/` 29, `devbff/` 14, `src/agents/_shared/` 8, `src/agents/research/` 5 …) 이를 알리는 장치도 없다.

근본 원인: v2 의 목표는 "그림이 틀리지 않게(검증)" 였고 "한눈에 들어오게(전달)" 는 측정하지 않았다. 또 설계 참고였던 arch-explorer 는 **의도적으로** 박스 제목을 "레포에 있는 그대로의 이름" 으로, 화살표 라벨을 "설명이 아니라 경계를 넘는 것의 이름" 으로 쓰게 한다(build SKILL.md) — 개발자 독자를 전제한 규칙이 그대로 넘어왔다.

**독자 재정의**: 1차 독자는 코드를 직접 읽지 않는 사용자 본인, 2차는 그가 설명할 비개발자 동료다. 코드 위치는 필요할 때 펼쳐 보는 2단계 정보다.

## 목표

- 박스·화살표·시나리오 문장에 **코드 이름이 0개**이고, 낯선 용어는 전부 풀이가 붙는다 — 검증기가 강제
- **질문하지 않아도** 대표 흐름을 번호 순서로 따라갈 수 있다 (시나리오)
- scope 안의 소스 파일이 **조용히 빠지지 않는다** — 배정되거나, 이유와 함께 제외된다
- 에이전트가 개발하는 동안 **어느 박스를 건드리는지** 지도 위에 보인다
- 화살표 근거 검증(v2 의 graft 판정)은 그대로 유지한다

**비목표**

- 질문 패널 — 제거한다 (§6). 시나리오에 없는 질문은 지도를 만든 Claude Code 세션에서 묻는다
- 빠진 관계를 지도에 보조선으로 그리기 — archify 가 문서로 경고한 "화살표 20개 넘으면 주 경로가 안 보인다" 를 피해 카드로 옮긴다
- 한 장에 레포 전체 — 층(drill)으로 나눈다. archify 는 다이어그램당 노드 12개 상한을 둔다
- v2 모델 호환 — 기존 지도가 2~3개뿐이다. v2 모델은 "다시 만들 지도" 로 안내하고 멈춘다
- 테마 추가 — 기존 라이트/다크 유지

## 차용 지도 — 무엇을 어디서 가져오나

| 출처 (확인한 코드) | eli5 v3 에서 | 단계 |
|---|---|---|
| deadhd `template.html` 노드 = `label`+`sub` 만, 설명은 아래 카드 | 박스 = 쉬운 이름 + `say` 한 줄. 나머지는 박스 카드 | 1 |
| archify `label`/`sublabel`/`tag` + 의미 분류 `type` → 색·범례 | `title`·`say` + `kind` → 색 띠·범례 | 1 |
| archify `utils.mjs::textUnits` (전각 2칸) + 폭 초과 시 렌더 전 실패 | 길이 검사 | 1 |
| archify `geometry.mjs` 의 "Suggested fix" 오류 | 검증 오류마다 고칠 방법 한 줄 | 1 |
| deadhd `writing-rules.md` + 기본 규칙 + 처음·끝 재검토 | `~/.config/rakis/eli5-writing-rules.md` | 1 |
| deadhd `open.sh` — `ORCA_WORKTREE_ID` → `orca tab create`, 실패 시 브라우저 | `bin/open.py` | 1 |
| deadhd `render.py` — `mkstemp`→`os.replace`, `</`·`<!--` 이스케이프 | `render.py` 원자적 쓰기 | 1 |
| deadhd `evEl` — `{icon, text, href}` 칩, SVG sprite | 근거 칩 | 1·2 |
| archify `workflow.mainPath` — 순서 있는 id 목록, 사이에 화살표 있는지 검증 | 시나리오 연결 검사 (단, 번호로 **보이게** 그린다 — archify 는 반복 애니메이션만) | 2 |
| deadhd `substeps` 가로 단계선 | 시나리오 카드 안 세부 순서 | 2 |
| deadhd `linkify` (긴 키 우선·경계 검사) | `{{박스id}}` 토큰 링크 (한글 이름 경계 판정을 피해 id 표기) | 2 |
| arch-explorer diff — 파일마다 정확히 한 블록, 없으면 `other`, 스크립트 검사 | 층별 커버리지 검사 + `excluded` | 3 |
| deadhd `stats` ring | 커버리지 원형 그래프 | 3 |
| arch-explorer diff — `change` 겹쳐 그리기 + 안에 변경 있는 박스에 숫자 배지 | 진행 상태 겹쳐 그리기 + 상위 박스 집계 배지 | 2·4 |
| deadhd `meta refresh 15` + `sessionStorage` 직전 상태 비교 + 스크롤 복원 | 추적 중 자동 갱신, 새로 완료된 박스만 효과 | 4 |
| deadhd 카드 순서 막힘→진행→완료→남음, "도구 결과로 입증된 것만 done", 압축 시 footer | 진행 카드·상태 규칙 | 4 |

deadhd 를 그대로 쓰지 않는 부분: 문체 규칙을 지시문으로만 두는 점(→ v3 는 스크립트로 검사), 갱신을 지시문에만 기대는 점(→ v3 는 훅이 "건드림" 을 기계적으로 기록), lane/col 흐름도 배치(→ eli5 격자 유지).

## 단계

spec 은 하나, 구현은 단계마다 plan 을 따로 쓰고 따로 배포한다. 앞 단계가 배포된 뒤 다음 plan 을 쓴다.

| 단계 | 내용 | 의존 |
|---|---|---|
| 1 | 지도 가독성 + 패널 제거 | — |
| 2 | 시나리오 따라가기 | 1 (쉬운 말 검사·카드·칩) |
| 3 | 빠짐없이 (그 밖의 연결 · 커버리지 · 레포 전체 모드) | 1 |
| 4 | 작업 진행 표시 | 3 (레포 전체 지도·고정된 박스 id) |

## 설계

### 1단계 — 지도 가독성

#### 1.1 모델 v3

```json
{
  "meta": {
    "version": 3,
    "target": "한 턴의 요청 흐름",
    "summary": "화면에서 들어온 한 턴을 검사하고, 대화 그래프가 되묻기·승인·계산 제출 중 하나로 처리한다.",
    "glossary": {"LangGraph": "대화를 단계별 그래프로 돌리는 라이브러리", "SSE": "서버가 화면으로 결과를 흘려보내는 방식"},
    "scope": ["src/", "devbff/"],
    "graft_version": "0.16.0"
  },
  "views": {
    "L0": {
      "title": "L0 · 한 턴의 요청 흐름", "hint": "<이 층을 한 문장으로>", "parent": null,
      "rules": [],
      "nodes": [{"id": "api", "kind": "service", "title": "요청 받는 곳",
                 "say": "화면 요청을 검사하고 그래프로 넘긴다",
                 "detail": "<카드에만 — 2~3문장>", "code": ["src/api/routers/aimate.py", "_run_stream"],
                 "row": 0, "col": 1, "span": 1, "paths": ["src/api/", "src/streaming/"], "drill": "L1-api"}],
      "edges": [{"from": "api", "to": "graph", "label": "대화 단계 실행", "iface": "astream",
                 "grade": "code", "evidence": {"ref": "src/api/routers/aimate.py:270", "quote": "graph.astream("}}],
      "ifaces": []
    }
  },
  "unknowns": []
}
```

v2 대비 변경:

| 칸 | v2 | v3 |
|---|---|---|
| `meta.version` | 없음 | `3` 필수. 없거나 다르면 render 가 "v2 지도 — 다시 만든다" 로 멈춘다 |
| `meta.summary` | 없음 | 필수. 1~2문장 |
| `meta.glossary` | 없음 | 용어 → 풀이. 대소문자 섞인 고유명사·약어는 여기 있어야 쉬운 말 검사를 통과한다 |
| node `title` | 코드 이름 허용 | 쉬운 이름만 |
| node `lines[]` | 박스에 2~3줄 | 삭제 |
| node `say` | 없음 | 필수. 박스에 그리는 한 줄 |
| node `detail`, `code[]` | 없음 | 선택. 카드에만 |
| node `kind` | 없음 | 필수. `person` · `external` · `service` · `module` · `store` · `job` |
| edge `label` | 인터페이스 이름 | 쉬운 말. 코드 이름은 `ifaces[].items[].sig` 에 |

등급(`graft`/`code`/`record`/`unknown`)·evidence 형식·`paths`·`drill`·`ifaces`·`rules`·`unknowns` 는 v2 그대로.

#### 1.2 검증기 추가 (`validate.py`, integrity 오류 → exit 1)

모든 오류는 `위치 — 문제 — 고칠 방법` 한 줄 형식이다 (archify "Suggested fix").

**쉬운 말 검사** — 대상: node `title`·`say`, edge `label`, view `title`·`hint`, `meta.summary`, (2단계) scenario 텍스트

| 패턴 | 예 |
|---|---|
| snake_case `[a-z0-9]+_[a-z0-9_]+` | `collect_population` |
| camelCase `[a-z][a-z0-9]*[A-Z]` | `resolveMartSize` |
| 경로·확장자 `/` 포함 토큰, `\.\w{1,4}\b` | `src/api`, `turn.py` |
| 호출 `\w+\(` · 속성 접근 `\w+\.\w+` | `graph.astream` |
| `#`·`::` 심볼 표기 | `parser.py#LLMSlotParser` |

예외: `meta.glossary` 키와 정확히 일치하는 토큰(예: `PostgreSQL`, `LangGraph`). 대문자 약어(`API`, `LLM`, `S3`)도 glossary 에 있어야 통과 — 낯선 용어가 풀이 없이 남지 않게 한다.

```
L0/api.say 에 'graph.astream' — 코드 이름은 code[] 로 옮기고 하는 일을 쉬운 말로 쓴다
L0/pg.title 에 'PostgreSQL' — glossary 에 풀이를 추가한다
```

**길이 검사** — archify `textUnits` 방식: 전각(한글·CJK) 2, 그 외 1. 상한은 렌더 박스 폭에서 역산한 값으로 `render.py`·`validate.py` 가 같은 상수를 공유한다(초기값 `title` ≤ 24, `say` ≤ 30, edge `label` ≤ 18 — 1단계 구현 중 실제 박스 폭으로 확정). 자르지 않고 실패시킨다.

```
L1-graph/parse.say 가 34칸, 상한 30 — 4칸 줄이거나 detail 로 옮긴다
```

**필수 칸** — `meta.version == 3`, `meta.summary` 비지 않음, 모든 node `kind` 가 허용 목록, `say` 비지 않음, glossary 값 비지 않음.

#### 1.3 화면 (`map.html`)

- **머리**: 제목 → `summary` → `kind` 색 범례 → 흐린 칩 하나(근거 `graft 8 · 코드 25 · 미확인 0`, 미검증 배지)
- **박스**: 왼쪽 `kind` 색 띠, `title`(굵게), `say`(한 줄). 코드 글자 없음. `drill` 있으면 "안으로 ›" 표시 유지. glossary 용어는 점선 밑줄 + hover 풀이
- **화살표**: 기본은 모두 중립색 실선 + 쉬운 말 라벨. 머리의 "근거 보기" 토글을 켜면 v2 등급 스타일(실선·점선·주황). **`unknown` 은 토글과 무관하게 항상 빨간 점선**
- **오른쪽 박스 카드** (패널이 빠진 자리): 박스를 누르면 `say` · `detail` · "들어 있는 코드"(`code[]`, `paths`) · 이 박스를 지나는 인터페이스 카드 · 근거 칩. 칩 글자는 `router.py:34` 처럼 짧게, hover 에 전체 경로, 클릭 시 경로 복사
- **검증 리포트**: 맨 아래 접힌 `<details>` 안 — 강등 목록. "그림에 없는 관계" 는 3단계에서 박스 카드로 옮긴다
- 좁은 화면(< 900px)에서는 카드가 지도 아래로 내려간다

#### 1.4 문체 규칙

- `${XDG_CONFIG_HOME:-~/.config}/rakis/eli5-writing-rules.md` 가 있으면 따른다
- 없으면 기본: 하는 일을 쓴다 · 코드 이름을 쓰지 않는다 · 시스템을 의인화하지 않는다 · 박스 이름은 명사구
- 검증을 통과한 뒤 규칙에 비춰 **한 번** 다시 읽고 고친다 (스크립트가 못 잡는 어색함)

#### 1.5 패널 제거와 열기

삭제: `bin/server.py`, `assets/panel.html`, `assets/answer-rules.md`, `tests/unit/test_eli5_server.sh`, 서버용 fixture(가짜 claude), `stop` 명령.

신규 `bin/open.py`:
- `open <html>` — 모드 `auto`(기본): `ORCA_WORKTREE_ID` 가 있으면 `orca tab create` 시도 → 실패 시 시스템 브라우저(`open`/`xdg-open`). `--mode orca|browser|print`. 출력 `opened: orca-tab|browser|none <path>`. `PROGRESS_OPEN_DRY` 와 같은 드라이런 환경변수(`ELI5_OPEN_DRY=1`)로 테스트
- `status <model>` — server.py 에 있던 신선도 판정(사이드카 `commit` 이후 scope 변경 여부: `fresh|stale|unknown`)을 옮긴다

`render.py`: `mkstemp`→`os.replace` 원자적 쓰기, payload `</`·`<!--` 이스케이프, `meta.version != 3` 이면 exit 1.

SKILL.md: Phase 6 "열기" 를 `open.py` 로, `/rakis:eli5 open [<model>]` 은 status 확인 후 `open.py open`. "질문은 이 세션에서 하세요" 한 줄 안내.

#### 1.6 검증

- 단위: 쉬운 말(각 패턴 실패 · glossary 예외 통과 · 약어), 길이(한글·영문 혼합 경계값), 필수 칸, v2 모델 거부, 원자적 쓰기(중간 실패 시 기존 파일 보존), `open.py` 모드 선택(드라이런: Orca 있음/없음/실패)
- 실측: agent-production-profitability "한 턴의 요청 흐름" 을 v3 로 다시 만든다. 코드 이름 0개는 검증기가 보장. L0·L1-graph 스크린샷을 v2 와 나란히 놓고 **"한눈에 들어오는지" 는 사용자가 판정**한다 (스크립트로 잴 수 없는 기준)

#### 1.7 한 장 지도 — 층 이동을 없앤다 (2026-10-03 추가)

1단계 실측 지도를 본 사용자 판정: **"안으로 들어가면서 전체적인 흐름이 잘 안 보인다. 한눈에 모든 흐름이 보였으면 좋겠다."** 층(drill)은 안쪽을 보는 동안 바깥을 지운다. 세 안(묶음 펼친 한 장 · 자동 배치 흐름도 · 층 유지 + 미니맵) 중 사용자가 **묶음 펼친 한 장**을 골랐다. 이 절은 1.1~1.3 과 2~4단계의 층 관련 서술을 대체한다.

**모델**

- `views` 는 **정확히 하나**. view id 는 자유(관례 `L0`), `parent` 는 `null`. `drill` 은 없앤다
- node 에 `group` (선택): 같은 view 의 다른 node id. 그 node 의 **묶음 테두리 안**에 그린다
- **묶음(frame)** = 다른 node 가 `group` 으로 가리키는 node. 자기 칸(`row`·`col`·`span`)과 `paths` 를 갖지 않는다 — 테두리는 안쪽 박스들의 범위로, 경로는 안쪽 박스 `paths` 의 합으로 계산한다. 안쪽 박스 2개 이상. 묶음 안의 묶음 금지(한 단계)
- 예전 안쪽 층의 **대역 박스**(바깥 박스를 가리키려고 다시 그린 것)는 두지 않는다 — 화살표는 진짜 박스로 잇는다
- 화살표 끝은 박스 또는 묶음. 묶음 끝의 graft 판정은 계산된 경로 합으로 한다

**배치 — 단일 출처 `bin/layout.py`**

- 상수: 박스 `W=180`·`H=72`, 간격 `GX=110`·`GY=80`, 여백 `PAD=30`, 묶음 안쪽 여백 `FP=14`, 묶음 머리 `FT=48`(이름 + 한 줄)
- 박스 `x = PAD + FP + col·(W+GX)`, `y = PAD + FT + row·(H+GY)`. 묶음 = 안쪽 박스 외접 사각형을 좌우·아래 `FP`, 위 `FT` 만큼 넓힌 것
- 화살표 선분 = 두 사각형 중심을 잇는 직선을 각 사각형 경계에서 자른 것 (v2 `clip` 과 같은 식)
- `render.py` 가 이 계산 결과(`model.layout` — 박스·묶음 사각형, 화살표 선분, 전체 크기)를 HTML 에 넣고, `map.html` 은 계산하지 않고 그리기만 한다. 검증기의 관통 검사도 같은 함수를 쓴다 — 그림과 검사가 어긋나지 않는다

**검증 추가 (integrity → exit 1)**

| 검사 | 오류 예 |
|---|---|
| view 하나 | `views 가 2개 — 지도는 한 장이다. 안쪽 박스는 group 으로 묶음에 넣는다` |
| `drill`·`parent` 금지 | `L0/api.drill 은 없어졌다 — 안쪽 박스에 "group": "api" 를 단다` |
| 묶음 규칙 | 묶음 안의 묶음 · 안쪽 1개 · 묶음에 `row`/`col`/`paths` · 없는 `group` |
| 열 5개까지 | `L0/x.col 5 — 열은 0~4 (한 화면 폭)` |
| **화살표 관통** | `L0: api→jobs 화살표가 '대화 단계 진행기' 묶음을 지난다 — 박스를 옮기거나 화살표 경로가 비게 배치한다` — 화살표의 두 끝, 끝이 속한 묶음, 끝인 묶음의 안쪽 박스를 뺀 모든 박스·묶음과 선분 교차 검사 (archify `segmentIntersectsRect` 방식, 경계 2px 여유) |
| 라벨 길이 | edge `label` 상한 18 → **14칸** (간격이 고정되므로) |

`missing_edges` 는 안쪽 박스(잎) 단위로 매핑하고, 묶음 끝 화살표는 그 묶음 안 모든 박스의 화살표로 친다.

**화면**

- 묶음: 둥근 테두리, 왼쪽 위에 종류 색 점 + 이름 + 한 줄(`say`). 묶음 빈 곳을 누르면 묶음 카드 — 하는 일·안쪽 박스 목록(누르면 그 박스)·연결·용어·코드 자세히
- 선택 시 그 박스(묶음이면 안쪽 포함)에 닿지 않는 화살표를 흐리게
- 지도는 화면 전체 폭, 넘치면 `viewBox` 비율대로 축소. "안으로 ▸"·경로 표시줄(crumbs)의 층 이동은 없앤다

**2~4단계 대체**

- 2단계: `steps[].view` 없음 — 단계는 `box` 만. 연속 단계는 같은 지도 위 화살표로 이어져야 한다(묶음 끝 화살표는 그 안쪽 박스에도 유효). 층 이동 규칙·범위 배지("④–⑥") 삭제
- 3단계: 커버리지는 "층별" 이 아니라 **지도의 잎 박스 기준**(scope 파일 전부가 잎 박스 하나에 배정 또는 제외) + **묶음별**(묶음 경로 합 안의 파일은 안쪽 박스 중 하나에). 레포 전체 모드의 "L1 전부 펼치기·`--deepen`" 은 "L0 박스를 묶음으로 펼치기" 로 바뀌고, 박스가 많아 5열·관통 금지를 못 지키면 묶음 일부를 접은 지도(안쪽 없는 박스)로 낸다
- 4단계: 상위 박스 집계 배지 → **묶음 테두리 배지**

**위험**: 박스 20개 안팎을 5열 안에 관통 없이 배치하는 건 에이전트에게 어렵다. 관통 오류가 "어느 박스를 지나는지" 를 말해 줘 고칠 수는 있지만 재시도 횟수는 실측으로 확인한다.

### 2단계 — 시나리오 따라가기

#### 2.1 모델

```json
"scenarios": [{
  "id": "form-input",
  "title": "화면에서 조건을 입력하면",
  "summary": "입력은 검사를 거쳐 그래프로 가고, 칸이 비면 되묻고, 다 차면 승인 뒤 계산을 맡긴다.",
  "steps": [
    {"view": "L0", "box": "bff", "title": "화면이 요청을 보냄", "body": "한 턴을 {{api}} 로 넘긴다."},
    {"view": "L0", "box": "api", "title": "요청 접수·잠금", "body": "같은 대화가 돌고 있으면 거절한다.",
     "substeps": [{"label": "신원 확인"}, {"label": "대화 잠금"}, {"label": "턴 준비"}]},
    {"view": "L0", "box": "graph", "title": "대화 단계 실행", "body": "..."},
    {"view": "L1-graph", "box": "orch", "title": "갈래 고르기", "body": "폼 입력이면 AI 판단 없이 조건 해석으로 간다.",
     "evidence": [{"ref": "src/agents/orchestrator/nodes/classify.py:50", "quote": "form_values"}]}
  ]
}]
```

- 지도당 시나리오 2~4개, 시나리오당 단계 2~7개. 첫 시나리오는 `<대상>` 흐름 자체 (레포 전체 모드는 주요 입구 흐름)
- **근거 상속**: 단계 i→i+1 사이 화살표의 `grade`·`evidence` 를 그 단계가 이어받는다. `unknown` 화살표를 지나는 단계는 자동으로 "미확인" 배지. 층을 옮기는 연결(drill 들어가기·나오기)은 화살표가 아니라 상속할 근거가 없고, 같은 박스의 안팎이므로 근거가 필요 없다. 화살표에 없는 사실을 말하는 단계만 `evidence` 를 직접 달고, 기존 `check_code`(ref+quote 대조)를 거친다
- `{{박스id}}` — 같은 view 의 박스, 또는 `{{view:박스id}}`. 렌더 시 박스 이름 링크로 치환

#### 2.2 검증 (integrity → exit 1)

| 검사 | 오류 예 |
|---|---|
| `view`·`box` 존재 | `form-input.steps[3]: L1-graph 에 'orchestr' 없음 — 있는 id: orch, parse, …` |
| 연속 단계가 같은 view 면 `from→to` 화살표 존재 (방향 포함) | `steps[1]→[2]: api→guard 화살표 없음 — 반대 방향 guard→api 만 있다. 순서 또는 지도를 고친다` |
| view 가 바뀌면: 앞 박스의 `drill` 이 다음 view 이거나(들어가기), 다음 view 가 앞 view 의 `parent` 이고 다음 박스가 앞 view 를 drill 로 가진 박스(나오기) | `steps[2]→[3]: L0/guard 에서 L1-graph 로 갈 수 없다 — L0/graph 를 거친다` |
| 개수 2~4 / 2~7 | — |
| `{{id}}` 해석 가능 | `steps[0].body 의 {{apii}} — 있는 id: api, …` |
| `title`·`body`·`substeps[].label` 쉬운 말·길이 (1.2 규칙) | — |

#### 2.3 화면

- 머리 아래 시나리오 버튼 줄. 고르지 않으면 평소 지도
- 선택 시: 경로 박스에 ①②③ 번호 배지, 경로 화살표는 굵은 강조색, 나머지는 흐리게(opacity 0.3). 다른 view 의 단계는 그 view 로 들어가는 박스에 범위 배지("④–⑥")
- 오른쪽: 요약 + 단계 카드(번호 · 제목 · 본문 · `substeps` 가로선 · 근거 칩 · 미확인/기록 배지). 카드 클릭 → 해당 view 로 이동 + 박스 강조
- 한 단계씩: `←`/`→` 키, 이전/다음 버튼. 현재 단계 박스만 진하게
- 주소 해시 `#view=L0&scenario=form-input&step=3` — 링크를 보내면 같은 단계로 열린다

#### 2.4 검증

- 단위: 없는 박스, 화살표 없음, 반대 방향만 있음, drill 들어가기·나오기 통과, 엉뚱한 층 이동 실패, 8단계, 본문 코드 이름, `{{없는id}}`, `unknown` 등급 상속
- 실측: 같은 지도에 "화면에서 조건을 입력하면" 시나리오를 넣고, 오늘 받은 패널 답변(5섹션·25개)과 나란히 놓고 사용자가 판정. 해시 링크를 새 탭에 붙여 같은 단계가 열리는지 확인

#### 2.5 한 장 지도 위의 시나리오 — 시나리오 먼저 (2026-10-03 추가)

1단계를 끝낸 뒤 사용자: "이거 보고도 잘 이해가 안 된다." 지도를 열어 알고 싶은 것은 **무슨 일이 어떤 순서로 일어나는지**와 **에이전트 작업 상황**(4단계). 구조도는 "무엇이 있는가" 에 답하고 "무슨 일이 일어나는가" 에는 답하지 못한다. 이 절은 2.1~2.4 를 다음처럼 바꾼다.

- **시나리오 먼저**: 시나리오가 있는 지도를 열면 첫 시나리오가 선택된 채로 열린다 — 오른쪽 카드에 단계 목록, 지도에 ①②③. "구조만 보기" 로 끄면 1단계 지도. 주소가 `#scenario=none` 이면 끈 채로 연다
- **모델**: `steps[]` 에 `view` 없음 (한 장). 단계 `box` 는 박스 또는 묶음
- **잇기 규칙 완화**: 단계 i 의 박스는 "바로 앞 단계" 가 아니라 **지금까지 지나온 단계 박스 중 하나에서 나오는 화살표**로 닿아야 한다 (가장 최근에 지나온 박스 우선). 호출은 갔다가 돌아오는 나무 모양이라 한 줄 경로로는 "검사하고 돌아와 그래프로" 같은 흐름을 못 쓴다. 화살표 끝이 묶음이면 그 안쪽 박스에도, 단계 박스가 안쪽 박스면 그 묶음 끝 화살표도 유효하다. 반대 방향 화살표만 있으면 그렇다고 알려 준다
- **개수**: 시나리오 1~4개 (작은 지도는 하나로 충분), 단계 2~7개
- **근거**: 검증기가 단계마다 쓰인 화살표와 등급을 `validation.scenarios` 에 기록한다 — `{시나리오 id: [{"edge": 화살표 번호 | null, "grade": 등급 | null}]}`. 단계가 직접 단 `evidence` 는 `check_code` 로 판정하고, 실패하면 그 단계 등급을 `unknown` 으로 낮춘다 (화살표 강등과 같은 방식, exit 1 아님). 화면은 이 기록만 쓴다
- **쉬운 말**: 시나리오 `title`·`summary`·단계 `title`·`body`·`substeps[].label` 에 1.2 검사. 단계 `title` ≤ 24칸, `substeps[].label` ≤ 14칸
- **화면**: 머리 아래 "따라가 보기" 시나리오 버튼 줄. 선택하면 지나는 박스에 번호 배지(같은 박스를 두 번 지나면 "2·5"), 쓰인 화살표는 굵은 강조, 나머지 박스·화살표는 흐리게, 현재 단계 박스는 두꺼운 테두리. 오른쪽 카드는 요약 + 이전/다음 + 단계 카드(번호·제목·본문·하위 단계·미확인/기록 배지·근거 보기 시 근거 칩). 단계 카드나 지도 번호를 누르면 그 단계로. `←`/`→` 키. 본문의 `{{박스id}}` 는 박스 이름 버튼 — 누르면 박스 카드, 박스 카드에는 "← 시나리오로". 주소 `#scenario=<id>&step=<n>` 를 보내면 같은 단계로 열린다

#### 2.6 갈림길 — 어떤 상황에서 어디로 (2026-10-03 추가)

시나리오를 본 사용자: "이제 따라가진다. 그런데 어떤 상황에서는 이렇게 가고 어떤 상황에서는 이리로 가는지를 이해할 수 있어야 한다." 지도는 "조건에 따라 하나만 가는" 화살표(예: 입구 분류 → 조건 해석 / 보고서 / 이어받기 / 조건 바꾸기)와 "차례로 다 부르는" 화살표를 같은 선으로 그려 구분이 안 된다.

- **모델**: edge 에 `kind` (`call` 기본 · `branch`), `branch` 면 **`when`**(쉬운 말 조건, ≤ 30칸)과 **`when_evidence`**(`{ref, quote}` — 조건이 적힌 코드 줄) 필수. `when` 은 `branch` 에만
- **검증**: 위 규칙은 무결성 오류(exit 1). `when_evidence` 는 `check_code` 로 판정해 `validation.branches = {"<화살표 번호>": "code" | "unknown"}` 에 기록 — 틀리면 그 조건을 "미확인" 으로 표시(exit 0). 조건을 지어내지 못하게 하는 장치
- **화면**: 갈림길이 있는 박스·묶음에 ◆, 갈래 화살표는 시작점에 마름모. 시나리오 단계 박스가 갈림길이면 카드에 "◆ 여기서 갈라진다" — 갈래마다 `when → 가는 곳`, 이 이야기가 탄 갈래는 ● 표시, 그 갈래를 타는 다른 시나리오가 있으면 "이 길 따라가기", 마우스를 올리면 지도에서 그 갈래 화살표 강조. 박스 카드에도 같은 목록

### 3단계 — 빠짐없이

#### 3.1 그 밖의 연결

`validate.py` 의 `missing_edges` 는 그대로 계산한다(박스 쌍 단위, `wiring.json` `calls` 관계). 출력 위치만 바뀐다: 리포트를 `render.py` 가 읽어 **각 박스 카드의 "그 밖의 연결"** 칸에 상대 박스별로 묶어 그린다("PostgreSQL · S3 · 작업 스케줄러와도 연결 (graft 확인 5건)"), 펼치면 쌍마다 예시 심볼 칩. 하단 목록은 없앤다. 에이전트 규칙은 v2 그대로(의미 있으면 화살표로 추가).

#### 3.2 커버리지

- 기준 목록: `graft/.graph/wiring.json` 의 `kind == "file"` 노드 중 `meta.scope` 안. 별도 파일 순회 없음. wiring.json 이 없으면 커버리지 검사는 "건너뜀" 으로 보고
- 배정: 파일마다 같은 view 안에서 `paths` 가 **가장 길게 일치하는** 박스 하나 (경로가 겹쳐도 결정적 — 예: `s3` 의 `engine/snapshot_store.py` 가 `mart` 의 `engine/` 를 이긴다)
- 층별 검사: L0 에서는 scope 의 모든 파일, drill 된 박스의 하위 view 에서는 **그 박스에 배정된 파일 전부**가 하위 박스 중 하나에 배정되거나 제외돼야 한다
- 제외: `meta.excluded: [{"path": "tests/", "why": "테스트 코드"}]`. `why` 필수. 제외 파일은 "결정됨" 으로 집계하고 리포트에 이유와 함께
- 판정: 대상 지정 모드는 경고(리포트만), 레포 전체 모드는 미배정 ≥ 1 이면 integrity 오류
  ```
  L0: 미배정 80개 — src/agents/simulation/ 29, devbff/ 14, … — 박스 paths 에 넣거나 excluded 에 이유와 함께
  ```
- 화면: 머리에 원형 그래프 "파일 256/256 · 제외 45" (deadhd `stats` ring)

#### 3.3 레포 전체 모드

- `/rakis:eli5` (대상 없음) 또는 `--all`. scope 기본값은 `wiring.json` 파일들의 최상위 디렉터리 전부
- 조사: `graft map` 디렉터리 클러스터 → L0 후보
- 깊이: **L0 와 모든 L1 을 펼친다.** 그 아래는 `/rakis:eli5 --deepen <view:박스id>` 로 요청 시. 커버리지 보장은 펼친 층까지
- 시나리오: 주요 입구 흐름 2~4개

#### 3.4 검증

- 단위: 가장 긴 일치, 겹치는 paths, 층별 미배정, excluded(이유 누락 실패), 대상 모드 경고 vs 전체 모드 실패, wiring.json 없음
- 실측: agent-production-profitability 를 레포 전체 모드로 — 미배정 0, 층 수·박스 수 기록

### 4단계 — 작업 진행 표시

#### 4.1 쓰는 주체 분리 (같은 파일 동시 쓰기 방지)

| 파일 | 쓰는 쪽 | 내용 |
|---|---|---|
| `$ROOT/.eli5/track/<session_id>.json` — `--out` 과 무관하게 항상 이 위치 (훅이 찾을 수 있게) | `/rakis:eli5 track` | 추적 표식: `{model, slug, started_at}` — `model` 은 절대 경로, 나머지 두 파일은 그 모델 옆 `$OUT/` 에 |
| `<slug>.touched.<session_id>.json` | **훅 (자동)** | `{"files": {"src/api/turn.py": {"box": {"L0": "api", "L1-api": "prepare"}, "at": "..."}}}` |
| `<slug>.progress.<session_id>.json` | **에이전트** | deadhd 형식: `{task: {title, goal, doneWhen}, updated, items: [{id, title, body, state: plan\|now\|done\|blocked, boxes: ["L0:api"], evidence: []}], footer}` |

- **훅**: `hooks/hooks.json` 에 `PostToolUse` matcher `Edit|Write|MultiEdit|NotebookEdit` → `python3 "${CLAUDE_PLUGIN_ROOT}/skills/eli5/bin/track.py" touch`. stdin 의 `session_id`·`tool_input.file_path` 를 읽는다
  - 수정된 파일에서 위로 올라가며 `.eli5/track/<session_id>.json` 를 찾는다 (git 명령 없음). **없으면 즉시 exit 0** — 모든 레포의 모든 편집에서 도는 훅이다
  - 세션 단위 표식이라 같은 레포에서 다른 세션의 편집은 기록되지 않는다
  - `.eli5/` 안 파일 편집은 무시
  - 매핑: 3.2 의 가장 긴 일치를 view 마다. 어느 박스에도 안 맞으면 `"box": {}` (지도 밖)
  - 기록 후 `render.py` 를 호출해 다시 그린다 (validate·graft 재실행 없음)
  - 훅 실패는 편집을 막지 않는다 — 항상 exit 0, 오류는 `$OUT/track/<session_id>.log` 에
- **에이전트 규칙** (deadhd): `done` 은 이 세션의 도구 결과(통과한 테스트·쓴 파일·머지된 PR)로 입증된 것만, `now` 는 최대 1개, 컨텍스트가 압축됐으면 `footer` 에 밝힌다. 항목 상태가 바뀔 때 progress 파일을 쓰고 `render.py` 를 부른다. 갱신은 채팅에 보고하지 않는다
- **검증** (`render.py` 가 progress 파일을 읽을 때, 실패 시 진행 표시만 빼고 지도는 그린다 + 머리에 오류 배지): `now` ≤ 1, `boxes` 가 실재, `done` 은 `evidence` 비지 않음, `href` 는 http(s)

#### 4.2 화면

- 박스 상태: 진행(주황 테두리) · 완료(초록 ✓) · 막힘(빨강 !) · 계획(회색 점선) · **건드림만(파란 점 + "3파일")**. 한 박스에 여러 상태면 막힘 > 진행 > 완료 > 계획 > 건드림
- 상위 박스: 하위 view 상태를 숫자 배지로 집계("안에서 진행 1 · 완료 2")
- 지도 밖 변경: 머리에 "지도 밖 변경 2파일" 경고 + 목록 — 지도가 낡기 시작했다는 신호
- 오른쪽: deadhd 카드 막힘 → 진행 → 완료 → 남음. 카드 클릭 → 관련 박스 강조. 머리에 진행 막대 + 상태 집계
- 갱신: 추적 표식이 있을 때만 `<meta http-equiv="refresh" content="15">`. `sessionStorage` 에 직전 상태를 두고 새로 `done` 된 박스만 효과(`prefers-reduced-motion` 이면 생략). view·시나리오는 해시로 유지
- 신뢰 표시: "에이전트 갱신 12분 전" (`updated` 기준). 판단 상태가 낡은 정도를 숨기지 않는다. 건드림은 훅이 기록하므로 압축과 무관

#### 4.3 명령

```
/rakis:eli5 track [<model>]   표식 생성 + 지도 열기 (레포 전체 지도 권장)
/rakis:eli5 track off         표식 삭제 + 마지막 렌더 (자동 갱신 끔)
```

여러 세션이 각자 추적하면 지도 HTML 은 세션별로 따로 렌더한다(`<slug>.track.<session_id>.html`). 한 장에 여러 세션을 합치는 대시보드는 비목표.

#### 4.4 검증

- 단위: 경로→박스(가장 긴 일치·겹침·지도 밖), 세션 필터, `.eli5` 내부 무시, **표식 없을 때 10ms 이내 종료**(측정), 훅 예외 시에도 exit 0, progress 검증(`now` 2개 · 없는 박스 · 근거 없는 done), 렌더 병합, 자동 갱신 태그는 추적 중에만
- 실측: 추적 켠 세션에서 Edit 로 파일 하나 수정 → **20초 이내** 해당 박스 "건드림". 다른 세션에서 같은 레포 수정 → 표시 안 됨

## 완료 기준 (단계별, 실측)

1. **1단계**: 재생성한 지도에서 박스·화살표 코드 이름 0 (검증기), 사용자가 v2 와 나란히 보고 "한눈에 들어온다" 판정
2. **2단계**: "화면에서 조건을 입력하면" 시나리오가 단계 ≤ 7, 모든 연결이 실제 화살표, 사용자가 패널 답변보다 이해된다고 판정. 공유 링크가 같은 단계를 연다
3. **3단계**: 레포 전체 모드에서 미배정 0, 제외는 전부 이유 있음
4. **4단계**: 편집 → 20초 이내 "건드림", 다른 세션 편집 미표시, 표식 없는 레포에서 훅 10ms 이내

## 위험

- **범위가 크다** (질문 패널 제거 + 4단계). 완화: 단계마다 plan·배포 분리. 4단계가 막혀도 1~3 은 쓸 수 있다
- **쉬운 말 검사의 오탐** — 정상 한국어 문장에 `.` 이 들어간 약어 등. 완화: glossary 예외, 오류 메시지에 해당 토큰 표시. 1단계 실측에서 오탐률 기록
- **레포 전체 모드 비용** — L1 전부 펼치기는 큰 레포에서 생성 시간이 길다. 완화: L2 이하는 요청 시만. 실측에서 시간 기록
- **PostToolUse 훅이 모든 편집에 붙는다** — 완화: 표식 없으면 파일 시스템 조회 몇 번 후 종료, 10ms 기준 테스트
- **에이전트 판단 상태는 여전히 지시문 의존** (deadhd 와 같은 한계) — 완화: "건드림" 은 훅이 보장하고, 판단 상태의 신선도를 화면에 표시

## 출처 표기

`SKILL.md` "출처" 절과 차용 코드 파일 머리 주석에 deadhd·archify MIT 저작권 문구를 남긴다. arch-explorer 는 "설계만 참고, 코드 미사용 — 라이선스 없음" 유지.
