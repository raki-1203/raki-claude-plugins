#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
FM="$SCRIPT_DIR/scripts/frontmatter.py"

PASS=0; FAIL=0
pass() { PASS=$((PASS+1)); echo "  ✅ $1"; }
fail() { FAIL=$((FAIL+1)); echo "  ❌ $1"; }

TMP=$(mktemp -d)
trap "rm -rf $TMP" EXIT

# 유효한 v3 frontmatter
cat > "$TMP/valid.md" <<'EOF'
---
title: "Valid"
type: source-summary
sources: ["[[raw/foo]]"]
related: []
created: 2026-04-17
updated: 2026-04-17
description: "한 줄"
---
body
EOF
uv run python3 "$FM" validate "$TMP/valid.md" && pass "valid v3" || fail "valid v3"

# type enum 밖
cat > "$TMP/bad_type.md" <<'EOF'
---
title: "X"
type: analysis
sources: []
related: []
created: 2026-04-17
updated: 2026-04-17
description: "d"
---
EOF
out=$(uv run python3 "$FM" validate "$TMP/bad_type.md" 2>&1 || true)
echo "$out" | grep -q "invalid type" && pass "bad type rejected" || fail "bad type rejected"

# confidence 있으면 거부
cat > "$TMP/has_conf.md" <<'EOF'
---
title: "X"
type: concept
sources: []
related: []
created: 2026-04-17
updated: 2026-04-17
description: "d"
confidence: high
---
EOF
out=$(uv run python3 "$FM" validate "$TMP/has_conf.md" 2>&1 || true)
echo "$out" | grep -q "confidence" && pass "confidence rejected" || fail "confidence rejected"

# 필수 필드 누락
cat > "$TMP/missing.md" <<'EOF'
---
title: "X"
type: concept
---
EOF
out=$(uv run python3 "$FM" validate "$TMP/missing.md" 2>&1 || true)
echo "$out" | grep -q "missing" && pass "missing fields rejected" || fail "missing fields rejected"

# strip confidence
cat > "$TMP/strip.md" <<'EOF'
---
title: "X"
type: concept
sources: []
related: []
created: 2026-04-17
updated: 2026-04-17
description: "d"
confidence: high
---
body
EOF
uv run python3 "$FM" strip-confidence "$TMP/strip.md"
grep -q "confidence" "$TMP/strip.md" && fail "strip-confidence" || pass "strip-confidence"

echo "=== $PASS passed, $FAIL failed ==="
[ $FAIL -eq 0 ]
