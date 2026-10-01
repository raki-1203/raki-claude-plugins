# eli5 테스트 공용 — source 해서 쓴다
ELI5_FIX="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$ELI5_FIX/../../.." && pwd)"
ELI5_BIN="$REPO_ROOT/skills/eli5/bin"
PASS=0
FAIL=0
pass() { PASS=$((PASS+1)); echo "  ✅ $1"; }
fail() { FAIL=$((FAIL+1)); echo "  ❌ $1${2:+ (got: $2)}"; }
finish() { echo "=== $PASS passed, $FAIL failed ==="; [ "$FAIL" -eq 0 ]; }
export ELI5_GRAFT_BIN="$ELI5_FIX/bin/graft"
export ELI5_CLAUDE_BIN="$ELI5_FIX/bin/claude"
