#!/usr/bin/env python3
"""eli5 지도 열기와 신선도 확인.

사용: open.py open <html> [--mode auto|orca|browser|print]
      open.py status --model <x.model.json> [--root <repo>]

열기 순서는 deadhd (MIT, Copyright (c) 2026 lcalmsky) skills/deadhd/open.sh 를 옮긴 것이다 —
Orca 안(ORCA_WORKTREE_ID)이면 Orca 탭, 실패하면 시스템 브라우저.
ELI5_OPEN_DRY=1 이면 브라우저를 실제로 띄우지 않고 명령만 출력한다 (테스트용).
"""
import argparse
import json
import os
import platform
import shutil
import subprocess
import sys
import urllib.parse
from pathlib import Path


def run(cmd):
    try:
        return subprocess.run(cmd, capture_output=True, timeout=15).returncode == 0
    except (OSError, subprocess.TimeoutExpired):
        return False


def open_browser(abs_path):
    dry = os.environ.get("ELI5_OPEN_DRY")
    cmds = []
    if platform.system() == "Darwin":
        cmds.append(["open", abs_path])
    if shutil.which("xdg-open"):
        cmds.append(["xdg-open", abs_path])
    for cmd in cmds:
        if dry:
            print("dry: " + " ".join(cmd))
            print(f"opened: browser {abs_path}")
            return
        if run(cmd):
            print(f"opened: browser {abs_path}")
            return
        print(f"skip: {cmd[0]} 실패", file=sys.stderr)
    print(f"opened: none {abs_path}")


def cmd_open(a):
    p = Path(a.html)
    if not p.is_file():
        print(f"no such file: {a.html}", file=sys.stderr)
        return 2
    abs_path = str(p.resolve())
    if a.mode == "print":
        print(f"opened: none {abs_path}")
        return 0
    if a.mode == "orca" or (a.mode == "auto" and os.environ.get("ORCA_WORKTREE_ID")):
        if not shutil.which("orca"):
            print("skip: orca 명령 없음", file=sys.stderr)
        elif run(["orca", "tab", "create", "--url", "file://" + urllib.parse.quote(abs_path), "--json"]):
            print(f"opened: orca-tab {abs_path}")
            return 0
        else:
            print("skip: orca tab create 실패", file=sys.stderr)
    open_browser(abs_path)
    return 0


def stem_of(p):
    return p.name[: -len(".model.json")] if p.name.endswith(".model.json") else p.stem


def map_status(model, root):
    html, sidecar = model.with_name(stem_of(model) + ".html"), model.with_name(stem_of(model) + ".eli5.json")
    if not html.exists():
        return "missing"
    try:
        sc = json.loads(sidecar.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return "unknown"
    if sc.get("version") != 1 or sc.get("dirty") or not sc.get("commit"):
        return "unknown"
    r = subprocess.run(["git", "-C", str(root), "diff", "--name-only", sc["commit"], "--", *(sc.get("scope") or ["."])],
                       capture_output=True, text=True)
    if r.returncode != 0:
        return "unknown"
    changed = [l for l in r.stdout.splitlines() if l and not l.startswith((".eli5/", "graft/"))]
    return "stale" if changed else "fresh"


def cmd_status(a):
    model = Path(a.model).resolve()
    if a.root:
        root = Path(a.root).resolve()
    else:
        r = subprocess.run(["git", "-C", str(model.parent), "rev-parse", "--show-toplevel"], capture_output=True, text=True)
        root = Path(r.stdout.strip()) if r.returncode == 0 else model.parent
    print(json.dumps({"map": map_status(model, root)}, ensure_ascii=False))
    return 0


def main():
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    o = sub.add_parser("open")
    o.add_argument("html")
    o.add_argument("--mode", choices=["auto", "orca", "browser", "print"], default="auto")
    s = sub.add_parser("status")
    s.add_argument("--model", required=True)
    s.add_argument("--root")
    a = ap.parse_args()
    return cmd_open(a) if a.cmd == "open" else cmd_status(a)


if __name__ == "__main__":
    sys.exit(main())
