# eli5 v3 1b단계 — 층 없는 한 장 지도 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 안쪽 층으로 들어가면 바깥 흐름이 사라지는 문제를 없앤다 — 지도는 한 장, 안쪽이 있는 박스는 그 자리에서 묶음(테두리)으로 펼쳐 모든 흐름이 한 화면에 보이게 한다.

**Architecture:** 배치 계산을 새 모듈 `bin/layout.py` 하나로 모은다(박스·묶음 사각형, 화살표 선분, 관통·테두리 침범 검사). `validate.py` 는 한 장 규칙과 관통을 이 모듈로 검사하고, `render.py` 는 계산 결과를 `MODEL.layout` 으로 HTML 에 넣으며, `map.html` 은 계산하지 않고 그리기만 한다 — 그림과 검사가 같은 숫자를 쓴다.

**Tech Stack:** Python 3 표준 라이브러리(시스템 3.9 에서도 파싱돼야 함 — f-string 안 같은 따옴표 중첩 금지), 바닐라 JS/SVG, bash 단위 테스트(`tests/fixtures/eli5/lib.sh`), `jq`, `node`(있을 때만 쓰는 템플릿 함수 테스트).

**Spec:** `docs/superpowers/specs/2026-10-02-eli5-v3-readable-map-design.md` — 1.7절 "한 장 지도". 이전 plan `docs/superpowers/plans/2026-10-02-eli5-v3-stage1-readable-map.md`(Task 1~8)의 결과 위에 쌓는다.

## Global Constraints

- 브랜치 `feat/eli5-v3`. push·merge 는 범위 밖
- 모델 `views` 는 정확히 1개, `parent` 는 `null`, `drill` 금지
- 묶음 = 다른 node 의 `group` 이 가리키는 node. 묶음은 `row`·`col`·`span`·`paths` 를 갖지 않는다. 안쪽 박스 ≥ 2. 묶음 안의 묶음 금지
- 열은 0~4 (`col + span ≤ 5`)
- 배치 상수(단일 출처 `layout.py`): `W=180 H=72 GX=110 GY=80 PAD=30 FP=14 FT=48`
- edge `label` 상한 14칸 (`plain.LABEL_MAX`), title 24·say 30 은 그대로
- 관통 검사: 화살표의 두 끝, 끝이 속한 묶음, 끝인 묶음의 안쪽 박스를 뺀 모든 박스·묶음과 선분 교차 (경계 2px 여유). 묶음 밖 박스가 묶음 테두리와 겹치면 실패
- 오류 문자열은 `<위치/대상> … — <고칠 방법>` 한 줄
- 차용 출처 주석: `segment_hits_rect` → archify (MIT, Copyright (c) 2026 tt-a1i, 2025 Cocoon AI)
- 커밋 메시지 conventional, 끝에 `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`

## Review Focus

1. **묶음 끝 화살표의 graft 판정** — `api→core`(core 가 묶음)에서 `to_sym` 이 안쪽 박스 경로에 있을 때. 기대: 묶음 경로 = 안쪽 박스 paths 합으로 판정해 graft 유지 → Task 10 테스트 "묶음 끝 화살표 graft 유지"
2. **선분이 박스 꼭짓점·경계를 스치기만 할 때** — 기대: 2px 안쪽으로 줄인 사각형으로 검사해 스침은 관통 아님 → Task 9 테스트 "경계 스침은 통과"
3. **안쪽 박스끼리의 화살표가 같은 묶음 테두리를 지나는 것** — 기대: 자기 묶음은 장애물이 아니다 → Task 9 테스트 "자기 묶음 안 화살표 통과"
4. **시스템 Python 3.9 로 스크립트를 돌림** — 기대: 문법 오류 없이 파싱 → Task 9·10·11 마지막 확인 단계 `/usr/bin/python3 -c "import ast; ..."`
5. **group 이 엉뚱한 값(없는 id·자기 자신)** — 기대: 계산이 죽지 않고 검증 오류 한 줄 → Task 10 테스트 "group 자기 자신"

---

## File Structure

| 파일 | 상태 | 책임 |
|---|---|---|
| `skills/eli5/bin/layout.py` | 신규 | 배치 상수, 묶음 찾기, 사각형·선분 계산, 관통·침범 검사 |
| `skills/eli5/bin/plain.py` | 수정 | `LABEL_MAX` 18 → 14 |
| `skills/eli5/bin/validate.py` | 수정 | 한 장 규칙, 묶음 규칙, 관통, 묶음 graft 판정 경로, 잎 단위 누락 탐지 |
| `skills/eli5/bin/render.py` | 수정 | `layout.compute` 결과를 payload 의 `layout` 으로 (저장 모델에는 넣지 않음) |
| `skills/eli5/assets/map.html` | 수정 | `MODEL.layout` 으로 그리기, 묶음 테두리·카드, 층 이동 UI 제거, 폭 맞춤 |
| `skills/eli5/SKILL.md`, `commands/help.md`, `README.md`, `CHANGELOG.md` | 수정 | 한 장 지도 규칙 |
| `tests/unit/test_eli5_layout.sh` | 신규 | — |
| `tests/fixtures/eli5/model.json` | 재작성 | 한 장 + 묶음 1개 |
| `tests/unit/test_eli5_validate.sh` · `test_eli5_render.sh` | 수정 | — |
| `lint.sh`, `test.sh` | 수정 | eli5 테스트 목록에 `layout` |

---

### Task 9: 배치 모듈 `layout.py`

**Files:**
- Create: `skills/eli5/bin/layout.py`
- Test: `tests/unit/test_eli5_layout.sh`

**Interfaces:**
- Consumes: 없음
- Produces (Task 10·11 이 쓴다):
  - 상수 `W, H, GX, GY, PAD, FP, FT`, `MAX_COLS = 5`
  - `children(view: dict) -> dict[str, list[str]]` — 묶음 id → 안쪽 박스 id (존재하는 id 를 가리키는 group 만)
  - `compute(view: dict) -> {"boxes": {id: [x, y, w, h]}, "frames": {id: [x, y, w, h]}, "edges": [[x1, y1, x2, y2] | None], "size": [w, h]}` — `edges` 는 `view["edges"]` 와 같은 순서·길이
  - `segment_hits_rect(seg, rect, inset=2) -> bool`
  - `rects_overlap(a, b) -> bool`
  - `problems(view: dict, lay: dict) -> list[str]` — 관통·테두리 침범 오류 문자열

- [ ] **Step 1: 실패하는 테스트 작성**

`tests/unit/test_eli5_layout.sh`:

```bash
#!/bin/bash
set -uo pipefail
source "$(dirname "$0")/../fixtures/eli5/lib.sh"

py() { python3 - "$ELI5_BIN" <<PY
import sys, copy; sys.path.insert(0, sys.argv[1])
import layout
V = {"nodes": [{"id": "api", "row": 0, "col": 0}, {"id": "core"},
               {"id": "engine", "group": "core", "row": 0, "col": 1},
               {"id": "init", "group": "core", "row": 1, "col": 1},
               {"id": "agent", "row": 2, "col": 0}],
     "edges": [{"from": "api", "to": "core"}, {"from": "core", "to": "agent"}, {"from": "agent", "to": "api"}]}
$1
PY
}
check() { if out=$(py "$1" 2>&1); then pass "$2"; else fail "$2" "$out"; fi; }

echo "🔧 layout — 계산"
check 'assert layout.children(V) == {"core": ["engine", "init"]}' "묶음 찾기"
check 'assert layout.children({"nodes": [{"id": "a", "group": "ghost"}]}) == {}' "없는 group 은 묶음 아님"
check 'L = layout.compute(V); assert L["boxes"]["api"] == [44, 78, 180, 72] and "core" not in L["boxes"], L["boxes"]' "박스 좌표"
check 'L = layout.compute(V); assert L["frames"]["core"] == [320, 30, 208, 286], L["frames"]' "묶음 = 안쪽 외접 + 여백"
check 'L = layout.compute(V); assert len(L["edges"]) == 3 and all(L["edges"]) and L["size"] == [558, 484], L' "선분·크기"
check 'v = copy.deepcopy(V); v["edges"].append({"from": "api", "to": "ghost"}); assert layout.compute(v)["edges"][3] is None' "끝이 없는 화살표는 None"

echo "🔧 layout — 검사"
check 'assert layout.problems(V, layout.compute(V)) == []' "깨끗한 배치"
check 'v = copy.deepcopy(V); v["nodes"][4].update(row=0, col=2); p = layout.problems(v, layout.compute(v)); assert any("engine" in x and "박스를 지난다" in x for x in p) and any("core" in x and "묶음을 지난다" in x for x in p), p' "관통 — 박스·묶음"
check 'v = copy.deepcopy(V); v["nodes"].append({"id": "x", "row": 1, "col": 1}); v["nodes"][3].update(row=2, col=1); p = layout.problems(v, layout.compute(v)); assert any("묶음 테두리 안에" in x for x in p), p' "묶음 밖 박스의 테두리 침범"
check 'v = copy.deepcopy(V); v["edges"].append({"from": "engine", "to": "init"}); assert layout.problems(v, layout.compute(v)) == []' "자기 묶음 안 화살표 통과"
check 'assert not layout.segment_hits_rect([0, 0, 100, 0], [10, 0, 20, 20]) and layout.segment_hits_rect([0, 10, 100, 10], [10, 0, 20, 20])' "경계 스침은 통과"
check 'assert layout.rects_overlap([0, 0, 10, 10], [5, 5, 10, 10]) and not layout.rects_overlap([0, 0, 10, 10], [10, 0, 5, 5])' "사각형 겹침"
finish
```

- [ ] **Step 2: 실패 확인**

Run: `bash tests/unit/test_eli5_layout.sh`
Expected: 12개 모두 ❌ (`No module named 'layout'`)

- [ ] **Step 3: 구현**

`skills/eli5/bin/layout.py`:

```python
#!/usr/bin/env python3
"""eli5 지도 배치 — 박스·묶음 사각형과 화살표 선분을 계산한다.

render.py(그리기)와 validate.py(관통 검사)가 이 모듈 하나를 쓴다 — 그림과 검사가 어긋나지 않게.
segment_hits_rect 는 archify (MIT, Copyright (c) 2026 tt-a1i, 2025 Cocoon AI)
renderers/shared/geometry.mjs 의 segmentIntersectsRect 와 같은 검사다 (Liang–Barsky 선분 자르기).
"""
W, H, GX, GY, PAD, FP, FT = 180, 72, 110, 80, 30, 14, 48
MAX_COLS = 5


def children(view):
    """{묶음 id: [안쪽 박스 id]} — group 이 가리키는 node 가 묶음이다."""
    ids = {n["id"] for n in view.get("nodes", [])}
    kids = {}
    for n in view.get("nodes", []):
        g = n.get("group")
        if g in ids:
            kids.setdefault(g, []).append(n["id"])
    return kids


def _center(r):
    return r[0] + r[2] / 2, r[1] + r[3] / 2


def _clip(r, tx, ty):
    cx, cy = _center(r)
    dx, dy = tx - cx, ty - cy
    if not dx and not dy:
        return cx, cy
    s = min(abs(r[2] / 2 / (dx or 1e-9)), abs(r[3] / 2 / (dy or 1e-9)))
    return cx + dx * s, cy + dy * s


def compute(view):
    """{"boxes": {id: [x,y,w,h]}, "frames": {...}, "edges": [[x1,y1,x2,y2] | None], "size": [w,h]}"""
    kids = children(view)
    boxes = {}
    for n in view.get("nodes", []):
        if n["id"] in kids:
            continue
        span = n.get("span", 1)
        boxes[n["id"]] = [PAD + FP + n.get("col", 0) * (W + GX), PAD + FT + n.get("row", 0) * (H + GY),
                          span * W + (span - 1) * GX, H]
    frames = {}
    for fid, cs in kids.items():
        rs = [boxes[c] for c in cs if c in boxes]
        if rs:
            x0, y0 = min(r[0] for r in rs) - FP, min(r[1] for r in rs) - FT
            x1, y1 = max(r[0] + r[2] for r in rs) + FP, max(r[1] + r[3] for r in rs) + FP
            frames[fid] = [x0, y0, x1 - x0, y1 - y0]
    rect = {**boxes, **frames}
    edges = []
    for e in view.get("edges", []):
        a, b = rect.get(e.get("from")), rect.get(e.get("to"))
        if not a or not b:
            edges.append(None)
            continue
        x1, y1 = _clip(a, *_center(b))
        x2, y2 = _clip(b, *_center(a))
        edges.append([round(x1, 1), round(y1, 1), round(x2, 1), round(y2, 1)])
    every = list(rect.values())
    return {"boxes": boxes, "frames": frames, "edges": edges,
            "size": [max((r[0] + r[2] for r in every), default=0) + PAD, max((r[1] + r[3] for r in every), default=0) + PAD]}


def segment_hits_rect(seg, r, inset=2):
    x1, y1, x2, y2 = seg
    xmin, ymin, xmax, ymax = r[0] + inset, r[1] + inset, r[0] + r[2] - inset, r[1] + r[3] - inset
    dx, dy = x2 - x1, y2 - y1
    t0, t1 = 0.0, 1.0
    for p, q in ((-dx, x1 - xmin), (dx, xmax - x1), (-dy, y1 - ymin), (dy, ymax - y1)):
        if p == 0:
            if q < 0:
                return False
            continue
        t = q / p
        if p < 0:
            if t > t1:
                return False
            t0 = max(t0, t)
        else:
            if t < t0:
                return False
            t1 = min(t1, t)
    return t0 <= t1


def rects_overlap(a, b):
    return a[0] < b[0] + b[2] and b[0] < a[0] + a[2] and a[1] < b[1] + b[3] and b[1] < a[1] + a[3]


def problems(view, lay):
    """[(종류, 설명)] — 화살표가 상관없는 박스·묶음을 지나거나, 묶음 밖 박스가 묶음 테두리 안에 있다."""
    nodes = {n["id"]: n for n in view.get("nodes", [])}
    kids = children(view)
    name = lambda i: nodes.get(i, {}).get("title") or i
    out = []
    for bid, r in lay["boxes"].items():
        for fid, fr in lay["frames"].items():
            if nodes[bid].get("group") != fid and rects_overlap(r, fr):
                out.append(f"'{name(bid)}' 박스가 '{name(fid)}' 묶음 테두리 안에 있다 — 묶음 밖으로 옮기거나 \"group\": \"{fid}\" 를 단다")
    for i, e in enumerate(view.get("edges", [])):
        seg = lay["edges"][i]
        if not seg:
            continue
        skip = set()
        for end in (e["from"], e["to"]):
            skip.add(end)
            skip.update(kids.get(end, []))
            if nodes.get(end, {}).get("group"):
                skip.add(nodes[end]["group"])
        for oid, r in list(lay["boxes"].items()) + list(lay["frames"].items()):
            if oid not in skip and segment_hits_rect(seg, r):
                what = "묶음을" if oid in lay["frames"] else "박스를"
                out.append(f"{name(e['from'])}→{name(e['to'])} 화살표가 '{name(oid)}' {what} 지난다 — 박스를 옮겨 화살표 길을 비운다")
    return out
```

- [ ] **Step 4: 통과 확인**

Run: `bash tests/unit/test_eli5_layout.sh && /usr/bin/python3 -c "import ast; ast.parse(open('skills/eli5/bin/layout.py').read())"`
Expected: `=== 12 passed, 0 failed ===`, 파싱 오류 없음

- [ ] **Step 5: 커밋**

```bash
chmod +x tests/unit/test_eli5_layout.sh
git add skills/eli5/bin/layout.py tests/unit/test_eli5_layout.sh
git commit -m "feat(eli5): 배치 모듈 — 묶음·사각형·선분 계산과 관통 검사를 한 곳에

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 10: 검증기 — 한 장 규칙·묶음·관통 + fixture

**Files:**
- Modify: `skills/eli5/bin/plain.py` (`TITLE_MAX, SAY_MAX, LABEL_MAX = 24, 30, 18` 줄)
- Modify: `skills/eli5/bin/validate.py` (import, `integrity_errors`, `v3_errors` 끝, 새 `effective_nodes`, `missing_edges`, `main` 의 judge 루프)
- Rewrite: `tests/fixtures/eli5/model.json`
- Modify: `tests/unit/test_eli5_validate.sh`

**Interfaces:**
- Consumes: Task 9 `layout.children`, `layout.compute`, `layout.problems`, `layout.MAX_COLS`
- Produces: `effective_nodes(view) -> dict[id, node]` (묶음은 `paths` = 안쪽 박스 paths 합). 한 장 fixture (view id `L0`, 묶음 `core` = `engine` + `init`) — Task 11 이 쓴다. `missing_edges` 는 잎 박스 단위로 보고

- [ ] **Step 1: fixture 를 한 장으로 재작성**

`tests/fixtures/eli5/model.json`:

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
         "detail": "작업 번호를 받아 실행하고 결과를 에이전트에 보낸다.", "code": ["src/core/"]},
        {"id": "engine", "group": "core", "kind": "module", "title": "작업 실행기", "say": "작업을 실행하고 결과를 보낸다",
         "code": ["src/core/engine.py", "run_job"], "row": 0, "col": 1, "paths": ["src/core/engine.py"]},
        {"id": "init", "group": "core", "kind": "module", "title": "모듈 입구", "say": "엔진을 바깥에 내보인다",
         "row": 1, "col": 1, "paths": ["src/core/__init__.py"]},
        {"id": "agent", "kind": "external", "title": "에이전트 서비스", "say": "바깥에서 작업을 받아 처리한다",
         "row": 2, "col": 0, "paths": []}
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
    }
  },
  "unknowns": []
}
```

- [ ] **Step 2: 테스트 고치기·추가 (실패 상태 만들기)**

`tests/unit/test_eli5_validate.sh` 에서 두 줄 교체:

- `integrity 'm["views"]["L0"]["nodes"][1]["drill"]="ghost"' "drill 대상" "없는 drill"` → `integrity 'm["views"]["L0"]["nodes"][0]["drill"]="L0"' "drill 은 없어졌다" "drill 금지"`
- `integrity 'm["views"]["L0"]["nodes"][1]["col"]=0' "겹쳐" "격자 겹침"` → `integrity 'm["views"]["L0"]["nodes"][2].update(row=0, col=0)' "겹쳐" "격자 겹침"`

누락 탐지 기대값 줄 `'[["L0","core","api"]]'` 를 `'[["L0","engine","api"]]'` 로, 그 줄의 pass 문구 `"그림에 없는 관계 1건 (방향 구분)"` 를 `"그림에 없는 관계 1건 — 잎 박스 단위 (방향 구분)"` 로.

`integrity 'm["meta"]["glossary"]["API"]=""' "풀이가 비었다" "glossary 빈 풀이"` 줄 바로 아래에 추가:

```bash
integrity 'm["views"]["L1"]={"title":"L1 · 안쪽","hint":"안쪽","parent":"L0","rules":[],"nodes":[],"edges":[],"ifaces":[]}' "지도는 한 장" "view 둘 거부"
integrity 'm["views"]["L0"]["parent"]="L0"' "parent 는 없어졌다" "parent 금지"
integrity 'm["views"]["L0"]["nodes"][1]["col"]=1' "묶음은 자기 칸" "묶음에 칸 금지"
integrity 'm["views"]["L0"]["nodes"][3].pop("group")' "안쪽 박스가 1개" "묶음 안쪽 1개 거부"
integrity 'm["views"]["L0"]["nodes"][2]["group"]="ghost"' "group .ghost. 없음" "없는 group"
integrity 'm["views"]["L0"]["nodes"][1]["group"]="core"' "자기 자신" "group 자기 자신"
integrity 'm["views"]["L0"]["nodes"][1]["group"]="api"' "한 단계만" "묶음 안의 묶음 거부"
integrity 'm["views"]["L0"]["nodes"][4]["col"]=5' "열은 0~4" "열 5개 상한"
integrity 'm["views"]["L0"]["nodes"][4].update(row=0, col=2)' "지난다" "화살표 관통"
integrity 'm["views"]["L0"]["nodes"][4].update(row=1, col=1); m["views"]["L0"]["nodes"][3].update(row=2, col=1)' "테두리 안에" "묶음 테두리 침범"
integrity 'm["views"]["L0"]["edges"][0]["label"]="작업을 실행해 달라"' "칸, 상한 14" "edge label 14칸"
fresh; run >/dev/null; [ "$(grade '.views.L0.edges[0].grade')" = "graft" ] && pass "묶음 끝 화살표 graft 유지 (안쪽 paths 합)" || fail "묶음 graft" "$(grade '.validation.downgrades')"
```

- [ ] **Step 3: 실패 확인**

Run: `bash tests/unit/test_eli5_validate.sh`
Expected: 새 항목과 교체 항목이 ❌ — 최소 "drill 금지", "view 둘 거부", "parent 금지", "묶음에 칸 금지", "묶음 안쪽 1개 거부", "없는 group", "group 자기 자신", "묶음 안의 묶음 거부", "열 5개 상한", "화살표 관통", "묶음 테두리 침범", "edge label 14칸", "묶음 graft", 누락 탐지

- [ ] **Step 4: 구현**

`skills/eli5/bin/plain.py`: `TITLE_MAX, SAY_MAX, LABEL_MAX = 24, 30, 18` → `TITLE_MAX, SAY_MAX, LABEL_MAX = 24, 30, 14`

`skills/eli5/bin/validate.py`:

(a) `import plain  # noqa: E402` 다음 줄에 `import layout  # noqa: E402`

(b) `integrity_errors` 에서 다음 세 줄을 지운다 (한 장 규칙은 `v3_errors` 가 맡는다):

```python
        if v.get("parent") and v["parent"] not in views:
            errs.append(f"{vid}: parent '{v['parent']}' 없음")
```
```python
            if n.get("drill") and n["drill"] not in views:
                errs.append(f"{vid}/{n['id']}: drill 대상 view '{n['drill']}' 없음")
```

같은 함수에서 `cells = {}` 줄 바로 앞에 `kids = layout.children(v)` 를, `for n in v.get("nodes", []):` 다음 줄(격자 루프 첫 줄)에 묶음 건너뛰기를 넣는다:

```python
        kids = layout.children(v)
        cells = {}
        for n in v.get("nodes", []):
            if n["id"] in kids:
                continue  # 묶음은 칸이 없다 — 테두리는 안쪽 박스로 계산한다
```

(c) `v3_errors` 의 마지막 `return errs` 를 다음으로 교체:

```python
    views = model.get("views") or {}
    if len(views) != 1:
        errs.append(f"views 가 {len(views)}개 — 지도는 한 장이다. 안쪽 박스는 \"group\" 으로 묶음에 넣는다")
    for vid, v in views.items():
        if v.get("parent") is not None:
            errs.append(f"{vid}.parent 는 없어졌다 — 지도는 한 장이다 (null)")
        nodes = {n["id"]: n for n in v.get("nodes", [])}
        kids = layout.children(v)
        for n in v.get("nodes", []):
            w, g = f"{vid}/{n['id']}", n.get("group")
            if "drill" in n:
                errs.append(f"{w}.drill 은 없어졌다 — 안쪽 박스에 \"group\": \"{n['id']}\" 를 단다")
            if g is not None:
                if g == n["id"]:
                    errs.append(f"{w}.group 이 자기 자신이다 — 바깥 묶음 박스의 id 를 쓴다")
                elif g not in nodes:
                    errs.append(f"{w}.group '{g}' 없음 — 같은 지도의 박스 id 를 쓴다")
                elif nodes[g].get("group") is not None:
                    errs.append(f"{w}.group '{g}' 는 이미 묶음 안의 박스다 — 묶음은 한 단계만")
            if n["id"] in kids:
                if len(kids[n["id"]]) < 2:
                    errs.append(f"{w} 묶음의 안쪽 박스가 1개 — 2개 이상 넣거나 묶음을 풀어 보통 박스로")
                for f in ("row", "col", "span", "paths"):
                    if f in n:
                        errs.append(f"{w}.{f} — 묶음은 자기 칸·경로가 없다 (안쪽 박스로 계산한다)")
            elif n.get("col", 0) + n.get("span", 1) > layout.MAX_COLS:
                errs.append(f"{w}.col {n.get('col', 0)} — 열은 0~{layout.MAX_COLS - 1} (span 포함, 한 화면 폭)")
    if not errs:  # 구조가 맞을 때만 배치를 계산한다 — 아니면 관통 오류가 잡음이 된다
        for vid, v in views.items():
            errs += [f"{vid}: {p}" for p in layout.problems(v, layout.compute(v))]
    return errs


def effective_nodes(view):
    """묶음은 자기 paths 가 없다 — graft 판정에는 안쪽 박스 paths 의 합을 쓴다."""
    kids = layout.children(view)
    nodes = {n["id"]: n for n in view.get("nodes", [])}
    return {nid: ({**n, "paths": [p for c in kids[nid] for p in nodes[c].get("paths", [])]} if nid in kids else n)
            for nid, n in nodes.items()}
```

(d) `missing_edges` 의 view 루프 본문 앞부분을:

```python
    for vid, v in model["views"].items():
        kids = layout.children(v)
        expand = lambda i: [i, *kids.get(i, [])]  # 묶음 끝 화살표는 안쪽 박스 모두의 화살표로 친다
        drawn = {(a, b) for e in v.get("edges", []) for a in expand(e["from"]) for b in expand(e["to"])}
        leaves = [n for n in v.get("nodes", []) if n["id"] not in kids]
```

로 바꾸고(기존 `drawn = {...}` 줄 대체), 같은 루프의 두 `next(...)` 에서 `for n in v.get("nodes", [])` 를 `for n in leaves` 로.

(e) `main()` 의 judge 루프에서 `nodes = {n["id"]: n for n in v.get("nodes", [])}` 를 `nodes = effective_nodes(v)` 로.

- [ ] **Step 5: 통과 확인**

Run: `bash tests/unit/test_eli5_validate.sh && bash tests/unit/test_eli5_plain.sh && /usr/bin/python3 -c "import ast; ast.parse(open('skills/eli5/bin/validate.py').read())"`
Expected: 두 파일 `0 failed`, 파싱 오류 없음

- [ ] **Step 6: 커밋**

```bash
git add skills/eli5/bin/plain.py skills/eli5/bin/validate.py tests/fixtures/eli5/model.json tests/unit/test_eli5_validate.sh
git commit -m "feat(eli5): 한 장 지도 검증 — 묶음 규칙·열 상한·화살표 관통·묶음 graft 판정

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 11: render 가 배치를 넣고, 지도는 그리기만

**Files:**
- Modify: `skills/eli5/bin/render.py`
- Modify: `skills/eli5/assets/map.html`
- Modify: `tests/unit/test_eli5_render.sh`

**Interfaces:**
- Consumes: Task 9 `layout.compute`, Task 10 fixture
- Produces: HTML 의 `MODEL.layout` (`boxes`·`frames`·`edges`·`size`). 저장되는 `*.model.json` 에는 `layout` 이 없다. DOM: 묶음 `<g class="frame">`, 카드의 안쪽 박스 버튼 `data-sel`. `window.ELI5 = {MODEL, state, go, select}` 유지

- [ ] **Step 1: 실패 테스트 추가**

`tests/unit/test_eli5_render.sh` — `finish` 바로 위에:

```bash
python3 - "$H" "$M" <<'PY' && pass "payload 에 배치(layout), 저장 모델에는 없음" || fail "payload layout"
import json, re, sys
h = open(sys.argv[1], encoding="utf-8").read()
model = json.loads(re.search(r"const MODEL = (.*?);\n\(function", h, re.S).group(1))
L = model["layout"]
assert set(L["boxes"]) == {"api", "engine", "init", "agent"} and set(L["frames"]) == {"core"}, L
assert len(L["edges"]) == 3 and L["size"][0] > 0
assert "layout" not in json.load(open(sys.argv[2], encoding="utf-8"))
PY
! grep -q '안으로' "$TPL" && ! grep -q 'data-go' "$TPL" && pass "층 이동 UI 없음" || fail "층 이동 UI 잔존"
grep -q 'MODEL.layout' "$TPL" && grep -q 'class: "frame' "$TPL" && grep -q 'data-sel' "$TPL" && ! grep -q 'function box(' "$TPL" \
  && pass "지도는 MODEL.layout 으로 그리고 묶음·안쪽 박스 버튼이 있다" || fail "layout 그리기"
```

- [ ] **Step 2: 실패 확인**

Run: `bash tests/unit/test_eli5_render.sh`
Expected: 위 3개 ❌

- [ ] **Step 3: render.py**

`import tempfile` 다음 줄에 넣고, `TEMPLATE = ...` 아래에서 layout 을 import 한다:

```python
sys.path.insert(0, str(Path(__file__).resolve().parent))
import layout  # noqa: E402
```

(`from pathlib import Path` 보다 아래에 와야 한다 — `TEMPLATE = ...` 줄 바로 다음에 둔다.)

payload 줄을:

```python
    # 배치는 그릴 때만 필요하다 — 저장 모델에는 넣지 않고 HTML payload 에만 싣는다
    shown = {**model, "layout": layout.compute(next(iter(model["views"].values())))}
    # 데이터 안의 문자열이 script 블록을 닫거나(</) HTML 주석을 열지(<!--) 못하게 한다. 둘 다 JS 문자열 이스케이프라 값은 그대로다.
    payload = json.dumps(shown, ensure_ascii=False).replace("</", "<\\/").replace("<!--", "<\\u0021--")
```

(기존 주석 한 줄과 payload 줄을 위 세 줄+주석으로 대체)

- [ ] **Step 4: map.html**

(a) CSS — 다음을 바꾼다:
- `main{max-width:1320px;margin:0 auto;padding:16px}` → `main{max-width:1600px;margin:0 auto;padding:16px}`
- `.node.drill rect.bg{stroke:var(--fg);stroke-width:2.5}` 줄과 `.node .go{fill:var(--accent);font-size:11px}` 줄 삭제
- `.diagram{...}` 줄 아래에 추가:

```css
#svg{display:block;max-width:100%;height:auto}
.frame{cursor:pointer}
.frame .fbg{fill:var(--bg);stroke:var(--line);stroke-width:1.5}
.frame.sel .fbg{stroke:var(--accent);stroke-width:2.5}
.frame .title{font-weight:600;font-size:13px}
.frame .sub{fill:var(--muted);font-size:11px}
```

(b) JS 상수줄 `const W = 200, H = 72, GX = 90, GY = 60, PAD = 30, NS = "http://www.w3.org/2000/svg";` 와 다음 줄 `let gx = GX;  // …` 를:

```js
  const NS = "http://www.w3.org/2000/svg";
```

로. `const rootView = …` 줄 다음에:

```js
  // 배치는 render.py 가 layout.py 로 계산해 넣는다 — 여기서는 그리기만 한다 (검증기의 관통 검사와 같은 숫자)
  const V = views[rootView], LAY = MODEL.layout || {boxes: {}, frames: {}, edges: [], size: [0, 0]};
  const NODE = Object.fromEntries((V.nodes || []).map(n => [n.id, n]));
  const KIDS = {};
  for (const n of V.nodes || []) if (n.group && NODE[n.group]) (KIDS[n.group] = KIDS[n.group] || []).push(n.id);
  const rel = id => id ? new Set([id, ...(KIDS[id] || []), ...(NODE[id] && NODE[id].group ? [NODE[id].group] : [])]) : null;
```

(c) `function box(n) {…}` 와 `function clip(b, tx, ty) {…}` 두 함수를 통째로 지운다.

(d) `function draw() {…}` 전체를:

```js
  function draw() {
    const svg = $("svg"), [sw, sh] = LAY.size;
    svg.innerHTML = "";
    svg.setAttribute("viewBox", `0 0 ${sw} ${sh}`);
    svg.setAttribute("width", sw);
    svg.setAttribute("height", sh);
    const defs = el("defs", {}, svg);
    for (const g of Object.keys(GRADE)) {
      const m = el("marker", {id: "ah-" + g, viewBox: "0 0 10 10", refX: "9", refY: "5", markerWidth: "7", markerHeight: "7", orient: "auto-start-reverse"}, defs);
      el("path", {d: "M0,0 L10,5 L0,10 z", class: "g-" + g, style: "fill:currentColor;stroke:none;stroke-dasharray:none"}, m);
    }
    for (const [fid, r] of Object.entries(LAY.frames)) {
      const n = NODE[fid], g = el("g", {class: "frame" + (state.node === fid ? " sel" : "")}, svg);
      el("rect", {x: r[0], y: r[1], width: r[2], height: r[3], rx: 10, class: "fbg"}, g);
      el("circle", {cx: r[0] + 16, cy: r[1] + 17, r: 5, class: "k-" + (n.kind || "module")}, g);
      el("text", {x: r[0] + 28, y: r[1] + 22, class: "title"}, g).textContent = n.title;
      el("text", {x: r[0] + 14, y: r[1] + 38, class: "sub"}, g).textContent = n.say || "";
      el("title", {}, g).textContent = (KIND[n.kind] || "") + " 묶음 — 빈 곳을 누르면 설명";
      g.addEventListener("click", () => select(state.node === fid ? null : fid));
    }
    const R = rel(state.node);
    (V.edges || []).forEach((e, i) => {
      const s = LAY.edges[i];
      if (!s) return;
      const [x1, y1, x2, y2] = s, g2 = shown(e);
      const g = el("g", {class: "edge" + (R && !R.has(e.from) && !R.has(e.to) ? " dim" : "")}, svg);
      el("path", {d: `M${x1},${y1} L${x2},${y2}`, class: "g-" + g2, "marker-end": `url(#ah-${g2})`}, g);
      if (e.label) {
        const t = el("text", {x: (x1 + x2) / 2, y: (y1 + y2) / 2 - 4, "text-anchor": "middle", class: "g-" + g2}, g);
        t.textContent = e.label;
        try { const bb = t.getBBox(); g.insertBefore(el("rect", {x: bb.x - 3, y: bb.y - 1, width: bb.width + 6, height: bb.height + 2, class: "lbl-bg"}), t); } catch (_) {}
      }
      el("title", {}, g).textContent = GRADE[e.grade] + (evText(e.evidence) ? " — " + evText(e.evidence) : "");
      if (e.iface) { g.style.cursor = "pointer"; g.addEventListener("click", () => flash(state.view, e.iface)); }
    });
    for (const n of V.nodes || []) {
      const B = LAY.boxes[n.id];
      if (!B) continue;
      const g = el("g", {class: "node" + (state.node === n.id ? " sel" : "")}, svg);
      el("rect", {x: B[0], y: B[1], width: B[2], height: B[3], rx: 6, class: "bg"}, g);
      el("rect", {x: B[0] + 1, y: B[1] + 1, width: 5, height: B[3] - 2, rx: 2, class: "k-" + (n.kind || "module")}, g);
      el("text", {x: B[0] + 16, y: B[1] + 27, class: "title"}, g).textContent = n.title;
      el("text", {x: B[0] + 16, y: B[1] + 47, class: "sub"}, g).textContent = n.say || "";
      const terms = termsIn(n.title, n.say);
      el("title", {}, g).textContent = (KIND[n.kind] || "") + terms.map(t => `\n${t}: ${gloss[t]}`).join("");
      g.addEventListener("click", () => select(state.node === n.id ? null : n.id));
    }
  }
```

(e) `side()` 에서:
- `const v = views[state.view], n = state.node && (v.nodes || []).find(x => x.id === state.node);` 바로 다음 줄에 `const mine = n ? new Set([n.id, ...(KIDS[n.id] || [])]) : null;` 추가
- conns 필터 `(v.edges || []).filter(e => e.from === n.id || e.to === n.id)` → `(v.edges || []).filter(e => mine.has(e.from) || mine.has(e.to))`, 같은 map 안의 `const out = e.from === n.id, other = nodeTitle(state.view, out ? e.to : e.from);` → `const out = mine.has(e.from), other = nodeTitle(state.view, out ? e.to : e.from);`
- ifs 필터 `(v.ifaces || []).filter(f => f.from === n.id || f.to === n.id)` → `(v.ifaces || []).filter(f => mine.has(f.from) || mine.has(f.to))`
- innerHTML 의 `${n.drill ? `<p><button class="link" type="button" data-go="${esc(n.drill)}">안으로 들어가기 ▸</button></p>` : ""}` 를 다음으로 교체:

```js
      ${KIDS[n.id] ? `<h3>안쪽 박스</h3>${KIDS[n.id].map(c => `<div class="conn"><button class="link" type="button" data-sel="${esc(c)}">${esc(NODE[c].title)}</button> — ${esc(NODE[c].say || "")}</div>`).join("")}` : ""}
```

(f) 카드 클릭 처리 `const t = ev.target.closest && ev.target.closest("[data-copy],[data-go],[data-close]");` → `"[data-copy],[data-sel],[data-close]"`, 그 아래 `if (t.dataset.go) return go(t.dataset.go);` → `if (t.dataset.sel) return select(t.dataset.sel);`

(g) `function draw()` 위에서 `gx` 를 쓰던 곳이 없는지 확인: `grep -n 'gx\|box(\|clip(' skills/eli5/assets/map.html` 결과 없음.

- [ ] **Step 5: 통과 확인**

Run: `bash tests/unit/test_eli5_render.sh && grep -n 'gx\|box(\|clip(\|n.drill' skills/eli5/assets/map.html; /usr/bin/python3 -c "import ast; ast.parse(open('skills/eli5/bin/render.py').read())"`
Expected: `0 failed`, grep 결과 없음, 파싱 오류 없음

- [ ] **Step 6: 브라우저 확인**

Task 5 Step 5 와 같은 방법(fixture 를 validate·render 후 `python3 -m http.server 8799 --bind 127.0.0.1`)으로 열어 확인:
1. `작업 엔진` 묶음 테두리 안에 `작업 실행기`·`모듈 입구`, 묶음 머리에 색 점·이름·한 줄
2. `요청 받는 곳 → 작업 엔진` 화살표가 묶음 테두리에 닿는다
3. 묶음 빈 곳 클릭 → 카드에 "안쪽 박스" 두 버튼, 버튼 클릭 → 그 박스 카드. 그 박스 선택 시 묶음 끝 화살표(작업 실행·작업 전달)는 흐려지지 않는다
4. "안으로" 글자·경로 이동 없음
5. 800px iframe 에서 지도가 폭에 맞게 줄어든다 (가로 스크롤 없음)
결함은 고치고 Step 5 부터. 끝나면 서버를 끈다.

- [ ] **Step 7: 커밋**

```bash
git add skills/eli5/bin/render.py skills/eli5/assets/map.html tests/unit/test_eli5_render.sh
git commit -m "feat(eli5): 한 장 지도 그리기 — 배치는 render 가 넣고, 묶음 테두리·안쪽 박스 카드

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 12: 절차·안내 문서와 테스트 배선

**Files:**
- Modify: `skills/eli5/SKILL.md`, `commands/help.md`, `README.md`, `CHANGELOG.md`, `lint.sh`, `test.sh`

**Interfaces:**
- Consumes: Task 9~11 규칙
- Produces: 에이전트가 따를 한 장 지도 작성 규칙

- [ ] **Step 1: 낡은 서술 확인 (실패 상태)**

Run: `grep -n 'drill\|드릴다운\|하위 view\|L1\b\|5~9' skills/eli5/SKILL.md commands/help.md README.md`
Expected: 여러 줄

- [ ] **Step 2: SKILL.md 고치기**

- frontmatter `description` 의 `드릴다운 HTML 지도` → `한 장 HTML 지도(안쪽이 있는 박스는 묶음으로 펼침)`
- Phase 2 모델 예시의 `"nodes": [...]` 를:

```json
      "nodes": [{"id": "api", "kind": "service", "title": "요청 받는 곳", "say": "<묶음 머리 한 줄>"},
                {"id": "route", "group": "api", "kind": "module", "title": "요청 입구", "say": "<박스에 그리는 한 줄>",
                 "detail": "<카드에만 — 2~3문장>", "code": ["src/api/routes.py", "handle"],
                 "row": 0, "col": 1, "span": 1, "paths": ["src/api/routes.py"]}],
```

  로, 예시의 `"title": "L0 · <쉬운 말>", "hint": "<이 층을 한 문장으로>", "parent": null,` 는 `"title": "<지도 이름>", "hint": "<지도를 한 문장으로>", "parent": null,` 로
- "사람이 읽는 칸" 표의 edge `label` 행 `쉬운 말, 18칸 이하` → `쉬운 말, 14칸 이하`
- "작성 규칙" 첫 항목(`- 레이어: L0 = …`)을 다음 네 항목으로 교체:

```markdown
- **지도는 한 장이다.** `views` 에는 view 하나, `parent` 는 `null`, `drill` 은 쓰지 않는다. 바깥에서 본 단위(프로세스·저장소·외부 시스템)를 박스로 두고, 안쪽을 보여 줄 박스는 **묶음**으로 펼친다 — 안쪽 박스에 `"group": "<바깥 박스 id>"` 를 단다
- 묶음은 자기 `row`·`col`·`paths` 를 쓰지 않는다 (안쪽 박스로 계산). 안쪽 박스 2개 이상, 묶음 안의 묶음 금지. 바깥 박스를 가리키려고 안쪽에 대역 박스를 다시 그리지 않는다 — 화살표를 진짜 박스로 잇는다
- 열은 0~4 (한 화면 폭). 흐름 순서대로 왼→오, 위→아래. 같은 칸 금지
- **화살표는 직선이고, 다른 박스·묶음을 지나면 검증기가 거부한다.** 오류가 "어느 박스를 지나는지" 말해 준다. 멀리 되돌아가는 화살표(보고·콜백)는 가장자리 열이나 빈 행으로 길을 비운다. 묶음 밖 박스를 묶음 테두리 안에 두지 않는다
```

- Phase 3 의 exit 1 설명 아래에 한 줄 추가: `  - 관통·테두리 오류는 박스 칸(row·col)을 옮긴다. 화살표를 지워서 피하지 않는다 — 지운 관계는 "그림에 없는 관계" 로 다시 나온다`
- `## open` 절의 마지막 문단 `v2 모델(\`meta.version\` 없음)은 …` 다음에 한 줄: `층이 여러 개인 v3 초기 지도(views 2개 이상·drill)도 검증기가 거부한다 — 안쪽 층을 묶음으로 옮겨 다시 만든다.`

- [ ] **Step 3: help·README·CHANGELOG·배선**

- `commands/help.md` eli5 블록의 `코드베이스·시스템 구조를 드릴다운 HTML 지도로 그린다.` → `코드베이스·시스템 구조를 한 장 HTML 지도로 그린다. 안쪽이 있는 박스는 묶음 테두리로 펼쳐 모든 흐름을 한 화면에.`
- `README.md` 의 `| \`eli5\` | 코드를 안 읽는 사람도 읽는 드릴다운 HTML 지도` → `| \`eli5\` | 코드를 안 읽는 사람도 읽는 한 장 HTML 지도`
- `CHANGELOG.md` 의 eli5 v3 항목 끝 `(1단계 — 시나리오·커버리지·작업 진행 표시는 다음 단계)` 앞에 문장 추가: `실측 지도를 본 사용자가 "안으로 들어가면 전체 흐름이 안 보인다" 고 해서 층(drill)을 없앴다 — 지도는 한 장이고 안쪽이 있는 박스는 묶음 테두리로 그 자리에서 펼친다. 배치는 \`layout.py\` 한 곳에서 계산해 그림과 검증이 같은 숫자를 쓰고, 화살표가 다른 박스·묶음을 지나면 검증기가 어느 박스인지 알려 주며 거부한다(archify \`segmentIntersectsRect\` 방식). `
- `lint.sh`: `for t in prep plain validate render open; do` → `for t in prep plain layout validate render open; do`
- `test.sh` `test_eli5` 의 `for t in prep plain validate render open; do` → `for t in prep plain layout validate render open; do`

- [ ] **Step 4: 확인**

Run: `grep -n 'drill\|드릴다운\|하위 view' skills/eli5/SKILL.md commands/help.md README.md; ./lint.sh 2>&1 | tail -2; ./test.sh eli5 2>&1 | tail -1`
Expected: grep 은 SKILL.md 의 "`drill` 은 쓰지 않는다"·"drill" 거부 안내 줄만, lint·test 통과

- [ ] **Step 5: 커밋**

```bash
git add skills/eli5/SKILL.md commands/help.md README.md CHANGELOG.md lint.sh test.sh
git commit -m "docs(eli5): 한 장 지도 작성 규칙 — 묶음·5열·관통 금지

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 13: 실측 — 업무 지도를 한 장으로 다시 만들고 사용자 판정

**Files:** 대상 레포 `.eli5/` 출력물만 (추적 파일 무변경)

**Interfaces:**
- Consumes: Task 9~12 전체, 현재 v3 모델(층 3개) `agent-production-profitability/.eli5/one-turn-request-flow.model.json`
- Produces: 한 장 지도, 판정 기록, 배치 재시도 횟수

- [ ] **Step 1: 보존**

```bash
R=/Users/raki-1203/workspace/KT/agent-production-profitability
cp $R/.eli5/one-turn-request-flow.model.json /tmp/eli5-v3-layers.model.json
git -C $R status --short > /tmp/eli5-v3b-before.txt
```

- [ ] **Step 2: 한 장 모델로 옮기기**

`/tmp/eli5-v3-layers.model.json` 에서 시작해 SKILL.md 의 작성 규칙대로 새 모델을 쓴다:
- 묶음 `api`(요청 받는 곳) = L1-api 의 route·stream·settle·prepare·tools·sse, 묶음 `graph`(대화 단계 진행기) = L1-graph 의 orch·parse·others·clarify·confirm·simulate·attach·report. 대역 박스(L1-api 의 guard·graph, L1-graph 의 jobs)는 버린다
- 잎 박스: bff·guard·llm·jobs·mart·pg·s3
- 같은 관계가 두 층에 있으면(api→guard 와 prepare→guard, api→graph 와 stream→graph, graph→jobs 와 simulate→jobs) **안쪽 박스 쪽**을 남기고 바깥 쪽과 그 iface 를 지운다. 근거(evidence)는 옮기지 않고 남긴 화살표 것을 쓴다. bff→api 는 bff→route 로 (근거 `aimate.py:336` 은 route 의 것)
- 규칙(rules) 7개는 한 view 로 모은다
- 라벨 14칸 초과는 줄인다
- 배치는 흐름 순서로 직접 놓고, `validate.py` 의 관통 오류를 따라 옮긴다. **validate 실행 횟수를 센다**

- [ ] **Step 3: 검증·렌더**

```bash
SK=/Users/raki-1203/workspace/raki-claude-plugins/skills/eli5
python3 $SK/bin/validate.py $R/.eli5/one-turn-request-flow.model.json --root $R --graft-status ok
python3 $SK/bin/render.py $R/.eli5/one-turn-request-flow.model.json --root $R
```

Expected: 강등 0 (근거는 v3 층 모델과 같다), integrity 오류 0

- [ ] **Step 4: 대상 레포 무변경**

`git -C $R status --short | diff /tmp/eli5-v3b-before.txt -` → 차이 없음

- [ ] **Step 5: 사용자 판정**

`python3 $SK/bin/open.py open $R/.eli5/one-turn-request-flow.html` 로 연다. 보고: 박스 수, validate 재시도 횟수, 관통 때문에 옮긴 박스. 묻는다: "한 장에 모든 흐름이 한눈에 들어오나요?" — 판정 전에는 완료로 보고하지 않는다.
