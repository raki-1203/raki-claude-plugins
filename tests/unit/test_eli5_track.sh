#!/bin/bash
set -uo pipefail
source "$(dirname "$0")/../fixtures/eli5/lib.sh"
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
R="$T/r"; bash "$ELI5_FIX/make_repo.sh" "$R"
export FAKE_GRAFT_CALLERS="$ELI5_FIX/callers.json"
mkdir -p "$R/.eli5"; M="$R/.eli5/app.model.json"; cp "$ELI5_FIX/model.json" "$M"
python3 "$ELI5_BIN/validate.py" "$M" --root "$R" >/dev/null
TR="$ELI5_BIN/track.py"; SID=sid-1
H="$R/.eli5/app.track.$SID.html"; TF="$R/.eli5/app.touched.$SID.json"; PF="$R/.eli5/app.progress.$SID.json"
hook() { printf '{"session_id":"%s","tool_name":"Edit","tool_input":{"file_path":"%s"}}' "$1" "$2" | python3 -S "$TR" touch; }
payload() { python3 - "$H" <<'PY'
import json, re, sys
h = open(sys.argv[1], encoding="utf-8").read()
print(json.dumps(json.loads(re.search(r"const MODEL = (.*?);\n\(function", h, re.S).group(1))["track"], ensure_ascii=False))
PY
}

echo "🔧 track — 시작·종료"
MSUM=$(md5 -q "$M")
out=$(CLAUDE_CODE_SESSION_ID=$SID python3 "$TR" start --model "$M")
[ -f "$R/.eli5/track/$SID.json" ] && [ -f "$H" ] && pass "start — 표식과 추적 화면" || fail "start" "$out"
grep -q 'http-equiv="refresh" content="15"' "$H" && pass "추적 중에는 15초 자동 새로고침" || fail "자동 새로고침"
[ "$(payload | jq -r .live)" = "true" ] && pass "payload live=true" || fail "live"
err=$(env -u CLAUDE_CODE_SESSION_ID python3 "$TR" start --model "$M" 2>&1 >/dev/null); rc=$?; [ $rc -eq 2 ] && echo "$err" | grep -q "세션 id" && pass "세션 id 없으면 exit 2 + 안내" || fail "세션 id 없음" "rc=$rc $err"

echo "🔧 track — 훅 기록"
hook $SID "$R/src/core/engine.py"; [ $? -eq 0 ] && [ "$(jq -r '.files["src/core/engine.py"].box' "$TF")" = "engine" ] && pass "고친 파일 → 잎 박스(engine)" || fail "박스 매핑" "$(cat "$TF" 2>/dev/null)"
[ "$(payload | jq -r '.touched["src/core/engine.py"].box')" = "engine" ] && pass "화면 다시 그림 (touched 반영)" || fail "다시 그림"
hook $SID "$R/docs/adr-1.md"; [ "$(jq -r '.files["docs/adr-1.md"].box' "$TF")" = "null" ] && pass "지도 밖 파일 → box null" || fail "지도 밖"
hook other-sid "$R/src/api/server.py"; [ "$(jq -r '.files["src/api/server.py"] // "none"' "$TF")" = "none" ] && pass "다른 세션의 편집은 기록 안 함" || fail "세션 필터"
hook $SID "$R/.eli5/app.model.json"; [ "$(jq -r '.files[".eli5/app.model.json"] // "none"' "$TF")" = "none" ] && pass ".eli5 안 파일 무시" || fail ".eli5 무시"
echo 'not json' | python3 -S "$TR" touch; [ $? -eq 0 ] && pass "깨진 입력에도 exit 0" || fail "깨진 입력"
hook nobody "$T/elsewhere/x.py"; [ $? -eq 0 ] && pass "표식 없는 곳은 바로 exit 0" || fail "표식 없음"
s=$(python3 -c "import time,subprocess,sys; t=time.time(); rs=[subprocess.run([sys.executable,'-S','$TR','touch'],input=b'{\"session_id\":\"x\",\"tool_input\":{\"file_path\":\"/tmp/nope/x.py\"}}').returncode for _ in range(5)]; print(int((time.time()-t)/5*1000) if rs==[0]*5 else 9999)")
[ "$s" -lt 80 ] && pass "표식 없을 때 평균 ${s}ms (< 80ms)" || fail "훅 비용" "${s}ms"

echo "🔧 track — 진행 파일"
cat > "$PF" <<'J'
{"task": {"title": "작업 실행기 고치기", "goal": "실행 결과를 정확히 보낸다"}, "updated": "2026-10-03 22:00 KST",
 "items": [{"id": "a", "title": "실행기 수정", "body": "결과 형식을 바꾼다", "state": "now", "boxes": ["engine"]},
           {"id": "b", "title": "테스트", "body": "단위 테스트 통과", "state": "done", "boxes": ["api"], "evidence": [{"text": "pytest 12 passed"}]}]}
J
python3 "$ELI5_BIN/render.py" "$M" --root "$R" --track $SID >/dev/null
[ "$(payload | jq -r '.progress.items|length')" = "2" ] && [ "$(payload | jq -r '.errors|length')" = "0" ] && pass "진행 파일을 화면에 싣는다" || fail "진행 파일" "$(payload)"
python3 - "$PF" <<'PY'
import json, sys
p = sys.argv[1]; d = json.load(open(p)); d["items"][1]["state"] = "now"; d["items"].append({"id": "c", "title": "x", "state": "done", "boxes": ["ghost"]}); json.dump(d, open(p, "w"))
PY
python3 "$ELI5_BIN/render.py" "$M" --root "$R" --track $SID >/dev/null
e=$(payload | jq -r '.errors|join(" | ")')
echo "$e" | grep -q '최대 1개' && echo "$e" | grep -q "ghost" && echo "$e" | grep -q '근거가 없다' && [ "$(payload | jq -r .progress)" = "null" ] \
  && pass "진행 파일 오류(now 2개·없는 박스·근거 없는 완료)는 오류로 싣고 진행은 뺀다" || fail "진행 검증" "$e"
[ "$(md5 -q "$M")" = "$MSUM" ] && pass "추적 렌더는 모델을 다시 쓰지 않는다" || fail "모델 보존"

echo "🔧 track — 끝"
CLAUDE_CODE_SESSION_ID=$SID python3 "$TR" stop --model "$M" >/dev/null
[ ! -f "$R/.eli5/track/$SID.json" ] && ! grep -q 'http-equiv="refresh"' "$H" && [ "$(payload | jq -r .live)" = "false" ] && pass "stop — 표식 삭제, 자동 새로고침 끔" || fail "stop"
finish
