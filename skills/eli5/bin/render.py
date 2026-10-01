#!/usr/bin/env python3
"""eli5 지도 모델 → 단일 HTML + 사이드카.

사용: render.py <x.model.json> --root <repo>
출력: 같은 폴더의 <x>.html, <x>.eli5.json. LLM 은 HTML 을 직접 쓰지 않는다 — 모양은 모델로만 바꾼다.
"""
import argparse
import datetime
import json
import subprocess
import sys
from pathlib import Path

TEMPLATE = Path(__file__).resolve().parent.parent / "assets" / "map.html"


def git(root, *args):
    r = subprocess.run(["git", "-C", str(root), *args], capture_output=True, text=True)
    return r.stdout.strip() if r.returncode == 0 else ""


def stem_of(p):
    return p.name[: -len(".model.json")] if p.name.endswith(".model.json") else p.stem


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("model")
    ap.add_argument("--root", required=True)
    a = ap.parse_args()
    mp, root = Path(a.model).resolve(), Path(a.root).resolve()
    model = json.loads(mp.read_text(encoding="utf-8"))
    if "validation" not in model:
        print(json.dumps({"error": "validate.py 를 먼저 실행한다 (model.validation 없음)"}, ensure_ascii=False))
        return 1
    meta = model.setdefault("meta", {})
    meta["commit"] = git(root, "rev-parse", "HEAD")
    meta["built_at"] = datetime.datetime.now().astimezone().isoformat(timespec="seconds")
    scope = meta.get("scope") or ["."]
    dirty = bool(git(root, "status", "--porcelain", "--", *scope))
    payload = json.dumps(model, ensure_ascii=False).replace("</", "<\\/")
    title = str(meta.get("target") or stem_of(mp)).replace("&", "&amp;").replace("<", "&lt;")
    html = TEMPLATE.read_text(encoding="utf-8")
    html = html.replace("/*__ELI5_MODEL__*/null", payload, 1).replace("__ELI5_TITLE__", title, 1)
    out = mp.with_name(stem_of(mp) + ".html")
    out.write_text(html, encoding="utf-8")
    sidecar = mp.with_name(stem_of(mp) + ".eli5.json")
    sidecar.write_text(json.dumps({
        "version": 1, "commit": meta["commit"], "scope": scope, "dirty": dirty, "built_at": meta["built_at"],
        "graft_version": meta.get("graft_version"), "quick": bool(model["validation"].get("quick")),
    }, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    mp.write_text(json.dumps(model, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"html": str(out), "sidecar": str(sidecar)}, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main())
