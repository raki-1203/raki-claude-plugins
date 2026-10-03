#!/usr/bin/env python3
"""eli5 지도 모델 → 단일 HTML + 사이드카.

사용: render.py <x.model.json> --root <repo>
출력: 같은 폴더의 <x>.html, <x>.eli5.json. LLM 은 HTML 을 직접 쓰지 않는다 — 모양은 모델로만 바꾼다.
"""
import argparse
import datetime
import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path

TEMPLATE = Path(__file__).resolve().parent.parent / "assets" / "map.html"
sys.path.insert(0, str(Path(__file__).resolve().parent))
import layout  # noqa: E402


def git(root, *args):
    r = subprocess.run(["git", "-C", str(root), *args], capture_output=True, text=True)
    return r.stdout.strip() if r.returncode == 0 else ""


def stem_of(p):
    return p.name[: -len(".model.json")] if p.name.endswith(".model.json") else p.stem


def write_atomic(path, text):
    """임시 파일에 다 쓴 뒤 교체한다 — 읽는 쪽이 반쯤 쓰인 파일을 보지 않게.
    deadhd (MIT, Copyright (c) 2026 lcalmsky) render.py 의 mkstemp → os.replace 방식."""
    path = Path(path)
    fd, tmp = tempfile.mkstemp(dir=str(path.parent), prefix="." + path.name + ".", suffix=".tmp")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            f.write(text)
        os.replace(tmp, path)
    except BaseException:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("model")
    ap.add_argument("--root", required=True)
    a = ap.parse_args()
    mp, root = Path(a.model).resolve(), Path(a.root).resolve()
    model = json.loads(mp.read_text(encoding="utf-8"))
    if (model.get("meta") or {}).get("version") != 3:
        print(json.dumps({"error": "v3 지도가 아니다 (meta.version != 3) — v2 지도는 다시 만든다"}, ensure_ascii=False))
        return 1
    if "validation" not in model:
        print(json.dumps({"error": "validate.py 를 먼저 실행한다 (model.validation 없음)"}, ensure_ascii=False))
        return 1
    meta = model.setdefault("meta", {})
    meta["commit"] = git(root, "rev-parse", "HEAD")
    meta["built_at"] = datetime.datetime.now().astimezone().isoformat(timespec="seconds")
    scope = meta.get("scope") or ["."]
    dirty = bool(git(root, "status", "--porcelain", "--", *scope))
    # 배치는 그릴 때만 필요하다 — 저장 모델에는 넣지 않고 HTML payload 에만 싣는다
    shown = {**model, "layout": layout.compute(next(iter(model["views"].values())))}
    # 데이터 안의 문자열이 script 블록을 닫거나(</) HTML 주석을 열지(<!--) 못하게 한다. 둘 다 JS 문자열 이스케이프라 값은 그대로다.
    payload = json.dumps(shown, ensure_ascii=False).replace("</", "<\\/").replace("<!--", "<\\u0021--")
    title = str(meta.get("target") or stem_of(mp)).replace("&", "&amp;").replace("<", "&lt;")
    html = TEMPLATE.read_text(encoding="utf-8")
    html = html.replace("/*__ELI5_MODEL__*/null", payload, 1).replace("__ELI5_TITLE__", title, 1)
    out = mp.with_name(stem_of(mp) + ".html")
    write_atomic(out, html)
    sidecar = mp.with_name(stem_of(mp) + ".eli5.json")
    write_atomic(sidecar, json.dumps({
        "version": 1, "commit": meta["commit"], "scope": scope, "dirty": dirty, "built_at": meta["built_at"],
        "graft_version": meta.get("graft_version"), "quick": bool(model["validation"].get("quick")),
    }, ensure_ascii=False, indent=2) + "\n")
    write_atomic(mp, json.dumps(model, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps({"html": str(out), "sidecar": str(sidecar)}, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main())
