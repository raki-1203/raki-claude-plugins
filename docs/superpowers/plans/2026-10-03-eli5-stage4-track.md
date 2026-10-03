# eli5 4단계 — 작업 진행 표시 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 에이전트가 일하는 동안 지도 위에서 "어디를 고치고 있고 어디까지 됐는지" 보이게 한다.

**Architecture:** `track.py start` 가 세션 표식(`$ROOT/.eli5/track/<sid>.json`)을 만들고, PostToolUse 훅 `track.py touch` 가 고친 파일을 잎 박스에 매핑해 `<slug>.touched.<sid>.json` 에 기록한 뒤 `render.py --track` 으로 추적 화면을 다시 그린다. 에이전트는 판단 상태를 `<slug>.progress.<sid>.json`(deadhd 형식)에 쓴다. 화면은 15초마다 새로고침하고 진행 카드·박스 상태·묶음 집계를 그린다.

**Tech Stack:** Python 3 표준 라이브러리(3.9 파싱), 바닐라 JS/SVG, bash 테스트, Claude Code 플러그인 훅.

**Spec:** `docs/superpowers/specs/2026-10-02-eli5-v3-readable-map-design.md` 4.1~4.5 (4.5 우선)

## Global Constraints

- 브랜치 `feat/eli5-track`. push·merge 범위 밖
- 세션 id = `--session` 또는 `CLAUDE_CODE_SESSION_ID` (없으면 exit 2)
- `touch` 는 어떤 입력에도 exit 0, 오류는 `.eli5/track/<sid>.log`. 표식 없을 때 평균 80ms 미만(실측 30ms)
- 추적 렌더는 모델·사이드카를 쓰지 않는다
- 진행 파일: state ∈ plan·now·done·blocked, now ≤ 1, boxes 는 지도 id, done 은 evidence 필수, href 는 http(s)
- 커밋 conventional + `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`

## Review Focus

1. **진행 파일이 아직 없을 때** — 기대: 화면은 "아직 진행 상황을 쓰지 않았다" + 건드림만 → Task 2 브라우저 확인
2. **같은 박스를 가리키는 항목이 여럿(진행·완료)** — 기대: 더 급한 상태(막힘>진행>완료>남음)로 표시 → Task 2 브라우저 확인
3. **추적을 끝낸 뒤 화면** — 기대: 새로고침 꺼짐, "추적 끝남" → Task 1 테스트 stop

---

### Task 1: track.py 와 render 추적 모드

**Files:** Create `skills/eli5/bin/track.py`, `tests/unit/test_eli5_track.sh`; Modify `skills/eli5/bin/render.py`

- [ ] **Step 1: 실패 테스트** — `tests/unit/test_eli5_track.sh`:

```bash
#!/bin/bash
set -uo pipefail
source "$(dirname "$0")/../fixtures/eli5/lib.sh"
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
R="$T/r"; bash "$ELI5_FIX/make_repo.sh" "$R"
export FAKE_GRAFT_CALLERS="$ELI5_FIX/callers.json"
mkdir -p "$R/.eli5"; M="$R/.eli5/app.model.json"; cp "$ELI5_FIX/model.json" "$M"
python3 "$ELI5_BIN/validate.py" "$M" --root "$R" >/dev/null
TR="$ELI5_BIN/track.py"; SID=sid-1
H="$R/.eli5/app.track.$SID.html"; TF="$R/.eli5/app.touched.$SID.json"; PF="$R/.eli5/app.progress.$SID.json"
hook() { printf '{"session_id":"%s","tool_name":"Edit","tool_input":{"file_path":"%s"}}' "$1" "$2" | python3 -S "$TR" touch; }
payload() { python3 - "$H" <<'PY'
import json, re, sys
h = open(sys.argv[1], encoding="utf-8").read()
print(json.dumps(json.loads(re.search(r"const MODEL = (.*?);\n\(function", h, re.S).group(1))["track"], ensure_ascii=False))
PY
}

echo "🔧 track — 시작·종료"
MSUM=$(md5 -q "$M")
out=$(CLAUDE_CODE_SESSION_ID=$SID python3 "$TR" start --model "$M")
[ -f "$R/.eli5/track/$SID.json" ] && [ -f "$H" ] && pass "start — 표식과 추적 화면" || fail "start" "$out"
grep -q 'http-equiv="refresh" content="15"' "$H" && pass "추적 중에는 15초 자동 새로고침" || fail "자동 새로고침"
[ "$(payload | jq -r .live)" = "true" ] && pass "payload live=true" || fail "live"
env -u CLAUDE_CODE_SESSION_ID python3 "$TR" start --model "$M" >/dev/null 2>&1; [ $? -eq 2 ] && pass "세션 id 없으면 exit 2" || fail "세션 id 없음"

echo "🔧 track — 훅 기록"
hook $SID "$R/src/core/engine.py"; [ $? -eq 0 ] && [ "$(jq -r '.files["src/core/engine.py"].box' "$TF")" = "engine" ] && pass "고친 파일 → 잎 박스(engine)" || fail "박스 매핑" "$(cat "$TF" 2>/dev/null)"
[ "$(payload | jq -r '.touched["src/core/engine.py"].box')" = "engine" ] && pass "화면 다시 그림 (touched 반영)" || fail "다시 그림"
hook $SID "$R/docs/adr-1.md"; [ "$(jq -r '.files["docs/adr-1.md"].box' "$TF")" = "null" ] && pass "지도 밖 파일 → box null" || fail "지도 밖"
hook other-sid "$R/src/api/server.py"; [ "$(jq -r '.files["src/api/server.py"] // "none"' "$TF")" = "none" ] && pass "다른 세션의 편집은 기록 안 함" || fail "세션 필터"
hook $SID "$R/.eli5/app.model.json"; [ "$(jq -r '.files[".eli5/app.model.json"] // "none"' "$TF")" = "none" ] && pass ".eli5 안 파일 무시" || fail ".eli5 무시"
echo 'not json' | python3 -S "$TR" touch; [ $? -eq 0 ] && pass "깨진 입력에도 exit 0" || fail "깨진 입력"
hook nobody "$T/elsewhere/x.py"; [ $? -eq 0 ] && pass "표식 없는 곳은 바로 exit 0" || fail "표식 없음"
s=$(python3 -c "import time,subprocess,sys; t=time.time(); [subprocess.run([sys.executable,'-S','$TR','touch'],input=b'{\"session_id\":\"x\",\"tool_input\":{\"file_path\":\"/tmp/nope/x.py\"}}') for _ in range(5)]; print(int((time.time()-t)/5*1000))")
[ "$s" -lt 80 ] && pass "표식 없을 때 평균 ${s}ms (< 80ms)" || fail "훅 비용" "${s}ms"

echo "🔧 track — 진행 파일"
cat > "$PF" <<'J'
{"task": {"title": "작업 실행기 고치기", "goal": "실행 결과를 정확히 보낸다"}, "updated": "2026-10-03 22:00 KST",
 "items": [{"id": "a", "title": "실행기 수정", "body": "결과 형식을 바꾼다", "state": "now", "boxes": ["engine"]},
           {"id": "b", "title": "테스트", "body": "단위 테스트 통과", "state": "done", "boxes": ["api"], "evidence": [{"text": "pytest 12 passed"}]}]}
J
python3 "$ELI5_BIN/render.py" "$M" --root "$R" --track $SID >/dev/null
[ "$(payload | jq -r '.progress.items|length')" = "2" ] && [ "$(payload | jq -r '.errors|length')" = "0" ] && pass "진행 파일을 화면에 싣는다" || fail "진행 파일" "$(payload)"
python3 - "$PF" <<'PY'
import json, sys
p = sys.argv[1]; d = json.load(open(p)); d["items"][1]["state"] = "now"; d["items"].append({"id": "c", "title": "x", "state": "done", "boxes": ["ghost"]}); json.dump(d, open(p, "w"))
PY
python3 "$ELI5_BIN/render.py" "$M" --root "$R" --track $SID >/dev/null
e=$(payload | jq -r '.errors|join(" | ")')
echo "$e" | grep -q '최대 1개' && echo "$e" | grep -q "ghost" && echo "$e" | grep -q '근거가 없다' && [ "$(payload | jq -r .progress)" = "null" ] \
  && pass "진행 파일 오류(now 2개·없는 박스·근거 없는 완료)는 오류로 싣고 진행은 뺀다" || fail "진행 검증" "$e"
[ "$(md5 -q "$M")" = "$MSUM" ] && pass "추적 렌더는 모델을 다시 쓰지 않는다" || fail "모델 보존"

echo "🔧 track — 끝"
CLAUDE_CODE_SESSION_ID=$SID python3 "$TR" stop --model "$M" >/dev/null
[ ! -f "$R/.eli5/track/$SID.json" ] && ! grep -q 'http-equiv="refresh"' "$H" && [ "$(payload | jq -r .live)" = "false" ] && pass "stop — 표식 삭제, 자동 새로고침 끔" || fail "stop"
finish
```

- [ ] **Step 2: 실패 확인** — `bash tests/unit/test_eli5_track.sh` → 전부 ❌ (track.py 없음)
- [ ] **Step 3: render.py** — `def main():` 위에:

```python
PROGRESS_STATES = ("plan", "now", "done", "blocked")


def build_html(shown, title):
    # 데이터 안의 문자열이 script 블록을 닫거나(</) HTML 주석을 열지(<!--) 못하게 한다. 둘 다 JS 문자열 이스케이프라 값은 그대로다.
    payload = json.dumps(shown, ensure_ascii=False).replace("</", "<\\/").replace("<!--", "<\\u0021--")
    title = str(title).replace("&", "&amp;").replace("<", "&lt;")
    html = TEMPLATE.read_text(encoding="utf-8")
    return html.replace("/*__ELI5_MODEL__*/null", payload, 1).replace("__ELI5_TITLE__", title, 1)


def progress_errors(prog, ids):
    """진행 파일 규칙 — deadhd 와 같다: 진행(now)은 최대 1개, 완료는 도구 결과 근거가 있어야 한다."""
    items = prog.get("items") if isinstance(prog, dict) else None
    if not isinstance(items, list):
        return ["items 가 목록이 아니다"]
    errs, nows = [], 0
    for k, it in enumerate(items):
        w = f"items[{k}]"
        st = it.get("state")
        if st not in PROGRESS_STATES:
            errs.append(f"{w}.state '{st}' — plan·now·done·blocked 중 하나")
        nows += st == "now"
        for b in it.get("boxes") or []:
            if b not in ids:
                errs.append(f"{w}.boxes 의 '{b}' 는 지도에 없다")
        if st == "done" and not it.get("evidence"):
            errs.append(f"{w}: 완료인데 근거가 없다 — 통과한 테스트·쓴 파일·머지된 PR 을 evidence 로")
        for ev in it.get("evidence") or []:
            href = ev.get("href")
            if href is not None and not str(href).lower().startswith(("http://", "https://")):
                errs.append(f"{w}.evidence 의 href 는 http(s) 만")
    if nows > 1:
        errs.append(f"진행(now) 항목이 {nows}개 — 최대 1개")
    return errs


def render_track(model, mp, root, sid):
    """추적 화면 — 지도 + 훅이 기록한 건드림 + 에이전트 진행 파일. 모델·사이드카는 건드리지 않는다."""
    stem = stem_of(mp)

    def load(p, default):
        try:
            return json.loads(p.read_text(encoding="utf-8"))
        except (OSError, ValueError):
            return default

    tpath, ppath = mp.with_name(f"{stem}.touched.{sid}.json"), mp.with_name(f"{stem}.progress.{sid}.json")
    view = next(iter(model["views"].values()))
    prog = load(ppath, None)
    errs = progress_errors(prog, {n["id"] for n in view.get("nodes", [])}) if prog is not None else []
    live = (root / ".eli5" / "track" / f"{sid}.json").exists()
    at = (datetime.datetime.fromtimestamp(ppath.stat().st_mtime).astimezone().isoformat(timespec="seconds")
          if ppath.exists() else None)
    track = {"session": sid, "live": live, "touched": (load(tpath, {}) or {}).get("files", {}),
             "progress": None if errs else prog, "errors": errs, "progress_at": at}
    html = build_html({**model, "layout": layout.compute(view), "track": track},
                      str((model.get("meta") or {}).get("target") or stem) + " — 진행")
    if live:  # 추적 중에만 15초마다 다시 읽는다 (deadhd 방식)
        html = html.replace('<meta charset="utf-8">', '<meta charset="utf-8">\n<meta http-equiv="refresh" content="15">', 1)
    out = mp.with_name(f"{stem}.track.{sid}.html")
    write_atomic(out, html)
    print(json.dumps({"html": str(out), "live": live, "errors": errs}, ensure_ascii=False))
    return 0
```

`main()`: `ap.add_argument("--root", required=True)` 다음에 `ap.add_argument("--track", metavar="SESSION", help="추적 화면 — 세션 id")`. `"validation" not in model` 검사 블록 다음에 `if a.track:\n        return render_track(model, mp, root, a.track)`. 기존 payload·title·html 세 줄(주석 포함)을 `html = build_html(shown, meta.get("target") or stem_of(mp))` 로.

- [ ] **Step 4: track.py** — `skills/eli5/bin/track.py`:

```python
#!/usr/bin/env python3
"""eli5 작업 진행 추적 — 표식을 만들고, 훅이 수정된 파일을 박스에 기록하고, 추적 화면을 다시 그린다.

사용: track.py start --model <x.model.json> [--session <id>]   표식 생성 + 추적 화면 렌더
      track.py stop  --model <x.model.json> [--session <id>]   표식 삭제 + 마지막 렌더(자동 새로고침 끔)
      track.py touch                                            PostToolUse 훅 — stdin JSON 을 읽는다

세션 id 는 --session, 없으면 CLAUDE_CODE_SESSION_ID (훅 입력의 session_id 와 같다).
touch 는 어떤 경우에도 exit 0 — 훅 실패가 편집을 막으면 안 된다. 오류는 .eli5/track/<sid>.log 에 남긴다.
"""
import json
import os
import sys

TRACK = os.path.join(".eli5", "track")


def _marker_for(path, sid):
    """수정된 파일에서 위로 올라가며 이 세션의 표식을 찾는다 — git 명령 없이 stat 몇 번."""
    d = os.path.dirname(os.path.abspath(path))
    while True:
        m = os.path.join(d, TRACK, sid + ".json")
        if os.path.exists(m):
            return d, m
        parent = os.path.dirname(d)
        if parent == d:
            return None, None
        d = parent


def _stem(model):
    name = os.path.basename(model)
    return model[: -len(".model.json")] if name.endswith(".model.json") else os.path.splitext(model)[0]


def _write(path, data):
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
    os.replace(tmp, path)


def box_for(rel, view):
    """레포 상대 경로 → 잎 박스 id (paths 가 가장 길게 일치하는 것). 없으면 None."""
    groups = {n.get("group") for n in view.get("nodes", []) if n.get("group")}
    best, blen = None, -1
    for n in view.get("nodes", []):
        if n["id"] in groups:
            continue
        for pre in n.get("paths") or []:
            pre = pre.rstrip("/")
            if (rel == pre or rel.startswith(pre + "/")) and len(pre) > blen:
                best, blen = n["id"], len(pre)
    return best


def _render(model, root, sid):
    import subprocess
    here = os.path.dirname(os.path.abspath(__file__))
    subprocess.run([sys.executable, os.path.join(here, "render.py"), model, "--root", root, "--track", sid],
                   capture_output=True, timeout=30)


def touch(stdin_text, now):
    try:
        ev = json.loads(stdin_text or "{}")
    except ValueError:
        return
    sid = ev.get("session_id") or ""
    ti = ev.get("tool_input") or {}
    path = ti.get("file_path") or ti.get("notebook_path") or ""
    if not sid or not path:
        return
    root, marker = _marker_for(path, sid)
    if not marker:
        return  # 이 세션은 추적 중이 아니다 — 가장 흔한 경로, 여기서 바로 끝난다
    rel = os.path.relpath(os.path.abspath(path), root)
    if rel.split(os.sep)[0] == ".eli5":
        return
    log = os.path.join(root, TRACK, sid + ".log")
    try:
        with open(marker, encoding="utf-8") as f:
            model = json.load(f)["model"]
        with open(model, encoding="utf-8") as f:
            view = next(iter(json.load(f)["views"].values()))
        tpath = _stem(model) + ".touched." + sid + ".json"
        data = {"files": {}}
        if os.path.exists(tpath):
            with open(tpath, encoding="utf-8") as f:
                data = json.load(f)
        data["files"][rel] = {"box": box_for(rel, view), "at": now}
        _write(tpath, data)
        _render(model, root, sid)
    except Exception as e:  # noqa: BLE001 — 훅은 절대 실패하지 않는다
        with open(log, "a", encoding="utf-8") as f:
            f.write(f"{now} touch {rel}: {e!r}\n")


def _root_of(model):
    import subprocess
    r = subprocess.run(["git", "-C", os.path.dirname(os.path.abspath(model)), "rev-parse", "--show-toplevel"],
                       capture_output=True, text=True)
    return r.stdout.strip() if r.returncode == 0 else os.path.dirname(os.path.abspath(model))


def main(argv, now):
    import argparse
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    sub.add_parser("touch")
    for name in ("start", "stop"):
        p = sub.add_parser(name)
        p.add_argument("--model", required=True)
        p.add_argument("--session", default=os.environ.get("CLAUDE_CODE_SESSION_ID", ""))
    a = ap.parse_args(argv)
    if a.cmd == "touch":
        touch(sys.stdin.read(), now)
        return 0
    if not a.session:
        print("세션 id 가 없다 — --session 을 주거나 Claude Code 안에서 실행한다 (CLAUDE_CODE_SESSION_ID)", file=sys.stderr)
        return 2
    model = os.path.abspath(a.model)
    root = _root_of(model)
    os.makedirs(os.path.join(root, TRACK), exist_ok=True)
    marker = os.path.join(root, TRACK, a.session + ".json")
    if a.cmd == "start":
        _write(marker, {"model": model, "started_at": now})
    elif os.path.exists(marker):
        os.remove(marker)
    _render(model, root, a.session)
    print(f"{a.cmd}: {_stem(model)}.track.{a.session}.html")
    return 0


if __name__ == "__main__":
    import datetime
    sys.exit(main(sys.argv[1:], datetime.datetime.now().astimezone().isoformat(timespec="seconds")))
```

- [ ] **Step 5: 통과** — `bash tests/unit/test_eli5_track.sh && bash tests/unit/test_eli5_render.sh && /usr/bin/python3 -c "import ast; [ast.parse(open(f).read()) for f in ('skills/eli5/bin/track.py','skills/eli5/bin/render.py')]"`
- [ ] **Step 6: 커밋** — `feat(eli5): 작업 진행 추적 — 세션 표식, 훅 기록, 추적 화면 렌더`

---

### Task 2: 추적 화면

**Files:** Modify `skills/eli5/assets/map.html`, `tests/unit/test_eli5_render.sh`

- [ ] **Step 1: 실패 테스트** — render 테스트 `finish` 위에:

```bash
grep -q 'const TR = MODEL.track' "$TPL" && grep -q 'function trCard' "$TPL" && grep -q 'function trackbar' "$TPL" && grep -q 'eli5-track:' "$TPL" && grep -q '진행 상황으로' "$TPL" \
  && pass "추적 화면 — 진행 카드·머리 막대·박스 상태·새로 완료 반짝임·박스 카드에서 돌아가기" || fail "추적 화면"
```

- [ ] **Step 2: 실패 확인**
- [ ] **Step 3: 구현** — 다음 패치 스크립트를 `python3 <script> skills/eli5/assets/map.html` 로 적용:

```python
"""map.html 에 추적 화면을 넣는다 — Task 2 Step 3. 기준 문자열이 정확히 한 번 나와야 한다."""
import pathlib, sys
p = pathlib.Path(sys.argv[1]); s = p.read_text()

def rep(o, n):
    global s
    assert s.count(o) == 1, (o[:70], s.count(o)); s = s.replace(o, n)

# CSS
rep(".fdot{fill:currentColor;stroke:var(--box);stroke-width:1.5}\n", """.fdot{fill:currentColor;stroke:var(--box);stroke-width:1.5}
.node.t-now rect.bg,.frame.t-now .fbg{stroke:var(--record);stroke-width:3}
.node.t-done rect.bg,.frame.t-done .fbg{stroke:var(--graft);stroke-width:2.5}
.node.t-blocked rect.bg,.frame.t-blocked .fbg{stroke:var(--unknown);stroke-width:3}
.node.t-plan rect.bg,.frame.t-plan .fbg{stroke:var(--muted);stroke-width:2;stroke-dasharray:5 4}
.node.t-touched rect.bg{stroke:var(--accent);stroke-width:2}
.tmark{font-size:13px;font-weight:700}.tmark.done{fill:var(--graft)}.tmark.now{fill:var(--record)}.tmark.blocked{fill:var(--unknown)}.tmark.plan{fill:var(--muted)}
.tmark.touched{fill:var(--accent);font-size:11px;font-weight:600}.tagg{fill:var(--muted);font-size:11px}
.node.pop rect.bg{animation:pop 1.1s ease 2}@keyframes pop{50%{fill:var(--accent-soft)}}
@media (prefers-reduced-motion:reduce){.node.pop rect.bg{animation:none}}
.track{flex-basis:100%;font-size:13px;color:var(--fg)}.tbar{height:8px;border-radius:4px;background:var(--line);overflow:hidden;margin:6px 0 4px;max-width:420px}
.tbar i{display:block;height:100%;background:var(--graft)}
.card.t-now{border-color:var(--record)}.card.t-blocked{border-color:var(--unknown)}.card.t-done{opacity:.85}
""")

# 상태 계산 — FORK 정의 다음
rep("  const forks = id =>", """  // 작업 진행 (track.py 가 render --track 으로 넣는다) — 박스마다 가장 급한 상태, 고친 파일 수, 지도 밖 파일
  const TR = MODEL.track || null, PROG = TR && TR.progress;
  const RANK = {blocked: 4, now: 3, done: 2, plan: 1}, SNAME = {blocked: "막힘", now: "진행", done: "완료", plan: "남음"};
  const GLYPH = {blocked: "!", now: "▶", done: "✓", plan: "○"};
  const boxState = {}, touchedN = {}, outside = [];
  if (PROG) for (const it of PROG.items || []) for (const b of it.boxes || []) if (!boxState[b] || RANK[it.state] > RANK[boxState[b]]) boxState[b] = it.state;
  if (TR) for (const [f, r] of Object.entries(TR.touched || {})) { if (r.box) touchedN[r.box] = (touchedN[r.box] || 0) + 1; else outside.push(f); }
  const POP = new Set((() => {  // 새로 완료된 박스만 한 번 반짝인다 — 15초 새로고침 사이 직전 상태와 비교 (deadhd 방식)
    if (!PROG) return [];
    const key = "eli5-track:" + TR.session, done = Object.keys(boxState).filter(b => boxState[b] === "done");
    let prev = null;
    try { prev = JSON.parse(sessionStorage.getItem(key) || "null"); } catch (_) {}
    try { sessionStorage.setItem(key, JSON.stringify(done)); } catch (_) {}
    return prev ? done.filter(b => !prev.includes(b)) : [];
  })());
  const forks = id =>""")

# 묶음: 상태 테두리 + 안쪽 집계
rep('''const n = NODE[fid], g = el("g", {class: "frame" + (state.node === fid ? " sel" : "")''',
    '''const n = NODE[fid], g = el("g", {class: "frame" + (boxState[fid] ? " t-" + boxState[fid] : "") + (state.node === fid ? " sel" : "")''')
rep('''      if (FORK.has(fid)) el("text", {x: r[0] + r[2] - 16, y: r[1] + 22, class: "forkmark"}, g).textContent = "◆";
''', '''      if (FORK.has(fid)) el("text", {x: r[0] + r[2] - 16, y: r[1] + 22, class: "forkmark"}, g).textContent = "◆";
      if (TR) {
        const kids = KIDS[fid] || [], agg = ["blocked", "now", "done"].map(s => [s, kids.filter(c => boxState[c] === s).length]).filter(([, c]) => c);
        const t = kids.filter(c => touchedN[c]).length;
        const text = agg.map(([s, c]) => `${SNAME[s]} ${c}`).concat(t ? [`건드림 ${t}`] : []).join(" · ");
        if (text) el("text", {x: r[0] + r[2] - 34, y: r[1] + 22, "text-anchor": "end", class: "tagg"}, g).textContent = "안에서 " + text;
      }
''')

# 박스: 상태 테두리·표시
rep('''const g = el("g", {class: "node" + (state.node === n.id ? " sel" : "")''',
    '''const g = el("g", {class: "node" + (boxState[n.id] ? " t-" + boxState[n.id] : touchedN[n.id] ? " t-touched" : "") + (POP.has(n.id) ? " pop" : "") + (state.node === n.id ? " sel" : "")''')
rep('''      if (FORK.has(n.id)) el("text", {x: B[0] + B[2] - 16, y: B[1] + 20, class: "forkmark"}, g).textContent = "◆";
''', '''      if (FORK.has(n.id)) el("text", {x: B[0] + B[2] - 16, y: B[1] + 20, class: "forkmark"}, g).textContent = "◆";
      if (boxState[n.id]) el("text", {x: B[0] + B[2] - 12, y: B[1] + B[3] - 10, "text-anchor": "end", class: "tmark " + boxState[n.id]}, g).textContent = GLYPH[boxState[n.id]];
      if (touchedN[n.id]) el("text", {x: B[0] + B[2] - (boxState[n.id] ? 28 : 12), y: B[1] + B[3] - 10, "text-anchor": "end", class: "tmark touched"}, g).textContent = `● ${touchedN[n.id]}파일`;
''')

# 카드: 진행 상황 패널
rep('''    const mine = n ? new Set([n.id, ...(KIDS[n.id] || [])]) : null, S = !n && sc();
    $("side").classList.toggle("open", !!(n || S));
    document.body.classList.toggle("card-open", !!(n || S));
    if (S) { $("side").innerHTML = scCard(S); return; }''',
'''    const mine = n ? new Set([n.id, ...(KIDS[n.id] || [])]) : null, S = !n && sc(), P = !n && !S && TR;
    $("side").classList.toggle("open", !!(n || S || P));
    document.body.classList.toggle("card-open", !!(n || S || P));
    if (S) { $("side").innerHTML = scCard(S); return; }
    if (P) { $("side").innerHTML = trCard(); return; }''')
rep('''${state.sc ? `<p><button class="link" type="button" data-back>← 시나리오로</button></p>` : ""}''',
    '''${state.sc || TR ? `<p><button class="link" type="button" data-back>← ${state.sc ? "시나리오로" : "진행 상황으로"}</button></p>` : ""}''')
rep("  function forkHtml(id, taken) {", """  function trCard() {
    const meta = MODEL.meta || {};
    if (!PROG) return `<div class="k">작업 진행</div><h2>${esc(meta.target || "")}</h2>
      <p class="detail">${TR.errors.length ? "진행 파일에 오류가 있어 진행 상황을 뺐다 — 고친 파일 표시만 보인다." : "에이전트가 아직 진행 상황을 쓰지 않았다. 고친 파일은 지도에 파란 점으로 보인다."}</p>
      ${TR.errors.map(e => `<div class="conn"><span class="tag g-unknown">오류</span> ${esc(e)}</div>`).join("")}`;
    const card = (it, st) => `<div class="card t-${st}"><div class="t">${GLYPH[st]} ${esc(it.title || "")}</div>${it.body ? `<p>${esc(it.body)}</p>` : ""}
      ${(it.boxes || []).map(b => `<button class="link" type="button" data-sel="${esc(b)}">${esc(NODE[b] ? NODE[b].title : b)}</button>`).join(" · ")}
      <div>${(it.evidence || []).map(e => e.href ? `<a class="chip" href="${esc(e.href)}" target="_blank" rel="noopener">${esc(e.text || e.href)}</a>` : `<span class="chip">${esc(e.text || "")}</span>`).join("")}</div></div>`;
    const sec = (st, h) => { const xs = (PROG.items || []).filter(i => i.state === st); return xs.length ? `<h3>${h} ${xs.length}</h3>` + xs.map(it => card(it, st)).join("") : ""; };
    const task = PROG.task || {};
    return `<div class="k">작업 진행</div><h2>${esc(task.title || meta.target || "")}</h2>${task.goal ? `<p class="detail">${esc(task.goal)}</p>` : ""}
      ${task.doneWhen ? `<p class="detail">완료 조건: ${esc(task.doneWhen)}</p>` : ""}
      ${sec("blocked", "막힌 일")}${sec("now", "지금 하는 일")}${sec("done", "끝난 일")}${sec("plan", "남은 일")}
      ${PROG.footer ? `<p class="detail">${esc(PROG.footer)}</p>` : ""}`;
  }
  function trackbar() {
    const items = (PROG && PROG.items) || [], done = items.filter(i => i.state === "done").length;
    const ago = TR.progress_at ? Math.max(0, Math.round((Date.now() - Date.parse(TR.progress_at)) / 60000)) : null;
    const tally = ["blocked", "now", "done", "plan"].map(s => [s, items.filter(i => i.state === s).length]).filter(([, c]) => c).map(([s, c]) => `${SNAME[s]} ${c}`).join(" · ");
    $("scbar").innerHTML = `<div class="track"><b>작업 진행${PROG && PROG.task && PROG.task.title ? " — " + esc(PROG.task.title) : ""}</b>`
      + (items.length ? `<div class="tbar"><i style="width:${Math.round(done * 100 / items.length)}%"></i></div>${done}/${items.length} 완료 · ${tally}` : "")
      + (ago !== null ? ` · 에이전트 갱신 ${ago}분 전` : "")
      + (outside.length ? ` · <span class="tag g-unknown" title="${esc(outside.join("\\n"))}">지도 밖 변경 ${outside.length}파일</span>` : "")
      + (TR.errors.length ? ` · <span class="tag g-unknown">진행 파일 오류 ${TR.errors.length}</span>` : "")
      + (TR.live ? " · 15초마다 새로고침" : " · 추적 끝남") + `</div>`;
  }
  function forkHtml(id, taken) {""")

# 시작: 추적 화면이면 시나리오 대신 진행 상황
rep('''  if (SCS.length) play(s0 ? decodeURIComponent(s0[1]) : SCS[0].id, s0 ? (+s0[2] || 1) - 1 : 0);
  else scbar();''', '''  if (TR) { trackbar(); side(); }  // 추적 화면은 진행 상황이 먼저다 — 시나리오는 끈다
  else if (SCS.length) play(s0 ? decodeURIComponent(s0[1]) : SCS[0].id, s0 ? (+s0[2] || 1) - 1 : 0);
  else scbar();''')
p.write_text(s)
print("patched")
```

- [ ] **Step 4: 통과** — render·validate·track 테스트 0 failed
- [ ] **Step 5: 브라우저** — fixture 에 track start + 진행 파일(now·done·blocked 섞기, 같은 박스 두 항목) + 훅 2건(안쪽·지도 밖)으로 렌더해 확인: 카드 섹션 순서 막힘→진행→완료→남음, 박스 테두리·표시, 묶음 "안에서 …", 머리 막대·"지도 밖 변경", 박스 클릭 → "← 진행 상황으로", 진행 파일 없을 때 안내, 새로고침 태그
- [ ] **Step 6: 커밋** — `feat(eli5): 추적 화면 — 진행 카드, 박스 상태, 묶음 집계, 새로 완료 반짝임`

---

### Task 3: 훅 등록과 문서

- [ ] `hooks/hooks.json` 에 `"PostToolUse": [{"matcher": "Edit|Write|MultiEdit|NotebookEdit", "hooks": [{"type": "command", "command": "python3 -S \"${CLAUDE_PLUGIN_ROOT}/skills/eli5/bin/track.py\" touch", "timeout": 5}]}]`
- [ ] `lint.sh`·`test.sh` eli5 루프에 `track`
- [ ] SKILL.md 에 `## track` 절(시작·진행 파일 작성 규칙·끝), 인자 블록에 `/rakis:eli5 track [<model>]`·`track off`; help·CHANGELOG
- [ ] lint·test 통과, 커밋 `docs(eli5): 작업 진행 추적 — track 명령과 훅`

---

### Task 4: 실측

- [ ] 업무 지도로 이 세션에서 `track.py start`, 실제 훅 명령 문자열(hooks.json 그대로)에 이 세션 id·업무 레포 파일 경로를 담은 JSON 을 넣어 2~3건 기록(파일은 고치지 않는다), 진행 파일을 써서 화면 확인 → 20초 이내 반영(새로고침), 사용자 판정. 끝나면 `track.py stop`. 대상 레포 `git status` 무변경
