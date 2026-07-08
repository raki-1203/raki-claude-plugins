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
PREPROCESS=1                # ffmpeg 음질 전처리(정규화+디노이즈) on/off
# 도메인 용어 힌트(초기 프롬프트). far-field·저음량에서 고유명사 오인식을 줄임.
# 회의별 용어는 meeting-digest 스킬이 --prompt 로 덮어씀.
PROMPT="다음은 한국어 IT 프로젝트 회의 녹음입니다. 에이전트, 아키텍처, 인터페이스, 파이프라인, 가드레일, 대시보드, API, 스웨거, 백로그, 스프린트 같은 기술 용어가 등장합니다."

while [ $# -gt 0 ]; do
  case "$1" in
    --audio)        AUDIO="$2"; shift 2 ;;
    --out-dir)      OUT_DIR="$2"; shift 2 ;;
    --model)        MODEL="$2"; shift 2 ;;
    --lang)         LANG="$2"; shift 2 ;;
    --prompt)       PROMPT="$2"; shift 2 ;;   # 도메인 용어 힌트 덮어쓰기
    --no-preprocess) PREPROCESS=0; shift ;;   # 전처리 건너뛰고 원본 그대로 전사
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

# ── 음질 전처리 (far-field·저음량 회의 녹음 대응) ─────────────────────
# mlx_whisper는 VAD 필터가 없어(=faster-whisper 전용), 무음/저SNR 구간에서
# hallucination(반복·유튜브 자막 클리셰)이 잘 터진다. ffmpeg로 저역잡음 제거
# + FFT 디노이즈 + EBU R128 음량 정규화 후 16kHz mono로 넘겨 SNR을 끌어올린다.
# (silenceremove로 무음 삭제 시 타임스탬프가 깨지므로 쓰지 않음 → SRT 유지)
INPUT="$AUDIO"
if [ "$PREPROCESS" = "1" ]; then
  if command -v ffmpeg >/dev/null 2>&1; then
    PREP="$OUT_DIR/audio.prep.wav"
    echo "▶ 음질 전처리 (highpass+afftdn+loudnorm → 16kHz mono)"
    if ffmpeg -hide_banner -loglevel error -y -i "$AUDIO" \
         -af "highpass=f=80,afftdn=nf=-25,loudnorm=I=-16:TP=-1.5:LRA=11" \
         -ar 16000 -ac 1 "$PREP" && [ -f "$PREP" ]; then
      INPUT="$PREP"
      echo "  ✓ 전처리 완료 → $PREP"
    else
      echo "  ⚠ 전처리 실패 — 원본으로 진행" >&2
    fi
  else
    echo "  ⚠ ffmpeg 없음 — 전처리 건너뜀(원본으로 진행)" >&2
  fi
fi

echo "▶ 전사 시작 (model=$MODEL → $REPO, lang=$LANG)"
echo "  입력:   $INPUT"
echo "  출력:   $OUT_DIR"
echo "  (모델 첫 실행 시 HuggingFace에서 자동 다운로드 ~3GB 소요)"

# mlx_whisper는 --output-name 으로 출력 파일명을 직접 지정 → transcript.* 로 바로 생성
#
# 무음 구간 hallucination(같은 문구 무한 반복) stuck-loop 방지 옵션:
#   --condition-on-previous-text False : 이전 출력에 condition 안 해 반복 전파 차단
#   --hallucination-silence-threshold 2 : 무음 2초↑ 구간의 hallucination 억제
#   --no-speech-threshold 0.6 / --compression-ratio-threshold 2.0 : 무음/반복 세그먼트 컷
# (긴 회의·발화 드문 녹음에서 1문장 무한반복으로 전사가 통째로 손상되는 것을 막음)
# --initial-prompt : 도메인 용어 힌트로 고유명사 오인식 완화
# --logprob-threshold -0.5 : 저확신(웅얼거림·잡음) 세그먼트를 hallucination으로 컷
#   (기본 -1.0보다 공격적 — far-field 녹음의 환각 세그먼트 억제)
mlx_whisper \
  "$INPUT" \
  --model "$REPO" \
  --language "$LANG" \
  --output-dir "$OUT_DIR" \
  --output-name transcript \
  --output-format all \
  --initial-prompt "$PROMPT" \
  --condition-on-previous-text False \
  --hallucination-silence-threshold 2 \
  --no-speech-threshold 0.6 \
  --logprob-threshold -0.5 \
  --compression-ratio-threshold 2.0 \
  --verbose False \
  || { echo "❌ 전사 실패" >&2; exit 4; }

# 전처리 중간 산출물 정리 (raw/ 오염 방지)
[ -f "$OUT_DIR/audio.prep.wav" ] && rm -f "$OUT_DIR/audio.prep.wav"

if [ ! -f "$OUT_DIR/transcript.txt" ]; then
  echo "❌ transcript.txt 생성 실패" >&2
  exit 4
fi

WORD_COUNT=$(wc -w < "$OUT_DIR/transcript.txt" | tr -d ' ')
LINE_COUNT=$(wc -l < "$OUT_DIR/transcript.txt" | tr -d ' ')

echo "✓ 전사 완료: ${WORD_COUNT}단어 / ${LINE_COUNT}줄"
echo "  → $OUT_DIR/transcript.txt"
