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
