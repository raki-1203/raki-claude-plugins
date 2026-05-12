#!/bin/bash
# meeting-digest 전사 래퍼 — whisper-ctranslate2 호출
#
# Usage:
#   transcribe.sh --audio <path> --out-dir <dir> [--model large-v3] [--lang ko] [--compute-type int8]
#
# 출력:
#   <out-dir>/transcript.txt   (plain text)
#   <out-dir>/transcript.json  (segments + timestamps)
#   <out-dir>/transcript.srt   (자막)
#
# Exit codes:
#   0  성공
#   2  의존성 누락 (whisper-ctranslate2)
#   3  오디오 파일 없음/읽기 실패
#   4  전사 실패

set -e

MODEL="large-v3"
LANG="ko"
COMPUTE_TYPE="int8"
AUDIO=""
OUT_DIR=""

while [ $# -gt 0 ]; do
  case "$1" in
    --audio)        AUDIO="$2"; shift 2 ;;
    --out-dir)      OUT_DIR="$2"; shift 2 ;;
    --model)        MODEL="$2"; shift 2 ;;
    --lang)         LANG="$2"; shift 2 ;;
    --compute-type) COMPUTE_TYPE="$2"; shift 2 ;;
    *) echo "unknown arg: $1" >&2; exit 1 ;;
  esac
done

if [ -z "$AUDIO" ] || [ -z "$OUT_DIR" ]; then
  echo "usage: transcribe.sh --audio <path> --out-dir <dir> [--model X] [--lang Y] [--compute-type Z]" >&2
  exit 1
fi

if ! command -v whisper-ctranslate2 >/dev/null 2>&1; then
  echo "❌ whisper-ctranslate2 미설치 — /rakis:setup 실행" >&2
  exit 2
fi

if [ ! -f "$AUDIO" ]; then
  echo "❌ 오디오 파일 없음: $AUDIO" >&2
  exit 3
fi

mkdir -p "$OUT_DIR"

echo "▶ 전사 시작 (model=$MODEL, lang=$LANG, compute=$COMPUTE_TYPE)"
echo "  오디오: $AUDIO"
echo "  출력:   $OUT_DIR"
echo "  (large-v3 첫 실행 시 모델 다운로드 ~3GB 소요)"

# whisper-ctranslate2는 입력 파일명을 기준으로 출력 파일을 만든다.
# 일관된 이름(transcript.*)을 위해 임시 디렉터리에 처리 후 rename.
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

AUDIO_BASE=$(basename "$AUDIO")
AUDIO_STEM="${AUDIO_BASE%.*}"

whisper-ctranslate2 \
  "$AUDIO" \
  --model "$MODEL" \
  --language "$LANG" \
  --compute_type "$COMPUTE_TYPE" \
  --output_dir "$TMP_DIR" \
  --output_format all \
  --verbose False \
  || { echo "❌ 전사 실패" >&2; exit 4; }

# 결과 파일을 transcript.* 로 정규화
for ext in txt json srt vtt tsv; do
  src="$TMP_DIR/$AUDIO_STEM.$ext"
  if [ -f "$src" ]; then
    cp "$src" "$OUT_DIR/transcript.$ext"
  fi
done

if [ ! -f "$OUT_DIR/transcript.txt" ]; then
  echo "❌ transcript.txt 생성 실패" >&2
  exit 4
fi

WORD_COUNT=$(wc -w < "$OUT_DIR/transcript.txt" | tr -d ' ')
LINE_COUNT=$(wc -l < "$OUT_DIR/transcript.txt" | tr -d ' ')

echo "✓ 전사 완료: ${WORD_COUNT}단어 / ${LINE_COUNT}줄"
echo "  → $OUT_DIR/transcript.txt"
