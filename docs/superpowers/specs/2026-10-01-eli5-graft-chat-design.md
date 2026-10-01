# eli5 v2 — graft 검증 지도 + 질문 패널 설계

- **작성일**: 2026-10-01
- **상태**: 설계 승인 대기
- **영향 범위**: rakis `eli5` 스킬 (1.0.0 → 2.0.0). 플러그인 버전은 pre-push 훅이 `feat:` 커밋을 보고 자동 bump (3.20.0)
- **단계**: 1단계 (현재 코드 지도 + 질문 패널). PR 리뷰용 diff 모드는 2단계 별도 spec
- **참고**: [robintech-seoul/agent-toolkit](https://github.com/robintech-seoul/agent-toolkit) `arch-explorer` · `code-wiki` (라이선스 없음 — 설계만 참고, 코드 미사용), [graft](https://github.com/trailhq/Graft) 0.16.0
- **vault 근거**: `wiki/comparisons/graft-vs-code-wiki-arch-explorer.md`, `wiki/sources/desty-github-io-blog-60-eli5-visual-explainer.md`

## 배경

eli5 1.0.0은 117줄 지시문이다. LLM이 조사하고, 조사 기록표(확인/해석/미확인)를 만들고, HTML을 직접 쓰고, 스스로 의미 검증을 한다. 두 가지가 부족하다.

1. **정확도가 LLM의 성실성에 달려 있다.** "확인" 등급 화살표도 결국 LLM이 "코드에서 읽었다"고 주장한 것이다. 이를 기계적으로 반증할 장치가 없다. 레이아웃·스타일도 매 실행 LLM이 HTML을 새로 써서 흔들린다.
2. **지도가 일방향이다.** 그림을 보다 생긴 질문("이 박스 뭐야", "그럼 에러 나면?")은 터미널로 돌아가 물어야 하고, 그 답은 지도와 연결되지 않는다.

arch-explorer는 2번을 풀었지만(로컬 서버가 채팅 패널을 주입, headless `claude -p`가 답변) 1번은 풀지 않았다 — LLM이 쓴 MODEL을 신뢰하고 체크리스트로 사후 점검한다. 또 서버가 `stop` 전까지 무기한 생존해 고아 프로세스 위험을 사용자에게 넘긴다.

이 환경은 graft(tree-sitter 결정적 호출 그래프)를 이미 쓴다. graft는 정확하지만 에이전트용이라 사람용 레이어 지도가 없다. **두 장점을 합친다: 지도는 사람용으로 LLM이 쓰고, 화살표의 진위는 graft로 판정한다.**

## 목표

- 지도 위 모든 화살표·설계 규칙에 **기계로 판정한 근거 등급**을 붙인다
- 지도를 보면서 **여러 턴으로 질문**하고, 답의 인용이 지도로 링크된다
- 브라우저 탭을 닫으면 서버와 자식 프로세스가 **스스로 정리**된다
- 업무 레포에서 실행해도 `git status`가 깨끗하다

**비목표**

- PR/브랜치 diff 지도 (2단계)
- codex 엔진 (claude만)
- 죽은 서버의 자동 부활 — 브라우저는 프로세스를 띄울 수 없고, 가능한 유일한 방법(launchd socket activation)은 상주 에이전트를 요구해 좀비 방지 목표와 상충한다
- code-wiki 도입 — 지식 베이스 역할은 graft가 맡는다

## 설계

### 1. 구성요소

```
skills/eli5/
  SKILL.md              Phase 0~6 절차 (아래 §2)
  bin/
    graft_prep.py       graft 확인·빌드, 생성된 ignore 파일을 .git/info/exclude 로 이전
    validate.py         지도 모델 결정적 검증 (§4)
    render.py           모델 JSON → 단일 HTML (템플릿에 MODEL 삽입)
    server.py           서빙 + 패널 주입 + SSE 수명 + /api/ask → claude -p (§5)
  assets/
    map.html            지도 템플릿 — 격자 레이아웃·SVG 화살표·드릴다운·카드·4등급 스타일
    panel.html          질문 패널 (서버가 서빙할 때만 주입, Shadow DOM)
    answer-rules.md     claude -p 에 붙이는 답변 규칙
tests/unit/test_eli5_validate.sh
tests/unit/test_eli5_render.sh
tests/unit/test_eli5_server.sh
tests/fixtures/eli5/    가짜 graft·claude 스크립트, 픽스처 레포·모델
```

- 모든 Python 스크립트는 **표준 라이브러리만** 쓴다. 실행은 `python3` 직접 — 플러그인 레포에 `pyproject.toml`이 없고, 대상 레포의 Python 환경과 섞이지 않게 한다
- **역할 분리**: LLM은 내용(무엇을 그릴지·근거)만 쓰고, 판정(validate)과 그리기(render)는 스크립트가 한다. LLM은 HTML을 쓰지 않는다

### 2. 스킬 절차

```
/rakis:eli5 <대상> [--out <dir>] [--quick] [--no-open]
/rakis:eli5 open [<model.json>]     기존 지도를 패널과 함께 열기
/rakis:eli5 stop [<model.json>]     서버 수동 종료
```

| Phase | 하는 일 | 실패 시 |
|---|---|---|
| 0 graft 준비 | `graft_prep.py` — graft 설치·인덱스 확인, 없으면 `graft build`, 새로 생긴 `.gitignore`/`.ignore` 변경을 원복하고 `graft/`·`.ignore` 를 `.git/info/exclude` 에 추가 | graft 미설치: 계속 진행, `graft` 등급 없음을 기록 |
| 1 조사 | 1.0.0과 동일한 추적 순서. 1차 도구는 `graft map` → `graft ask` → `graft callers`, 이어서 소스·ADR·PR·`git log` | — |
| 2 모델 작성 | LLM이 `<out>/<slug>.model.json` 작성 (§3) | — |
| 3 검증 | `validate.py` — 무결성 오류면 exit 1 → LLM이 고쳐 재실행. 강등은 경고 | 3회 실패 시 중단, 오류 보고 |
| 4 렌더 | `render.py` → `<out>/<slug>.html` + 사이드카 `<slug>.eli5.json` | — |
| 5 렌더링 검증 | 브라우저로 열어 겹침·잘림·관통 확인 (Chrome 자동화 있으면 스크린샷) | 없으면 사용자에게 확인 요청 |
| 6 열기 | `server.py open` — 패널과 함께 브라우저 오픈 | `claude` 없음: `file://` 로 패널 없이 오픈 |

`--quick`: Phase 3의 `code` 등급 quote 검사와 Phase 5를 생략. 출력·HTML 상단에 "미검증" 배지. 무결성 검사와 `graft` 판정은 생략하지 않는다(비용이 거의 없다).

**출력 위치**: 기본 `<repo>/.eli5/`. 첫 실행 시 `.eli5/` 를 `.git/info/exclude` 에 추가한다. `.gitignore` 는 건드리지 않는다. 종료 시 `git status --short` 가 실행 전과 같은지 확인해 보고한다.

### 3. 지도 모델

```jsonc
{
  "meta": { "target": "...", "commit": "<sha>", "scope": ["src/"], "built_at": "...",
            "graft_version": "0.16.0" },          // render 가 사이드카로도 복사
  "views": {
    "<viewId>": {
      "title": "...", "hint": "...", "parent": "<viewId>|null",
      "rules":  [{ "text": "adapter 는 runtime 을 import 하지 않는다", "grade": "...", "evidence": {...} }],
      "nodes":  [{ "id": "...", "title": "...", "lines": ["..."],
                   "row": 0, "col": 1, "span": 1,           // 격자 — 좌표는 템플릿이 계산
                   "paths": ["src/runtime/"],               // 이 박스가 담당하는 경로. 검증 기준점
                   "drill": "<viewId>?" }],
      "edges":  [{ "from": "<nodeId>", "to": "<nodeId>", "label": "run(session, task)",
                   "iface": "<ifaceId>?", "grade": "...", "evidence": {...} }],
      "ifaces": [{ "id": "...", "title": "...", "from": "...", "to": "...", "transport": "python call|http|queue|subprocess|file",
                   "items": [{ "sig": "...", "desc": "...", "ref": "path:line" }] }]
    }
  },
  "unknowns": [{ "text": "...", "why": "..." }]
}
```

- 레이아웃은 행·열 격자다. arch-explorer는 좌표를 손으로 쓰지만("hand-set coordinates beat auto-layout"), 여기는 매 실행 LLM이 쓰므로 좌표 실수를 줄이는 쪽을 택한다
- `ref` 는 항상 `path:line` 단일 문자열 — 패널이 답변 속 인용을 이것과 **정확 일치**로만 카드에 링크한다

### 4. 근거 등급과 검증 (`validate.py`)

| 등급 | 그림 | evidence | 판정 |
|---|---|---|---|
| `graft` | 실선 | `{from_sym, to_sym}` (graft 노드 id, 예 `pkg/a.py#main`) | ① `graft callers <to_sym> --json` 결과 hits 에 `from_sym` 이 있다 ② `from_sym`·`to_sym` 의 path 가 각각 from·to 박스 `paths[]` 아래다 |
| `code` | 점선 | `{ref: "path:line", quote}` | 파일 존재, `line±2` 범위에 `quote` 부분 문자열 존재. **존재하지 않는 인용을 거른다** |
| `record` | 주황 점선 | `{ref}` — 커밋 해시 / `PR#n` / 문서 경로 | 대상 존재만 확인 (`git cat-file -e`, 파일 존재, PR 은 형식만). 해석의 옳고 그름은 판정 불가 |
| `unknown` | 빨간 점선 | 없음 | 판정 없음. `unknowns[]` 에 같은 `text` 항목이 없으면 검증기가 자동 추가한다 |

`rules[]` 는 `code`·`record`·`unknown` 만 허용한다. 설계 규칙은 대개 "A 는 B 를 import 하지 않는다" 같은 **부재** 주장이라 `callers` 의 존재 판정으로 증명할 수 없다. `rules[]` 에 `graft` 가 오면 무결성 오류로 처리한다.

**강등**: `graft` 판정 실패 → evidence 에 `ref`+`quote` 가 함께 있고 통과하면 `code`, 아니면 `unknown` + `unknowns[]` 에 자동 추가. `code` 실패 → `unknown`. 강등은 경고이며 모델 파일을 갱신하고 리포트에 `주장 → 판정` 으로 남긴다.

**무결성 오류 (exit 1)**: 존재하지 않는 노드를 가리키는 edge, 없는 view 로의 drill, 존재하지 않는 iface 참조, 어떤 edge 도 참조하지 않는 iface, 같은 view 안 격자 칸 중복, `rules[]` 의 `graft` 등급.

**누락 탐지 (경고)**: `graft/.graph/wiring.json` 의 `calls` edge 중 서로 다른 박스의 `paths[]` 에 걸치는데 지도에 대응 edge 가 없는 것을 "그림에 없는 관계" 로 보고한다. wiring.json 은 graft 내부 포맷이므로 `meta.version == 1` 일 때만 읽고, 아니면 누락 탐지를 건너뛰고 그 사실을 보고한다. 판정(위 표)은 공개 CLI 로만 한다.

**리포트**: `{ counts: {graft, code, record, unknown}, downgrades: [...], integrity_errors: [...], missing_edges: [...], graft: "ok|absent|index-built" }` — JSON 으로 stdout, SKILL 이 사람용 요약으로 옮긴다.

실측 메모 (2026-10-01, graft 0.16.0): `callers --json` 은 호출자 심볼의 span 만 주고 호출 줄은 주지 않는다. `requests.post` 같은 HTTP 호출은 edge 로 잡히지 않는다 — 프로세스 경계 화살표는 대부분 `code` 등급이 된다. 이것이 등급을 나눈 이유다.

### 5. 서버 (`server.py`)

**기동** — `open`:
1. 상태 파일 `$TMPDIR/rakis-eli5/<sha1(root+model)>.json` (0600): `{pid, port, token, started_at, conversations: {conv_id: session_id}}`
2. pid 생존 + `/health` 응답 → 재사용, URL 만 출력
3. 아니면 `start_new_session=True` 로 분리 기동, 15초까지 `/health` 폴링. 포트는 상태 파일의 이전 포트 우선, 사용 중이면 OS 할당
4. 브라우저로 `http://127.0.0.1:<port>/?t=<token>` 오픈

**보안**: `127.0.0.1` bind. 모든 요청 Host 헤더 화이트리스트(DNS rebinding 방지). `/?t=` → `HttpOnly; SameSite=Strict` 쿠키 → 303. `/api/*` 는 쿠키 필수, `hmac.compare_digest`. POST 는 Origin 추가 검사.

**서빙**: 디스크의 HTML 을 읽어 `</body>` 앞에 패널을 주입해 응답. 파일은 바꾸지 않는다. 패널은 Shadow DOM, 공간은 `html { padding-right }` 로 확보(arch-explorer 가 `body` margin 으로 겪은 밀림 버그 회피).

**수명**:

| 장치 | 동작 |
|---|---|
| SSE `/api/life` | 패널이 연결 유지, 서버가 15초마다 ping. 연결 수 0 → 30초 유예, 재연결 시 취소, 만료 시 종료 |
| 하드캡 | 기동 후 24시간이면 연결과 무관하게 종료 |
| 종료 처리 | SIGTERM·`atexit` 에서 진행 중인 자식 프로세스 그룹 전부 `killpg(SIGTERM)` → 5초 → `SIGKILL`, 상태 파일은 자기 pid 일 때만 삭제(재사용 경쟁 방지). 대화 매핑은 별도 파일로 보존 |
| `stop` | 상태 파일의 pid 에 SIGTERM, 10초 내 미종료 시 SIGKILL |

타이머 heartbeat 대신 연결 끊김을 쓰는 이유: Chrome 은 백그라운드 탭 타이머를 분 단위로 지연시켜 heartbeat 를 오판한다.

**질문** — `POST /api/ask {conv_id, question, context}` → NDJSON 스트림:

```
claude -p --output-format stream-json --verbose --include-partial-messages
  --tools Read,Grep,Glob
  --strict-mcp-config --mcp-config <{"mcpServers":{"graft":{"command":"graft","args":["mcp","<root>"]}}}>
  --allowedTools mcp__graft
  --setting-sources "" --settings '{"disableAllHooks":true}'
  --append-system-prompt <answer-rules.md + 모델 경로>
  [--resume <session_id>]
```

- cwd = 레포 루트. 환경변수에서 `CLAUDECODE`·`CLAUDE_CODE_ENTRYPOINT`·`CLAUDE_CODE_SSE_PORT` 제거(부모 Claude Code 세션 중첩 오인 방지)
- Bash 권한 없이 graft 를 쓰도록 graft MCP 하나만 연결 — `--tools` 만으로는 사용자 MCP 가 남으므로 `--strict-mcp-config` 필수
- `--allowedTools mcp__graft` 필수 — 없으면 MCP 도구 호출이 `permission_denied` 로 막혀 답이 "권한이 필요합니다" 로 끝난다 (2026-10-01 실측)
- `--setting-sources "" --settings '{"disableAllHooks":true}'` 필수 — 없으면 사용자 전역 hook(실측 SessionStart 6개, claude-mem 등)이 패널 질문마다 실행돼 지연과 기록 오염이 생긴다. 인증은 영향 없음(실측)
- 실측: `--resume <session_id>` 는 **별도 프로세스에서도** 이전 턴을 기억한다 → 서버 재기동 후 대화 이어가기가 성립한다
- 질문 stdin 으로 `[map context]` 블록 + 질문 전달. 블록: 현재 view(id·title·hint), 선택 박스(id·title·lines 상위 6), 이 view 의 iface 상위 30 × item 상위 4 `{sig, ref}`. 서버에서 6000자 상한 재적용
- 이벤트 정규화: `session` / `delta` / `tool`(읽는 파일·graft 호출 표시용) / `final` / `error`. **스트림은 반드시 `final` 또는 `error` 하나로 끝난다** — 비정상 종료는 종료 코드 + stderr 끝 20줄을 `error` 로
- 질문당 타임아웃 180초 → 프로세스 그룹 kill → `error`. 클라이언트 연결 끊김(쓰기 실패) 시 즉시 kill
- 대화당 동시 질문 1개 (위반 시 409)
- `session` 이벤트의 session_id 를 상태 파일 `conversations` 에 저장 → 서버 재기동 후에도 `--resume` 으로 이어간다

**answer-rules.md 요지**: graft 와 지도 모델을 1차 근거로 한다 / 소스는 필요한 것만 연다 / 모든 주장에 `path:line` / 근거 없으면 모른다고 한다 / 질문 언어로 답한다 / 지도의 `unknown` 요소는 "지도에서도 미확인" 이라고 밝힌다 / 짧게.

### 6. 패널

- 상단: 엔진 배지, 새 대화, 선택 칩(`<view> › <node>` ×)
- 지도 템플릿이 `arch:view`·`arch:select` CustomEvent 를 쏘고 패널이 듣는다. `MODEL` 은 전역 변수(classic script)
- 답변 렌더: 전부 escape 후 code·bold·link·`path:line` 만 토큰화하는 마크다운 부분집합. `path:line` 이 iface `ref` 와 정확히 일치하면 카드 링크 → 클릭 시 해당 view 로 이동 후 카드 하이라이트
- `tool` 이벤트로 "읽는 중: …" 표시
- **SSE 끊김 → 재연결 시도 30초 → 실패 시 "서버 종료됨" 배너 + 재시작 명령(`/rakis:eli5 open <model>`) 복사 버튼.** 입력 중이던 질문은 보존
- 지도가 낡았으면(§7) 상단 경고 배너

### 7. 낡음 판정

사이드카 `<slug>.eli5.json`: `{version: 1, commit, scope, dirty, built_at, graft_version}`. `open` 시 `git diff --name-only <commit>..HEAD -- <scope>` (`.eli5/`·`graft/` 제외) 가 비어 있지 않으면 stale. `missing | unknown | stale | fresh`. stale 이면 "다시 만들기 / 그대로 열기" 를 묻는다 — 기본은 그대로 열기(재빌드 비용이 크고 파일 변경이 곧 구조 변경은 아님).

## 오류 처리

| 상황 | 동작 |
|---|---|
| graft 미설치 | Phase 0 경고, `graft` 등급 판정 불가 → `graft` 주장은 전부 강등. 리포트·지도 상단에 "graft 없음" |
| graft 인덱스 없음 | `graft build` (Tier 1, $0) → ignore 파일 원복·exclude 이전 |
| graft 얕은 지원 언어 | 판정 실패로 강등. 리포트에 "언어 지원 범위 가능성" 표기 |
| `claude` 미설치 | 패널 없이 `file://` 오픈 |
| `claude` 비정상 종료 / 타임아웃 | `error` 이벤트로 그대로 노출. 빈 답을 성공으로 표시하지 않는다 |
| 포트 충돌 | OS 할당 포트로 대체 |
| 상태 파일의 pid 가 죽어 있음 | 상태 파일 정리 후 새로 기동 (대화 매핑은 유지) |
| validate 3회 연속 무결성 실패 | 중단, 오류 목록 보고 |

## 테스트

**단위** (`tests/unit/test_eli5_*.sh`, 가짜 `graft`·`claude` 를 PATH 앞에 둬서 결정적):

- validate: 등급별 통과/실패, `graft`→`code`→`unknown` 강등 경로, quote 불일치, 무결성 오류 6종 exit 1, wiring.json 버전 불일치 시 누락 탐지 건너뜀, graft 부재
- render: 출력 HTML 에 MODEL 포함·JSON 파싱 가능, 사이드카 생성, 4등급 CSS 클래스
- server:
  - 토큰 없음·잘못된 Host·잘못된 Origin 거부
  - **SSE 끊김 → 유예 후 프로세스 종료** (테스트용 `ELI5_GRACE_SEC=1`)
  - 하드캡 (`ELI5_MAX_LIFE_SEC=2`)
  - 질문 타임아웃 시 자식 프로세스 그룹 전멸 (`sleep` 하는 가짜 claude, `ps` 로 확인)
  - 스트림이 항상 `final`/`error` 로 끝남 (가짜 claude 가 exit 1)
  - 재기동 후 `--resume <저장된 id>` 전달 (가짜 claude 가 argv 를 에코)
  - `stop` 동작, 죽은 pid 상태 파일 정리
- graft_prep: 픽스처 git 레포에서 실행 후 `git status --short` 무변화, `.git/info/exclude` 에 항목 추가

**실측** (가짜 CLI 통과는 실행 검증이 아니다 — arch-explorer DESIGN-open 의 교훈):

1. 실제 `claude` 로 2턴 대화 + 서버 재기동 후 3번째 질문이 맥락을 이어가는지
2. 실제 레포 1곳(rakis 자신 또는 업무 레포)에서 Phase 0~6 완주, 리포트의 강등·누락 목록을 사람이 훑어 오판 여부 확인
3. 탭 닫고 40초 후 `ps -Ao pid,ppid,args | grep -E 'server.py|claude -p'` 결과 0건
4. 실행 전후 `git status --short` 동일

## 2단계 예고 (이 spec 범위 밖)

`/rakis:eli5 diff [head [base]]` — merge-base 기준으로 head 의 지도를 만들고 추가·변경·삭제 박스/화살표를 표시. `graft blast` 로 영향 범위를 함께 보여준다. 1단계의 모델·validate·render·server 를 그대로 재사용하고 모델에 `change: added|modified|removed` 필드만 더한다.
