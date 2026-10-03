#!/bin/bash
set -uo pipefail
source "$(dirname "$0")/../fixtures/eli5/lib.sh"

py() { python3 - "$ELI5_BIN" <<PY
import sys, copy; sys.path.insert(0, sys.argv[1])
import layout
V = {"nodes": [{"id": "api", "row": 0, "col": 0}, {"id": "core"},
               {"id": "engine", "group": "core", "row": 0, "col": 1},
               {"id": "init", "group": "core", "row": 1, "col": 1},
               {"id": "agent", "row": 2, "col": 0}],
     "edges": [{"from": "api", "to": "core"}, {"from": "core", "to": "agent"}, {"from": "agent", "to": "api"}]}
$1
PY
}
check() { if out=$(py "$1" 2>&1); then pass "$2"; else fail "$2" "$out"; fi; }

echo "🔧 layout — 계산"
check 'assert layout.children(V) == {"core": ["engine", "init"]}' "묶음 찾기"
check 'assert layout.children({"nodes": [{"id": "a", "group": "ghost"}]}) == {}' "없는 group 은 묶음 아님"
check 'L = layout.compute(V); assert L["boxes"]["api"] == [44, 78, 180, 72] and "core" not in L["boxes"], L["boxes"]' "박스 좌표"
check 'L = layout.compute(V); assert L["frames"]["core"] == [320, 30, 208, 316], L["frames"]' "묶음 = 안쪽 외접 + 여백"
check 'L = layout.compute(V); assert len(L["edges"]) == 3 and all(L["edges"]) and L["size"] == [558, 544], L' "선분·크기"
check 'v = copy.deepcopy(V); v["edges"].append({"from": "api", "to": "ghost"}); assert layout.compute(v)["edges"][3] is None' "끝이 없는 화살표는 None"

echo "🔧 layout — 검사"
check 'assert layout.problems(V, layout.compute(V)) == []' "깨끗한 배치"
check 'v = copy.deepcopy(V); v["nodes"][4].update(row=0, col=2); p = layout.problems(v, layout.compute(v)); assert any("engine" in x and "박스를 지난다" in x for x in p) and any("core" in x and "묶음을 지난다" in x for x in p), p' "관통 — 박스·묶음"
check 'v = copy.deepcopy(V); v["nodes"].append({"id": "x", "row": 1, "col": 1}); v["nodes"][3].update(row=2, col=1); p = layout.problems(v, layout.compute(v)); assert any("묶음 테두리 안에" in x for x in p), p' "묶음 밖 박스의 테두리 침범"
check 'v = copy.deepcopy(V); v["edges"].append({"from": "engine", "to": "init"}); assert layout.problems(v, layout.compute(v)) == []' "자기 묶음 안 화살표 통과"
check 'assert not layout.segment_hits_rect([0, 0, 100, 0], [10, 0, 20, 20]) and layout.segment_hits_rect([0, 10, 100, 10], [10, 0, 20, 20])' "경계 스침은 통과"
check 'assert layout.rects_overlap([0, 0, 10, 10], [5, 5, 10, 10]) and not layout.rects_overlap([0, 0, 10, 10], [10, 0, 5, 5])' "사각형 겹침"
check 'v = {"nodes": [{"id": "a", "row": 0, "col": 0}, {"id": "f"}, {"id": "b", "group": "f", "row": 1, "col": 0}, {"id": "c", "group": "f", "row": 1, "col": 1}, {"id": "x", "row": 2, "col": 0}], "edges": [{"from": "a", "to": "f"}]}; p = layout.problems(v, layout.compute(v)); assert p == [], p' "줄 사이 화살표는 충분히 길다"
check 'v = {"nodes": [{"id": "f"}, {"id": "a", "group": "f", "row": 0, "col": 0}, {"id": "b", "group": "f", "row": 0, "col": 1}, {"id": "g"}, {"id": "c", "group": "g", "row": 1, "col": 0}, {"id": "d", "group": "g", "row": 1, "col": 1}], "edges": [{"from": "a", "to": "g"}]}; L = layout.compute(v); s = L["edges"][0]; n = ((s[2]-s[0])**2 + (s[3]-s[1])**2) ** 0.5; assert n >= layout.MIN_EDGE, n' "묶음 사이 화살표도 MIN_EDGE 이상"
check 'v = {"nodes": [{"id": "a", "row": 0, "col": 0}, {"id": "b", "row": 0, "col": 1, "span": 1}], "edges": [{"from": "a", "to": "b"}]}; L = layout.compute(v); L["edges"][0] = [0, 0, 10, 0]; p = layout.problems(v, L); assert any("너무 짧" in x for x in p), p' "너무 짧은 화살표는 거부"
finish
