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
python3 "$ELI5_BIN/validate.py" "$M" --root "$R" >/dev/null
python3 - "$M" <<'PY'
import json, sys
p = sys.argv[1]
m = json.load(open(p, encoding="utf-8"))
m["views"]["L0"]["hint"] = "</script><b>x</b>"
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
assert model["views"]["L0"]["hint"] == "</script><b>x</b>"
assert model["validation"]["counts"]["graft"] == 1
PY
[ "$(jq -r .commit "$S")" = "$(git -C "$R" rev-parse HEAD)" ] && pass "사이드카 commit = HEAD" || fail "사이드카 commit" "$(cat "$S")"
[ "$(jq -r .dirty "$S")" = "false" ] && [ "$(jq -r .version "$S")" = "1" ] && pass "dirty=false, version=1" || fail "사이드카 필드" "$(cat "$S")"
[ "$(jq -r .meta.commit "$M")" = "$(git -C "$R" rev-parse HEAD)" ] && pass "모델 meta.commit 갱신" || fail "meta.commit"
grep -q '<title>fixture 앱 — eli5</title>' "$H" && pass "title 치환" || fail "title"
grep -q 'window.ELI5' "$H" && grep -q 'eli5:select' "$H" && pass "패널 계약(window.ELI5·이벤트)" || fail "패널 계약"
echo "# x" >> "$R/src/core/engine.py"
python3 "$ELI5_BIN/render.py" "$M" --root "$R" >/dev/null
[ "$(jq -r .dirty "$S")" = "true" ] && pass "scope 안 미커밋 변경 → dirty=true" || fail "dirty 감지"
finish
