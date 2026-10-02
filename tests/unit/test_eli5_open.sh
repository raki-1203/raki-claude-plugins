#!/bin/bash
set -uo pipefail
source "$(dirname "$0")/../fixtures/eli5/lib.sh"
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
PY=$(command -v python3)
O="$ELI5_BIN/open.py"
R="$T/저장소 a:1"
bash "$ELI5_FIX/make_repo.sh" "$R"
export FAKE_GRAFT_CALLERS="$ELI5_FIX/callers.json"
mkdir -p "$R/.eli5"; M="$R/.eli5/app.model.json"; H="$R/.eli5/app.html"
cp "$ELI5_FIX/model.json" "$M"

echo "🔧 open.py status"
[ "$("$PY" "$O" status --model "$M" | jq -r .map)" = "missing" ] && pass "렌더 전 → missing" || fail "missing"
"$PY" "$ELI5_BIN/validate.py" "$M" --root "$R" >/dev/null && "$PY" "$ELI5_BIN/render.py" "$M" --root "$R" >/dev/null
[ "$("$PY" "$O" status --model "$M" | jq -r .map)" = "fresh" ] && pass "렌더 직후 → fresh" || fail "fresh" "$("$PY" "$O" status --model "$M")"
echo "# x" >> "$R/src/core/engine.py"; git -C "$R" -c user.email=t@t -c user.name=t commit -qam change
[ "$("$PY" "$O" status --model "$M" | jq -r .map)" = "stale" ] && pass "scope 코드 커밋 → stale" || fail "stale"
jq '.dirty=true' "$R/.eli5/app.eli5.json" > "$T/s" && mv "$T/s" "$R/.eli5/app.eli5.json"
[ "$("$PY" "$O" status --model "$M" | jq -r .map)" = "unknown" ] && pass "dirty 사이드카 → unknown" || fail "unknown"

echo "🔧 open.py open"
out=$("$PY" "$O" open "$H" --mode print)
[ "$out" = "opened: none $(cd "$(dirname "$H")" && pwd -P)/app.html" ] || [ "$out" = "opened: none $H" ] && pass "print 모드 → 경로만" || fail "print" "$out"
err=$("$PY" "$O" open "$T/nope.html" 2>&1 >/dev/null); rc=$?; [ $rc -eq 2 ] && echo "$err" | grep -q "no such file" && pass "없는 파일 → exit 2" || fail "없는 파일" "rc=$rc $err"

mkdir -p "$T/bin"
cat > "$T/bin/orca" <<'SH'
#!/bin/bash
echo "$@" >> "$FAKE_ORCA_LOG"
exit "${FAKE_ORCA_RC:-0}"
SH
chmod +x "$T/bin/orca"
export FAKE_ORCA_LOG="$T/orca.log"

out=$(env -u ORCA_WORKTREE_ID ELI5_OPEN_DRY=1 PATH="$T/bin:/usr/bin:/bin" "$PY" "$O" open "$H")
echo "$out" | grep -q '^opened: browser ' && [ ! -s "$FAKE_ORCA_LOG" ] && pass "auto · Orca 밖 → 브라우저" || fail "auto 브라우저" "$out"

out=$(ORCA_WORKTREE_ID=w1 ELI5_OPEN_DRY=1 PATH="$T/bin:/usr/bin:/bin" "$PY" "$O" open "$H")
echo "$out" | grep -q '^opened: orca-tab ' && pass "auto · Orca 안 → Orca 탭" || fail "auto orca" "$out"
grep -q -- '--url file://.*%EC%A0%80%EC%9E%A5%EC%86%8C%20a%3A1/.eli5/app.html' "$FAKE_ORCA_LOG" && pass "한글·공백 경로 인코딩" || fail "URL 인코딩" "$(cat "$FAKE_ORCA_LOG")"

out=$(FAKE_ORCA_RC=1 ORCA_WORKTREE_ID=w1 ELI5_OPEN_DRY=1 PATH="$T/bin:/usr/bin:/bin" "$PY" "$O" open "$H" 2>&1)
echo "$out" | grep -q 'skip: orca' && echo "$out" | grep -q '^opened: browser ' && pass "Orca 실패 → 브라우저로 대체" || fail "orca 실패 대체" "$out"

out=$(ELI5_OPEN_DRY=1 PATH="/usr/bin:/bin" "$PY" "$O" open "$H" --mode orca 2>&1)
echo "$out" | grep -q 'orca 명령 없음' && echo "$out" | grep -q '^opened: browser ' && pass "--mode orca · 명령 없음 → 브라우저" || fail "orca 없음" "$out"
finish
