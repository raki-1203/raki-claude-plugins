# eli5 2b — 갈림길 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** "어떤 상황에서는 이리로, 어떤 상황에서는 저리로" 를 보여 준다 — 조건에 따라 하나만 가는 화살표를 갈림길로 표시하고, 조건을 쉬운 말과 코드 근거로 단다.

**Architecture:** edge 에 `kind: "branch"`·`when`·`when_evidence`. `validate.py` 가 규칙(무결성)과 조건 근거(`validation.branches`)를 판정하고, `map.html` 은 ◆·마름모 시작점·"여기서 갈라진다" 목록을 그린다.

**Tech Stack:** Python 3 표준 라이브러리(3.9 파싱), 바닐라 JS/SVG, bash 테스트.

**Spec:** `docs/superpowers/specs/2026-10-02-eli5-v3-readable-map-design.md` 2.6

## Global Constraints

- 브랜치 `feat/eli5-scenarios` 에 이어서. push·merge 범위 밖
- `kind` ∈ {없음, `call`, `branch`}. `branch` ⇒ `when`(쉬운 말, ≤ `plain.SAY_MAX` 30칸) + `when_evidence {ref, quote}` 필수. `branch` 아닌데 `when`/`when_evidence` 있으면 오류
- 조건 근거 실패 = 그 조건 "미확인" (exit 0)
- 커밋 conventional + `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`

## Review Focus

1. **갈래가 하나뿐인 갈림길**(예: 승인하면 → 계산, 아니면 멈춤) — 기대: 허용, ◆ 표시, 목록에 한 줄 → Task 6 브라우저 확인
2. **시나리오의 마지막 단계가 갈림길** — 기대: 탄 갈래 없음(● 없음), 목록은 보임 → Task 6 브라우저 확인
3. **조건 문장에 코드 이름** — 기대: 쉬운 말 검사로 거부 → Task 5 테스트 "조건에 코드 이름"

---

### Task 5: 검증기 — 갈림길 규칙과 조건 근거

**Files:** `skills/eli5/bin/validate.py`, `tests/fixtures/eli5/model.json`, `tests/unit/test_eli5_validate.sh`

**Interfaces:**
- Produces: `branch_errors(model) -> list[str]`, `branch_report(model, root, quick) -> {"<i>": "code" | "unknown"}` → `validation.branches`. fixture 의 `core→agent` 가 갈림길

- [ ] **Step 1: fixture** — `tests/fixtures/eli5/model.json` 의 `{"from": "core", "to": "agent", "label": "작업 전달", "iface": "agent-http", "grade": "code",` 를 `{"from": "core", "to": "agent", "label": "작업 전달", "iface": "agent-http", "grade": "code", "kind": "branch", "when": "작업을 마치면", "when_evidence": {"ref": "src/core/engine.py:5", "quote": "requests.post("},` 로

- [ ] **Step 2: 실패 테스트** — `echo "🔧 누락 탐지"` 앞에:

```bash
echo "🔧 갈림길"
fresh; out=$(run); [ "$(echo "$out" | jq -c .branches)" = '{"1":"code"}' ] && pass "갈림길 조건 근거 판정 기록" || fail "갈림길 기록" "$(echo "$out" | jq -c .branches)"
fresh; edit 'm["views"]["L0"]["edges"][1]["when_evidence"]["quote"]="requests.get("'
out=$(run); [ $? -eq 0 ] && [ "$(echo "$out" | jq -r '.branches["1"]')" = "unknown" ] && pass "조건 근거가 틀리면 unknown (exit 0)" || fail "조건 근거" "$out"
integrity 'm["views"]["L0"]["edges"][1]["kind"]="maybe"' "call · branch" "kind 허용값"
integrity 'm["views"]["L0"]["edges"][1].pop("when")' "when 이 비었다" "갈림길에 when 필수"
integrity 'm["views"]["L0"]["edges"][1].pop("when_evidence")' "when_evidence 가 없다" "갈림길에 근거 필수"
integrity 'm["views"]["L0"]["edges"][0]["when"]="항상"' "갈림길(kind: branch)에만" "when 은 갈림길에만"
integrity 'm["views"]["L0"]["edges"][1]["when"]="run_job 이 끝나면"' "run_job" "조건에 코드 이름"
```

- [ ] **Step 3: 실패 확인** — `bash tests/unit/test_eli5_validate.sh` → 위 7개 ❌

- [ ] **Step 4: 구현** — `def under(path, prefixes):` 위에:

```python
def branch_errors(model):
    """갈림길 — 조건에 따라 하나만 가는 화살표는 쉬운 말 조건(when)과 그 코드 근거를 단다."""
    g = (model.get("meta") or {}).get("glossary") or {}
    errs = []
    for vid, v in (model.get("views") or {}).items():
        for e in v.get("edges", []):
            w, kind = f"{vid}: {e.get('from')}→{e.get('to')}", e.get("kind")
            if kind not in (None, "call", "branch"):
                errs.append(f"{w}.kind '{kind}' — call · branch 중 하나 (조건에 따라 하나만 가면 branch)")
            if kind != "branch":
                if "when" in e or "when_evidence" in e:
                    errs.append(f"{w}: when 은 갈림길(kind: branch)에만 — kind 를 branch 로 하거나 when 을 뺀다")
                continue
            when = e.get("when")
            if not isinstance(when, str) or not when.strip():
                errs.append(f"{w}: 갈림길인데 when 이 비었다 — 어떤 상황에서 이쪽으로 가는지 쉬운 말로 쓴다")
            else:
                errs += plain.check_plain(f"{w}.when", when, g, plain.SAY_MAX)
            ev = e.get("when_evidence") or {}
            if not ev.get("ref") or not ev.get("quote"):
                errs.append(f"{w}: when_evidence 가 없다 — 조건이 적힌 코드 줄을 ref(path:line)·quote 로 단다")
    return errs


def branch_report(model, root, quick):
    """{"<화살표 번호>": "code" | "unknown"} — 갈림길 조건의 근거를 판정한다. 틀리면 그 조건을 미확인으로 보인다."""
    view = next(iter(model["views"].values()))
    out = {}
    for i, e in enumerate(view.get("edges", [])):
        if e.get("kind") == "branch":
            ok, _ = check_code(e.get("when_evidence") or {}, root, quick)
            out[str(i)] = "code" if ok else "unknown"
    return out
```

`main()`: `errs = integrity_errors(model) + v3_errors(model)` → `errs = integrity_errors(model) + v3_errors(model) + branch_errors(model)`. report 의 `"scenarios": scenario_report(model, root, a.quick)}` → `"scenarios": scenario_report(model, root, a.quick), "branches": branch_report(model, root, a.quick)}`

- [ ] **Step 5: 통과** — `bash tests/unit/test_eli5_validate.sh && bash tests/unit/test_eli5_render.sh && /usr/bin/python3 -c "import ast; ast.parse(open('skills/eli5/bin/validate.py').read())"` → 0 failed

- [ ] **Step 6: 커밋** — `feat(eli5): 갈림길 검증 — branch·when·조건 근거`

---

### Task 6: 지도 — ◆·마름모·"여기서 갈라진다"

**Files:** `skills/eli5/assets/map.html`, `tests/unit/test_eli5_render.sh`

- [ ] **Step 1: 실패 테스트** — `finish` 위에:

```bash
grep -q 'id: "fk-" + g' "$TPL" && grep -q 'function forkHtml' "$TPL" && grep -q 'data-hl' "$TPL" && grep -q 'data-play' "$TPL" && grep -q 'class: "forkmark"' "$TPL" \
  && pass "갈림길 UI — 마름모 시작점·◆·갈라지는 목록·화살표 강조·다른 길 따라가기" || fail "갈림길 UI"
```

- [ ] **Step 2: 실패 확인**

- [ ] **Step 3: CSS** — `.edge.path text{…}` 줄 다음에:

```css
.edge.hl path{stroke:var(--record);stroke-width:4;stroke-dasharray:none}.edge.hl text{fill:var(--record)}.edge.dim.hl{opacity:1}
.forkmark{fill:var(--record);font-size:12px}
.fork{margin:10px 0 2px;padding:8px 10px;border:1px dashed var(--record);border-radius:8px;font-size:13px}
.fork .br{margin:5px 0}.fork .br.on{font-weight:600}
```

- [ ] **Step 4: JS**
- `const SCS = …` 줄 다음에:

```js
  const FORK = new Set((V.edges || []).filter(e => e.kind === "branch").map(e => e.from));
  const forks = id => (V.edges || []).map((e, i) => [e, i]).filter(([e]) => e.kind === "branch" && e.from === id);
```

- draw() 의 화살표 마커 루프 안(`el("path", {d: "M0,0 L10,5 L0,10 z", …}, m);` 다음)에:

```js
      const f = el("marker", {id: "fk-" + g, viewBox: "0 0 10 10", refX: "5", refY: "5", markerWidth: "9", markerHeight: "9", orient: "auto"}, defs);
      el("path", {d: "M5,0 L10,5 L5,10 L0,5 z", class: "g-" + g, style: "fill:currentColor;stroke:none;stroke-dasharray:none"}, f);
```

- 화살표 g 생성 `const g = el("g", {class: "edge" + …}, svg);` 의 속성 객체에 `"data-i": i` 추가. 그 아래 path 생성 `el("path", {d: …, class: "g-" + g2, "marker-end": \`url(#ah-${g2})\`}, g);` 다음 줄에 `if (e.kind === "branch") g.lastChild.setAttribute("marker-start", \`url(#fk-${g2})\`);`
- 화살표 툴팁 `el("title", {}, g).textContent = GRADE[e.grade] + (…);` 를 `el("title", {}, g).textContent = (e.when ? "조건: " + e.when + "\n" : "") + GRADE[e.grade] + (evText(e.evidence) ? " — " + evText(e.evidence) : "");`
- 묶음 루프의 `el("title", {}, g).textContent = (KIND[n.kind] || "") + " 묶음 — 빈 곳을 누르면 설명";` 앞에 `if (FORK.has(fid)) el("text", {x: r[0] + r[2] - 16, y: r[1] + 22, class: "forkmark"}, g).textContent = "◆";`
- 박스 루프의 `const terms = termsIn(n.title, n.say);` 앞에 `if (FORK.has(n.id)) el("text", {x: B[0] + B[2] - 16, y: B[1] + 20, class: "forkmark"}, g).textContent = "◆";`
- `function scCard(S) {` 위에:

```js
  function forkHtml(id, taken) {
    const list = forks(id), BR = (MODEL.validation || {}).branches || {};
    if (!list.length) return "";
    return `<div class="fork"><b>◆ 여기서 갈라진다</b>${list.map(([e, i]) => {
      const on = taken === i;
      const other = SCS.map(s => [s, (SCV[s.id] || []).findIndex(r => r.edge === i)]).find(([s, k]) => k > 0 && !(on && s.id === state.sc));
      return `<div class="br${on ? " on" : ""}" data-hl="${i}">${on ? "●" : "○"} ${rich(e.when || "")} → <b>${esc(nodeTitle(state.view, e.to))}</b>`
        + (BR[i] === "unknown" ? ` <span class="tag g-unknown">미확인</span>` : "")
        + (on ? ` <span class="detail">← 이 이야기</span>` : "")
        + (other && !on ? ` <button class="link" type="button" data-play="${esc(other[0].id)}:${other[1]}">이 길 따라가기</button>` : "") + `</div>`;
    }).join("")}</div>`;
  }
```

- scCard 의 `.now` 안 본문 `<p>${stepBody(st.body || "")}</p>` 다음에 `${forkHtml(st.box, (rows[i + 1] || {}).edge)}`
- 박스 카드의 `${n.group && NODE[n.group] ? …속한 묶음… : ""}` 줄 다음에 `${forkHtml(n.id, null)}`
- 카드 클릭: closest 선택자에 `,[data-play]` 추가, `if (t.dataset.sel) return select(t.dataset.sel);` 앞에:

```js
    if (t.dataset.play) { const [sid, k] = t.dataset.play.split(":"); return play(sid, +k); }
```

- 카드 클릭 리스너 다음에:

```js
  $("side").addEventListener("mouseover", ev => {
    const b = ev.target.closest && ev.target.closest("[data-hl]");
    document.querySelectorAll(".edge.hl").forEach(x => x.classList.remove("hl"));
    const g = b && document.querySelector(`.edge[data-i="${b.dataset.hl}"]`);
    if (g) g.classList.add("hl");
  });
```

- [ ] **Step 5: 통과** — render·validate 테스트 0 failed
- [ ] **Step 6: 브라우저** — fixture: `에이전트 서비스` 로 가는 화살표 시작에 마름모, `작업 엔진` 묶음에 ◆, 시나리오 2단계(작업 실행기 — 묶음의 안쪽이라 ◆ 없음) / 묶음 카드에 "여기서 갈라진다: 작업을 마치면 → 에이전트 서비스", 그 줄에 마우스 → 화살표 주황 강조
- [ ] **Step 7: 커밋** — `feat(eli5): 갈림길 표시 — ◆, 마름모 시작점, 여기서 갈라진다`

---

### Task 7: SKILL.md·CHANGELOG

- [ ] Phase 2 "작성 규칙" 끝에: `- **갈림길**: 조건에 따라 하나만 가는 화살표는 \`"kind": "branch"\`, \`"when": "<어떤 상황이면, 쉬운 말 30칸>"\`, \`"when_evidence": {"ref": "path:line", "quote": "<조건이 적힌 줄>"}\`. 차례로 다 부르는 화살표는 \`kind\` 를 쓰지 않는다. 조건은 지어내지 않는다 — 근거가 틀리면 지도에 "미확인" 으로 나온다. 갈림길 박스를 지나는 시나리오를 갈래마다 하나씩 두면 "이 길 따라가기" 로 이어진다`
- [ ] CHANGELOG `### Added` 첫 항목: `- \`eli5\` **갈림길 — 어떤 상황에서 어디로.** 조건에 따라 하나만 가는 화살표를 \`kind: branch\` 로 구분하고 쉬운 말 조건(\`when\`)과 그 조건이 적힌 코드 줄(\`when_evidence\`)을 단다. 지도에는 ◆ 와 마름모 시작점, 시나리오·박스 카드에는 "여기서 갈라진다" 목록(이 이야기가 탄 갈래 표시, 다른 갈래를 타는 시나리오로 바로 이동). 설계: spec 2.6`
- [ ] lint·test 통과, 커밋 `docs(eli5): 갈림길 작성 규칙`

---

### Task 8: 실측 — 업무 지도 갈림길 3곳 + 시나리오 1개

- [ ] 갈림길(근거는 `src/agents/simulation/router.py`): 입구 분류 → 이어받기("계산 중인 작업이 있으면", :31 `if state.get("pending_job"):`) · 조건 해석("조건을 말하면", :34 `== "simulate":`) · 보고서("보고서를 달라면", :39 `== "report":`) · 조건 바꾸기("다른 안·여유·범위를 물으면", :45 `== "reselect":`); 조건 해석 → 되묻기("빈 칸이 남아 있으면", :144 `stage_slot_questions(state, "population")`) · 확정("칸이 다 차면", :165 `return "confirm"`); 확정·승인 → 계산 맡기기("사용자가 승인하면", :93 `if is_gate_approved(state):`)
- [ ] 시나리오 "보고서를 요청하면" 추가 (4개째)
- [ ] validate(실행 횟수)·render·대상 레포 무변경, 열어서 사용자 판정: "어떤 상황에서 어디로 가는지 보이나요?"
