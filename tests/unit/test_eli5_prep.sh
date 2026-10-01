#!/bin/bash
set -uo pipefail
source "$(dirname "$0")/../fixtures/eli5/lib.sh"
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
P="$ELI5_BIN/graft_prep.py"

echo "🔧 graft_prep — 인덱스 없음"
bash "$ELI5_FIX/make_repo.sh" "$T/r"
out=$(python3 "$P" --root "$T/r/src")
[ "$(echo "$out" | jq -r .graft)" = "index-built" ] && pass "인덱스 없으면 빌드" || fail "인덱스 없으면 빌드" "$out"
[ "$(echo "$out" | jq -r .root)" = "$(cd "$T/r" && pwd -P)" ] && pass "하위 경로에서도 레포 루트 탐지" || fail "루트 탐지" "$out"
[ -f "$T/r/graft/INDEX.md" ] && pass "graft/ 생성" || fail "graft/ 생성"
[ ! -f "$T/r/.gitignore" ] && pass "graft 가 새로 만든 .gitignore 제거" || fail ".gitignore 제거"
[ -z "$(git -C "$T/r" status --short)" ] && pass "git status 깨끗" || fail "git status 깨끗" "$(git -C "$T/r" status --short | tr '\n' ' ')"
EX="$T/r/.git/info/exclude"
grep -qx '/graft/' "$EX" && grep -qx '/.ignore' "$EX" && grep -qx '/.eli5/' "$EX" && pass "exclude 3항목" || fail "exclude 3항목" "$(cat "$EX")"

echo "🔧 graft_prep — 재실행"
out2=$(python3 "$P" --root "$T/r")
[ "$(echo "$out2" | jq -r .graft)" = "ok" ] && pass "인덱스 있으면 ok" || fail "재실행 ok" "$out2"
[ "$(grep -cx '/graft/' "$EX")" = "1" ] && pass "exclude 중복 없음" || fail "exclude 중복" "$(cat "$EX")"

echo "🔧 graft_prep — 추적 중인 .gitignore"
bash "$ELI5_FIX/make_repo.sh" "$T/r2"
echo "node_modules/" > "$T/r2/.gitignore"
git -C "$T/r2" add .gitignore
git -C "$T/r2" -c user.email=t@t -c user.name=t commit -qm gi
python3 "$P" --root "$T/r2" >/dev/null
[ "$(cat "$T/r2/.gitignore")" = "node_modules/" ] && pass "추적 .gitignore 원복" || fail "추적 .gitignore 원복" "$(cat "$T/r2/.gitignore")"
[ -z "$(git -C "$T/r2" status --short)" ] && pass "r2 git status 깨끗" || fail "r2 git status" "$(git -C "$T/r2" status --short)"

echo "🔧 graft_prep — graft 없음 / git 아님"
bash "$ELI5_FIX/make_repo.sh" "$T/r3"
out3=$(ELI5_GRAFT_BIN=/nonexistent/graft python3 "$P" --root "$T/r3")
[ "$(echo "$out3" | jq -r .graft)" = "absent" ] && pass "graft 없음 → absent" || fail "absent" "$out3"
grep -qx '/.eli5/' "$T/r3/.git/info/exclude" && pass "graft 없어도 .eli5 exclude" || fail ".eli5 exclude"
mkdir -p "$T/plain"
python3 "$P" --root "$T/plain" >/dev/null && fail "git 아니면 exit 1" || pass "git 아니면 exit 1"
finish
