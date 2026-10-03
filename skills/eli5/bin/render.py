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


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("model")
    ap.add_argument("--root", required=True)
    ap.add_argument("--track", metavar="SESSION", help="추적 화면 — 세션 id")
    a = ap.parse_args()
    mp, root = Path(a.model).resolve(), Path(a.root).resolve()
    model = json.loads(mp.read_text(encoding="utf-8"))
    if (model.get("meta") or {}).get("version") != 3:
        print(json.dumps({"error": "v3 지도가 아니다 (meta.version != 3) — v2 지도는 다시 만든다"}, ensure_ascii=False))
        return 1
    if "validation" not in model:
        print(json.dumps({"error": "validate.py 를 먼저 실행한다 (model.validation 없음)"}, ensure_ascii=False))
        return 1
    if a.track:
        return render_track(model, mp, root, a.track)
    meta = model.setdefault("meta", {})
    meta["commit"] = git(root, "rev-parse", "HEAD")
    meta["built_at"] = datetime.datetime.now().astimezone().isoformat(timespec="seconds")
    scope = meta.get("scope") or ["."]
    dirty = bool(git(root, "status", "--porcelain", "--", *scope))
    # 배치는 그릴 때만 필요하다 — 저장 모델에는 넣지 않고 HTML payload 에만 싣는다
    shown = {**model, "layout": layout.compute(next(iter(model["views"].values())))}
    html = build_html(shown, meta.get("target") or stem_of(mp))
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
