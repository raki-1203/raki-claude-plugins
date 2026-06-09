#!/bin/bash
# meeting-digest 전사 래퍼 — mlx-whisper 호출 (Apple Silicon 네이티브)
#
# Usage:
#   transcribe.sh --audio <path> --out-dir <dir> [--model large-v3] [--lang ko]
#
# --model: short name(large-v3, medium, small, base, tiny) 또는
#          full HF repo("org/repo"). short name은 mlx-community repo로 매핑.
#
# 출력:
#   <out-dir>/transcript.txt   (plain text)
#   <out-dir>/transcript.json  (segments + timestamps)
#   <out-dir>/transcript.srt   (자막)
#
# Exit codes:
#   0  성공
#   2  의존성 누락 (mlx_whisper)
#   3  오디오 파일 없음/읽기 실패
#   4  전사 실패

set -e

MODEL="large-v3"
LANG="ko"
AUDIO=""
OUT_DIR=""

while [ $# -gt 0 ]; do
  case "$1" in
    --audio)        AUDIO="$2"; shift 2 ;;
    --out-dir)      OUT_DIR="$2"; shift 2 ;;
    --model)        MODEL="$2"; shift 2 ;;
    --lang)         LANG="$2"; shift 2 ;;
    --compute-type) shift 2 ;;  # 하위호환: mlx에선 무의미, 무시
    *) echo "unknown arg: $1" >&2; exit 1 ;;
  esac
done

if [ -z "$AUDIO" ] || [ -z "$OUT_DIR" ]; then
  echo "usage: transcribe.sh --audio <path> --out-dir <dir> [--model X] [--lang Y]" >&2
  exit 1
fi

if ! command -v mlx_whisper >/dev/null 2>&1; then
  echo "❌ mlx_whisper 미설치 — /rakis:setup 실행" >&2
  exit 2
fi

if [ ! -f "$AUDIO" ]; then
  echo "❌ 오디오 파일 없음: $AUDIO" >&2
  exit 3
fi

# short name → mlx-community HF repo 매핑 ("/" 포함 시 직접 지정으로 간주)
case "$MODEL" in
  */*) REPO="$MODEL" ;;
  *)   REPO="mlx-community/whisper-${MODEL}-mlx" ;;
esac

mkdir -p "$OUT_DIR"

echo "▶ 전사 시작 (model=$MODEL → $REPO, lang=$LANG)"
echo "  오디오: $AUDIO"
echo "  출력:   $OUT_DIR"
echo "  (모델 첫 실행 시 HuggingFace에서 자동 다운로드 ~3GB 소요)"

# mlx_whisper는 --output-name 으로 출력 파일명을 직접 지정 → transcript.* 로 바로 생성
mlx_whisper \
  "$AUDIO" \
  --model "$REPO" \
  --language "$LANG" \
  --output-dir "$OUT_DIR" \
  --output-name transcript \
  --output-format all \
  --verbose False \
  || { echo "❌ 전사 실패" >&2; exit 4; }

if [ ! -f "$OUT_DIR/transcript.txt" ]; then
  echo "❌ transcript.txt 생성 실패" >&2
  exit 4
fi

WORD_COUNT=$(wc -w < "$OUT_DIR/transcript.txt" | tr -d ' ')
LINE_COUNT=$(wc -l < "$OUT_DIR/transcript.txt" | tr -d ' ')

echo "✓ 전사 완료: ${WORD_COUNT}단어 / ${LINE_COUNT}줄"
echo "  → $OUT_DIR/transcript.txt"
