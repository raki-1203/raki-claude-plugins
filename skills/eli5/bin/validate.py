#!/usr/bin/env python3
"""eli5 지도 모델 결정적 검증기.

사용: validate.py <model.json> --root <repo> [--quick] [--graft-status ok|absent|index-built]
- 무결성 오류가 있으면 exit 1 — 모델은 건드리지 않는다
- 근거 등급을 판정하고 강등을 모델에 반영한다. 리포트는 model["validation"] 과 stdout 에 남긴다
- graft 판정은 공개 CLI(`graft callers --json`)로만 한다. wiring.json(내부 포맷)은 누락 탐지에만 쓴다
"""
import argparse
import json
import os
import re
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import plain  # noqa: E402
import layout  # noqa: E402

GRADES = ("graft", "code", "record", "unknown")
RULE_GRADES = ("code", "record", "unknown")
GRAFT_BIN = os.environ.get("ELI5_GRAFT_BIN", "graft")
SHA_RE = re.compile(r"^[0-9a-f]{7,40}$")
PR_RE = re.compile(r"^PR#\d+$")
MIN_QUOTE = 8  # 이보다 짧으면 어느 코드에나 있는 글자라 인용 대조가 무의미하다


def integrity_errors(model):
    views = model.get("views") or {}
    if not views:
        return ["views 가 비어 있다"]
    errs = []
    for vid, v in views.items():
        nodes = {n["id"]: n for n in v.get("nodes", [])}
        ifaces = {i["id"] for i in v.get("ifaces", [])}
        used = set()
        kids = layout.children(v)
        cells = {}
        for n in v.get("nodes", []):
            if n["id"] in kids:
                continue  # 묶음은 칸이 없다 — 테두리는 안쪽 박스로 계산한다
            row, col, span = n.get("row", 0), n.get("col", 0), n.get("span", 1)
            for c in range(col, col + span):
                if (row, c) in cells:
                    errs.append(f"{vid}: 격자 칸 ({row},{c}) 를 '{cells[(row, c)]}' 와 '{n['id']}' 가 겹쳐 쓴다")
                cells[(row, c)] = n["id"]
        for e in v.get("edges", []):
            name = f"{e.get('from')}→{e.get('to')}"
            for end in ("from", "to"):
                if e.get(end) not in nodes:
                    errs.append(f"{vid}: edge {name} 의 {end} 노드 없음")
            if e.get("grade") not in GRADES:
                errs.append(f"{vid}: edge {name} 등급 '{e.get('grade')}' 은 허용되지 않는다")
            if e.get("iface"):
                if e["iface"] not in ifaces:
                    errs.append(f"{vid}: edge {name} 의 iface '{e['iface']}' 없음")
                used.add(e["iface"])
        for i in sorted(ifaces - used):
            errs.append(f"{vid}: iface '{i}' 를 참조하는 edge 가 없다")
        for r in v.get("rules", []):
            if r.get("grade") not in RULE_GRADES:
                errs.append(f"{vid}: rule '{r.get('text')}' 등급 '{r.get('grade')}' — 규칙은 code/record/unknown 만 허용")
    return errs


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


def under(path, prefixes):
    for p in prefixes or []:
        p = p.rstrip("/")
        if path == p or path.startswith(p + "/"):
            return True
    return False


class Graft:
    def __init__(self, root, status):
        self.root, self.status, self.cache = root, status, {}

    def callers(self, to_sym):
        if to_sym not in self.cache:
            path, _, name = to_sym.partition("#")
            try:
                r = subprocess.run([GRAFT_BIN, "callers", name, "--in", path, "--json", str(self.root)],
                                   capture_output=True, text=True, timeout=60)
                data = json.loads(r.stdout or "{}")
            except (OSError, subprocess.TimeoutExpired, ValueError):
                data = {}
            hits = set()
            for m in data.get("matches", []):
                if (m.get("symbol") or {}).get("id") == to_sym:
                    hits.update(h.get("id") for h in m.get("hits", []))
            self.cache[to_sym] = hits
        return self.cache[to_sym]


def check_graft(ev, frm, to, graft):
    if graft.status != "ok":
        return False, "graft 없음"
    fs, ts = ev.get("from_sym", ""), ev.get("to_sym", "")
    if "#" not in fs or "#" not in ts:
        return False, "from_sym/to_sym 이 graft 노드 id 형식(path#symbol)이 아니다"
    if not under(fs.split("#")[0], frm.get("paths")):
        return False, f"{fs} 가 '{frm['id']}' 박스 paths 밖이다"
    if not under(ts.split("#")[0], to.get("paths")):
        return False, f"{ts} 가 '{to['id']}' 박스 paths 밖이다"
    if fs not in graft.callers(ts):
        return False, f"graft callers {ts} 에 {fs} 가 없다"
    return True, ""


def parse_ref(ref):
    path, sep, line = (ref or "").rpartition(":")
    if not sep or not path or not line.isdigit():
        return None, None
    return path, int(line)


def check_code(ev, root, quick):
    path, line = parse_ref(ev.get("ref"))
    if path is None:
        return False, f"ref '{ev.get('ref')}' 가 path:line 형식이 아니다"
    f = root / path
    if not f.is_file():
        return False, f"{path} 파일 없음"
    if quick:
        return True, ""
    quote = ev.get("quote") or ""
    if not quote:
        return False, "quote 없음"
    if len(quote.strip()) < MIN_QUOTE:
        return False, f"quote '{quote}' 가 너무 짧다 ({MIN_QUOTE}자 이상)"
    lines = f.read_text(encoding="utf-8", errors="replace").splitlines()
    window = "\n".join(lines[max(0, line - 3): line + 2])
    if quote not in window:
        return False, f"{path}:{line}±2 에 '{quote}' 없음"
    return True, ""


def check_record(ev, root):
    ref = (ev.get("ref") or "").strip()
    if not ref:
        return False, "ref 없음"
    if PR_RE.match(ref):
        return True, ""
    if SHA_RE.match(ref):
        r = subprocess.run(["git", "-C", str(root), "cat-file", "-e", ref + "^{commit}"], capture_output=True)
        return (True, "") if r.returncode == 0 else (False, f"커밋 {ref} 없음")
    path, line = parse_ref(ref)
    target = root / (path if path is not None else ref)
    return (True, "") if target.exists() else (False, f"{ref} 없음")


def judge(item, ctx):
    """등급을 판정하고 실패하면 강등한다. 강등했으면 기록 dict, 아니면 None."""
    grade, ev = item.get("grade"), item.get("evidence") or {}
    if grade == "graft":
        ok, why = check_graft(ev, ctx["from"], ctx["to"], ctx["graft"])
        if ok:
            return None
        if ev.get("ref"):
            ok2, why2 = check_code(ev, ctx["root"], ctx["quick"])
            if ok2:
                item["grade"] = "code"
                return {"claimed": "graft", "result": "code", "reason": why}
            why = f"{why}; code 판정도 실패: {why2}"
        item["grade"] = "unknown"
        return {"claimed": "graft", "result": "unknown", "reason": why}
    if grade == "code":
        ok, why = check_code(ev, ctx["root"], ctx["quick"])
    elif grade == "record":
        ok, why = check_record(ev, ctx["root"])
    else:
        return None
    if ok:
        return None
    item["grade"] = "unknown"
    return {"claimed": grade, "result": "unknown", "reason": why}


def missing_edges(model, root):
    wiring = root / "graft" / ".graph" / "wiring.json"
    if not wiring.is_file():
        return [], "wiring.json 없음 — 누락 탐지 건너뜀"
    try:
        data = json.loads(wiring.read_text(encoding="utf-8"))
    except ValueError:
        return [], "wiring.json 파싱 실패 — 누락 탐지 건너뜀"
    ver = (data.get("meta") or {}).get("version")
    if ver != 1:
        return [], f"wiring.json 버전 {ver} 미지원 — 누락 탐지 건너뜀"
    out, seen = [], set()
    for vid, v in model["views"].items():
        kids = layout.children(v)
        expand = lambda i: [i, *kids.get(i, [])]  # 묶음 끝 화살표는 안쪽 박스 모두의 화살표로 친다
        drawn = {(a, b) for e in v.get("edges", []) for a in expand(e["from"]) for b in expand(e["to"])}
        leaves = [n for n in v.get("nodes", []) if n["id"] not in kids]
        for ed in data.get("edges", []):
            if ed.get("relation") != "calls":
                continue
            sp, tp = ed["source"].split("#")[0], ed["target"].split("#")[0]
            a = next((n["id"] for n in leaves if under(sp, n.get("paths"))), None)
            b = next((n["id"] for n in leaves if under(tp, n.get("paths"))), None)
            if a and b and a != b and (a, b) not in drawn and (vid, a, b) not in seen:
                seen.add((vid, a, b))
                out.append({"view": vid, "from": a, "to": b, "example": f"{ed['source']} → {ed['target']}"})
    return out, ""


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("model")
    ap.add_argument("--root", required=True)
    ap.add_argument("--quick", action="store_true")
    ap.add_argument("--graft-status", choices=["ok", "absent", "index-built"], default="ok")
    a = ap.parse_args()
    mp, root = Path(a.model), Path(a.root).resolve()
    model = json.loads(mp.read_text(encoding="utf-8"))
    errs = integrity_errors(model) + v3_errors(model) + branch_errors(model)
    if not errs:  # 시나리오는 지도가 맞을 때만 판정한다
        errs = scenario_errors(model)
    if errs:
        print(json.dumps({"integrity_errors": errs}, ensure_ascii=False, indent=2))
        return 1
    graft = Graft(root, "absent" if a.graft_status == "absent" else "ok")
    unknowns = model.setdefault("unknowns", [])

    def note_unknown(text, why):
        if not any(u.get("text") == text for u in unknowns):
            unknowns.append({"text": text, "why": why})

    downgrades = []
    for vid, v in model["views"].items():
        nodes = effective_nodes(v)
        for e in v.get("edges", []):
            # 사람이 읽는 목록("확인 못 한 것")에 들어가므로 id 가 아니라 이름으로 쓴다
            label = (f"{v.get('title') or vid}: {nodes[e['from']].get('title') or e['from']} → {nodes[e['to']].get('title') or e['to']}"
                     + (f" ({e['label']})" if e.get("label") else ""))
            d = judge(e, {"from": nodes[e["from"]], "to": nodes[e["to"]], "graft": graft, "root": root, "quick": a.quick})
            if d:
                downgrades.append({"view": vid, "kind": "edge", "id": label, **d})
            if e["grade"] == "unknown":
                note_unknown(label, d["reason"] if d else "근거 없음")
        for r in v.get("rules", []):
            label = f"{v.get('title') or vid}: 규칙 — {r.get('text')}"
            d = judge(r, {"root": root, "quick": a.quick})
            if d:
                downgrades.append({"view": vid, "kind": "rule", "id": label, **d})
            if r["grade"] == "unknown":
                note_unknown(label, d["reason"] if d else "근거 없음")
    counts = {g: 0 for g in GRADES}
    for v in model["views"].values():
        for it in v.get("edges", []) + v.get("rules", []):
            counts[it["grade"]] += 1
    missing, skipped = missing_edges(model, root)
    report = {"counts": counts, "downgrades": downgrades, "integrity_errors": [],
              "missing_edges": missing, "missing_edges_skipped": skipped,
              "graft": a.graft_status, "quick": a.quick, "scenarios": scenario_report(model, root, a.quick), "branches": branch_report(model, root, a.quick)}
    model["validation"] = report
    mp.write_text(json.dumps(model, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(report, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
