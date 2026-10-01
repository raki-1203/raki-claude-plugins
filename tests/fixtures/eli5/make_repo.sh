#!/bin/bash
# 사용: make_repo.sh <dir> — eli5 테스트용 git 레포 생성
set -euo pipefail
d="$1"
mkdir -p "$d/src/api" "$d/src/core" "$d/docs"
cat > "$d/src/api/server.py" <<'PY'
from src.core.engine import run_job


def handle(req):
    return run_job(req["id"])
PY
cat > "$d/src/core/engine.py" <<'PY'
import requests


def run_job(job_id):
    requests.post("http://agent/run", json={"id": job_id})
    return job_id
PY
echo "# ADR-1 엔진은 HTTP 로 에이전트를 부른다" > "$d/docs/adr-1.md"
touch "$d/src/__init__.py" "$d/src/api/__init__.py" "$d/src/core/__init__.py"
git -C "$d" init -q
git -C "$d" -c user.email=t@t -c user.name=t add -A
git -C "$d" -c user.email=t@t -c user.name=t commit -qm init
