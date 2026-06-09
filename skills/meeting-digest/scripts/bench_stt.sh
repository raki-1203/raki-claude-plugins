#!/bin/bash
# meeting-digest STT 벤치마크 — M4 Mac에서 3개 구성 속도/정확도 비교
#
#   1) whisper-ctranslate2  large-v3   int8   (현재 스킬 기준 = pseudo-reference)
#   2) mlx-whisper          large-v3
#   3) mlx-whisper          large-v3-turbo
#
# 측정: wall-clock, RTF(=처리시간/오디오길이), 실시간배속, peak RAM,
#       large-v3(기준) 대비 CER(문자오류율), 출력 글자수.
#
# 공정성: 모델 다운로드/Metal 커널 컴파일은 워밍업으로 분리하고
#         본 측정은 클립 1회로 한다(다운로드 시간 오염 방지).
#
# Usage:
#   bench_stt.sh [--audio <path>] [--clip-secs 180] [--out-dir <dir>]
#   (--audio 생략 시 가장 최근 회의 audio.m4a 자동 선택)

set -u

CLIP_SECS=180
WARMUP_SECS=8
OUT_DIR="$HOME/stt-bench-out"
AUDIO=""
VENV="/tmp/.stt-bench-venv"

while [ $# -gt 0 ]; do
  case "$1" in
    --audio)     AUDIO="$2"; shift 2 ;;
    --clip-secs) CLIP_SECS="$2"; shift 2 ;;
    --out-dir)   OUT_DIR="$2"; shift 2 ;;
    *) echo "unknown arg: $1" >&2; exit 1 ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CER_PY="$SCRIPT_DIR/bench_cer.py"

# ---- 0. 의존성 ----------------------------------------------------------
for c in ffmpeg ffprobe uv whisper-ctranslate2; do
  command -v "$c" >/dev/null 2>&1 || { echo "❌ 필요 도구 없음: $c" >&2; exit 2; }
done
[ -x /usr/bin/time ] || { echo "❌ /usr/bin/time 없음" >&2; exit 2; }

if [ -z "$AUDIO" ]; then
  AUDIO=$(ls -t "$HOME"/Library/CloudStorage/Nextcloud*/Vault/raw/meetings/*/*/audio.m4a 2>/dev/null | head -1)
fi
[ -n "$AUDIO" ] && [ -f "$AUDIO" ] || { echo "❌ 오디오 없음 (--audio 로 지정): $AUDIO" >&2; exit 3; }

# ---- 1. mlx-whisper venv 준비 ------------------------------------------
if [ ! -x "$VENV/bin/mlx_whisper" ]; then
  echo "▶ mlx-whisper 격리 설치 ($VENV)"
  uv venv "$VENV" --python 3.11 >/dev/null 2>&1
  uv pip install --python "$VENV" mlx-whisper >/dev/null 2>&1 || { echo "❌ mlx-whisper 설치 실패" >&2; exit 2; }
fi
MLX="$VENV/bin/mlx_whisper"

mkdir -p "$OUT_DIR"
echo "▶ 오디오: $AUDIO"
echo "▶ 출력:   $OUT_DIR"
echo "▶ 클립:   워밍업 ${WARMUP_SECS}s / 본측정 ${CLIP_SECS}s"
echo

# ---- 2. 클립 추출 (16kHz mono wav) -------------------------------------
CLIP="$OUT_DIR/clip.wav"
WARM="$OUT_DIR/warmup.wav"
ffmpeg -y -loglevel error -i "$AUDIO" -t "$CLIP_SECS"   -ar 16000 -ac 1 "$CLIP" </dev/null
ffmpeg -y -loglevel error -i "$AUDIO" -t "$WARMUP_SECS" -ar 16000 -ac 1 "$WARM" </dev/null
DUR=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$CLIP")
echo "▶ 본측정 클립 길이: ${DUR}s"
echo

# ---- 3. 엔진별 명령 구성 (CMD 전역 배열) -------------------------------
build_cmd() {  # $1=engine $2=audio $3=outdir
  local engine="$1" audio="$2" out="$3"
  case "$engine" in
    ct2)   CMD=(whisper-ctranslate2 "$audio" --model large-v3 --language ko
                --compute_type int8 --output_dir "$out" --output_format txt --verbose False) ;;
    mlxv3) CMD=("$MLX" "$audio" --model mlx-community/whisper-large-v3-mlx --language ko
                --output-dir "$out" --output-name out --output-format txt --verbose False) ;;
    turbo) CMD=("$MLX" "$audio" --model mlx-community/whisper-large-v3-turbo --language ko
                --output-dir "$out" --output-name out --output-format txt --verbose False) ;;
  esac
}

parse_real() { grep -E '[0-9.]+ real' "$1" | tail -1 | awk '{print $1}'; }
parse_rss()  { grep 'maximum resident set size' "$1" | tail -1 | awk '{printf "%.0f", $1/1048576}'; }

declare -a R_NAME R_REAL R_RTF R_SPEED R_RSS R_TXT
run_engine() {  # $1=표시명 $2=서브디렉터리 $3=txt파일명 $4=engine_id
  local name="$1" sub="$2" txtbase="$3" engine="$4"
  local d="$OUT_DIR/$sub"; mkdir -p "$d"
  local tlog="$OUT_DIR/$sub.time"

  printf "  · %-26s 워밍업..." "$name"
  build_cmd "$engine" "$WARM" "$d"
  "${CMD[@]}" >/dev/null 2>&1
  echo " 측정..."
  build_cmd "$engine" "$CLIP" "$d"
  /usr/bin/time -l "${CMD[@]}" >"$tlog.out" 2>"$tlog"
  local rc=$?

  local txt="$d/$txtbase" real rss rtf speed
  real=$(parse_real "$tlog"); rss=$(parse_rss "$tlog")
  if [ $rc -ne 0 ] || [ -z "$real" ] || [ ! -f "$txt" ]; then
    R_NAME+=("$name"); R_REAL+=("FAIL"); R_RTF+=("-"); R_SPEED+=("-"); R_RSS+=("${rss:-?}"); R_TXT+=("$txt")
    echo "    ⚠ 실패 (로그: $tlog)"; return
  fi
  rtf=$(awk -v r="$real" -v d="$DUR" 'BEGIN{printf "%.3f", r/d}')
  speed=$(awk -v r="$real" -v d="$DUR" 'BEGIN{printf "%.1f", d/r}')
  R_NAME+=("$name"); R_REAL+=("$real"); R_RTF+=("$rtf"); R_SPEED+=("$speed"); R_RSS+=("$rss"); R_TXT+=("$txt")
}

echo "▶ 전사 실행 (3개 구성, 각 워밍업+측정)"
run_engine "ct2 large-v3 (int8)" ct2   "clip.txt" ct2
run_engine "mlx large-v3"        mlxv3 "out.txt"  mlxv3
run_engine "mlx large-v3-turbo"  turbo "out.txt"  turbo
echo

# ---- 4. CER (ct2 large-v3 = 기준) --------------------------------------
REF="${R_TXT[0]}"
declare -a R_CER
for i in 0 1 2; do
  if [ "$i" -eq 0 ]; then R_CER+=("기준"); continue; fi
  hyp="${R_TXT[$i]}"
  if [ -f "$REF" ] && [ -f "$hyp" ]; then
    out=$("$VENV/bin/python" "$CER_PY" "$REF" "$hyp" 2>/dev/null)
    R_CER+=("$(echo "$out" | awk '{print $1"%"}')")
  else
    R_CER+=("-")
  fi
done

# ---- 5. 결과 표 ---------------------------------------------------------
echo "════════════════════════════════════════════════════════════════════════"
echo " STT 벤치 결과  (오디오 ${DUR}s, M4 Mac)"
echo "════════════════════════════════════════════════════════════════════════"
printf "%-22s %9s %7s %10s %8s %12s\n" "구성" "시간(s)" "RTF" "실시간배속" "RAM(MB)" "CER(vs기준)"
printf -- "------------------------------------------------------------------------\n"
for i in 0 1 2; do
  printf "%-22s %9s %7s %9sx %8s %12s\n" \
    "${R_NAME[$i]}" "${R_REAL[$i]}" "${R_RTF[$i]}" "${R_SPEED[$i]}" "${R_RSS[$i]}" "${R_CER[$i]}"
done
echo "════════════════════════════════════════════════════════════════════════"
echo "· RTF<1 = 실시간보다 빠름. 실시간배속 = 오디오길이/처리시간."
echo "· CER = ct2 large-v3 출력을 기준으로 한 문자 불일치율(공백 제외). 낮을수록 기준과 유사."
echo "· 절대 정확도 아님 — 기준 자체가 정답은 아니므로 육안 비교 병행:"
for i in 0 1 2; do echo "    ${R_NAME[$i]}: ${R_TXT[$i]}"; done
