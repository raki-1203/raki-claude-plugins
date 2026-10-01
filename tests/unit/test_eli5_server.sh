#!/bin/bash
set -uo pipefail
source "$(dirname "$0")/../fixtures/eli5/lib.sh"
T=$(mktemp -d)
export TMPDIR="$T/tmp"; mkdir -p "$TMPDIR"
export ELI5_GRACE_SEC=1 ELI5_INITIAL_GRACE_SEC=60 ELI5_PING_SEC=0.3 ELI5_ASK_TIMEOUT_SEC=2 ELI5_MAX_LIFE_SEC=86400
export FAKE_CLAUDE_ARGV_LOG="$T/argv.log" FAKE_CLAUDE_MODE_FILE="$T/mode" FAKE_GRAFT_CALLERS="$ELI5_FIX/callers.json"
export CLAUDECODE=1
S="$ELI5_BIN/server.py"
R="$T/저장소 a:1"
bash "$ELI5_FIX/make_repo.sh" "$R"; mkdir -p "$R/.eli5"; M="$R/.eli5/app.model.json"
cp "$ELI5_FIX/model.json" "$M"
python3 "$ELI5_BIN/validate.py" "$M" --root "$R" >/dev/null
python3 "$ELI5_BIN/render.py" "$M" --root "$R" >/dev/null
STATE=$(python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import server; print(server.Paths(sys.argv[2]).state)' "$ELI5_BIN" "$M")
JAR="$T/jar"; BGPIDS=()
cleanup() {
  for p in "${BGPIDS[@]:-}"; do [ -n "$p" ] && kill "$p" 2>/dev/null; done
  python3 "$S" stop --model "$M" >/dev/null 2>&1
  pkill -f "sleep 3001" 2>/dev/null
  rm -rf "$T"
}
trap cleanup EXIT
alive() { kill -0 "$1" 2>/dev/null; }
wait_dead() { local i; for i in $(seq 1 $(($2 * 10))); do alive "$1" || return 0; sleep 0.1; done; return 1; }
start() {
  OUT=$(python3 "$S" open --model "$M" --no-browser)
  URL=$(echo "$OUT" | jq -r .url); PID=$(echo "$OUT" | jq -r .pid); BASE=${URL%%/\?*}
  rm -f "$JAR"; curl -s -o /dev/null -c "$JAR" "$URL"
}
life() { curl -s -N -b "$JAR" "$BASE/api/life" >/dev/null 2>&1 & LIFE=$!; BGPIDS+=("$LIFE"); }
code() { curl -s -o /dev/null -w '%{http_code}' "$@"; }

echo "🔧 기동·보안"
start
[ "$(echo "$OUT" | jq -r .panel)" = "true" ] && alive "$PID" && pass "open → 서버 기동" || fail "open" "$OUT"
[ -f "$STATE" ] && [ "$(stat -f %Lp "$STATE")" = "600" ] && pass "상태 파일 0600" || fail "상태 파일 권한"
curl -s "$BASE/health" | jq -e .ok >/dev/null && pass "/health" || fail "/health"
[ "$(code "$BASE/")" = "403" ] && pass "토큰 없으면 403" || fail "토큰 없음"
[ "$(code "$BASE/?t=wrong")" = "403" ] && pass "틀린 토큰 403" || fail "틀린 토큰"
grep -q 'eli5' "$JAR" && pass "토큰 → 쿠키" || fail "쿠키"
PAGE=$(curl -s -b "$JAR" "$BASE/")
echo "$PAGE" | grep -q 'eli5-panel-host' && echo "$PAGE" | grep -q 'const MODEL' && pass "패널 주입된 지도" || fail "패널 주입"
grep -q 'eli5-panel-host' "$R/.eli5/app.html" && fail "디스크 html 불변" || pass "디스크 html 불변"
[ "$(code -b "$JAR" -H 'Host: evil.example' "$BASE/")" = "403" ] && pass "잘못된 Host 403" || fail "Host 검사"
[ "$(code -b "$JAR" -X POST -H 'Content-Type: application/json' -d '{}' "$BASE/api/ask")" = "403" ] && pass "Origin 없는 POST 403" || fail "Origin 검사"
OUT2=$(python3 "$S" open --model "$M" --no-browser)
[ "$(echo "$OUT2" | jq -r .reused)" = "true" ] && [ "$(echo "$OUT2" | jq -r .pid)" = "$PID" ] && pass "재실행은 기존 서버 재사용" || fail "재사용" "$OUT2"
[ "$(python3 "$S" status --model "$M" | jq -r .server)" = "running" ] && pass "status: running" || fail "status running"
[ "$(python3 "$S" status --model "$M" | jq -r .map)" = "fresh" ] && pass "status: map fresh" || fail "status fresh"

echo "🔧 수명"
life; L1=$LIFE; life; L2=$LIFE; sleep 0.8
kill "$L1"; sleep 2
alive "$PID" && pass "탭 2개 중 1개 닫힘 → 유지" || fail "탭 하나 닫힘"
kill "$L2"
wait_dead "$PID" 4 && pass "마지막 탭 닫힘 → 유예 후 종료" || fail "SSE 끊김 종료"
[ ! -f "$STATE" ] && pass "종료 시 상태 파일 정리" || fail "상태 파일 정리"
OLDPORT=${BASE##*:}
start
[ "${BASE##*:}" = "$OLDPORT" ] && pass "재기동 시 이전 포트 재사용" || fail "포트 재사용" "$BASE vs $OLDPORT"
python3 "$S" stop --model "$M" | jq -e .stopped >/dev/null && wait_dead "$PID" 3 && pass "stop" || fail "stop"
python3 -m http.server "$OLDPORT" --bind 127.0.0.1 >/dev/null 2>&1 & BLOCK=$!; BGPIDS+=("$BLOCK"); sleep 0.5
start
[ "${BASE##*:}" != "$OLDPORT" ] && alive "$PID" && pass "이전 포트 점유 시 다른 포트" || fail "포트 충돌" "$BASE"
kill "$BLOCK"
python3 "$S" stop --model "$M" >/dev/null; wait_dead "$PID" 3
export ELI5_INITIAL_GRACE_SEC=1; start; export ELI5_INITIAL_GRACE_SEC=60
wait_dead "$PID" 4 && pass "아무도 안 열면 초기 유예 후 종료" || fail "초기 유예"
export ELI5_MAX_LIFE_SEC=2; start; export ELI5_MAX_LIFE_SEC=86400; life
wait_dead "$PID" 5 && pass "하드캡 — 연결 있어도 종료" || fail "하드캡"
kill "$LIFE" 2>/dev/null
printf '{"pid": 999999, "port": 1, "token": "x"}' > "$STATE"
start
[ "$(echo "$OUT" | jq -r .reused)" = "false" ] && alive "$PID" && pass "죽은 pid 상태 파일 → 새로 기동" || fail "죽은 pid" "$OUT"
python3 "$S" stop --model "$M" >/dev/null; wait_dead "$PID" 3
printf '{"pid": %d, "port": 1, "token": "x"}' $$ > "$STATE"
python3 "$S" stop --model "$M" | jq -e '.stopped==false' >/dev/null && alive $$ && pass "health 안 맞는 pid 는 죽이지 않음" || fail "pid 재사용 보호"
echo "# changed" >> "$R/src/core/engine.py"
[ "$(python3 "$S" status --model "$M" | jq -r .map)" = "stale" ] && pass "status: 코드 바뀌면 stale" || fail "stale"
git -C "$R" checkout -q -- src/core/engine.py
OUT3=$(ELI5_CLAUDE_BIN=/nonexistent/claude python3 "$S" open --model "$M" --no-browser)
[ "$(echo "$OUT3" | jq -r .panel)" = "false" ] && echo "$OUT3" | jq -e '.url|startswith("file://")' >/dev/null && pass "claude 없음 → file:// 로 패널 없이" || fail "claude 없음" "$OUT3"
finish
