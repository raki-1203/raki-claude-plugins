#!/bin/bash
# meeting-digest STT 벤치 — 현행 mlx-whisper large-v3 vs Qwen3-ASR (M4 Pro)
#
#   1) mlx-whisper large-v3      (현행 스킬 = pseudo-reference)
#   2) Qwen3-ASR-1.7B
#   3) Qwen3-ASR-0.6B
#
# 공정성:
#   - transcribe.sh와 동일한 ffmpeg 전처리(highpass+afftdn+loudnorm)를 클립에 1회 적용
#   - 세 엔진 모두 같은 wav를 입력받음
#   - 모델 다운로드/Metal 커널 컴파일은 워밍업으로 분리
#   - 도메인 용어 힌트를 양쪽에 동등하게 투입(whisper: --initial-prompt, qwen: --context)
#
# 측정: wall-clock, RTF, 실시간배속, peak RAM, 기준 대비 CER, 반복(환각) 지표
#
# Usage: bench_qwen3.sh --audio <path> [--clip-secs 300] [--start-secs 600] [--out-dir <dir>]

set -u

CLIP_SECS=300
START_SECS=600
WARMUP_SECS=10
AUDIO=""
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OUT_DIR="$HOME/stt-bench-out"
QVENV="/tmp/.qwen3-bench-venv"

while [ $# -gt 0 ]; do
  case "$1" in
    --audio)      AUDIO="$2"; shift 2 ;;
    --clip-secs)  CLIP_SECS="$2"; shift 2 ;;
    --start-secs) START_SECS="$2"; shift 2 ;;
    --out-dir)    OUT_DIR="$2"; shift 2 ;;
    *) echo "unknown arg: $1" >&2; exit 1 ;;
  esac
done

CER_PY="$SCRIPT_DIR/bench_cer.py"
REP_PY="$SCRIPT_DIR/bench_repeat.py"
QWEN="$QVENV/bin/mlx-qwen3-asr"

# 도메인 용어 힌트 — transcribe.sh의 기본 PROMPT와 같은 취지
WPROMPT="다음은 한국어 IT 프로젝트 회의 녹음입니다. 에이전트, 아키텍처, 인터페이스, 파이프라인, 가드레일, 대시보드, API, 스웨거, 백로그, 스프린트 같은 기술 용어가 등장합니다."
QCONTEXT="에이전트 아키텍처 인터페이스 파이프라인 가드레일 대시보드 API 스웨거 백로그 스프린트 국민카드 상품수익성"

# 사내망 TLS 가로채기 대응 — 번들이 있을 때만 export (셸 전역 설정 아님)
if [ -f "$HOME/.config/rakis/corp-ca-bundle.pem" ]; then
  export SSL_CERT_FILE="$HOME/.config/rakis/corp-ca-bundle.pem"
  export REQUESTS_CA_BUNDLE="$SSL_CERT_FILE"
fi

for c in ffmpeg ffprobe mlx_whisper; do
  command -v "$c" >/dev/null 2>&1 || { echo "❌ 필요 도구 없음: $c" >&2; exit 2; }
done
# Qwen3-ASR은 벤치 전용이라 스킬 의존성에 넣지 않고 격리 venv에 설치한다.
# (mlx-qwen3-asr은 torch/transformers를 안 끌어온다 — mlx+numpy+regex+hf-hub만)
if [ ! -x "$QWEN" ]; then
  command -v uv >/dev/null 2>&1 || { echo "❌ uv 없음 — /rakis:setup 실행" >&2; exit 2; }
  echo "▶ mlx-qwen3-asr 격리 설치 ($QVENV)"
  uv venv "$QVENV" --python 3.11 >/dev/null 2>&1
  uv pip install --python "$QVENV" mlx-qwen3-asr >/dev/null 2>&1 \
    || { echo "❌ mlx-qwen3-asr 설치 실패 (사내망이면 corp-ca-bundle.pem 확인)" >&2; exit 2; }
fi
[ -n "$AUDIO" ] && [ -f "$AUDIO" ] || { echo "❌ 오디오 없음: $AUDIO" >&2; exit 3; }

mkdir -p "$OUT_DIR"

# ---- 클립 추출 (production과 동일 전처리) -------------------------------
CLIP="$OUT_DIR/clip.wav"
WARM="$OUT_DIR/warmup.wav"
AF="highpass=f=80,afftdn=nf=-25,loudnorm=I=-16:TP=-1.5:LRA=11"
echo "▶ 클립 추출 (${START_SECS}s부터 ${CLIP_SECS}s, 전처리 적용)"
ffmpeg -y -loglevel error -ss "$START_SECS" -t "$CLIP_SECS" -i "$AUDIO" \
  -af "$AF" -ar 16000 -ac 1 "$CLIP" </dev/null || exit 3
ffmpeg -y -loglevel error -ss "$START_SECS" -t "$WARMUP_SECS" -i "$AUDIO" \
  -af "$AF" -ar 16000 -ac 1 "$WARM" </dev/null || exit 3
DUR=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$CLIP")
echo "▶ 오디오: $AUDIO"
echo "▶ 클립 길이: ${DUR}s"
echo

# ---- 엔진 명령 ----------------------------------------------------------
build_cmd() {  # $1=engine $2=audio $3=outdir
  local engine="$1" audio="$2" out="$3"
  case "$engine" in
    mlxv3)
      CMD=(mlx_whisper "$audio" --model mlx-community/whisper-large-v3-mlx
           --language ko --output-dir "$out" --output-name out --output-format txt
           --initial-prompt "$WPROMPT"
           --condition-on-previous-text False --hallucination-silence-threshold 2
           --no-speech-threshold 0.6 --logprob-threshold -0.5
           --compression-ratio-threshold 2.0 --verbose False) ;;
    qwen17)
      CMD=("$QWEN" "$audio" --model Qwen/Qwen3-ASR-1.7B --language ko
           --context "$QCONTEXT" --output-dir "$out" -f txt --no-progress --quiet) ;;
    qwen06)
      CMD=("$QWEN" "$audio" --model Qwen/Qwen3-ASR-0.6B --language ko
           --context "$QCONTEXT" --output-dir "$out" -f txt --no-progress --quiet) ;;
  esac
}

parse_real() { grep -E '[0-9.]+ real' "$1" | tail -1 | awk '{print $1}'; }
parse_rss()  { grep 'maximum resident set size' "$1" | tail -1 | awk '{printf "%.0f", $1/1048576}'; }

declare -a R_NAME R_REAL R_RTF R_SPEED R_RSS R_TXT
run_engine() {  # $1=표시명 $2=서브디렉터리 $3=출력txt명 $4=engine_id
  local name="$1" sub="$2" txtbase="$3" engine="$4"
  local d="$OUT_DIR/$sub"; mkdir -p "$d"
  local tlog="$OUT_DIR/$sub.time"

  printf "  · %-24s 워밍업..." "$name"
  build_cmd "$engine" "$WARM" "$d"
  "${CMD[@]}" >/dev/null 2>&1
  printf " 측정..."
  build_cmd "$engine" "$CLIP" "$d"
  /usr/bin/time -l "${CMD[@]}" >"$tlog.out" 2>"$tlog"
  local rc=$?

  local txt="$d/$txtbase" real rss rtf speed
  real=$(parse_real "$tlog"); rss=$(parse_rss "$tlog")
  if [ $rc -ne 0 ] || [ -z "$real" ] || [ ! -f "$txt" ]; then
    R_NAME+=("$name"); R_REAL+=("FAIL"); R_RTF+=("-"); R_SPEED+=("-")
    R_RSS+=("${rss:-?}"); R_TXT+=("$txt")
    echo " ⚠ 실패 (rc=$rc, 로그: $tlog)"; return
  fi
  rtf=$(awk -v r="$real" -v d="$DUR" 'BEGIN{printf "%.3f", r/d}')
  speed=$(awk -v r="$real" -v d="$DUR" 'BEGIN{printf "%.1f", d/r}')
  R_NAME+=("$name"); R_REAL+=("$real"); R_RTF+=("$rtf"); R_SPEED+=("$speed")
  R_RSS+=("$rss"); R_TXT+=("$txt")
  echo " ${real}s"
}

echo "▶ 전사 실행 (3개 구성)"
run_engine "mlx-whisper large-v3" mlxv3  "out.txt"  mlxv3
run_engine "Qwen3-ASR-1.7B"       qwen17 "clip.txt" qwen17
run_engine "Qwen3-ASR-0.6B"       qwen06 "clip.txt" qwen06
echo

# ---- CER (mlx-whisper large-v3 = 기준) + 반복 지표 ----------------------
REF="${R_TXT[0]}"
declare -a R_CER R_REP
for i in 0 1 2; do
  hyp="${R_TXT[$i]}"
  if [ "$i" -eq 0 ]; then
    R_CER+=("기준")
  elif [ -f "$REF" ] && [ -f "$hyp" ]; then
    R_CER+=("$(python3 "$CER_PY" "$REF" "$hyp" 2>/dev/null | awk '{print $1"%"}')")
  else
    R_CER+=("-")
  fi
  if [ -f "$hyp" ]; then
    R_REP+=("$(python3 "$REP_PY" "$hyp" 2>/dev/null | awk '{print "x"$1" / "$2"%"}')")
  else
    R_REP+=("-")
  fi
done

# ---- 결과 --------------------------------------------------------------
echo "══════════════════════════════════════════════════════════════════════════════"
echo " STT 벤치  (far-field 회의 ${DUR}s, M4 Pro, 전처리 동일)"
echo "══════════════════════════════════════════════════════════════════════════════"
printf "%-22s %8s %7s %9s %8s %11s %14s\n" \
  "구성" "시간(s)" "RTF" "배속" "RAM(MB)" "CER(vs기준)" "최장반복/반복률"
printf -- "------------------------------------------------------------------------------\n"
for i in 0 1 2; do
  printf "%-22s %8s %7s %8sx %8s %11s %14s\n" \
    "${R_NAME[$i]}" "${R_REAL[$i]}" "${R_RTF[$i]}" "${R_SPEED[$i]}" \
    "${R_RSS[$i]}" "${R_CER[$i]}" "${R_REP[$i]}"
done
echo "══════════════════════════════════════════════════════════════════════════════"
echo "· CER은 절대 정확도가 아니라 현행 large-v3 출력 대비 문자 불일치율(공백 제외)."
echo "· 최장반복 = 4자 이상 구절의 최대 연속 반복 횟수(x3 이상이면 환각 루프 의심)."
echo "· 반복률 = 3회 이상 등장한 4-gram이 차지하는 문자 비율."
echo "· 품질 판정은 수치가 아니라 아래 텍스트 육안 비교로:"
for i in 0 1 2; do echo "    ${R_NAME[$i]}: ${R_TXT[$i]}"; done
