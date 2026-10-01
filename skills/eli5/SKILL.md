---
name: eli5
description: "코드베이스·시스템 구조를 사람이 따라 내려갈 수 있는 드릴다운 HTML 지도로 만들고, 지도 옆 패널에서 바로 여러 턴으로 질문할 수 있게 연다. 화살표마다 graft 호출 그래프·소스 인용·기록으로 근거를 기계 판정해 실선(graft 증명)·점선(코드 읽음)·주황(기록 해석)·빨강(미확인)으로 구분한다. '그림으로 설명해줘', '구조 좀 그려줘', '이 코드 어떻게 도는지 보여줘', '아키텍처 지도', '/rakis:eli5 <대상>' 일 때 사용. 낯선 모듈 파악·설계 검토·장애 경로 추적·구현 전 정렬 확인."
version: 2.0.0
license: MIT
---

# eli5 — 근거가 검증된 지도 + 질문 패널

정돈된 상자와 화살표는 정확하다는 인상을 준다. 하지만 그림의 사실성은 무엇을 읽고 그렸는지에만 달려 있다. v1 은 그 판단을 LLM 의 성실성에 맡겼다. v2 는 **LLM 은 내용만 쓰고, 판정과 그리기는 스크립트가 한다.**

- 화살표의 진위는 `validate.py` 가 graft 호출 그래프·파일·git 으로 판정한다. 주장한 근거가 확인되지 않으면 자동으로 강등된다
- HTML 은 `render.py` 가 고정 템플릿으로 만든다. LLM 은 HTML 을 쓰지 않는다
- 지도는 `server.py` 가 질문 패널을 붙여 연다. 답은 read-only `claude -p` 가 지도 모델과 graft 를 근거로 만든다

쓰임은 쉬운 설명이 아니다. **구현 전에 사람과 에이전트가 같은 시스템을 보고 있는지 확인하는 것**이다.

## 인자

```
/rakis:eli5 <설명할 대상> [--out <dir>] [--quick] [--no-open]
/rakis:eli5 open [<model.json>]      기존 지도를 패널과 함께 다시 연다
/rakis:eli5 stop [<model.json>]      패널 서버 수동 종료
```

- `--out` — 출력 폴더. 기본 `<레포>/.eli5/` (`.git/info/exclude` 로 숨긴다)
- `--quick` — 인용 줄 대조(quote)와 Phase 5 렌더링 확인을 생략한다. 지도에 "미검증" 배지가 붙고, **구현·리뷰의 근거로 쓰지 않는다.** 무결성 검사와 graft 판정은 생략하지 않는다
- `--no-open` — 지도만 만들고 서버는 띄우지 않는다

## 경로 약속

- `$SKILL` = 이 스킬의 base directory (호출 시 "Base directory for this skill" 로 주어진다). 스크립트는 `$SKILL/bin/`
- `$ROOT` = 대상 git 레포 루트. `$OUT` = `--out` 또는 `$ROOT/.eli5`
- slug = 대상을 영문 kebab-case 3~5 단어로 축약
- `$MODEL` = `$OUT/<slug>.model.json` → 지도 `$OUT/<slug>.html`, 사이드카 `$OUT/<slug>.eli5.json`

## 원칙

- 코드 실행 순서가 아니라 **사람과 시스템이 주고받는 일의 순서**로 그린다
- **모르는 것은 그리지 않는다.** 그려야 한다면 `unknown` 등급으로 그리고 `unknowns` 에 남긴다
- 글은 박스 라벨 수준으로. 상세는 인터페이스 카드로
- 대상 레포의 추적 파일을 바꾸지 않는다

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
  "meta": {"target": "<대상>", "scope": ["src/"], "graft_version": "<Phase 0 version>"},
  "views": {
    "L0": {
      "title": "L0 · 실행 단위", "hint": "<이 층을 한 문장으로>", "parent": null,
      "rules": [{"text": "<설계 규칙>", "grade": "code|record|unknown", "evidence": {}}],
      "nodes": [{"id": "api", "title": "API 서버", "lines": ["<2~3줄>"], "row": 0, "col": 0, "span": 1,
                 "paths": ["src/api/"], "drill": "L1-api"}],
      "edges": [{"from": "api", "to": "core", "label": "<인터페이스 이름>", "iface": "<iface id>",
                 "grade": "graft|code|record|unknown", "evidence": {}}],
      "ifaces": [{"id": "...", "title": "...", "from": "api", "to": "core", "transport": "python call|http|queue|subprocess|file",
                  "items": [{"sig": "<시그니처>", "desc": "<한 줄>", "ref": "path:line"}]}]
    }
  },
  "unknowns": [{"text": "...", "why": "..."}]
}
```

**등급과 evidence** — 검증기가 이 형식으로만 판정한다:

| 등급 | 언제 | evidence |
|---|---|---|
| `graft` | Phase 1-3 에서 `graft callers` 로 직접 본 호출 | `{"from_sym": "src/api/server.py#handle", "to_sym": "src/core/engine.py#run_job"}` — 노드 id 를 **복사**. 지어내면 검증기가 강등한다. 같은 관계를 코드로도 읽었다면 `ref`·`quote` 를 함께 넣는다 (graft 판정 실패 시 code 로 강등되는 안전망) |
| `code` | 소스에서 직접 읽은 관계 (HTTP·큐·subprocess 등) | `{"ref": "src/core/engine.py:5", "quote": "requests.post"}` — quote 는 그 줄(±2)에 실제로 있는 10~40자 |
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

- **exit 1** — `integrity_errors` 를 고치고 다시 실행한다. 3 회 연속 실패하면 멈추고 오류 목록을 보고한다
- **exit 0** — 리포트를 읽는다
  - `downgrades`: **받아들인다.** 강등을 피하려고 근거를 바꾸지 않는다. 예외는 하나 — 사유가 "paths 밖" 이고 박스 `paths[]` 를 실제로 잘못 잡은 경우에만 paths 를 고쳐 재검증한다
  - `missing_edges`: graft 가 찾았는데 그림에 없는 관계. 의미 있는 관계면 graft 등급 edge 로 추가하고 재검증한다. 의도적으로 뺐다면 그대로 둔다 (지도 하단에 노출된다)

## Phase 4: 렌더

```bash
python3 "$SKILL/bin/render.py" "$MODEL" --root "$ROOT"
```

HTML 을 직접 쓰거나 고치지 않는다. 모양을 바꾸려면 모델을 고쳐 Phase 3 부터 다시.

## Phase 5: 렌더링 확인

`--quick` 이면 생략하고 출력에 "렌더링 미확인" 을 남긴다.

- Chrome 자동화(`mcp__claude-in-chrome__*`)가 있으면 `file://<html>` 을 열고 view 마다(`#view=<id>`) 스크린샷을 찍어 박스 겹침·라벨 충돌·박스를 관통하는 화살표·잘린 글자를 확인한다. 문제는 모델의 격자를 고쳐 Phase 3~4 를 다시 돈다
- 없으면 `open "<html>"` 후 사용자에게 확인을 요청한다. "열릴 것이다" 로 넘어가지 않는다

## Phase 6: 열기

`--no-open` 이 아니면:

```bash
python3 "$SKILL/bin/server.py" open --model "$MODEL"
```

- `panel: false` 면 `reason` 을 전한다 (claude CLI 없음 → 패널 없는 지도만 열림)
- `git -C "$ROOT" status --short` 가 Phase 0 기록과 같은지 대조한다. 다르면 무엇이 생겼는지 보고한다

## Phase 7: 출력

```
✓ <slug>.html   패널: <url>
  근거: graft a · 코드 b · 기록 c · 미확인 d   (검증 강등 n건)
  그림에 없는 관계: m건
  확인 못 한 것:
    - <unknowns 항목>
  서버: 탭을 닫으면 30초 뒤 자동 종료 · 수동 종료 /rakis:eli5 stop
```

마지막 줄로 안내한다:

> 이 지도는 코드를 대신하지 않는다. 어디부터 어떤 관점으로 읽을지 정해주는 첫 지도다. 중요한 결론은 원본 코드·로그·변경 이력으로 다시 확인한다.

## open / stop

- `open` — 모델 경로가 없으면 `$ROOT/.eli5/*.model.json` 중 가장 최근 것. 먼저 `python3 "$SKILL/bin/server.py" status --model "$MODEL"` 로 지도 상태를 본다. `stale` 이면 "지도가 코드보다 낡았다 — 다시 만들까요, 그대로 열까요?" 를 묻는다 (기본 그대로 열기 — 열면 패널에 경고 배너). 다시 만들기는 기존 모델을 출발점으로 Phase 1 부터
- `stop` — `python3 "$SKILL/bin/server.py" stop --model "$MODEL"`

## 하지 않는 것

- 보안 검토·장애 원인 보고서를 대체하지 않는다
- 그림이 틀렸다는 지적을 받기 전에 구현으로 넘어가지 않는다 — 이 스킬의 존재 이유가 그 확인 단계다
- 조사 없이 그림부터 그리지 않는다
- graft 등급을 graft 로 보지 않고 주장하지 않는다

## 출처

- 공식 `eli5` 스킬 — [anthropics/claude-plugins-community](https://github.com/anthropics/claude-plugins-community/tree/main/eli5) (Thariq Shihipar, MIT)
- 보강 조건 — [앤트로픽의 ELI5 스킬 (desty, 2026-08-23)](https://desty.github.io/blog/60-eli5-visual-explainer/)
- 레이어 드릴다운·인터페이스 카드·패널 주입 구조 — [robintech-seoul/agent-toolkit](https://github.com/robintech-seoul/agent-toolkit) `arch-explorer` (설계만 참고, 코드 미사용 — 라이선스 없음)
- 호출 그래프 — [graft](https://github.com/trailhq/Graft) (MIT)
- 설계 문서 — `docs/superpowers/specs/2026-10-01-eli5-graft-chat-design.md`
