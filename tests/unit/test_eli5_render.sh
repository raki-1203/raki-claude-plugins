#!/bin/bash
set -uo pipefail
source "$(dirname "$0")/../fixtures/eli5/lib.sh"
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
R="$T/저장소 a:1"
bash "$ELI5_FIX/make_repo.sh" "$R"
export FAKE_GRAFT_CALLERS="$ELI5_FIX/callers.json"
mkdir -p "$R/.eli5"; M="$R/.eli5/app.model.json"
cp "$ELI5_FIX/model.json" "$M"

echo "🔧 render"
python3 "$ELI5_BIN/render.py" "$M" --root "$R" >/dev/null 2>&1 && fail "validate 전 render 거부" || pass "validate 전 render 거부"
cp "$M" "$T/v2.model.json"
python3 - "$T/v2.model.json" <<'PY'
import json, sys
p = sys.argv[1]; m = json.load(open(p, encoding="utf-8")); m["meta"]["version"] = 2; m["validation"] = {}
json.dump(m, open(p, "w", encoding="utf-8"), ensure_ascii=False)
PY
out=$(python3 "$ELI5_BIN/render.py" "$T/v2.model.json" --root "$R"); rc=$?
[ $rc -eq 1 ] && echo "$out" | jq -e '.error|test("v3")' >/dev/null && pass "v2 모델 render 거부" || fail "v2 거부" "rc=$rc $out"
python3 "$ELI5_BIN/validate.py" "$M" --root "$R" >/dev/null
python3 - "$M" <<'PY'
import json, sys
p = sys.argv[1]
m = json.load(open(p, encoding="utf-8"))
m["views"]["L0"]["hint"] = "</script><b>x</b><!--y-->"
json.dump(m, open(p, "w", encoding="utf-8"), ensure_ascii=False)
PY
out=$(python3 "$ELI5_BIN/render.py" "$M" --root "$R"); rc=$?
[ $rc -eq 0 ] && pass "exit 0" || fail "exit 0" "$out"
H="$R/.eli5/app.html"; S="$R/.eli5/app.eli5.json"
[ -f "$H" ] && [ -f "$S" ] && pass "html + 사이드카 생성" || fail "출력 파일"
python3 - "$H" <<'PY' && pass "MODEL 파싱 가능 + </script> 이스케이프" || fail "MODEL 파싱"
import json, re, sys
h = open(sys.argv[1], encoding="utf-8").read()
assert h.count("</script>") == 1, h.count("</script>")
m = re.search(r"const MODEL = (.*?);\n\(function", h, re.S)
model = json.loads(m.group(1))
assert "<!--" not in h.split("const MODEL = ", 1)[1].split(";\n(function", 1)[0]
assert model["views"]["L0"]["hint"] == "</script><b>x</b><!--y-->"
assert model["validation"]["counts"]["graft"] == 1
PY
[ "$(jq -r .commit "$S")" = "$(git -C "$R" rev-parse HEAD)" ] && pass "사이드카 commit = HEAD" || fail "사이드카 commit" "$(cat "$S")"
[ "$(jq -r .dirty "$S")" = "false" ] && [ "$(jq -r .version "$S")" = "1" ] && pass "dirty=false, version=1" || fail "사이드카 필드" "$(cat "$S")"
[ "$(jq -r .meta.commit "$M")" = "$(git -C "$R" rev-parse HEAD)" ] && pass "모델 meta.commit 갱신" || fail "meta.commit"
grep -q '<title>fixture 앱 — eli5</title>' "$H" && pass "title 치환" || fail "title"
for id in summary legend chips ev side unknowns downs missing; do
  grep -q "id=\"$id\"" "$H" || { fail "DOM 계약 #$id"; continue; }
done && pass "DOM 계약 (summary·legend·chips·ev·side·unknowns·downs·missing)"
grep -q '<details id="report">' "$H" && pass "검증 리포트는 접힌 details" || fail "접힌 리포트"
grep -q 'window.ELI5 = {MODEL, state, go, select, play}' "$H" && pass "window.ELI5 계약" || fail "window.ELI5"
! grep -q 'eli5:select\|panel\|/api/ask' "$H" && pass "패널 흔적 없음" || fail "패널 흔적"
! grep -q 'n.lines' "$H" && pass "박스에 lines 를 그리지 않음" || fail "lines 잔존"
echo "# x" >> "$R/src/core/engine.py"
python3 "$ELI5_BIN/render.py" "$M" --root "$R" >/dev/null
[ "$(jq -r .dirty "$S")" = "true" ] && pass "scope 안 미커밋 변경 → dirty=true" || fail "dirty 감지"
python3 - "$ELI5_BIN" "$T" <<'PY' && pass "원자적 쓰기 — 실패 시 기존 파일 보존·임시 파일 없음" || fail "원자적 쓰기"
import sys; from pathlib import Path
sys.path.insert(0, sys.argv[1]); import render
d = Path(sys.argv[2]); p = d / "a.html"; p.write_text("old", encoding="utf-8")
try:
    render.write_atomic(p, None)  # 쓰기 중 TypeError
except TypeError:
    pass
assert p.read_text(encoding="utf-8") == "old"
assert not [x for x in d.iterdir() if x.name.startswith(".a.html.")]
render.write_atomic(p, "new"); assert p.read_text(encoding="utf-8") == "new"
PY
if command -v node >/dev/null 2>&1; then
  SHORT=$(grep -o 'const short = .*;$' "$ELI5_FIX/../../../skills/eli5/assets/map.html")
  out=$(node -e "$SHORT; console.log([short('src/core/'), short('src/core/engine.py:5'), short('src/a/x.py#f → src/b/y.py#g'), short('handle')].join('|'))")
  [ "$out" = "core/|engine.py:5|x.py#f → y.py#g|handle" ] && pass "칩 이름 줄이기 (폴더는 마지막 폴더/)" || fail "칩 이름 줄이기" "$out"
else
  echo "  ⏭️  node 없음 — 칩 이름 테스트 건너뜀"
fi
TPL="$ELI5_FIX/../../../skills/eli5/assets/map.html"
! grep -q 'grid-template-columns:minmax(0,1fr) 340px' "$TPL" && grep -q 'aside.side{position:fixed' "$TPL" && grep -q 'classList.toggle("open"' "$TPL" \
  && pass "A: 카드는 박스를 누를 때만 열리는 겹침 카드 — 지도는 전체 폭" || fail "A: 겹침 카드"
grep -q '<details class="code"><summary>코드 자세히</summary>' "$TPL" && grep -q 'overflow-wrap:anywhere' "$TPL" \
  && pass "B: 코드·인터페이스는 접힌 '코드 자세히' 안, 긴 코드는 줄바꿈" || fail "B: 코드 접기"
if command -v node >/dev/null 2>&1; then
  CL=$(grep -o 'const codeList = .*;$' "$TPL")
  out=$(node -e "$CL; console.log(codeList({code: ['src/a.py', 'src/s/'], paths: ['src/api/', 'src/s/']}).join('|') + '#' + codeList({}).length)")
  [ "$out" = "src/a.py|src/s/|src/api/#0" ] && pass "C: 들어 있는 코드 중복 제거" || fail "C: 중복 제거" "$out"
fi
python3 - "$H" "$M" <<'PY' && pass "payload 에 배치(layout), 저장 모델에는 없음" || fail "payload layout"
import json, re, sys
h = open(sys.argv[1], encoding="utf-8").read()
model = json.loads(re.search(r"const MODEL = (.*?);\n\(function", h, re.S).group(1))
L = model["layout"]
assert set(L["boxes"]) == {"api", "engine", "init", "agent"} and set(L["frames"]) == {"core"}, L
assert len(L["edges"]) == 3 and L["size"][0] > 0
assert "layout" not in json.load(open(sys.argv[2], encoding="utf-8"))
PY
! grep -q '안으로' "$TPL" && ! grep -q 'data-go' "$TPL" && pass "층 이동 UI 없음" || fail "층 이동 UI 잔존"
grep -q 'MODEL.layout' "$TPL" && grep -q 'class: "frame' "$TPL" && grep -q 'data-sel' "$TPL" && ! grep -q 'function box(' "$TPL" \
  && pass "지도는 MODEL.layout 으로 그리고 묶음·안쪽 박스 버튼이 있다" || fail "layout 그리기"
grep -q '속한 묶음' "$TPL" && grep -q 'data-sel="${esc(n.group)}"' "$TPL" && pass "안쪽 박스 카드에 속한 묶음 링크" || fail "속한 묶음 링크"
grep -q 'body.card-open main{padding-right' "$TPL" && grep -q 'classList.toggle("card-open"' "$TPL" && grep -q 'width:min(340px,100vw)' "$TPL" \
  && pass "카드가 열리면 지도를 밀어낸다 (넓은 화면)" || fail "카드 밀어내기"
grep -q 'id="scbar"' "$TPL" && grep -q 'data-step' "$TPL" && grep -q 'data-back' "$TPL" && grep -q '#scenario=' "$TPL" && grep -q 'class: "badge"' "$TPL" \
  && pass "시나리오 UI — 버튼 줄·단계 이동·시나리오로 돌아가기·주소·번호 배지" || fail "시나리오 UI"
python3 - "$H" <<'PY' && pass "payload 에 시나리오 기록" || fail "payload 시나리오"
import json, re, sys
h = open(sys.argv[1], encoding="utf-8").read()
m = json.loads(re.search(r"const MODEL = (.*?);\n\(function", h, re.S).group(1))
assert m["scenarios"][0]["id"] == "run" and len(m["validation"]["scenarios"]["run"]) == 3
PY
if command -v node >/dev/null 2>&1; then
  BODY=$(grep -o 'const stepBody = .*;$' "$TPL"); ESC=$(grep -o 'const esc = .*;$' "$TPL")
  out=$(node -e "const NODE={core:{title:'작업 <엔진>'}}; $ESC; $BODY; console.log(stepBody('<b>x</b> {{core}} {{ghost}}'))")
  echo "$out" | grep -q '&lt;b&gt;x&lt;/b&gt;' && echo "$out" | grep -q 'data-sel="core">작업 &lt;엔진&gt;</button>' && echo "$out" | grep -q '{{ghost}}' \
    && pass "본문 이스케이프 — {{id}} 만 박스 버튼" || fail "본문 이스케이프" "$out"
fi
grep -q 'querySelector(".node.cur, .frame.cur")' "$TPL" && grep -q 'block: "nearest"' "$TPL" && pass "단계를 넘기면 현재 박스가 보이게 스크롤" || fail "현재 박스 스크롤"
grep -q 'class="allsteps"' "$TPL" && grep -q 'class="now"' "$TPL" && pass "카드는 지금 단계 하나만 크게, 전체 단계는 접어서" || fail "지금 단계 카드"
grep -q 'S.steps.slice(0, state.step + 1)' "$TPL" && grep -q 'rows.slice(1, state.step + 1)' "$TPL" && pass "지도는 지나온 단계까지만 번호·강조" || fail "지나온 길만"
grep -q -- '--accent-soft' "$TPL" && grep -q '.node.cur rect.bg{fill:var(--accent-soft)' "$TPL" && pass "지금 단계 박스는 색을 채워 강조" || fail "지금 박스 강조"
grep -q '<details id="rulesbox"' "$TPL" && pass "설계 규칙은 접어 둔다" || fail "규칙 접기"
grep -q 'id: "fk-" + g' "$TPL" && grep -q 'function forkHtml' "$TPL" && grep -q 'data-hl' "$TPL" && grep -q 'data-play' "$TPL" && grep -q 'class: "forkmark"' "$TPL" \
  && pass "갈림길 UI — 마름모 시작점·◆·갈라지는 목록·화살표 강조·다른 길 따라가기" || fail "갈림길 UI"
grep -q 'const forks = id => (V.edges || \[\]).map((e, i) => \[e, i\]).filter((\[e\]) => e.kind === "branch" && (e.from === id || (NODE\[id\] && e.from === NODE\[id\].group)))' "$TPL" \
  && pass "안쪽 박스는 속한 묶음의 갈림길도 보인다" || fail "묶음 갈림길"
grep -q '위에서부터 차례로 본다' "$TPL" && pass "갈래가 여럿이면 위에서부터 차례로 본다고 알린다" || fail "갈래 순서 안내"
finish
