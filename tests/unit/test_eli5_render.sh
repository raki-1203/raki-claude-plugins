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
grep -q 'window.ELI5 = {MODEL, state, go, select}' "$H" && pass "window.ELI5 계약" || fail "window.ELI5"
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
! grep -q '340px' "$TPL" && grep -q 'aside.side{position:fixed' "$TPL" && grep -q 'classList.toggle("open"' "$TPL" \
  && pass "A: 카드는 박스를 누를 때만 열리는 겹침 카드 — 지도는 전체 폭" || fail "A: 겹침 카드"
grep -q '<details class="code"><summary>코드 자세히</summary>' "$TPL" && grep -q 'overflow-wrap:anywhere' "$TPL" \
  && pass "B: 코드·인터페이스는 접힌 '코드 자세히' 안, 긴 코드는 줄바꿈" || fail "B: 코드 접기"
if command -v node >/dev/null 2>&1; then
  CL=$(grep -o 'const codeList = .*;$' "$TPL")
  out=$(node -e "$CL; console.log(codeList({code: ['src/a.py', 'src/s/'], paths: ['src/api/', 'src/s/']}).join('|') + '#' + codeList({}).length)")
  [ "$out" = "src/a.py|src/s/|src/api/#0" ] && pass "C: 들어 있는 코드 중복 제거" || fail "C: 중복 제거" "$out"
fi
finish
