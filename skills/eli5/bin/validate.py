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
        if v.get("parent") and v["parent"] not in views:
            errs.append(f"{vid}: parent '{v['parent']}' 없음")
        cells = {}
        for n in v.get("nodes", []):
            if n.get("drill") and n["drill"] not in views:
                errs.append(f"{vid}/{n['id']}: drill 대상 view '{n['drill']}' 없음")
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
    return errs


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
        drawn = {(e["from"], e["to"]) for e in v.get("edges", [])}
        for ed in data.get("edges", []):
            if ed.get("relation") != "calls":
                continue
            sp, tp = ed["source"].split("#")[0], ed["target"].split("#")[0]
            a = next((n["id"] for n in v.get("nodes", []) if under(sp, n.get("paths"))), None)
            b = next((n["id"] for n in v.get("nodes", []) if under(tp, n.get("paths"))), None)
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
    errs = integrity_errors(model) + v3_errors(model)
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
        nodes = {n["id"]: n for n in v.get("nodes", [])}
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
              "graft": a.graft_status, "quick": a.quick}
    model["validation"] = report
    mp.write_text(json.dumps(model, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(report, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
