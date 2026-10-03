# eli5 2단계 — 시나리오 따라가기 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 지도를 열면 "무슨 일이 어떤 순서로 일어나는가" 가 먼저 보이게 한다 — 대표 흐름(시나리오)이 선택된 채로 열리고, 지나는 박스에 ①②③, 오른쪽 카드에 단계 설명이 나온다.

**Architecture:** 시나리오는 모델의 `scenarios[]` 에 에이전트가 쓴다. `validate.py` 가 각 단계가 지도 위 실제 화살표로 이어지는지(지나온 박스 중 하나에서 나오는 화살표) 검사하고, 단계마다 쓰인 화살표와 근거 등급을 `validation.scenarios` 에 기록한다. `map.html` 은 그 기록만 써서 번호·강조·카드를 그린다 — 화면이 판정을 다시 하지 않는다.

**Tech Stack:** Python 3 표준 라이브러리(시스템 3.9 파싱 가능), 바닐라 JS/SVG, bash 단위 테스트, `jq`.

**Spec:** `docs/superpowers/specs/2026-10-02-eli5-v3-readable-map-design.md` — 2.5절 (2.1~2.4 를 대체하는 부분은 2.5 가 우선)

## Global Constraints

- 브랜치 `feat/eli5-scenarios` (main `9b6342e` 에서). push·merge 범위 밖
- 시나리오 1~4개, 단계 2~7개. 단계 `box` 는 박스 또는 묶음
- 잇기: 단계 i(≥1) 박스로 가는 화살표가 지금까지 지나온 단계 박스(최근 우선) 중 하나에서 나와야 한다. 끝 판정은 `_ends(i) = {i} ∪ 안쪽 박스(묶음이면) ∪ 바깥 묶음(안쪽 박스면)`
- 쉬운 말 검사: 시나리오 `title`(≤24)·`summary`, 단계 `title`(≤24)·`body`(`{{id}}` 토큰은 빼고 검사)·`substeps[].label`(≤14)
- 단계 근거 실패는 exit 1 이 아니라 그 단계 등급 `unknown`
- 시나리오 검사는 다른 무결성 오류가 없을 때만 돈다
- 오류 문자열 `<위치> … — <고칠 방법>`
- 커밋 conventional + `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`

## Review Focus

1. **같은 박스를 두 번 지나는 시나리오** — 기대: 배지에 "2·5" 처럼 두 번호 → Task 2 브라우저 확인 6
2. **첫 단계가 묶음, 다음 단계가 그 안쪽 박스** — 기대: 화살표가 없어 잇기 실패로 보고 (묶음과 안쪽은 화살표가 아니다) → Task 1 테스트 "묶음→자기 안쪽 단계는 화살표 아님"
3. **본문에 HTML 특수문자** — 기대: 글자 그대로, `{{id}}` 만 버튼 → Task 2 테스트 "본문 이스케이프"
4. **시나리오가 없는 지도** — 기대: 1단계 화면 그대로 (버튼 줄 없음, 카드 닫힘) → Task 2 테스트 "시나리오 없는 지도"
5. **`#scenario=none` 주소** — 기대: 구조도만 → Task 2 브라우저 확인 5

---

### Task 1: 검증기 — 시나리오 잇기·쉬운 말·근거 기록

**Files:**
- Modify: `skills/eli5/bin/validate.py` (새 함수 4개를 `def under(path, prefixes):` 바로 위에, `main()` 두 곳)
- Modify: `tests/fixtures/eli5/model.json` (`"unknowns": []` 앞에 `scenarios`)
- Modify: `tests/unit/test_eli5_validate.sh`

**Interfaces:**
- Consumes: `layout.children`, `plain.check_plain`, `plain.TITLE_MAX`, `plain.LABEL_MAX`, `check_code`
- Produces: `TOKEN_RE`, `scenario_links(view, steps) -> list[int | None]`, `scenario_errors(model) -> list[str]`, `scenario_report(model, root, quick) -> {sid: [{"edge": int | None, "grade": str | None}]}`. 리포트 키 `validation.scenarios` (Task 2 가 씀). fixture 시나리오 `run` (api → engine → agent)

- [ ] **Step 1: fixture 에 시나리오 추가**

`tests/fixtures/eli5/model.json` 의 `  "unknowns": []` 줄 바로 앞에:

```json
  "scenarios": [
    {"id": "run", "title": "요청이 들어오면", "summary": "요청이 엔진을 거쳐 에이전트까지 간다.",
     "steps": [
       {"box": "api", "title": "요청 접수", "body": "들어온 요청을 {{core}} 로 넘긴다."},
       {"box": "engine", "title": "작업 실행", "body": "작업 하나를 실행한다.",
        "substeps": [{"label": "번호 확인"}, {"label": "실행"}]},
       {"box": "agent", "title": "에이전트에 전달", "body": "결과를 에이전트에 보낸다.",
        "evidence": [{"ref": "src/core/engine.py:5", "quote": "requests.post"}]}
     ]}
  ],
```

- [ ] **Step 2: 실패 테스트**

`tests/unit/test_eli5_validate.sh` 의 `echo "🔧 누락 탐지"` 줄 바로 앞에:

```bash
echo "🔧 시나리오"
fresh; out=$(run)
[ "$(echo "$out" | jq -c '.scenarios.run')" = '[{"edge":null,"grade":null},{"edge":0,"grade":"graft"},{"edge":1,"grade":"code"}]' ] \
  && pass "단계별 화살표·등급 기록 (묶음 끝 화살표를 안쪽 박스에 적용)" || fail "시나리오 기록" "$(echo "$out" | jq -c .scenarios)"
fresh; edit 'm["scenarios"][0]["steps"][2]["evidence"][0]["quote"]="requests.get("'
out=$(run); [ "$(echo "$out" | jq -r '.scenarios.run[2].grade')" = "unknown" ] && pass "단계 근거가 틀리면 그 단계 unknown (exit 0)" || fail "단계 근거" "$out"
integrity 'm["scenarios"][0]["steps"][1]["box"]="ghost"' "박스 .ghost. 없음" "없는 박스"
integrity 'm["scenarios"][0]["steps"].reverse()' "반대 방향" "반대 방향만 있음"
integrity 'm["scenarios"][0]["steps"][0]["body"]="{{ghost}} 로 넘긴다"' "{{ghost}}" "없는 박스 토큰"
integrity 'm["scenarios"][0]["steps"]=m["scenarios"][0]["steps"]*3' "단계가 9개" "단계 8개 이상"
integrity 'm["scenarios"].append(dict(m["scenarios"][0]))' "겹친다" "시나리오 id 중복"
integrity 'm["scenarios"][0]["steps"][1]["body"]="run_job 을 부른다"' "run_job" "본문 코드 이름"
integrity 'm["scenarios"][0]["steps"][1]["substeps"][0]["label"]="작업 번호를 확인한다"' "상한 14" "하위 단계 길이"
integrity 'm["scenarios"]=[]' "1~4개" "시나리오 0개"
integrity 'm["scenarios"][0]["steps"]=[{"box":"core","title":"엔진","body":"엔진"},{"box":"engine","title":"실행기","body":"실행"}]' "가는 화살표가 없다" "묶음→자기 안쪽 단계는 화살표 아님"
fresh; edit 'm["scenarios"][0]["steps"].insert(2, {"box":"init","title":"입구","body":"입구"}); m["scenarios"][0]["steps"][3]["box"]="agent"'
out=$(run); [ $? -eq 0 ] && [ "$(echo "$out" | jq -r '.scenarios.run[3].edge')" = "1" ] && pass "지나온 박스 중 하나에서 이어지면 통과 (나무 모양)" || fail "나무 모양 잇기" "$out"
fresh; edit 'del m["scenarios"]'; run >/dev/null; [ $? -eq 0 ] && pass "시나리오 없는 모델 통과" || fail "시나리오 없음"
```

(`run` 이 `init` 로 갈 화살표: `api→core` 의 끝 `core` 는 `init` 의 묶음 → 통과. 그다음 `agent` 는 `engine`·`init` 의 묶음 `core→agent` 로 통과)

- [ ] **Step 3: 실패 확인**

Run: `bash tests/unit/test_eli5_validate.sh`
Expected: 시나리오 절 항목 ❌ (`.scenarios` 가 null · 무결성 rc=0), 나머지 ✅

- [ ] **Step 4: 구현**

`skills/eli5/bin/validate.py` — `def under(path, prefixes):` 바로 위에:

```python
TOKEN_RE = re.compile(r"\{\{([^{}]+)\}\}")


def _ends(i, nodes, kids):
    """박스 i 에 닿는 화살표 끝 — 자기, 안쪽 박스(묶음이면), 바깥 묶음(안쪽 박스면)."""
    n = nodes.get(i, {})
    return {i, *kids.get(i, []), *([n["group"]] if n.get("group") else [])}


def scenario_links(view, steps):
    """단계마다 쓰인 화살표 번호 — 지금까지 지나온 박스(최근 우선)에서 나오는 화살표. 첫 단계·못 찾으면 None."""
    nodes = {n["id"]: n for n in view.get("nodes", [])}
    kids = layout.children(view)
    edges = view.get("edges", [])
    out, seen = [], []
    for st in steps:
        hit = None
        for prev in reversed(seen):
            hit = next((i for i, e in enumerate(edges)
                        if e["from"] in _ends(prev, nodes, kids) and e["to"] in _ends(st.get("box"), nodes, kids)), None)
            if hit is not None:
                break
        out.append(hit)
        seen.append(st.get("box"))
    return out


def scenario_errors(model):
    """시나리오 — 단계는 지도 위 실제 화살표를 따라가야 한다 (archify mainPath 방식을 나무 모양으로 넓힘)."""
    scs = model.get("scenarios")
    if scs is None:
        return []
    if not isinstance(scs, list) or not 1 <= len(scs) <= 4:
        return ["scenarios 는 1~4개 — 지도에서 가장 중요한 흐름만 고른다"]
    g = (model.get("meta") or {}).get("glossary") or {}
    view = next(iter(model["views"].values()))
    nodes = {n["id"]: n for n in view.get("nodes", [])}
    kids = layout.children(view)
    errs, ids = [], set()
    for sc in scs:
        sid = sc.get("id")
        w = f"scenarios[{sid}]"
        if not sid or sid in ids:
            errs.append(f"{w}: id 가 비었거나 겹친다 — 시나리오마다 다른 영문 id")
        ids.add(sid)
        for f, limit in (("title", plain.TITLE_MAX), ("summary", None)):
            t = sc.get(f)
            if not isinstance(t, str) or not t.strip():
                errs.append(f"{w}.{f} 가 비었다 — 쉬운 말로 쓴다")
            else:
                errs += plain.check_plain(f"{w}.{f}", t, g, limit)
        steps = sc.get("steps") or []
        if not 2 <= len(steps) <= 7:
            errs.append(f"{w}: 단계가 {len(steps)}개 — 2~7개로 묶는다 (비개발자가 이해할 단위)")
            continue
        missing = False
        for k, st in enumerate(steps):
            ws = f"{w}.steps[{k}]"
            if st.get("box") not in nodes:
                errs.append(f"{ws}: 박스 '{st.get('box')}' 없음 — 있는 id: {', '.join(sorted(nodes))}")
                missing = True
            for f, limit in (("title", plain.TITLE_MAX), ("body", None)):
                t = st.get(f)
                if not isinstance(t, str) or not t.strip():
                    errs.append(f"{ws}.{f} 가 비었다 — 쉬운 말로 쓴다")
                else:
                    errs += plain.check_plain(f"{ws}.{f}", TOKEN_RE.sub("", t), g, limit)
            for j, sub in enumerate(st.get("substeps") or []):
                errs += plain.check_plain(f"{ws}.substeps[{j}]", sub.get("label") or "", g, plain.LABEL_MAX)
            for tok in TOKEN_RE.findall(st.get("body") or ""):
                if tok not in nodes:
                    errs.append(f"{ws}.body 의 {{{{{tok}}}}} — 있는 박스 id 를 쓴다")
        if missing:
            continue
        links = scenario_links(view, steps)
        for k in range(1, len(steps)):
            if links[k] is None:
                a, b = steps[k - 1]["box"], steps[k]["box"]
                rev = any(e["from"] in _ends(b, nodes, kids) and e["to"] in _ends(a, nodes, kids) for e in view.get("edges", []))
                how = f"반대 방향({b}→{a})만 있다. 순서를 바꾸거나 지도를 고친다" if rev else "지나온 박스에서 오는 화살표를 지도에 그리거나 단계를 고친다"
                errs.append(f"{w}.steps[{k}]: 지나온 박스에서 '{b}' 로 가는 화살표가 없다 — {how}")
    return errs


def scenario_report(model, root, quick):
    """{시나리오 id: [{"edge": 번호|None, "grade": 등급|None}]} — 화살표 등급을 물려받고, 단계 근거가 틀리면 unknown."""
    view = next(iter(model["views"].values()))
    edges = view.get("edges", [])
    out = {}
    for sc in model.get("scenarios") or []:
        rows = []
        for st, hit in zip(sc["steps"], scenario_links(view, sc["steps"])):
            grade = edges[hit]["grade"] if hit is not None else None
            for ev in st.get("evidence") or []:
                ok, _ = check_code(ev, root, quick)
                if not ok:
                    grade = "unknown"
                elif grade is None:
                    grade = "code"
            rows.append({"edge": hit, "grade": grade})
        out[sc["id"]] = rows
    return out
```

`main()`:
- `    errs = integrity_errors(model) + v3_errors(model)` 다음 줄에:

```python
    if not errs:  # 시나리오는 지도가 맞을 때만 판정한다
        errs = scenario_errors(model)
```

- `report = {...}` 의 마지막 `"graft": a.graft_status, "quick": a.quick}` 를 `"graft": a.graft_status, "quick": a.quick, "scenarios": scenario_report(model, root, a.quick)}` 로 (판정 루프가 화살표 등급을 확정한 뒤라 강등이 반영된다)

- [ ] **Step 5: 통과 확인**

Run: `bash tests/unit/test_eli5_validate.sh && bash tests/unit/test_eli5_render.sh && /usr/bin/python3 -c "import ast; ast.parse(open('skills/eli5/bin/validate.py').read())"`
Expected: 둘 다 `0 failed`, 파싱 오류 없음

- [ ] **Step 6: 커밋**

```bash
git add skills/eli5/bin/validate.py tests/fixtures/eli5/model.json tests/unit/test_eli5_validate.sh
git commit -m "feat(eli5): 시나리오 검증 — 지나온 박스에서 잇기, 쉬운 말, 단계별 근거 기록

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: 지도 — 시나리오 먼저 열기

**Files:**
- Modify: `skills/eli5/assets/map.html`
- Modify: `tests/unit/test_eli5_render.sh`

**Interfaces:**
- Consumes: `MODEL.scenarios`, `MODEL.validation.scenarios` (Task 1)
- Produces: `window.ELI5 = {MODEL, state, go, select, play}`, `state.sc`·`state.step`, 주소 `#scenario=<id>&step=<n>` / `#scenario=none`

- [ ] **Step 1: 실패 테스트**

`tests/unit/test_eli5_render.sh`:
- `grep -q 'window.ELI5 = {MODEL, state, go, select}' "$H"` 를 `grep -q 'window.ELI5 = {MODEL, state, go, select, play}' "$H"` 로 (같은 줄의 pass/fail 문구는 그대로)
- `finish` 바로 위에:

```bash
grep -q 'id="scbar"' "$TPL" && grep -q 'data-step' "$TPL" && grep -q 'data-back' "$TPL" && grep -q '#scenario=' "$TPL" && grep -q 'class: "badge"' "$TPL" \
  && pass "시나리오 UI — 버튼 줄·단계 이동·시나리오로 돌아가기·주소·번호 배지" || fail "시나리오 UI"
python3 - "$H" <<'PY' && pass "payload 에 시나리오 기록" || fail "payload 시나리오"
import json, re, sys
h = open(sys.argv[1], encoding="utf-8").read()
m = json.loads(re.search(r"const MODEL = (.*?);\n\(function", h, re.S).group(1))
assert m["scenarios"][0]["id"] == "run" and len(m["validation"]["scenarios"]["run"]) == 3
PY
if command -v node >/dev/null 2>&1; then
  BODY=$(grep -o 'const stepBody = .*;$' "$TPL"); ESC=$(grep -o 'const esc = .*;$' "$TPL")
  out=$(node -e "const NODE={core:{title:'작업 <엔진>'}}; $ESC; $BODY; console.log(stepBody('<b>x</b> {{core}} {{ghost}}'))")
  echo "$out" | grep -q '&lt;b&gt;x&lt;/b&gt;' && echo "$out" | grep -q 'data-sel="core">작업 &lt;엔진&gt;</button>' && echo "$out" | grep -q '{{ghost}}' \
    && pass "본문 이스케이프 — {{id}} 만 박스 버튼" || fail "본문 이스케이프" "$out"
fi
```

- [ ] **Step 2: 실패 확인**

Run: `bash tests/unit/test_eli5_render.sh`
Expected: window.ELI5 · 시나리오 UI · 본문 이스케이프 ❌ (payload 시나리오는 Task 1 로 이미 ✅)

- [ ] **Step 3: 구현 — CSS**

`.frame.sel .fbg{…}` 줄 다음에:

```css
.frame.cur .fbg{stroke:var(--accent);stroke-width:3}
.scbar{margin:10px 0 0;display:flex;flex-wrap:wrap;gap:6px;align-items:center;font-size:13px;color:var(--muted)}
.scbar button{border:1px solid var(--line);background:var(--box);color:var(--fg);border-radius:14px;padding:3px 12px;cursor:pointer;font:inherit}
.scbar button.on{border-color:var(--accent);color:var(--accent);font-weight:600}
.edge.path path{stroke:var(--accent);stroke-width:3;stroke-dasharray:none}
.edge.path text{fill:var(--accent);font-weight:600}
.node.off,.frame.off{opacity:.35}
.node.cur rect.bg{stroke:var(--accent);stroke-width:3}
.badge{cursor:pointer}.badge rect{fill:var(--accent)}.badge text{fill:#fff;font-size:11px;font-weight:700}
.steps{list-style:none;padding:0;margin:8px 0}
.step{border:1px solid var(--line);border-radius:8px;padding:8px 10px;margin:6px 0;cursor:pointer;background:var(--bg)}
.step.cur{border-color:var(--accent);box-shadow:0 0 0 1px var(--accent)}
.step p{margin:4px 0}
.step .no{display:inline-block;min-width:20px;height:20px;border-radius:10px;background:var(--accent);color:#fff;text-align:center;font-size:11px;line-height:20px;margin-right:6px}
.subs{font-size:12px;color:var(--muted)}
.scnav{display:flex;gap:12px;align-items:center;margin:6px 0}
button.link:disabled{color:var(--muted);cursor:default}
```

- [ ] **Step 4: 구현 — HTML·상태·도우미**

- `<div id="evlegend" hidden>…</div>` 줄 다음에 `  <div class="scbar" id="scbar"></div>`
- `const state = {view: null, node: null, ev: false};` → `const state = {view: null, node: null, ev: false, sc: null, step: 0};`
- `const codeList = …;` 줄 다음에:

```js
  const SCS = MODEL.scenarios || [], SCV = (MODEL.validation || {}).scenarios || {};
  const sc = () => SCS.find(s => s.id === state.sc) || null;
  const stepBody = t => esc(t).replace(/\{\{([^{}]+)\}\}/g, (m, id) => NODE[id] ? `<button class="link" type="button" data-sel="${esc(id)}">${esc(NODE[id].title)}</button>` : m);
```

- [ ] **Step 5: 구현 — draw() 에 시나리오 표시**

`draw()` 안:
- `const R = rel(state.node);` 를 다음으로 교체:

```js
    const R = rel(state.node), S = !state.node && sc(), rows = S ? (SCV[S.id] || []) : [];
    const pathE = new Set(rows.map(r => r.edge).filter(i => i !== null && i !== undefined));
    const nums = {};
    if (S) S.steps.forEach((st, i) => (nums[st.box] = nums[st.box] || []).push(i + 1));
    const curBox = S ? S.steps[state.step].box : null;
    const inPath = id => !!nums[id] || (KIDS[id] || []).some(c => nums[c]) || !!(NODE[id] && NODE[id].group && nums[NODE[id].group]);
```

- 묶음 루프의 `const n = NODE[fid], g = el("g", {class: "frame" + (state.node === fid ? " sel" : "")}, svg);` 를 `const n = NODE[fid], g = el("g", {class: "frame" + (state.node === fid ? " sel" : "") + (S && !inPath(fid) ? " off" : "") + (curBox === fid ? " cur" : "")}, svg);` 로
- 화살표의 `const g = el("g", {class: "edge" + (R && !R.has(e.from) && !R.has(e.to) ? " dim" : "")}, svg);` 를 `const g = el("g", {class: "edge" + (R ? (!R.has(e.from) && !R.has(e.to) ? " dim" : "") : S ? (pathE.has(i) ? " path" : " dim") : "")}, svg);` 로
- 박스 루프의 `const g = el("g", {class: "node" + (state.node === n.id ? " sel" : "")}, svg);` 를 `const g = el("g", {class: "node" + (state.node === n.id ? " sel" : "") + (S && !inPath(n.id) ? " off" : "") + (curBox === n.id ? " cur" : "")}, svg);` 로
- 박스 루프가 끝난 `}` 다음(draw 의 마지막 `}` 앞)에 번호 배지:

```js
    for (const [id, ns] of Object.entries(nums)) {
      const r = LAY.boxes[id] || LAY.frames[id];
      if (!r) continue;
      const label = ns.join("·"), w = 12 + label.length * 7;
      const g = el("g", {class: "badge"}, svg);
      el("rect", {x: r[0] + r[2] - w + 6, y: r[1] - 9, width: w, height: 18, rx: 9}, g);
      el("text", {x: r[0] + r[2] - w / 2 + 6, y: r[1] + 4, "text-anchor": "middle"}, g).textContent = label;
      g.addEventListener("click", ev => { ev.stopPropagation(); play(state.sc, ns[0] - 1); });
    }
```

- [ ] **Step 6: 구현 — 카드**

`function side() {` 다음 세 줄(`const v = …`, `const mine = …`, `$("side").classList.toggle("open", !!n);`, `document.body.classList.toggle("card-open", !!n);`)과 `if (!n) { $("side").innerHTML = ""; return; }` 를:

```js
    const v = views[state.view], n = state.node && (v.nodes || []).find(x => x.id === state.node);
    const mine = n ? new Set([n.id, ...(KIDS[n.id] || [])]) : null, S = !n && sc();
    $("side").classList.toggle("open", !!(n || S));
    document.body.classList.toggle("card-open", !!(n || S));
    if (S) { $("side").innerHTML = scCard(S); return; }
    if (!n) { $("side").innerHTML = ""; return; }
```

박스 카드 innerHTML 의 첫 줄 `$("side").innerHTML = \`<div class="k">` 를 `$("side").innerHTML = \`${state.sc ? \`<p><button class="link" type="button" data-back>← 시나리오로</button></p>\` : ""}<div class="k">` 로.

`function ifaceCard(f) {` 바로 위에:

```js
  function scCard(S) {
    const rows = SCV[S.id] || [], N = S.steps.length;
    return `<div class="k">시나리오</div><h2>${rich(S.title)}</h2><p>${rich(S.summary || "")}</p>
      <div class="scnav"><button class="link" type="button" data-step="${state.step - 1}" ${state.step ? "" : "disabled"}>← 이전</button>
        <span>${state.step + 1} / ${N}</span>
        <button class="link" type="button" data-step="${state.step + 1}" ${state.step < N - 1 ? "" : "disabled"}>다음 →</button></div>
      <ol class="steps">${S.steps.map((st, i) => {
        const row = rows[i] || {}, g = row.grade, e = row.edge;
        const badge = g === "unknown" ? ` <span class="tag g-unknown">미확인</span>` : g === "record" ? ` <span class="tag g-record">기록 해석</span>` : "";
        const ev = state.ev ? [e !== null && e !== undefined ? chip(evText(V.edges[e].evidence)) : "", ...(st.evidence || []).map(x => chip(x.ref))].join(" ") : "";
        return `<li class="step${i === state.step ? " cur" : ""}" data-step="${i}"><b><span class="no">${i + 1}</span>${rich(st.title)}</b>${badge}
          <p>${stepBody(st.body || "")}</p>${(st.substeps || []).length ? `<div class="subs">${st.substeps.map(x => esc(x.label)).join(" → ")}</div>` : ""}${ev}</li>`;
      }).join("")}</ol>
      <p class="detail">←/→ 키로 넘긴다. 파란 박스 이름을 누르면 그 박스 설명.</p>`;
  }
```

카드 클릭 처리:
- `ev.target.closest("[data-copy],[data-sel],[data-close]")` → `ev.target.closest("[data-copy],[data-sel],[data-close],[data-step],[data-back]")`
- `if (t.dataset.sel) return select(t.dataset.sel);` 다음 줄에:

```js
    if (t.dataset.step !== undefined) return t.disabled ? null : play(state.sc, +t.dataset.step);
    if (t.hasAttribute("data-back")) return select(null);
```

- [ ] **Step 7: 구현 — 재생·키·주소·시작**

`function select(nid) {` 바로 위에:

```js
  function scbar() {
    $("scbar").innerHTML = SCS.length ? "따라가 보기: " + SCS.map(s => `<button type="button" data-sc="${esc(s.id)}" class="${state.sc === s.id ? "on" : ""}">▶ ${esc(s.title)}</button>`).join("")
      + (state.sc ? ` <button type="button" data-sc="">구조만 보기</button>` : "") : "";
  }
  $("scbar").addEventListener("click", ev => { const b = ev.target.closest && ev.target.closest("[data-sc]"); if (b) play(b.dataset.sc || null, 0); });
  function play(id, step) {
    state.sc = SCS.some(s => s.id === id) ? id : null;
    const S = sc();
    state.step = S ? Math.max(0, Math.min(step, S.steps.length - 1)) : 0;
    state.node = null;
    const h = state.sc ? `#scenario=${encodeURIComponent(state.sc)}&step=${state.step + 1}` : "#scenario=none";
    if (location.hash !== h) history.replaceState(null, "", h);
    scbar(); draw(); side();
  }
```

- `document.addEventListener("keydown", ev => { if (ev.key === "Escape" && state.node) select(null); });` 를:

```js
  document.addEventListener("keydown", ev => {
    if (ev.key === "Escape" && state.node) return select(null);
    if (state.sc && !state.node && (ev.key === "ArrowRight" || ev.key === "ArrowLeft")) play(state.sc, state.step + (ev.key === "ArrowRight" ? 1 : -1));
  });
```

- `window.addEventListener("hashchange", () => {` 다음 줄에:

```js
    const s = location.hash.match(/^#scenario=([^&]*)(?:&step=(\d+))?/);
    if (s) return play(decodeURIComponent(s[1]), (+s[2] || 1) - 1);
```

- 맨 끝 세 줄(`window.ELI5 = …`, `header();`, `const m = …`, `go(…)`)을:

```js
  window.ELI5 = {MODEL, state, go, select, play};
  header();
  const m = location.hash.match(/^#view=(.+)$/), s0 = location.hash.match(/^#scenario=([^&]*)(?:&step=(\d+))?/);
  go(m && views[decodeURIComponent(m[1])] ? decodeURIComponent(m[1]) : rootView);
  // 시나리오 먼저 — 시나리오가 있으면 첫 시나리오를 고른 채로 연다 (#scenario=none 이면 구조도만)
  if (SCS.length) play(s0 ? decodeURIComponent(s0[1]) : SCS[0].id, s0 ? (+s0[2] || 1) - 1 : 0);
  else scbar();
```

- [ ] **Step 8: 통과 확인**

Run: `bash tests/unit/test_eli5_render.sh && bash tests/unit/test_eli5_validate.sh`
Expected: 둘 다 `0 failed`

- [ ] **Step 9: 브라우저 확인**

fixture 를 validate·render 하고 `http.server 8799` 로 열어:
1. 열자마자 "요청이 들어오면" 이 선택돼 있고 오른쪽 카드에 단계 3개, 지도의 `요청 받는 곳`·`작업 실행기`·`에이전트 서비스` 에 ①②③, 1번 박스 두꺼운 테두리, 경로 화살표 굵게, `모듈 입구` 흐림
2. `→` 키 두 번 → 3단계, 주소 `#scenario=run&step=3`
3. 2단계 본문의 파란 `작업 엔진` 클릭 → 묶음 카드 + "← 시나리오로" → 누르면 시나리오 카드로
4. "구조만 보기" → 카드 닫힘, 번호·강조 없음, 주소 `#scenario=none`
5. 주소 `#scenario=none` 으로 새로고침 → 구조도만. `#scenario=run&step=2` → 2단계로 열림
6. 같은 박스를 두 번 지나는 시나리오: 모델의 3단계 박스를 `api` 로 바꿔 렌더 → 배지 "1·3" (validate 는 agent→api 화살표로 통과) — 확인 후 원래대로
7. 시나리오를 지운 모델 → 버튼 줄 없음, 카드 닫힘
끝나면 서버를 끈다.

- [ ] **Step 10: 커밋**

```bash
git add skills/eli5/assets/map.html tests/unit/test_eli5_render.sh
git commit -m "feat(eli5): 시나리오 먼저 — 지나는 박스 번호·경로 강조·단계 카드·주소 공유

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: 절차·안내

**Files:** `skills/eli5/SKILL.md`, `commands/help.md`, `CHANGELOG.md`

- [ ] **Step 1: SKILL.md**

- description 끝의 `'/rakis:eli5 <대상>' 일 때 사용.` 앞에 `대표 흐름(시나리오)을 번호로 따라가는 화면이 먼저 열린다.` 를 넣는다
- `## Phase 3: 검증` 바로 위에 새 절:

```markdown
### 시나리오 — 무슨 일이 어떤 순서로

지도를 읽는 사람이 가장 먼저 궁금한 것은 "무슨 일이 어떤 순서로 일어나는가" 다. 지도를 열면 첫 시나리오가 선택된 채로 열린다.

```json
"scenarios": [{"id": "form-input", "title": "화면에서 조건을 입력하면",
  "summary": "<1~2문장 — 무슨 일이 일어나는지>",
  "steps": [{"box": "bff", "title": "화면이 요청을 보냄", "body": "한 턴을 {{route}} 로 넘긴다."},
            {"box": "route", "title": "요청 접수", "body": "...", "substeps": [{"label": "신원 확인"}]},
            {"box": "orch", "title": "갈래 고르기", "body": "...", "evidence": [{"ref": "path:line", "quote": "..."}]}]}]
```

- 시나리오 1~4개, 단계 2~7개. 첫 시나리오는 `<대상>` 흐름 그 자체. 단계는 함수가 아니라 비개발자가 이해할 단위
- **각 단계 박스로 가는 화살표가 지금까지 지나온 박스 중 하나에서 나와야 한다** (호출은 갔다 돌아오는 나무 모양이라 바로 앞 단계가 아니어도 된다). 화살표 끝이 묶음이면 그 안쪽 박스에도 통한다. 없으면 검증기가 알려 준다 — 지도에 화살표를 근거와 함께 그리거나 단계를 고친다. 화살표 없이 건너뛰는 이야기를 쓰지 않는다
- 근거는 화살표 것을 물려받는다. 화살표에 없는 사실을 말하는 단계만 `evidence` (code 등급 형식)를 단다 — 틀리면 그 단계가 "미확인" 으로 표시된다
- 본문의 `{{박스id}}` 는 박스 이름 버튼이 된다. `title` 24칸, 하위 단계 14칸, 쉬운 말 검사는 박스와 같다

```

- Phase 7 출력 블록의 `  그림에 없는 관계: m건` 다음 줄에 `  시나리오: <개수>개 — <제목들>`

- [ ] **Step 2: help·CHANGELOG**

- `commands/help.md` eli5 블록 `## 화면` 의 첫 줄 앞에 `- 처음 열면 대표 흐름(시나리오)이 선택돼 있다: 지나는 박스에 ①②③, 오른쪽 카드에 단계 설명, ←/→ 로 넘김, "구조만 보기" 로 끔`
- `CHANGELOG.md` `### Added` 첫 항목으로: `- \`eli5\` **시나리오 따라가기 — 무슨 일이 어떤 순서로.** 한 장 지도를 본 사용자가 "구조는 보이는데 무슨 일이 일어나는지는 모르겠다" 고 해서, 지도를 열면 대표 흐름이 선택된 채로 시작하게 했다. 지나는 박스에 번호, 쓰인 화살표 강조, 오른쪽 카드에 단계 설명(←/→, 주소로 같은 단계 공유). 단계는 지나온 박스 중 하나에서 나오는 실제 화살표로만 이어질 수 있고(호출의 나무 모양을 그대로), 검증기가 단계마다 쓰인 화살표와 근거 등급을 기록해 화면은 그 기록만 그린다. 설계: spec 2.5`

- [ ] **Step 3: 확인과 커밋**

Run: `./lint.sh 2>&1 | tail -1; ./test.sh eli5 2>&1 | tail -1`
Expected: 둘 다 통과

```bash
git add skills/eli5/SKILL.md commands/help.md CHANGELOG.md
git commit -m "docs(eli5): 시나리오 작성 규칙 — 지나온 박스에서 잇기, 1~4개, 2~7단계

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: 실측 — 업무 지도에 시나리오 넣고 사용자 판정

**Files:** 대상 레포 `.eli5/` 출력물만

- [ ] **Step 1**: `git -C $R status --short > /tmp/eli5-sc-before.txt`, 지금 모델 `/tmp/eli5-single.model.json` 으로 보존
- [ ] **Step 2**: SKILL.md 규칙대로 시나리오 2~3개를 쓴다 — 첫 번째는 "화면에서 조건을 입력하면" (대화창 서버 → 요청 입구 → 한 턴 진행 → 입력 준비 → 입력 안전 검사 → 입구 분류 → 조건 해석 같은 나무 모양). 근거가 필요한 단계 사실은 코드에서 읽어 `evidence`. validate 실행 횟수를 센다
- [ ] **Step 3**: validate·render, 강등·미확인 단계 수 확인. 대상 레포 `git status` 무변경
- [ ] **Step 4**: `open.py open` 으로 열고 사용자에게 묻는다: "열자마자 무슨 일이 어떤 순서로 일어나는지 따라가지나요?" — 판정 전에는 완료로 보고하지 않는다
