#!/bin/bash
set -uo pipefail
source "$(dirname "$0")/../fixtures/eli5/lib.sh"
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
bash "$ELI5_FIX/make_repo.sh" "$T/r"
export FAKE_GRAFT_CALLERS="$ELI5_FIX/callers.json"
V="$ELI5_BIN/validate.py"
fresh() { cp "$ELI5_FIX/model.json" "$T/m.model.json"; }
run() { python3 "$V" "$T/m.model.json" --root "$T/r" "$@"; }
edit() { python3 - "$T/m.model.json" "$1" <<'PY'
import json, sys
p, code = sys.argv[1], sys.argv[2]
m = json.load(open(p, encoding="utf-8"))
exec(code, {"m": m})
json.dump(m, open(p, "w", encoding="utf-8"), ensure_ascii=False)
PY
}
grade() { jq -r "$1" "$T/m.model.json"; }

echo "🔧 validate — 정상 모델"
fresh; out=$(run); rc=$?
[ $rc -eq 0 ] && pass "exit 0" || fail "exit 0" "$rc $out"
[ "$(echo "$out" | jq -c .counts)" = '{"graft":1,"code":1,"record":1,"unknown":1}' ] && pass "등급 집계" || fail "등급 집계" "$(echo "$out" | jq -c .counts)"
[ "$(echo "$out" | jq '.downgrades|length')" = "0" ] && pass "강등 없음" || fail "강등 없음" "$out"
[ "$(grade '.unknowns[0].text')" = "L0 · 실행 단위: 에이전트 서비스 → 요청 받는 곳 (결과 콜백?)" ] && pass "unknown edge 를 unknowns 에 자동 추가" || fail "unknowns 자동 추가" "$(grade .unknowns)"
[ "$(grade '.validation.counts.graft')" = "1" ] && pass "model.validation 기록" || fail "validation 기록"
run >/dev/null; [ "$(grade '.unknowns|length')" = "1" ] && pass "재실행해도 unknowns 중복 없음" || fail "unknowns 중복"

echo "🔧 강등"
fresh; edit 'm["views"]["L0"]["edges"][0]["evidence"].update(from_sym="src/api/server.py#other", ref="src/api/server.py:5", quote="run_job(")'
run >/dev/null; [ "$(grade '.views.L0.edges[0].grade')" = "code" ] && pass "graft 실패 + code 통과 → code" || fail "graft→code" "$(grade '.views.L0.edges[0].grade')"
fresh; edit 'm["views"]["L0"]["edges"][0]["evidence"]["from_sym"]="src/api/server.py#other"'
out=$(run); [ "$(grade '.views.L0.edges[0].grade')" = "unknown" ] && pass "graft 실패, code 근거 없음 → unknown" || fail "graft→unknown"
echo "$out" | jq -e '.downgrades[0] | .claimed=="graft" and .result=="unknown" and (.reason|test("callers"))' >/dev/null && pass "강등 사유 기록" || fail "강등 사유" "$out"
fresh; edit 'm["views"]["L0"]["edges"][0]["evidence"]["to_sym"]="src/api/server.py#handle"'
out=$(run); echo "$out" | jq -e '.downgrades[0].reason|test("paths 밖")' >/dev/null && pass "to_sym 이 박스 paths 밖 → 강등" || fail "paths 밖" "$out"
fresh; edit 'm["views"]["L0"]["edges"][0]["evidence"]["from_sym"]="handle"'
run >/dev/null; [ "$(grade '.views.L0.edges[0].grade')" = "unknown" ] && pass "노드 id 형식 아님 → unknown" || fail "id 형식"
fresh; edit 'm["views"]["L0"]["edges"][1]["evidence"]["quote"]="requests.get"'
run >/dev/null; [ "$(grade '.views.L0.edges[1].grade')" = "unknown" ] && pass "quote 불일치 → unknown" || fail "quote 불일치"
fresh; edit 'm["views"]["L0"]["edges"][1]["evidence"]["quote"]="requests.get"'
run --quick >/dev/null; [ "$(grade '.views.L0.edges[1].grade')" = "code" ] && pass "--quick 은 quote 검사 생략" || fail "--quick"
fresh; edit 'm["views"]["L0"]["edges"][1]["evidence"]["quote"]="re"'
out=$(run); [ "$(grade '.views.L0.edges[1].grade')" = "unknown" ] && echo "$out" | jq -e '.downgrades[0].reason|test("짧")' >/dev/null && pass "8자 미만 quote → unknown (어디에나 있는 글자로 통과 금지)" || fail "짧은 quote" "$out"
fresh; edit 'm["views"]["L0"]["edges"][1]["evidence"]["ref"]="src/core/nope.py:5"'
run >/dev/null; [ "$(grade '.views.L0.edges[1].grade')" = "unknown" ] && pass "없는 파일 인용 → unknown" || fail "없는 파일"
fresh; edit 'm["views"]["L0"]["rules"][0]["evidence"]["ref"]="deadbeefdeadbeef"'
run >/dev/null; [ "$(grade '.views.L0.rules[0].grade')" = "unknown" ] && pass "없는 커밋 → unknown" || fail "없는 커밋"
fresh; HEAD=$(git -C "$T/r" rev-parse HEAD); edit "m['views']['L0']['rules'][0]['evidence']['ref']='$HEAD'"
run >/dev/null; [ "$(grade '.views.L0.rules[0].grade')" = "record" ] && pass "실제 커밋 → record 유지" || fail "실제 커밋"
fresh; out=$(run --graft-status absent)
[ "$(grade '.views.L0.edges[0].grade')" = "unknown" ] && echo "$out" | jq -e '.downgrades[0].reason=="graft 없음"' >/dev/null && pass "graft 없음 → 강등" || fail "graft 없음" "$out"

echo "🔧 무결성 오류 (exit 1)"
integrity() {
  fresh; edit "$1"; local before; before=$(cat "$T/m.model.json"); out=$(run); local rc=$?
  if [ $rc -eq 1 ] && echo "$out" | jq -e --arg k "$2" '.integrity_errors|any(test($k))' >/dev/null \
     && [ "$(cat "$T/m.model.json")" = "$before" ]; then pass "$3"; else fail "$3" "rc=$rc $out"; fi
}
integrity 'm["views"]["L0"]["edges"][0]["to"]="ghost"' "노드 없음" "없는 노드"
integrity 'm["views"]["L0"]["nodes"][0]["drill"]="L0"' "drill 은 없어졌다" "drill 금지"
integrity 'm["views"]["L0"]["edges"][0]["iface"]="ghost"' "iface .ghost. 없음" "없는 iface"
integrity 'm["views"]["L0"]["edges"][0].pop("iface")' "참조하는 edge 가 없다" "고아 iface"
integrity 'm["views"]["L0"]["nodes"][2].update(row=0, col=0)' "겹쳐" "격자 겹침"
integrity 'm["views"]["L0"]["rules"][0]["grade"]="graft"' "규칙은" "규칙 graft 등급"
integrity 'm["meta"]["version"]=2' "v3 지도만" "v2 모델 거부"
integrity 'm["meta"].pop("version")' "v3 지도만" "version 없음 거부"
integrity 'm["meta"]["summary"]=""' "summary 가 비었다" "summary 필수"
integrity 'm["views"]["L0"]["nodes"][0]["lines"]=["handle(req)"]' "lines 는 v3" "lines 잔존 거부"
integrity 'm["views"]["L0"]["nodes"][0]["kind"]="server"' "kind .server." "kind 허용값"
integrity 'm["views"]["L0"]["nodes"][0].pop("say")' "say 가 비었다" "say 필수"
integrity 'm["views"]["L0"]["nodes"][0]["say"]="graph.astream을 부른다"' "graph.astream" "say 에 코드 이름(조사 결합)"
integrity 'm["views"]["L0"]["nodes"][0]["title"]="요청을 받아서 검사하는 곳입니다"' "칸, 상한 24" "title 길이"
integrity 'm["views"]["L0"]["edges"][0]["label"]="run_job"' "run_job" "edge label 코드 이름"
integrity 'del m["meta"]["glossary"]["HTTP"]' "HTTP" "glossary 없는 용어"
integrity 'm["meta"]["glossary"]["graph.astream"]="그래프 실행"' "코드 이름이다" "glossary 우회 금지"
integrity 'm["meta"]["glossary"]["API"]=""' "풀이가 비었다" "glossary 빈 풀이"
integrity 'm["views"]["L1"]={"title":"L1 · 안쪽","hint":"안쪽","parent":"L0","rules":[],"nodes":[],"edges":[],"ifaces":[]}' "지도는 한 장" "view 둘 거부"
integrity 'm["views"]["L0"]["parent"]="L0"' "parent 는 없어졌다" "parent 금지"
integrity 'm["views"]["L0"]["nodes"][1]["col"]=1' "묶음은 자기 칸" "묶음에 칸 금지"
integrity 'm["views"]["L0"]["nodes"][3].pop("group")' "안쪽 박스가 1개" "묶음 안쪽 1개 거부"
integrity 'm["views"]["L0"]["nodes"][2]["group"]="ghost"' "group .ghost. 없음" "없는 group"
integrity 'm["views"]["L0"]["nodes"][1]["group"]="core"' "자기 자신" "group 자기 자신"
integrity 'm["views"]["L0"]["nodes"][1]["group"]="api"' "한 단계만" "묶음 안의 묶음 거부"
integrity 'm["views"]["L0"]["nodes"][4]["col"]=5' "열은 0~4" "열 5개 상한"
integrity 'm["views"]["L0"]["nodes"][4].update(row=0, col=2)' "지난다" "화살표 관통"
integrity 'm["views"]["L0"]["nodes"][4].update(row=1, col=1); m["views"]["L0"]["nodes"][3].update(row=2, col=1)' "테두리 안에" "묶음 테두리 침범"
integrity 'm["views"]["L0"]["edges"][0]["label"]="작업을 실행해 달라"' "칸, 상한 14" "edge label 14칸"
fresh; edit 'm["views"]["L0"]["edges"][0]["to"]="core"; m["views"]["L0"]["nodes"][3]["paths"]=["src/core/engine.py"]'
run >/dev/null; [ "$(grade '.views.L0.edges[0].grade')" = "graft" ] && pass "묶음 끝 화살표 graft 유지 (안쪽 paths 합 — 어느 박스인지 가릴 수 없을 때)" || fail "묶음 graft" "$(grade '.validation.downgrades')"
integrity 'm["views"]["L0"]["edges"][0]["to"]="core"' "묶음 대신" "묶음 끝 근거가 안쪽 박스 하나면 거부 (graft to)"
integrity 'm["views"]["L0"]["edges"][1]["from"]="core"' "묶음 대신" "묶음 끝 근거가 안쪽 박스 하나면 거부 (code ref from)"
fresh; edit 'm["views"]["L0"]["nodes"][0]["detail"]="handle(req) 가 run_job 을 부른다"'
out=$(run); [ $? -eq 0 ] && pass "detail 은 쉬운 말 검사 대상 아님" || fail "detail 검사 제외" "$out"

echo "🔧 시나리오"
fresh; out=$(run)
[ "$(echo "$out" | jq -c '.scenarios.run')" = '[{"edge":null,"grade":null},{"edge":0,"grade":"graft"},{"edge":1,"grade":"code"}]' ] \
  && pass "단계별 화살표·등급 기록 (묶음 끝 화살표를 안쪽 박스에 적용)" || fail "시나리오 기록" "$(echo "$out" | jq -c .scenarios)"
fresh; edit 'm["scenarios"][0]["steps"][2]["evidence"][0]["quote"]="requests.get("'
out=$(run); [ "$(echo "$out" | jq -r '.scenarios.run[2].grade')" = "unknown" ] && pass "단계 근거가 틀리면 그 단계 unknown (exit 0)" || fail "단계 근거" "$out"
integrity 'm["scenarios"][0]["steps"][1]["box"]="ghost"' "박스 .ghost. 없음" "없는 박스"
integrity 'm["scenarios"][0]["steps"].reverse()' "반대 방향" "반대 방향만 있음"
integrity 'm["scenarios"][0]["steps"][0]["body"]="{{ghost}} 로 넘긴다"' "{{ghost}}" "없는 박스 토큰"
integrity 'm["scenarios"][0]["steps"]=m["scenarios"][0]["steps"]*3' "단계가 9개" "단계 8개 이상"
integrity 'm["scenarios"].append(dict(m["scenarios"][0]))' "겹친다" "시나리오 id 중복"
integrity 'm["scenarios"][0]["steps"][1]["body"]="run_job 을 부른다"' "run_job" "본문 코드 이름"
integrity 'm["scenarios"][0]["steps"][1]["substeps"][0]["label"]="작업 번호를 확인한다"' "상한 14" "하위 단계 길이"
integrity 'm["scenarios"]=[]' "1~4개" "시나리오 0개"
integrity 'm["scenarios"][0]["steps"]=[{"box":"core","title":"엔진","body":"엔진"},{"box":"engine","title":"실행기","body":"실행"}]' "가는 화살표가 없다" "묶음→자기 안쪽 단계는 화살표 아님"
fresh; edit 'm["views"]["L0"]["edges"].append({"from":"api","to":"init","label":"입구 확인","grade":"unknown","evidence":{}}); m["scenarios"][0]["steps"].append({"box":"init","title":"입구","body":"입구"})'
out=$(run); [ $? -eq 0 ] && [ "$(echo "$out" | jq -r '.scenarios.run[3].edge')" = "3" ] && pass "지나온 박스 중 하나에서 이어지면 통과 (나무 모양 — agent 뒤에 api 에서 init)" || fail "나무 모양 잇기" "$out"
fresh; edit 'del m["scenarios"]'; run >/dev/null; [ $? -eq 0 ] && pass "시나리오 없는 모델 통과" || fail "시나리오 없음"
echo "🔧 갈림길"
fresh; out=$(run); [ "$(echo "$out" | jq -c .branches)" = '{"1":"code"}' ] && pass "갈림길 조건 근거 판정 기록" || fail "갈림길 기록" "$(echo "$out" | jq -c .branches)"
fresh; edit 'm["views"]["L0"]["edges"][1]["when_evidence"]["quote"]="requests.get("'
out=$(run); [ $? -eq 0 ] && [ "$(echo "$out" | jq -r '.branches["1"]')" = "unknown" ] && pass "조건 근거가 틀리면 unknown (exit 0)" || fail "조건 근거" "$out"
integrity 'm["views"]["L0"]["edges"][1]["kind"]="maybe"' "call · branch" "kind 허용값"
integrity 'm["views"]["L0"]["edges"][1].pop("when")' "when 이 비었다" "갈림길에 when 필수"
integrity 'm["views"]["L0"]["edges"][1].pop("when_evidence")' "when_evidence 가 없다" "갈림길에 근거 필수"
integrity 'm["views"]["L0"]["edges"][0]["when"]="항상"' "갈림길.kind: branch.에만" "when 은 갈림길에만"
integrity 'm["views"]["L0"]["edges"][1]["when"]="run_job 이 끝나면"' "run_job" "조건에 코드 이름"
echo "🔧 누락 탐지"
mkdir -p "$T/r/graft/.graph"
cat > "$T/r/graft/.graph/wiring.json" <<'J'
{"meta":{"version":1},"edges":[
 {"source":"src/api/server.py#handle","target":"src/core/engine.py#run_job","relation":"calls"},
 {"source":"src/core/engine.py#run_job","target":"src/api/server.py#handle","relation":"calls"},
 {"source":"src/core/engine.py","target":"requests","relation":"imports"}]}
J
fresh; out=$(run)
[ "$(echo "$out" | jq -c '[.missing_edges[]|[.view,.from,.to]]')" = '[["L0","engine","api"]]' ] && pass "그림에 없는 관계 1건 — 잎 박스 단위 (방향 구분)" || fail "누락 탐지" "$(echo "$out" | jq -c .missing_edges)"
sed -i '' 's/"version":1/"version":2/' "$T/r/graft/.graph/wiring.json"
fresh; out=$(run)
echo "$out" | jq -e '(.missing_edges|length)==0 and (.missing_edges_skipped|test("버전"))' >/dev/null && pass "wiring 버전 불일치 → 건너뜀" || fail "버전 불일치" "$out"

echo "🔧 실제 graft (설치돼 있을 때만)"
REAL=$(PATH=/opt/homebrew/bin:/usr/local/bin:$PATH command -v graft || true)
if [ -n "$REAL" ]; then
  bash "$ELI5_FIX/make_repo.sh" "$T/real"
  (cd "$T/real" && "$REAL" build . >/dev/null 2>&1)
  cp "$ELI5_FIX/model.json" "$T/real.model.json"
  out=$(ELI5_GRAFT_BIN="$REAL" python3 "$V" "$T/real.model.json" --root "$T/real")
  [ "$(jq -r '.views.L0.edges[0].grade' "$T/real.model.json")" = "graft" ] && pass "실제 graft callers 로 graft 등급 유지" || fail "실제 graft" "$(echo "$out" | jq -c .downgrades)"
else
  echo "  ⏭️  graft 미설치 — 건너뜀"
fi
finish
