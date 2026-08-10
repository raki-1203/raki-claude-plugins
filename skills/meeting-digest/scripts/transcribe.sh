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
# 무음 구간 hallucination(같은 문구 무한 반복) stuck-loop 방지 옵션.
# ablate_flags.sh로 회의 3건 × 8구간 × 300초를 측정한 결과다
# (2026-06-17 상품수익성 워크샵 3구간 / 2026-06-12 상담지원 워크샵 3구간 /
#  2026-08-07 자체 스프린트 리뷰 2구간).
#
#   --condition-on-previous-text False   ← 근거 강함, 건드리지 말 것
#     이전 출력에 condition 안 해 반복 전파 차단. True로 되돌리면 **8구간 전부**
#     붕괴한다(반복률 100%). 최악 사례는 스프린트리뷰 5분 지점의 최장반복 x873,
#     4282자 전부 환각.
#
#   --logprob-threshold -0.5 (기본 -1.0보다 공격적)   ← 근거 약함
#     저확신(웅얼거림·잡음) 세그먼트를 hallucination으로 컷.
#     ⚠️ 회의마다 갈린다. 2026-06-17 회의에서는 -1.0으로 되돌리면 붕괴했으나
#     (10분 지점 x3 → x55, 90분 지점 x2 → x55) **다른 회의 2건에서는 재현되지
#     않았다** — 5구간 중 3구간에서 오히려 기본 -1.0이 근소 우위였다.
#     현재 값은 "1건에서 관찰된 효과"일 뿐이므로 일반 사실로 인용하지 말 것.
#     바꾸려면 표본을 더 늘려 판단한다.
#
#   --initial-prompt : 도메인 용어 힌트로 고유명사 오인식 완화.
#     회의 3건 8구간에서 프롬프트 문자열이 전사문으로 유출된 사례 0건.
#     (참고: Qwen3-ASR의 대응 기능 `--context`는 8구간 중 2구간에서 유출됐다)
#
# ⚠️ 제거한 플래그 3개 — 전부 무효였다. 되살리지 말 것:
#   --no-speech-threshold 0.6          기본값과 동일 → no-op
#   --compression-ratio-threshold 2.0  2.4(기본)와 3구간 출력 완전 동일 → no-op
#   --hallucination-silence-threshold 2
#       mlx_whisper transcribe.py의 `if word_timestamps:` 블록 안에 있어
#       --word-timestamps True 없이는 dead code. 살리려면 word-timestamps를
#       함께 켜야 하는데, 그건 전사 시간을 늘리고 화자분리 깜빡임도 개선하지
#       못했다(2026-08-07 실측, 롤백됨).
#
# 트레이드오프 주의: 위 옵션들은 환각을 막는 대신 어려운 far-field 구간의 실제
# 발화도 함께 버린다. 완화해서 되찾는 건 안 된다 — condition을 되돌리면 환각이
# 폭증하고, logprob은 회의에 따라 효과가 없다.
#
# ⚠️ 그리고 이 설정으로도 회의에 따라 크게 깨진다. 2026-06-12·2026-08-07 회의
# 5구간 중 4구간에서 반복률 38~100%가 나왔다(최악: 반복률 100%, `한국어 자막을
# 통해` ×44 같은 유튜브 자막 클리셰 루프). 내용 보존이 중요하면 엔진 교체가
# 답이다 — 같은 5구간에서 Qwen3-ASR-1.7B가 유효 전사량 +143%였다.
# bench_stt.sh 참고.
mlx_whisper \
  "$INPUT" \
  --model "$REPO" \
  --language "$LANG" \
  --output-dir "$OUT_DIR" \
  --output-name transcript \
  --output-format all \
  --initial-prompt "$PROMPT" \
  --condition-on-previous-text False \
  --logprob-threshold -0.5 \
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
