#!/bin/bash
# meeting-digest 화자 분리 wrapper — 격리 venv의 pyannote를 호출.
#
# venv(~/.local/share/rakis/diarize-venv)가 없으면 exit 2 (setup 필요).
# 나머지 인자·exit code는 diarize.py 로 그대로 전달.
#
# Usage:
#   diarize.sh --audio X --transcript-json Y --out-dir Z [--num-speakers N]

set -e
HERE="$(cd "$(dirname "$0")" && pwd)"
VENV_PY="$HOME/.local/share/rakis/diarize-venv/bin/python"

if [ ! -x "$VENV_PY" ]; then
  echo "❌ diarize venv 없음 ($VENV_PY) — /rakis:setup 실행" >&2
  exit 2
fi

# MPS 미지원 연산은 CPU로 폴백 (크래시 대신)
export PYTORCH_ENABLE_MPS_FALLBACK=1

exec "$VENV_PY" "$HERE/diarize.py" "$@"
