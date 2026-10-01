#!/usr/bin/env python3
"""eli5 Phase 0: graft 준비 + 생성물을 로컬 전용으로 숨긴다.

사용: graft_prep.py --root <레포 안의 경로> [--out-dir .eli5]
stdout JSON: {"graft": "ok|absent|index-built", "version": str|null, "root": str, "excluded": [...]}

업무 레포의 추적 파일을 바꾸지 않는다 — graft build 가 .gitignore 에 남긴 변경은 원복하고,
graft/ · .ignore · 출력 폴더는 .git/info/exclude 에만 올린다.
"""
import argparse
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

GRAFT_BIN = os.environ.get("ELI5_GRAFT_BIN", "graft")


def git(root, *args):
    return subprocess.run(["git", "-C", str(root), *args], capture_output=True, text=True)


def ensure_exclude(root, entries):
    p = git(root, "rev-parse", "--git-path", "info/exclude").stdout.strip()
    path = Path(p) if os.path.isabs(p) else Path(root) / p
    path.parent.mkdir(parents=True, exist_ok=True)
    have = path.read_text().splitlines() if path.exists() else []
    add = [e for e in dict.fromkeys(entries) if e not in have]
    if add:
        with path.open("a") as f:
            if have and have[-1] != "":
                f.write("\n")
            f.write("# rakis eli5 — 로컬 전용\n" + "\n".join(add) + "\n")
    return add


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", required=True)
    ap.add_argument("--out-dir", default=".eli5")
    a = ap.parse_args()
    top = git(a.root, "rev-parse", "--show-toplevel")
    if top.returncode != 0:
        print(json.dumps({"error": f"git 레포가 아니다: {a.root}"}, ensure_ascii=False))
        return 1
    root = Path(top.stdout.strip()).resolve()
    entries = []
    out_dir = (root / a.out_dir).resolve()
    if out_dir.is_relative_to(root) and out_dir != root:
        entries.append("/" + out_dir.relative_to(root).as_posix() + "/")

    exe = shutil.which(GRAFT_BIN)
    status, version = "absent", None
    if exe:
        r = subprocess.run([exe, "--version"], capture_output=True, text=True)
        version = r.stdout.strip() or None
        status = "ok"
        if not (root / "graft" / "INDEX.md").exists():
            before = {n: ((root / n).read_bytes() if (root / n).exists() else None) for n in (".gitignore", ".ignore")}
            r = subprocess.run([exe, "build", str(root)], capture_output=True, text=True)
            if r.returncode != 0:
                print(json.dumps({"error": "graft build 실패", "stderr": r.stderr[-2000:]}, ensure_ascii=False))
                return 1
            status = "index-built"
            gi = root / ".gitignore"
            if before[".gitignore"] is None:
                gi.unlink(missing_ok=True)
            else:
                gi.write_bytes(before[".gitignore"])
            if before[".ignore"] is not None:
                (root / ".ignore").write_bytes(before[".ignore"])
        if (root / "graft").exists() and git(root, "check-ignore", "-q", "graft/INDEX.md").returncode != 0:
            entries.append("/graft/")
        ign = root / ".ignore"
        if ign.exists() and git(root, "ls-files", "--error-unmatch", ".ignore").returncode != 0 \
                and git(root, "check-ignore", "-q", ".ignore").returncode != 0:
            entries.append("/.ignore")
    added = ensure_exclude(root, entries) if entries else []
    print(json.dumps({"graft": status, "version": version, "root": str(root), "excluded": added}, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main())
