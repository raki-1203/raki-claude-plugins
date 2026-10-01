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
echo "🔧 질문"
start; life
ask() { curl -s -N -b "$JAR" -H "Origin: $BASE" -H 'Content-Type: application/json' -d "$1" "$BASE/api/ask"; }
Q='{"conv_id":"c1","question":"이거 뭐야?","context":{"view":{"id":"L0","title":"L0"},"node":{"id":"core","title":"엔진","lines":["run_job"]},"ifaces":[]}}'
echo ok > "$T/mode"
r=$(ask "$Q")
[ "$(echo "$r" | tail -1 | jq -r .type)" = "final" ] && pass "스트림이 final 로 끝남" || fail "final" "$r"
echo "$r" | jq -s -e 'map(.type) | (index("session") != null) and (index("tool") != null) and (index("delta") != null)' >/dev/null && pass "session·tool·delta 이벤트" || fail "이벤트 종류" "$r"
echo "$r" | jq -s -e 'map(select(.type=="tool"))[0].detail=="src/app.py"' >/dev/null && pass "tool detail" || fail "tool detail" "$r"
A=$(tail -1 "$T/argv.log")
echo "$A" | jq -e '.env_claudecode==null' >/dev/null && pass "CLAUDECODE 제거" || fail "CLAUDECODE" "$A"
echo "$A" | jq -e '.argv as $a | ($a|index("--allowedTools")) as $i | $a[$i+1]=="mcp__graft"' >/dev/null && pass "--allowedTools mcp__graft" || fail "allowedTools" "$A"
echo "$A" | jq -e '.argv as $a | ($a|index("--setting-sources")) as $i | $a[$i+1]==""' >/dev/null \
  && echo "$A" | jq -e '.argv|index("{\"disableAllHooks\": true}") != null' >/dev/null && pass "hook 차단 플래그" || fail "hook 차단" "$A"
echo "$A" | jq -e '.argv|index("--strict-mcp-config") != null' >/dev/null && pass "--strict-mcp-config" || fail "strict-mcp" "$A"
echo "$A" | jq -e '.argv|index("--resume")==null' >/dev/null && pass "첫 질문은 --resume 없음" || fail "첫 질문 resume" "$A"
echo "$A" | jq -e '.stdin|contains("[map context]") and contains("selected box: core") and contains("이거 뭐야?")' >/dev/null && pass "[map context] + 질문 전달" || fail "map context" "$A"
ask "$Q" >/dev/null
tail -1 "$T/argv.log" | jq -e '.argv as $a | ($a|index("--resume")) as $i | $a[$i+1]=="sess-1"' >/dev/null && pass "같은 대화 → --resume sess-1" || fail "resume"
echo noise > "$T/mode"; r=$(ask "${Q/c1/c2}")
[ "$(echo "$r" | tail -1 | jq -r .type)" = "final" ] && pass "JSON 아닌 줄 무시" || fail "noise" "$r"
echo fail > "$T/mode"; r=$(ask "${Q/c1/c3}")
echo "$r" | tail -1 | jq -e '.type=="error" and (.message|contains("boom")) and (.message|contains("3"))' >/dev/null && pass "비정상 종료 → error + stderr" || fail "fail" "$r"
echo empty > "$T/mode"; r=$(ask "${Q/c1/c4}")
echo "$r" | tail -1 | jq -e '.type=="error" and (.message|contains("비어"))' >/dev/null && pass "빈 출력 → error" || fail "empty" "$r"
echo sleep > "$T/mode"
ask "${Q/c1/c5}" > "$T/slow.out" & SLOW=$!; BGPIDS+=("$SLOW"); sleep 0.5
[ "$(code -b "$JAR" -H "Origin: $BASE" -H 'Content-Type: application/json' -d "${Q/c1/c5}" "$BASE/api/ask")" = "409" ] && pass "같은 대화 동시 질문 409" || fail "409"
wait "$SLOW"
tail -1 "$T/slow.out" | jq -e '.type=="error" and (.message|contains("시간 초과"))' >/dev/null && pass "타임아웃 → error" || fail "timeout" "$(cat "$T/slow.out")"
sleep 1; pgrep -f "sleep 3001" >/dev/null && fail "타임아웃 후 손자 프로세스 정리" || pass "타임아웃 후 손자 프로세스 정리"
[ "$(code -b "$JAR" -H "Origin: $BASE" -H 'Content-Type: application/json' -d '{"conv_id":"bad id!","question":"x"}' "$BASE/api/ask")" = "400" ] && pass "잘못된 conv_id 400" || fail "400"

echo "🔧 재기동 후 대화 유지"
echo ok > "$T/mode"
kill "$LIFE"; python3 "$S" stop --model "$M" >/dev/null; wait_dead "$PID" 3
start; life; ask "$Q" >/dev/null
tail -1 "$T/argv.log" | jq -e '.argv as $a | ($a|index("--resume")) as $i | $a[$i+1]=="sess-1"' >/dev/null && pass "서버 재기동 후 --resume" || fail "재기동 resume" "$(tail -1 "$T/argv.log")"

echo "🔧 종료 시 진행 중 질문 정리"
kill "$LIFE"; python3 "$S" stop --model "$M" >/dev/null; wait_dead "$PID" 3
export ELI5_ASK_TIMEOUT_SEC=30; start; export ELI5_ASK_TIMEOUT_SEC=2; life
echo sleep > "$T/mode"
ask "${Q/c1/c6}" >/dev/null & BGPIDS+=("$!"); sleep 0.5
pgrep -f "sleep 3001" >/dev/null && pass "(전제) 질문 진행 중" || fail "(전제) 질문 진행 중"
kill "$LIFE"
wait_dead "$PID" 4 && pass "탭 닫힘 → 서버 종료" || fail "서버 종료"
sleep 0.5; pgrep -f "sleep 3001" >/dev/null && fail "진행 중 자식까지 정리" || pass "진행 중 자식까지 정리"
finish
