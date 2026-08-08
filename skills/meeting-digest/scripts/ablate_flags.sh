#!/bin/bash
# meeting-digest transcribe.sh 억제 플래그 ablation
#
# production이 기본값에서 벗어난 플래그는 실질 3개:
#   condition_on_previous_text  False  (기본 True)
#   logprob_threshold           -0.5   (기본 -1.0)   ← 더 공격적
#   compression_ratio_threshold 2.0    (기본 2.4)    ← 더 공격적
# (no_speech_threshold 0.6 = 기본값, hallucination_silence_threshold는
#  word_timestamps=True 없이는 dead code — 둘 다 무효라 ablation 대상 아님)
#
# 목적: 환각 루프를 억제하면서 실제 발화를 가장 덜 버리는 조합 찾기
# Usage: ablate_flags.sh --audio <path> [--clip-secs 300] [--starts "600 2400 5400"]

set -u

CLIP_SECS=300
STARTS="600 2400 5400"
AUDIO=""
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OUT_DIR="$HOME/stt-ablate-out"
MODEL="mlx-community/whisper-large-v3-mlx"
PROMPT="다음은 한국어 IT 프로젝트 회의 녹음입니다. 에이전트, 아키텍처, 인터페이스, 파이프라인, 가드레일, 대시보드, API, 스웨거, 백로그, 스프린트 같은 기술 용어가 등장합니다."

while [ $# -gt 0 ]; do
  case "$1" in
    --audio)     AUDIO="$2"; shift 2 ;;
    --clip-secs) CLIP_SECS="$2"; shift 2 ;;
    --starts)    STARTS="$2"; shift 2 ;;
    --out-dir)   OUT_DIR="$2"; shift 2 ;;
    *) echo "unknown arg: $1" >&2; exit 1 ;;
  esac
done

[ -n "$AUDIO" ] && [ -f "$AUDIO" ] || { echo "❌ 오디오 없음: $AUDIO" >&2; exit 3; }
REP_PY="$SCRIPT_DIR/bench_repeat.py"
AF="highpass=f=80,afftdn=nf=-25,loudnorm=I=-16:TP=-1.5:LRA=11"
mkdir -p "$OUT_DIR"

# 구성: 이름|condition|logprob|compression
CONFIGS=(
  "prod(현행)|False|-0.5|2.0"
  "-logprob|False|-1.0|2.0"
  "-compression|False|-0.5|2.4"
  "-condition|True|-0.5|2.0"
  "condition만|False|-1.0|2.4"
  "default(전부기본)|True|-1.0|2.4"
)

echo "▶ 오디오: $AUDIO"
echo "▶ 구간: $STARTS (각 ${CLIP_SECS}s)"
echo

for START in $STARTS; do
  CLIP="$OUT_DIR/clip_$START.wav"
  [ -f "$CLIP" ] || ffmpeg -y -loglevel error -ss "$START" -t "$CLIP_SECS" -i "$AUDIO" \
    -af "$AF" -ar 16000 -ac 1 "$CLIP" </dev/null || exit 3
done

for START in $STARTS; do
  CLIP="$OUT_DIR/clip_$START.wav"
  echo "═══ 구간 ${START}s ═══"
  printf "%-20s %8s %9s %9s %11s\n" "구성" "글자수" "최장반복" "반복률%" "유효글자수"
  printf -- "------------------------------------------------------------\n"
  for cfg in "${CONFIGS[@]}"; do
    IFS='|' read -r name cond lp cr <<< "$cfg"
    d="$OUT_DIR/${START}_$(echo "$name" | tr -d '()가-힣' | tr -c 'a-zA-Z0-9-' '_')"
    mkdir -p "$d"
    if [ ! -f "$d/out.txt" ]; then
      mlx_whisper "$CLIP" --model "$MODEL" --language ko \
        --output-dir "$d" --output-name out --output-format txt \
        --initial-prompt "$PROMPT" \
        --condition-on-previous-text "$cond" \
        --logprob-threshold "$lp" \
        --compression-ratio-threshold "$cr" \
        --verbose False >/dev/null 2>&1
    fi
    if [ -f "$d/out.txt" ]; then
      read -r run rep uniq chars <<< "$(python3 "$REP_PY" "$d/out.txt")"
      eff=$(awk -v c="$chars" -v r="$rep" 'BEGIN{printf "%.0f", c*(1-r/100)}')
      printf "%-20s %8s %9s %9s %11s\n" "$name" "$chars" "x$run" "$rep" "$eff"
    else
      printf "%-20s %8s\n" "$name" "FAIL"
    fi
  done
  echo
done

echo "· 유효글자수 = 글자수 × (1 − 반복률). 환각을 제외한 실질 전사량 근사."
echo "· 최장반복 x3 이상이면 환각 루프 의심 — 유효글자수만 보고 고르지 말 것."
echo "· 출력 경로: $OUT_DIR"
