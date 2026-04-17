#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$SCRIPT_DIR/scripts/slug.sh"

PASS=0
FAIL=0
pass() { PASS=$((PASS+1)); echo "  ✅ $1"; }
fail() { FAIL=$((FAIL+1)); echo "  ❌ $1 (got: '$2')"; }

# 기본 케이스
r=$(rakis_slug "https://karpathy.ai/llm-wiki-talk")
[ "$r" = "karpathy-ai-llm-wiki-talk" ] && pass "url basic" || fail "url basic" "$r"

r=$(rakis_slug "https://github.com/plastic-labs/honcho")
[ "$r" = "plastic-labs-honcho" ] && pass "github repo" || fail "github repo" "$r"

r=$(rakis_slug "Langchain — Anatomy of an Agent Harness (Part 1)")
[ "$r" = "langchain-anatomy-of-an-agent-harness-part-1" ] && pass "title with punct" || fail "title with punct" "$r"

# 60자 제한
long_input=$(printf 'a%.0s' {1..80})
r=$(rakis_slug "$long_input")
[ ${#r} -le 60 ] && pass "60 char limit" || fail "60 char limit" "$r (${#r})"

# 공백 전용은 실패해야 함
r=$(rakis_slug "   " 2>&1) && fail "empty input" "$r" || pass "empty input rejected"

echo "=== $PASS passed, $FAIL failed ==="
[ $FAIL -eq 0 ]
