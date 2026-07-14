#!/bin/bash
# meeting-digest 화자 분리 wrapper — 격리 venv의 senko를 호출.
#
# venv(~/.local/share/rakis/diarize-venv)가 없으면 exit 2 (setup 필요).
# 나머지 인자·exit code는 diarize.py 로 그대로 전달.
#
# Usage:
#   diarize.sh --audio X --transcript-json Y --out-dir Z

set -e
HERE="$(cd "$(dirname "$0")" && pwd)"
VENV_PY="$HOME/.local/share/rakis/diarize-venv/bin/python"

if [ ! -x "$VENV_PY" ]; then
  echo "❌ diarize venv 없음 ($VENV_PY) — /rakis:setup 실행" >&2
  exit 2
fi

exec "$VENV_PY" "$HERE/diarize.py" "$@"
