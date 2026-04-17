# rakis v3.0.0 Karpathy Alignment Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Karpathy LLM Wiki 3-Layer 사상에 완전 정렬하여 rakis를 v3.0.0으로 재설계 — `source-analyze` 단일 스킬을 `source-fetch` + `wiki-ingest`로 분리하고, raw 불변성·frontmatter 표준·마이그레이션 스킬·outputs/overview를 도입한다.

**Architecture:** 기존 플러그인은 마크다운 기반 스킬(Claude가 프롬프트로 실행)과 bash 유틸 · test.sh · lint.sh로 구성. v3에서도 동일 패턴 유지 — 스킬 SKILL.md 재작성이 산출물의 중심이며, 슬러그 생성/frontmatter 검증/마이그레이션은 `scripts/` 하위 bash/python 유틸로 분리한다. 테스트는 `lint.sh`(정적 lint)와 `test.sh`(통합)를 v3 검증 항목으로 확장.

**Tech Stack:** Bash · Python 3.13 (`uv run`) · Markdown (SKILL.md) · Obsidian MCP · notebooklm-py · repomix · graphify CLI

**Reference spec:** `docs/superpowers/specs/2026-04-17-karpathy-alignment-v3-design.md`

---

## File Structure

**신규 (Create):**
- `skills/source-fetch/SKILL.md` — URL/파일/repo를 raw/에 수집
- `skills/source-fetch/references/fetchers.md` — 유형별 fetch 전략
- `skills/source-fetch/references/enrich.md` — NotebookLM 임계값·호출
- `skills/migrate-v3/SKILL.md` — v2→v3 마이그레이션
- `skills/migrate-v3/references/checks.md` — pre-flight 상세
- `scripts/slug.sh` — slug 정규화 유틸
- `scripts/frontmatter.py` — frontmatter 파싱·검증
- `scripts/migrate_v3.py` — 실제 마이그레이션 실행
- `tests/fixtures/vault-v2-sample/` — golden 테스트 픽스처
- `tests/fixtures/vault-v3-expected/` — golden 기대 상태
- `tests/fixtures/sample-article.md` — 스모크 E2E 고정 입력
- `tests/e2e/smoke.sh` — 스모크 E2E 러너
- `tests/unit/test_slug.sh` — slug 유닛 테스트
- `tests/unit/test_frontmatter.sh` — frontmatter 유닛 테스트
- `tests/golden/run_migrate.sh` — golden 러너
- `CHANGELOG.md` — v3.0.0 섹션

**수정 (Modify):**
- `skills/wiki-ingest/SKILL.md` — 리디자인 (raw 전수 스캔 + 증분)
- `skills/wiki-query/SKILL.md` — `--scope project`, overview.md 참조, v3 스키마
- `skills/wiki-wrap-up/SKILL.md` — v3 frontmatter, graphify wiki-target 안내
- `skills/wiki-lint/SKILL.md` — outputs/ 저장, overview.md 갱신, v3 enum 검증
- `skills/wiki-init/SKILL.md` — v3 볼트 스키마로 초기화 (overview.md, outputs/)
- `commands/setup.md` — v2 구조 감지 시 migrate-v3 선행 안내
- `commands/help.md` — v3 명령 목록
- `commands/skill-mapping.md` — v3 스킬 맵
- `lint.sh` — frontmatter type enum 검증, confidence 거부, v3 스킬 목록
- `test.sh` — v3 파이프라인 smoke, source-analyze 제거 검증
- `.claude-plugin/plugin.json` — version 3.0.0
- `package.json` — version 3.0.0
- `README.md` — v3 워크플로(`source-fetch` → `wiki-ingest`)

**삭제 (Delete):**
- `skills/source-analyze/` — 구조 전체 제거 (references/ 포함)

---

## Phase 1 — 공통 기반 (유틸리티 + 테스트 스캐폴드)

### Task 1: slug 정규화 유틸 작성 (TDD)

**Files:**
- Create: `scripts/slug.sh`
- Create: `tests/unit/test_slug.sh`

- [ ] **Step 1: 실패 테스트 작성**

```bash
# tests/unit/test_slug.sh
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
```

- [ ] **Step 2: 테스트 실행해서 실패 확인**

Run: `bash tests/unit/test_slug.sh`
Expected: FAIL (scripts/slug.sh 없음 → source 실패)

- [ ] **Step 3: slug 유틸 구현**

```bash
# scripts/slug.sh
#!/bin/bash
# rakis v3 slug 정규화 — URL/제목을 kebab-case ASCII 60자 이하로

rakis_slug() {
  local input="$1"
  # URL 전처리: scheme/www 제거, path 유지
  input=$(echo "$input" | sed -E 's|^https?://(www\.)?||')
  # github.com/{owner}/{repo} → owner-repo
  if [[ "$input" =~ ^github\.com/([^/]+)/([^/]+) ]]; then
    input="${BASH_REMATCH[1]}-${BASH_REMATCH[2]}"
  fi
  # 소문자
  input=$(echo "$input" | tr '[:upper:]' '[:lower:]')
  # 비-ASCII 영숫자/공백/-/_ 를 공백으로
  input=$(echo "$input" | LC_ALL=C sed 's/[^a-z0-9 _-]/ /g')
  # 공백/언더스코어 → -
  input=$(echo "$input" | tr ' _' '--')
  # 연속 - 축약
  input=$(echo "$input" | sed 's/--*/-/g')
  # 앞뒤 - 제거
  input=$(echo "$input" | sed 's/^-//;s/-$//')
  # 60자 제한
  input=$(echo "$input" | cut -c1-60 | sed 's/-$//')
  if [ -z "$input" ]; then
    echo "error: empty slug after normalization" >&2
    return 1
  fi
  echo "$input"
}

# CLI 모드: `bash scripts/slug.sh <input>`
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  rakis_slug "$1"
fi
```

- [ ] **Step 4: 테스트 실행해서 통과 확인**

Run: `bash tests/unit/test_slug.sh`
Expected: PASS (모든 케이스)

- [ ] **Step 5: 커밋**

```bash
chmod +x scripts/slug.sh tests/unit/test_slug.sh
git add scripts/slug.sh tests/unit/test_slug.sh
git commit -m "feat(v3): slug 정규화 유틸 + 유닛 테스트"
```

### Task 2: frontmatter 검증 유틸 (TDD)

**Files:**
- Create: `scripts/frontmatter.py`
- Create: `tests/unit/test_frontmatter.sh`

- [ ] **Step 1: 실패 테스트 작성**

```bash
# tests/unit/test_frontmatter.sh
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
uv run python3 "$FM" validate "$TMP/bad_type.md" 2>&1 | grep -q "invalid type" && pass "bad type rejected" || fail "bad type rejected"

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
uv run python3 "$FM" validate "$TMP/has_conf.md" 2>&1 | grep -q "confidence" && pass "confidence rejected" || fail "confidence rejected"

# 필수 필드 누락
cat > "$TMP/missing.md" <<'EOF'
---
title: "X"
type: concept
---
EOF
uv run python3 "$FM" validate "$TMP/missing.md" 2>&1 | grep -q "missing" && pass "missing fields rejected" || fail "missing fields rejected"

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
```

- [ ] **Step 2: 실패 확인**

Run: `bash tests/unit/test_frontmatter.sh`
Expected: FAIL (scripts/frontmatter.py 없음)

- [ ] **Step 3: 유틸 구현**

```python
# scripts/frontmatter.py
"""rakis v3 frontmatter 검증 및 수정 유틸.

Usage:
    python3 frontmatter.py validate <file.md>
    python3 frontmatter.py strip-confidence <file.md>
"""
from __future__ import annotations
import sys
import re
from pathlib import Path

VALID_TYPES = {
    "source-summary", "project", "concept",
    "entity", "comparison", "index",
}
REQUIRED = ["title", "type", "sources", "related", "created", "updated", "description"]

FM_PATTERN = re.compile(r"^---\n(.*?)\n---\n", re.DOTALL)


def parse(text: str) -> tuple[dict, str, int, int]:
    m = FM_PATTERN.match(text)
    if not m:
        raise ValueError("no frontmatter block")
    body = text[m.end():]
    fm_text = m.group(1)
    fm: dict[str, str] = {}
    for line in fm_text.splitlines():
        if ":" in line and not line.startswith((" ", "-", "\t")):
            key, _, val = line.partition(":")
            fm[key.strip()] = val.strip()
    return fm, body, m.start(1), m.end(1)


def validate(path: Path) -> list[str]:
    text = path.read_text(encoding="utf-8")
    try:
        fm, _, _, _ = parse(text)
    except ValueError as e:
        return [f"{path}: {e}"]
    errs: list[str] = []
    if "confidence" in fm:
        errs.append(f"{path}: confidence field is removed in v3")
    for key in REQUIRED:
        if key not in fm:
            errs.append(f"{path}: missing required field '{key}'")
    t = fm.get("type", "")
    if t and t not in VALID_TYPES:
        errs.append(f"{path}: invalid type '{t}' (expected one of {sorted(VALID_TYPES)})")
    return errs


def strip_confidence(path: Path) -> bool:
    text = path.read_text(encoding="utf-8")
    new = re.sub(r"^confidence:.*\n", "", text, flags=re.MULTILINE)
    if new != text:
        path.write_text(new, encoding="utf-8")
        return True
    return False


def main() -> int:
    if len(sys.argv) < 3:
        print("usage: frontmatter.py {validate|strip-confidence} <file>", file=sys.stderr)
        return 2
    cmd, filearg = sys.argv[1], sys.argv[2]
    path = Path(filearg)
    if not path.exists():
        print(f"error: {path} not found", file=sys.stderr)
        return 2
    if cmd == "validate":
        errs = validate(path)
        for e in errs:
            print(e, file=sys.stderr)
        return 0 if not errs else 1
    if cmd == "strip-confidence":
        changed = strip_confidence(path)
        print("stripped" if changed else "no change")
        return 0
    print(f"error: unknown command {cmd}", file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main())
```

- [ ] **Step 4: 테스트 실행해서 통과 확인**

Run: `bash tests/unit/test_frontmatter.sh`
Expected: PASS (전 케이스)

- [ ] **Step 5: 커밋**

```bash
chmod +x tests/unit/test_frontmatter.sh
git add scripts/frontmatter.py tests/unit/test_frontmatter.sh
git commit -m "feat(v3): frontmatter 검증/confidence strip 유틸"
```

### Task 3: lint.sh v3 확장

**Files:**
- Modify: `lint.sh`

- [ ] **Step 1: 기존 lint.sh 끝에 v3 검사 블록 추가**

`lint.sh`의 기존 "스킬별 검증" 루프 바깥(파일 하단)에 다음을 추가:

```bash
# ─── v3 추가 검증 ───

echo "🧪 v3 유닛 테스트"

if bash tests/unit/test_slug.sh >/dev/null 2>&1; then
  pass "slug 유닛 테스트"
else
  fail "slug 유닛 테스트 — bash tests/unit/test_slug.sh"
fi

if bash tests/unit/test_frontmatter.sh >/dev/null 2>&1; then
  pass "frontmatter 유닛 테스트"
else
  fail "frontmatter 유닛 테스트 — bash tests/unit/test_frontmatter.sh"
fi

echo ""

echo "📋 v3 스킬 집합"

EXPECTED=(source-fetch wiki-ingest wiki-query wiki-wrap-up wiki-lint wiki-init migrate-v3)
FORBIDDEN=(source-analyze)

for s in "${EXPECTED[@]}"; do
  if [ -d "skills/$s" ]; then
    pass "스킬 존재: $s"
  else
    fail "스킬 누락: $s"
  fi
done

for s in "${FORBIDDEN[@]}"; do
  if [ -d "skills/$s" ]; then
    fail "스킬 제거 안됨 (v3에서 제거): $s"
  else
    pass "스킬 제거됨: $s"
  fi
done
```

- [ ] **Step 2: 아직 실행하지 않음 — 나머지 스킬 작업 후 검증 예정**

이 블록은 이후 Phase에서 스킬을 만들며 단계적으로 PASS로 전환된다. 지금은 동시에 FAIL로 떨어져도 정상.

- [ ] **Step 3: 커밋**

```bash
git add lint.sh
git commit -m "feat(v3): lint.sh에 v3 스킬 집합·유닛 테스트 검사 추가"
```

---

## Phase 2 — `source-fetch` 스킬 신규 작성

### Task 4: source-fetch SKILL.md 작성

**Files:**
- Create: `skills/source-fetch/SKILL.md`
- Create: `skills/source-fetch/references/fetchers.md`
- Create: `skills/source-fetch/references/enrich.md`

- [ ] **Step 1: 메인 SKILL.md 작성**

```markdown
---
name: source-fetch
description: Use when the user wants to add an external source (URL, GitHub repo, PDF, local file) to the Obsidian vault — saves the original to raw/ and optionally enriches with NotebookLM briefing/study-guide/mindmap. Does NOT write to wiki/.
---

# source-fetch — 원본만 raw/에 저장

외부 소스를 `raw/`에 불변 원본으로 저장한다. 어떤 LLM 분석도 하지 않는다. wiki 컴파일은 `/rakis:wiki-ingest`가 담당.

## Vault 경로 탐지

1. 환경변수 `OBSIDIAN_VAULT_PATH` 있으면 사용
2. `~/Library/Mobile Documents/com~apple~CloudDocs/Documents/Vault`
3. Vault `CLAUDE.md`에 "Three-Layer" 또는 "raw/" 언급 검증

## 인자

```
/rakis:source-fetch <url-or-path> [--slug <slug>] [--no-enrich|--force-enrich]
```

## Phase 0: 유형 감지 + slug 생성

| 유형 | 감지 | raw 경로 |
|------|------|---------|
| GitHub repo | `github.com/{owner}/{repo}` | `raw/repos/{owner}-{repo}/` |
| YouTube | `youtube.com`/`youtu.be` | `raw/articles/{slug}/` |
| PDF | `.pdf` | `raw/papers/{slug}/` |
| 웹 URL | `http(s)://` 기타 | `raw/articles/{slug}/` |
| 로컬 파일 | path 존재 | `raw/articles/{slug}/` (복사) |

slug는 `scripts/slug.sh`의 `rakis_slug` 함수로 정규화. `--slug` 인자가 있으면 그대로 사용(정규화 패스).

## Phase 1: 중복 체크

- `raw/{type}/{slug}/meta.json` 존재 여부 확인
- 존재 시: "이미 수집됨. 재수집(덮어쓰기) 또는 건너뛰기?" 질문 후 대기

## Phase 2: 원본 수집

> **유형별 상세**: `references/fetchers.md` 참조

요약:
- GitHub repo → `npx -y repomix --remote <url> --output raw/repos/{slug}/repomix.txt`
- 웹/YouTube/LinkedIn/X → WebFetch 또는 notebooklm 소스 텍스트로 `raw/articles/{slug}/source.md`
- PDF → 다운로드하여 `raw/papers/{slug}/source.pdf`
- 로컬 파일 → `cp` 후 확장자 유지

`meta.json`은 매번 작성:

```json
{
  "type": "repo|article|paper",
  "source_url": "<원본 URL 또는 로컬경로>",
  "captured_at": "<ISO 8601>",
  "contributor": "raki-1203",
  "slug": "<slug>",
  "size_bytes": <정수>,
  "source_file": "source.md|source.pdf|repomix.txt"
}
```

## Phase 3: NotebookLM enrich (임계값 자동)

> **임계값·호출 상세**: `references/enrich.md` 참조

요약 규칙:

| 조건 | 기본 동작 | `--no-enrich` | `--force-enrich` |
|------|----------|---------------|------------------|
| repo | enrich | skip | enrich |
| PDF | enrich | skip | enrich |
| 웹/로컬 텍스트 ≥5000자 | enrich | skip | enrich |
| 그 외 (짧은 글/트윗/이미지) | skip | skip | enrich |

enrich 조건 충족 시:
1. `command -v notebooklm` 확인 → 없으면 안내 후 건너뜀 (에러 아님)
2. `notebooklm auth check --test` → 실패 시 건너뜀
3. 노트북 생성 + 원본 업로드
4. `notebooklm notebook mindmap <id> --output raw/{type}/{slug}/notebooklm/mindmap.md`
5. `notebooklm notebook briefing <id> --output raw/{type}/{slug}/notebooklm/briefing.md`
6. `notebooklm notebook study-guide <id> --output raw/{type}/{slug}/notebooklm/study-guide.md`
7. 노트북 삭제 (ID 추적 안 함)

## Phase 4: 출력

- 요약 출력: 경로, 크기, enrich 여부
- **wiki 쓰지 않음**. 마지막 줄:
  > "raw 저장 완료. `/rakis:wiki-ingest` 로 위키에 반영하세요."

## 에러 처리

| 실패 지점 | 대응 |
|-----------|------|
| repomix | `gh clone` 폴백 → 실패 시 에러 |
| WebFetch | 사용자에게 텍스트 직접 입력 요청 |
| notebooklm 인증/업로드 | enrich 건너뛰고 raw만 저장 (에러 아님) |
| slug 정규화 공백 | 사용자에게 `--slug` 요청 |

## references/

| 파일 | 언제 |
|------|------|
| `fetchers.md` | 유형별 fetch 명령 상세 |
| `enrich.md` | NotebookLM 호출 순서·실패 처리 |
```

- [ ] **Step 2: references/fetchers.md 작성**

```markdown
# fetchers — 유형별 원본 수집 상세

## GitHub repo

```bash
mkdir -p "raw/repos/{slug}"
npx -y repomix --remote "{url}" --output "raw/repos/{slug}/repomix.txt"
```

repomix 실패 시 (예: 프라이빗 repo, 토큰 이슈):

```bash
gh repo clone "{owner}/{repo}" /tmp/repo-{slug}
cd /tmp/repo-{slug} && npx -y repomix --output "$VAULT/raw/repos/{slug}/repomix.txt"
rm -rf /tmp/repo-{slug}
```

`meta.json`에 `stars`, `language`, `license` 추가 가능:
```bash
gh api "repos/{owner}/{repo}" --jq '{stars: .stargazers_count, language: .language, license: .license.spdx_id}'
```

## 웹 페이지 (일반 URL)

WebFetch 도구 사용:
```
WebFetch(url="{url}", prompt="Extract main content as plain text. Preserve headings and code blocks.")
```

결과를 `raw/articles/{slug}/source.md`에 저장. 상단에 메타 주석:
```markdown
<!-- url: {url} -->
<!-- captured_at: {ISO8601} -->

{본문}
```

## YouTube

notebooklm-py가 YouTube URL을 직접 소스로 받음. `source.md`에는 자리표시자만:
```markdown
<!-- url: {url} -->
<!-- type: youtube -->
<!-- captured_at: {ISO8601} -->

(원본은 NotebookLM이 처리. 이 파일은 포인터 역할.)
```

enrich 시 notebooklm에 URL 직접 업로드. YouTube는 enrich 임계값 무관하게 enrich 시도(자막 없으면 skip).

## PDF

```bash
curl -L -o "raw/papers/{slug}/source.pdf" "{url}"
```

크기 검증: 0바이트면 실패로 간주.

## LinkedIn / X (Twitter)

WebFetch 후 본문 텍스트만 추출:
```
WebFetch(url="{url}", prompt="Extract the post body text and author name. No UI chrome.")
```

`source.md`에 저장 형식:
```markdown
<!-- url: {url} -->
<!-- platform: linkedin|x -->
<!-- captured_at: {ISO8601} -->

**Author:** {author}

{본문}
```

## 이미지

로컬 복사 + Vision 설명:
```
Read(file_path="{path}")
```

설명을 텍스트로 작성하여 `source.md`에 저장. 원본 이미지도 같은 폴더에 복사.

## 로컬 파일

```bash
cp "{path}" "raw/articles/{slug}/source.{ext}"
```

확장자는 원본 유지(`.md`, `.txt`, `.pdf` 등).
```

- [ ] **Step 3: references/enrich.md 작성**

```markdown
# enrich — NotebookLM 보조 산출물 생성

## 임계값 판정

```python
def should_enrich(meta, flag):
    if flag == "force":
        return True
    if flag == "no":
        return False
    t = meta["type"]
    if t in ("repo", "paper"):
        return True
    if t == "article" and meta["size_bytes"] >= 5000:
        return True
    return False
```

## 사전 조건

```bash
command -v notebooklm >/dev/null || { echo "notebooklm 미설치 — skip"; exit 0; }
notebooklm auth check --test 2>&1 | grep -q "Authentication is valid" || {
  echo "notebooklm 인증 만료 — skip"; exit 0;
}
```

둘 중 하나라도 실패하면 **에러 아님**, enrich만 건너뛴다.

## 실행 순서

```bash
NB_ID=$(notebooklm notebook create --title "{slug}" --format id)

# 업로드 (유형별)
case "$TYPE" in
  repo)   notebooklm source add --file "raw/repos/{slug}/repomix.txt" "$NB_ID" ;;
  paper)  notebooklm source add --file "raw/papers/{slug}/source.pdf" "$NB_ID" ;;
  article)
    if [ -n "$URL" ]; then
      notebooklm source add --url "$URL" "$NB_ID"
    else
      notebooklm source add --file "raw/articles/{slug}/source.md" "$NB_ID"
    fi
    ;;
esac

# 생성 대기 (notebooklm --wait 플래그 사용)
notebooklm notebook mindmap "$NB_ID" --wait --output "raw/{type}/{slug}/notebooklm/mindmap.md"
notebooklm notebook briefing "$NB_ID" --wait --output "raw/{type}/{slug}/notebooklm/briefing.md"
notebooklm notebook study-guide "$NB_ID" --wait --output "raw/{type}/{slug}/notebooklm/study-guide.md"

# 노트북 삭제 (ID 추적 안 함)
notebooklm notebook delete "$NB_ID" --yes
```

## 대용량 소스 분할

repomix.txt가 2MB 초과 시 notebooklm이 400 에러. 분할 업로드:

```bash
split -b 1800k -a 2 -d "raw/repos/{slug}/repomix.txt" /tmp/{slug}-part-
for p in /tmp/{slug}-part-*; do
  notebooklm source add --file "$p" "$NB_ID"
done
rm /tmp/{slug}-part-*
```

## Mock 모드 (CI/테스트용)

`RAKIS_NOTEBOOKLM_MOCK=1` 환경변수가 설정되면 실제 CLI 호출 대신 스텁 파일 생성:

```bash
if [ "${RAKIS_NOTEBOOKLM_MOCK:-0}" = "1" ]; then
  mkdir -p "raw/{type}/{slug}/notebooklm"
  echo "# Mock Mindmap for {slug}" > "raw/{type}/{slug}/notebooklm/mindmap.md"
  echo "# Mock Briefing for {slug}" > "raw/{type}/{slug}/notebooklm/briefing.md"
  echo "# Mock Study Guide for {slug}" > "raw/{type}/{slug}/notebooklm/study-guide.md"
  exit 0
fi
```
```

- [ ] **Step 4: lint.sh 실행하여 스킬 파싱 검증**

Run: `bash lint.sh 2>&1 | grep -E "source-fetch|source-analyze"`
Expected: source-fetch PASS (name 일치, description 존재), source-analyze는 아직 있어서 "제거됨" 검사는 FAIL

- [ ] **Step 5: 커밋**

```bash
git add skills/source-fetch/
git commit -m "feat(v3): source-fetch 스킬 신규 — raw 수집 + NotebookLM 임계값 enrich"
```

---

## Phase 3 — `wiki-ingest` 리디자인

### Task 5: wiki-ingest SKILL.md 재작성

**Files:**
- Modify: `skills/wiki-ingest/SKILL.md`

- [ ] **Step 1: 기존 파일 백업 읽기**

Run: `cat skills/wiki-ingest/SKILL.md | head -40`
기존 구조 확인 후 전면 재작성.

- [ ] **Step 2: SKILL.md 전면 재작성**

```markdown
---
name: wiki-ingest
description: Use when raw sources have been fetched (via /rakis:source-fetch or manual drop) and need to be compiled into wiki/ pages. Scans raw/ incrementally (only unprocessed sources), creates wiki/sources/{slug}.md, updates affected concept/project pages, and bumps index.md + log.md. Does NOT fetch — upstream work belongs to source-fetch.
---

# wiki-ingest — raw → wiki 컴파일

raw에 수집된 소스 중 아직 위키에 반영되지 않은 것을 찾아 `wiki/sources/{slug}.md`를 만들고, 영향받는 기존 위키 페이지를 업데이트한다.

## Vault 경로 탐지

source-fetch와 동일 순서 (`OBSIDIAN_VAULT_PATH` → iCloud → CLAUDE.md 검증).

## 인자

```
/rakis:wiki-ingest [--full]
```

- 기본: 증분 (미처리 소스만)
- `--full`: 전체 재컴파일 (마이그레이션·대규모 재구조화 용)

## Phase 0: 미처리 소스 탐지

```bash
# 1. 전수 스캔
find "$VAULT/raw" -name "meta.json" -type f

# 2. 각 meta.json마다 slug 추출 → wiki/sources/{slug}.md 존재 확인
# 존재하지 않으면 "미처리"로 분류
```

`--full` 플래그 있으면 기존 `wiki/sources/*` 페이지를 삭제하고 전체를 미처리로 취급(단, `index.md`·`overview.md`·`log.md`·`projects/`·`concepts/`·`entities/`는 보존).

미처리 0건이면 "변경 없음" 출력 후 종료.

## Phase 1: 소스 페이지 생성

각 미처리 소스마다:

1. `raw/{type}/{slug}/source.md|source.pdf|repomix.txt` 읽기
2. `raw/{type}/{slug}/notebooklm/briefing.md` 존재 시 핵심 요약 근거로 활용
3. `raw/{type}/{slug}/notebooklm/study-guide.md` 존재 시 주요 질문 추출
4. `wiki/sources/{slug}.md` 생성

Frontmatter (필수):

```yaml
---
title: "{meta.title or slug}"
type: source-summary
sources: ["[[raw/{type}/{slug}]]"]
related: []
created: {meta.captured_at date}
updated: {today}
description: "{한 줄 요약 — 20자 이내}"
comment: "{사용자가 제공했으면 기록. 없으면 생략}"
---
```

본문 구조 (섹션):
- **요약**: 3-5줄
- **핵심 개념**: 순차 bullet
- **주요 인용/발췌**: briefing.md 기반 (있을 때)
- **연관 질문**: study-guide.md 기반 (있을 때)
- **원본**: `[[raw/.../source...]]`

## Phase 2: 기존 페이지 업데이트 (index.md 기반 연결)

1. `$VAULT/index.md` 읽기
2. 새 소스의 핵심 키워드(`description`, 상위 개념)로 index 섹션 매칭
3. 매칭된 기존 wiki 페이지에 대해:
   - 해당 페이지 frontmatter `related:`에 `[[sources/{slug}]]` 추가 (중복 방지)
   - 해당 페이지 본문에 "관련 소스" 섹션이 있으면 한 줄 append, 없으면 섹션 생성
4. 매칭되는 프로젝트 있으면 `wiki/projects/{name}.md`의 섹션(Decisions/Patterns/Gotchas 중 적합한 곳)에 한 줄 추가
5. 새 개념이 등장했는데 `wiki/concepts/*`에 없으면 사용자 승인 후 신규 페이지 생성

## Phase 3: index.md · log.md 갱신

- `index.md`:
  - `sources/` 섹션에 `- [[sources/{slug}]] — {description}` 추가 (알파벳 정렬)
  - 새로 생성한 `concepts/`·`projects/` 페이지가 있으면 해당 섹션에도 추가
- `log.md`:
  - 위쪽에 `## [{YYYY-MM-DD}] {slug} | ingest — {description}` 한 줄 삽입

## Phase 4: 출력 + graphify 안내

출력:
```
✓ N개 소스 반영
  - sources/{slug1}.md (신규)
  - sources/{slug2}.md (신규)
  - concepts/{name}.md (업데이트)
  - projects/{name}.md (업데이트)

그래프 증분 업데이트 권장:
  cd "{VAULT}" && /graphify wiki --update
```

## 에러 처리

| 상황 | 대응 |
|------|------|
| raw meta.json 파싱 실패 | 해당 소스 건너뛰고 경고 출력, 계속 진행 |
| 대상 wiki 페이지 쓰기 실패 | 트랜잭션처럼 롤백 어려움 — 실패 지점까지 보고 후 종료 |
| `--full` 실행 중 중단 | 기존 sources/ 디렉터리는 이미 삭제됐으므로 다시 `--full` 재실행 권장 안내 |

## frontmatter 검증

모든 신규·업데이트 페이지는 쓰기 직후 검증:

```bash
uv run python3 "$PLUGIN_ROOT/scripts/frontmatter.py" validate "{path}"
```

실패 시 해당 파일을 `.broken.md`로 이름 변경하고 경고 출력.
```

- [ ] **Step 3: lint.sh 실행**

Run: `bash lint.sh 2>&1 | grep wiki-ingest`
Expected: frontmatter·description 검사 PASS

- [ ] **Step 4: 커밋**

```bash
git add skills/wiki-ingest/SKILL.md
git commit -m "refactor(v3): wiki-ingest raw 전수 스캔 + 증분 + index 기반 연결"
```

---

## Phase 4 — `wiki-query`, `wiki-wrap-up`, `wiki-lint` v3 반영

### Task 6: wiki-query 업데이트

**Files:**
- Modify: `skills/wiki-query/SKILL.md`

- [ ] **Step 1: 현재 Step 1의 `index.md` 읽기 전에 `overview.md` 참조 추가**

`skills/wiki-query/SKILL.md`에서 답변형 분기(Step 1~3) 섹션을 찾아 다음으로 교체:

```markdown
## Step 1 — 답변형 분기

1. **overview.md 먼저 읽기**: `$VAULT/wiki/overview.md` 존재 시 먼저 스캔하여 질문과 관련된 주요 페이지 힌트 수집 (없으면 skip).
2. **index.md 읽기**: 전체 페이지 목록에서 관련 frontmatter `description`·제목 매칭.
3. **개별 페이지 탐색**: Step 2에서 식별된 1-3개 wiki 페이지를 읽고 답변 합성.

## Step 2 — 탐색형 분기 (변경 없음)

(기존 Step 1-A 그대로 유지)

...
```

- [ ] **Step 2: `--scope project` 플래그 추가**

SKILL.md 상단 인자 섹션에 추가:

```markdown
## 인자

```
/rakis:wiki-query "<질문>" [--scope project]
```

- 기본: 전체 vault 탐색 (답변형/탐색형 자동 분기)
- `--scope project`: 탐색 범위를 `wiki/projects/{현재디렉토리basename}.md` + 그 `related:` 이웃으로 제한. 프로젝트 컨텍스트가 확실한 질문용.
```

Step 1-A(탐색형) 내부에 분기 처리:

```markdown
### 1-A-0: 스코프 체크

`--scope project`가 주어지면:
1. 현재 작업 디렉토리 basename으로 `wiki/projects/{name}.md` 찾기
2. 해당 페이지의 `related:` frontmatter에서 이웃 페이지 수집
3. graphify query는 이 페이지 집합에만 한정(`--nodes` 옵션 또는 필터 후처리)
4. 매칭되는 프로젝트 페이지 없으면 "프로젝트 페이지 없음. 스코프 해제" 경고 후 전체 탐색
```

- [ ] **Step 3: graphify 안내 문구 업데이트**

탐색형 폴백 메시지와 `--update` 안내에서 target을 `wiki`로:

```
설치 후 `cd "{VAULT}" && /graphify wiki --update` 실행 권장.
```

- [ ] **Step 4: confidence 필드 참조 제거**

SKILL.md 전역에서 `confidence` 단어 검색:
```bash
grep -n confidence skills/wiki-query/SKILL.md
```
발견되면 해당 줄 제거 (frontmatter 예시에도 없어야 함).

- [ ] **Step 5: lint.sh로 검증**

Run: `bash lint.sh 2>&1 | grep wiki-query`
Expected: PASS

- [ ] **Step 6: 커밋**

```bash
git add skills/wiki-query/SKILL.md
git commit -m "refactor(v3): wiki-query overview 참조, --scope project, graphify wiki 타겟"
```

### Task 7: wiki-wrap-up 업데이트

**Files:**
- Modify: `skills/wiki-wrap-up/SKILL.md`

- [ ] **Step 1: graphify 안내 target 변경**

SKILL.md 끝부분 "graphify 증분 업데이트 안내" 문구를 다음으로 교체:

```markdown
## 종료 안내

작업 저장 후 다음 명령을 사용자에게 안내:

> 그래프 증분 업데이트 권장: `cd "{VAULT}" && /graphify wiki --update`
```

- [ ] **Step 2: frontmatter 예시에서 confidence 제거**

SKILL.md 안의 모든 frontmatter 템플릿에서 `confidence:` 라인 제거. `type:` 값은 enum 내로만(`project|concept|...`).

- [ ] **Step 3: "예외 규칙" 명시**

SKILL.md 상단 "동작 범위" 섹션에 한 줄:

```markdown
> **예외 규칙(v3)**: wrap-up은 raw를 거치지 않고 wiki/log에 직접 쓴다. 대화 기반 지식은 log.md가 출처 역할을 겸한다.
```

- [ ] **Step 4: lint.sh 검증**

Run: `bash lint.sh 2>&1 | grep wiki-wrap-up`
Expected: PASS

- [ ] **Step 5: 커밋**

```bash
git add skills/wiki-wrap-up/SKILL.md
git commit -m "refactor(v3): wiki-wrap-up graphify wiki 타겟, confidence 제거"
```

### Task 8: wiki-lint 업데이트

**Files:**
- Modify: `skills/wiki-lint/SKILL.md`

- [ ] **Step 1: 검사 항목에 v3 스키마 추가**

SKILL.md "검사 항목" 섹션에 다음을 추가(기존 항목 유지):

```markdown
### v3 스키마 검사

1. **frontmatter `confidence` 필드 금지**
   ```bash
   grep -rln "^confidence:" "$VAULT/wiki/" && echo "위반: confidence 필드 발견"
   ```

2. **`type:` enum 검증** (source-summary / project / concept / entity / comparison / index)
   ```bash
   find "$VAULT/wiki" -name "*.md" -exec uv run python3 "$PLUGIN_ROOT/scripts/frontmatter.py" validate {} \;
   ```

3. **`raw/` 불변성 검증**
   `raw/`에 `graph-report.md`, `analysis.md` 같은 LLM 파생물이 있는지 확인:
   ```bash
   find "$VAULT/raw" -maxdepth 3 \( -name "graph-report.md" -o -name "analysis.md" \) -type f
   ```
   발견되면 "migrate-v3 미완료" 경고.
```

- [ ] **Step 2: outputs/ 저장 로직 추가**

"출력 처리" 섹션을 다음으로 교체:

```markdown
## 출력 처리

1. **상세 리포트 저장**: `$VAULT/outputs/lint-{YYYY-MM-DD}.md`에 발견 건 전체 기록 (재실행 시 덮어씀)
2. **overview.md 통계 갱신**: `$VAULT/wiki/overview.md`의 "통계" 섹션을 다음 블록으로 교체(없으면 생성):
   ```markdown
   ## 통계 (자동 갱신 · 최근 lint: {YYYY-MM-DD})

   - 총 wiki 페이지: {N}
   - 소스: {S}
   - 프로젝트: {P}
   - 개념: {C}
   - 최근 7일 새 페이지: {n}
   - 린트 위반: {V}건 (상세: `outputs/lint-{date}.md`)
   ```
3. **log.md 한 줄**: `## [{YYYY-MM-DD}] lint | {V}건 발견 (고아 {O}, stale {S}, frontmatter {F})`
4. **graphify 풀 리빌드 안내** (출력 마지막):
   > `cd "{VAULT}" && /graphify wiki` — 주 1회 풀 리빌드 권장
```

- [ ] **Step 3: 테스트 실행**

Run: `bash lint.sh 2>&1 | grep wiki-lint`
Expected: PASS

- [ ] **Step 4: 커밋**

```bash
git add skills/wiki-lint/SKILL.md
git commit -m "refactor(v3): wiki-lint outputs/ 저장, overview 갱신, v3 스키마 검증"
```

### Task 9: wiki-init v3 스키마 반영

**Files:**
- Modify: `skills/wiki-init/SKILL.md`

- [ ] **Step 1: 초기 생성 구조에 overview.md·outputs/ 추가**

SKILL.md "초기 구조 생성" 섹션에 다음 항목 추가:

```markdown
## 초기 구조 (v3)

```bash
mkdir -p "$VAULT"/{raw/articles,raw/repos,raw/papers,wiki/sources,wiki/projects,wiki/concepts,wiki/entities,wiki/comparisons,outputs}
```

초기 파일:
- `wiki/overview.md` — 서술형 대시보드 템플릿
- `index.md` — 빈 섹션 스켈레톤 (sources/projects/concepts/entities/comparisons)
- `log.md` — `# Log\n\n시간순 기록. Claude가 자동으로 추가.\n`
- `CLAUDE.md` — v3 스키마 설명 (type enum, raw 불변성, wrap-up 예외 규칙)
- `.rakis-v3-migrated` — marker (새 볼트는 마이그레이션 불필요 표시)

### overview.md 템플릿

```markdown
---
title: "Vault Overview"
type: index
sources: []
related: []
created: {YYYY-MM-DD}
updated: {YYYY-MM-DD}
description: "볼트 대시보드"
---

# {Vault 이름} Overview

## 주제 요약

(ingest 쌓이면 wiki-lint가 자동 갱신)

## 통계

(wiki-lint가 자동 갱신)

## 최근 활동

(wiki-lint가 자동 갱신)
```

### CLAUDE.md 스키마 핵심 내용

```markdown
# Vault Schema

## 3-Layer
- raw/     : 불변 원본. graph-report·analysis 같은 LLM 산출물 저장 금지
- wiki/    : LLM compile 결과. 사람/LLM 모두 편집 가능
- outputs/ : 일회성 산출물 (lint, graph-report 등). 날짜 고정

## frontmatter
- type 필드는 enum: source-summary | project | concept | entity | comparison | index
- confidence 필드 사용 금지 (v3에서 제거)

## 예외
- wrap-up은 raw를 거치지 않고 wiki·log에 직접 쓴다. log.md가 출처 역할.
```
```

- [ ] **Step 2: lint.sh 실행**

Run: `bash lint.sh 2>&1 | grep wiki-init`
Expected: PASS

- [ ] **Step 3: 커밋**

```bash
git add skills/wiki-init/SKILL.md
git commit -m "refactor(v3): wiki-init v3 스키마로 초기 볼트 생성"
```

---

## Phase 5 — `migrate-v3` 스킬 + 실행 스크립트

### Task 10: migrate_v3.py 작성 (TDD)

**Files:**
- Create: `scripts/migrate_v3.py`
- Create: `tests/golden/run_migrate.sh`
- Create: `tests/fixtures/vault-v2-sample/` (디렉토리 + 파일)
- Create: `tests/fixtures/vault-v3-expected/` (디렉토리 + 파일)

- [ ] **Step 1: v2 fixture 볼트 생성**

```bash
mkdir -p tests/fixtures/vault-v2-sample/{raw/repos/foo,wiki/sources,wiki/concepts}

cat > tests/fixtures/vault-v2-sample/raw/repos/foo/repomix.txt <<'EOF'
(샘플 repomix 원본)
EOF

cat > tests/fixtures/vault-v2-sample/raw/repos/foo/graph-report.md <<'EOF'
# Graph Report (v2 artifact)
...
EOF

cat > tests/fixtures/vault-v2-sample/raw/repos/foo/analysis.md <<'EOF'
---
title: foo analysis
type: analysis
confidence: high
---
(v2 analysis)
EOF

cat > tests/fixtures/vault-v2-sample/wiki/sources/bar.md <<'EOF'
---
title: bar
type: source-summary
sources: ["[[raw/articles/bar]]"]
related: []
created: 2026-04-10
updated: 2026-04-10
description: "bar 요약"
confidence: medium
---
body
EOF

cat > tests/fixtures/vault-v2-sample/Home.md <<'EOF'
# Home (v2)
Dashboard content.
EOF

cat > tests/fixtures/vault-v2-sample/log.md <<'EOF'
## [2026-04-10] bar | ingest
EOF

cat > tests/fixtures/vault-v2-sample/CLAUDE.md <<'EOF'
# Three-Layer Schema
raw/ wiki/ ...
EOF
```

- [ ] **Step 2: v3 expected fixture 생성**

```bash
mkdir -p tests/fixtures/vault-v3-expected/{raw/repos/foo,wiki/sources,wiki/concepts,outputs/archive-v2/repos/foo}

# repomix.txt 그대로 유지
cp tests/fixtures/vault-v2-sample/raw/repos/foo/repomix.txt tests/fixtures/vault-v3-expected/raw/repos/foo/repomix.txt

# meta.json 생성됨
cat > tests/fixtures/vault-v3-expected/raw/repos/foo/meta.json <<'EOF'
{
  "type": "repo",
  "source_url": "",
  "captured_at": "",
  "contributor": "raki-1203",
  "slug": "foo",
  "size_bytes": 17,
  "source_file": "repomix.txt"
}
EOF

# graph-report.md, analysis.md는 archive로 이동
cp tests/fixtures/vault-v2-sample/raw/repos/foo/graph-report.md tests/fixtures/vault-v3-expected/outputs/archive-v2/repos/foo/graph-report.md
cp tests/fixtures/vault-v2-sample/raw/repos/foo/analysis.md tests/fixtures/vault-v3-expected/outputs/archive-v2/repos/foo/analysis.md

# wiki/sources/bar.md — confidence 제거
cat > tests/fixtures/vault-v3-expected/wiki/sources/bar.md <<'EOF'
---
title: bar
type: source-summary
sources: ["[[raw/articles/bar]]"]
related: []
created: 2026-04-10
updated: 2026-04-10
description: "bar 요약"
---
body
EOF

# Home.md 사라지고 wiki/overview.md로
mkdir -p tests/fixtures/vault-v3-expected/wiki
cat > tests/fixtures/vault-v3-expected/wiki/overview.md <<'EOF'
---
title: "Vault Overview"
type: index
sources: []
related: []
created: MIGRATION_DATE
updated: MIGRATION_DATE
description: "볼트 대시보드"
---

# Home (v2)
Dashboard content.

## 통계

(wiki-lint가 자동 갱신)
EOF

# log.md 끝에 마이그레이션 기록 추가
cat > tests/fixtures/vault-v3-expected/log.md <<'EOF'
## [MIGRATION_DATE] migrate-v3 | v2 → v3 마이그레이션 완료 (archived 2, frontmatter 2)
## [2026-04-10] bar | ingest
EOF

cp tests/fixtures/vault-v2-sample/CLAUDE.md tests/fixtures/vault-v3-expected/CLAUDE.md
```

- [ ] **Step 3: golden 러너 작성 (실패 테스트)**

```bash
# tests/golden/run_migrate.sh
#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP=$(mktemp -d)
trap "rm -rf $TMP" EXIT

cp -R "$SCRIPT_DIR/tests/fixtures/vault-v2-sample/." "$TMP/"

export RAKIS_MIGRATION_DATE=2026-04-17
uv run python3 "$SCRIPT_DIR/scripts/migrate_v3.py" "$TMP"

# 비교: 날짜 플레이스홀더 치환
EXPECTED=$(mktemp -d)
trap "rm -rf $TMP $EXPECTED" EXIT
cp -R "$SCRIPT_DIR/tests/fixtures/vault-v3-expected/." "$EXPECTED/"
find "$EXPECTED" -type f -exec sed -i.bak "s/MIGRATION_DATE/2026-04-17/g" {} \;
find "$EXPECTED" -name "*.bak" -delete

# diff (marker 파일은 무시)
if diff -r --exclude=".rakis-v3-migrated" "$TMP" "$EXPECTED"; then
  echo "✅ golden diff empty"
  exit 0
else
  echo "❌ golden diff above"
  exit 1
fi
```

- [ ] **Step 4: 실패 확인**

Run: `chmod +x tests/golden/run_migrate.sh && bash tests/golden/run_migrate.sh`
Expected: FAIL (scripts/migrate_v3.py 없음)

- [ ] **Step 5: migrate_v3.py 구현**

```python
# scripts/migrate_v3.py
"""rakis v2 → v3 볼트 마이그레이션.

- raw/repos/*/graph-report.md · analysis.md → outputs/archive-v2/
- frontmatter에서 confidence 제거
- raw/repos/*/ 에 meta.json 없으면 생성
- Home.md → wiki/overview.md 리네이밍
- outputs/ 디렉토리 생성
- log.md에 마이그레이션 기록 한 줄 삽입

Usage:
    python3 migrate_v3.py <vault-path> [--dry-run]
"""
from __future__ import annotations
import argparse
import json
import os
import shutil
import sys
from datetime import date
from pathlib import Path


MIGRATION_DATE_ENV = "RAKIS_MIGRATION_DATE"


def today_str() -> str:
    override = os.environ.get(MIGRATION_DATE_ENV)
    return override if override else date.today().isoformat()


def archive_legacy_artifacts(vault: Path, dry_run: bool) -> int:
    count = 0
    for legacy_name in ("graph-report.md", "analysis.md"):
        for src in vault.glob(f"raw/repos/*/{legacy_name}"):
            rel = src.relative_to(vault)
            dst = vault / "outputs/archive-v2" / rel.relative_to("raw")
            if dry_run:
                print(f"MOVE  {src} → {dst}")
            else:
                dst.parent.mkdir(parents=True, exist_ok=True)
                shutil.move(str(src), str(dst))
            count += 1
    return count


def ensure_meta_json(vault: Path, dry_run: bool) -> int:
    count = 0
    for repo_dir in vault.glob("raw/repos/*"):
        if not repo_dir.is_dir():
            continue
        meta = repo_dir / "meta.json"
        if meta.exists():
            continue
        source_files = [f for f in ("repomix.txt", "source.md", "source.pdf")
                        if (repo_dir / f).exists()]
        src = source_files[0] if source_files else "unknown"
        size = (repo_dir / src).stat().st_size if src != "unknown" else 0
        data = {
            "type": "repo",
            "source_url": "",
            "captured_at": "",
            "contributor": "raki-1203",
            "slug": repo_dir.name,
            "size_bytes": size,
            "source_file": src,
        }
        if dry_run:
            print(f"CREATE {meta}")
        else:
            meta.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
        count += 1
    return count


def strip_confidence_all(vault: Path, dry_run: bool) -> int:
    count = 0
    for md in list(vault.glob("wiki/**/*.md")) + list(vault.glob("raw/**/*.md")):
        text = md.read_text(encoding="utf-8")
        if "\nconfidence:" in text or text.startswith("confidence:"):
            new = "".join(
                line for line in text.splitlines(keepends=True)
                if not line.lstrip().startswith("confidence:")
            )
            if dry_run:
                print(f"STRIP {md}")
            else:
                md.write_text(new, encoding="utf-8")
            count += 1
    return count


def promote_home_to_overview(vault: Path, dry_run: bool) -> bool:
    home = vault / "Home.md"
    overview = vault / "wiki/overview.md"
    if not home.exists() or overview.exists():
        return False
    original = home.read_text(encoding="utf-8")
    d = today_str()
    new_body = (
        "---\n"
        "title: \"Vault Overview\"\n"
        "type: index\n"
        "sources: []\n"
        "related: []\n"
        f"created: {d}\n"
        f"updated: {d}\n"
        "description: \"볼트 대시보드\"\n"
        "---\n\n"
        f"{original}\n\n"
        "## 통계\n\n"
        "(wiki-lint가 자동 갱신)\n"
    )
    if dry_run:
        print(f"MOVE  {home} → {overview} (with v3 template)")
        return True
    overview.parent.mkdir(parents=True, exist_ok=True)
    overview.write_text(new_body, encoding="utf-8")
    home.unlink()
    return True


def ensure_outputs_dir(vault: Path, dry_run: bool) -> bool:
    outputs = vault / "outputs"
    if outputs.exists():
        return False
    if dry_run:
        print(f"MKDIR {outputs}")
    else:
        outputs.mkdir(parents=True, exist_ok=True)
    return True


def append_log(vault: Path, archived: int, stripped: int, dry_run: bool) -> None:
    log = vault / "log.md"
    existing = log.read_text(encoding="utf-8") if log.exists() else ""
    line = f"## [{today_str()}] migrate-v3 | v2 → v3 마이그레이션 완료 (archived {archived}, frontmatter {stripped})\n"
    new = line + existing
    if dry_run:
        print(f"PREPEND {log}: {line.rstrip()}")
    else:
        log.write_text(new, encoding="utf-8")


def write_marker(vault: Path, dry_run: bool) -> None:
    marker = vault / ".rakis-v3-migrated"
    if marker.exists():
        return
    if dry_run:
        print(f"TOUCH {marker}")
    else:
        marker.write_text(today_str() + "\n", encoding="utf-8")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("vault")
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    vault = Path(args.vault).expanduser().resolve()
    if not vault.exists():
        print(f"error: {vault} not found", file=sys.stderr)
        return 2
    if (vault / ".rakis-v3-migrated").exists():
        print("already migrated — marker present, aborting", file=sys.stderr)
        return 0

    archived = archive_legacy_artifacts(vault, args.dry_run)
    ensure_meta_json(vault, args.dry_run)
    stripped = strip_confidence_all(vault, args.dry_run)
    promote_home_to_overview(vault, args.dry_run)
    ensure_outputs_dir(vault, args.dry_run)
    append_log(vault, archived, stripped, args.dry_run)
    if not args.dry_run:
        write_marker(vault, args.dry_run)

    if args.dry_run:
        print("\nDRY RUN — no files modified")
    else:
        print(f"\nMigration complete: archived {archived}, stripped confidence from {stripped} files")
        print("\nNext steps:")
        print(f'  rm -rf "{vault}/graphify-out/"   # v2 그래프 캐시 삭제')
        print(f'  cd "{vault}" && /graphify wiki    # v3 풀 빌드')
    return 0


if __name__ == "__main__":
    sys.exit(main())
```

- [ ] **Step 6: golden 테스트 재실행 — 통과 확인**

Run: `bash tests/golden/run_migrate.sh`
Expected: PASS (diff 없음)

- [ ] **Step 7: dry-run 보존 테스트**

```bash
TMP=$(mktemp -d)
cp -R tests/fixtures/vault-v2-sample/. "$TMP/"
BEFORE=$(find "$TMP" -type f | xargs ls -la | sha256sum)
uv run python3 scripts/migrate_v3.py "$TMP" --dry-run
AFTER=$(find "$TMP" -type f | xargs ls -la | sha256sum)
[ "$BEFORE" = "$AFTER" ] && echo "✅ dry-run 파일 보존" || echo "❌ dry-run이 파일 수정함"
rm -rf "$TMP"
```

Expected: ✅

- [ ] **Step 8: 커밋**

```bash
git add scripts/migrate_v3.py tests/fixtures/ tests/golden/
git commit -m "feat(v3): migrate_v3.py + golden 테스트 + 픽스처 볼트"
```

### Task 11: migrate-v3 SKILL.md 작성

**Files:**
- Create: `skills/migrate-v3/SKILL.md`
- Create: `skills/migrate-v3/references/checks.md`

- [ ] **Step 1: SKILL.md 작성**

```markdown
---
name: migrate-v3
description: Use once per vault to upgrade from rakis v2.x structure to v3.0 — archives raw/ LLM artifacts (graph-report/analysis.md), strips confidence frontmatter, promotes Home.md to wiki/overview.md, creates outputs/ dir, and writes a one-shot marker. Idempotent — safe to re-run, but aborts if marker exists.
---

# migrate-v3 — v2 → v3 볼트 마이그레이션

## 언제 쓰나

- v2.x rakis를 쓰던 사용자가 v3.0으로 업그레이드한 직후 1회
- 마커 파일(`.rakis-v3-migrated`)이 이미 있으면 건너뜀

## 인자

```
/rakis:migrate-v3 [--dry-run]
```

- `--dry-run`: 파일 수정 없이 변경 예정 리스트만 출력 (강력 권장)

## 실행 순서

1. **Vault 경로 탐지** (source-fetch와 동일 로직)
2. **마커 확인**: `.rakis-v3-migrated` 있으면 "이미 완료" 출력 후 종료
3. **백업 권장** — 사용자에게 다음 중 하나 실행 권고:
   - `cd "$VAULT" && git add -A && git commit -m "pre-migrate-v3 snapshot"` (git 관리 시)
   - `cp -R "$VAULT" "$VAULT-backup-v2"` (그 외)
4. **영향 범위 리포트**:
   ```bash
   uv run python3 "$PLUGIN_ROOT/scripts/migrate_v3.py" "$VAULT" --dry-run
   ```
   출력 확인 후 사용자 승인 대기
5. **실제 실행**:
   ```bash
   uv run python3 "$PLUGIN_ROOT/scripts/migrate_v3.py" "$VAULT"
   ```
6. **완료 후 안내**:
   ```
   ✓ 마이그레이션 완료.

   다음 단계:
     rm -rf "$VAULT/graphify-out/"   # v2 그래프 캐시 삭제
     cd "$VAULT" && /graphify wiki    # v3 기준 풀 빌드
   ```

## 롤백

자동 롤백 없음. 복구 옵션:
- `git reset --hard HEAD~1` (사전 git commit 했을 때)
- `cp -R "$VAULT-backup-v2/." "$VAULT/"` (사전 디렉토리 백업 했을 때)

## 멱등성

- 마커 파일이 존재하면 즉시 종료
- `--dry-run`은 파일을 수정하지 않으므로 안전

## 상세

> `references/checks.md` — Pre-flight 체크 / 경계 케이스 대응
```

- [ ] **Step 2: references/checks.md 작성**

```markdown
# migrate-v3 체크리스트

## Pre-flight 체크

1. 볼트 경로 존재 확인
2. `CLAUDE.md` 또는 `wiki/` 디렉토리 존재 → 실제 rakis 볼트 확인
3. 영향 예상:
   - `raw/repos/*/graph-report.md` 개수
   - `raw/repos/*/analysis.md` 개수
   - `confidence:` 라인 개수 (`grep -rc "^confidence:" wiki/`)
   - `Home.md` 존재 여부

## 경계 케이스

| 상황 | 대응 |
|------|------|
| Home.md와 wiki/overview.md가 모두 존재 | wiki/overview.md 우선, Home.md는 그대로 둠 |
| outputs/가 이미 존재 | 내용 건드리지 않고 그대로 둠 |
| raw/repos/*에 meta.json이 있음 | 덮어쓰지 않음 |
| confidence 필드가 중첩 YAML 내부에 있음 | top-level만 제거 (들여쓰기 있는 건 보존) |
| 마이그레이션 도중 실패 | 다음 재실행은 마커 없는 상태로 재개 (이미 이동된 파일은 건너뜀) |

## 디버깅

실패 시 다음 파일 확인:
- `outputs/archive-v2/` — 이동된 legacy 파일
- `log.md` 최상단 — 마이그레이션 기록 한 줄 있는지
- `.rakis-v3-migrated` — 성공 마커

마커가 없는데 실행되면 중단 없이 재시도되므로, 문제 해결 후 다시 호출.
```

- [ ] **Step 3: lint.sh 검증**

Run: `bash lint.sh 2>&1 | grep migrate-v3`
Expected: PASS

- [ ] **Step 4: 커밋**

```bash
git add skills/migrate-v3/
git commit -m "feat(v3): migrate-v3 스킬 — v2 → v3 볼트 마이그레이션"
```

---

## Phase 6 — `source-analyze` 제거 + `commands/setup.md` 가드

### Task 12: source-analyze 제거

**Files:**
- Delete: `skills/source-analyze/`

- [ ] **Step 1: 디렉토리 삭제**

```bash
git rm -r skills/source-analyze/
```

- [ ] **Step 2: lint.sh 실행**

Run: `bash lint.sh 2>&1 | grep source-analyze`
Expected: PASS ("스킬 제거됨: source-analyze")

- [ ] **Step 3: 커밋**

```bash
git commit -m "feat(v3)!: source-analyze 스킬 제거 (v3 단절)

v3에서는 /rakis:source-fetch + /rakis:wiki-ingest로 대체.
BREAKING CHANGE: /rakis:source-analyze 호출은 더 이상 동작하지 않음."
```

### Task 13: setup 커맨드에 v2 감지 가드 추가

**Files:**
- Modify: `commands/setup.md`

- [ ] **Step 1: setup.md 끝부분에 v2 감지 블록 추가**

기존 "완료" 섹션 직전에 다음 추가:

```markdown
## 단계 N: v2 구조 감지 (Vault 이동 전 체크)

Vault 경로가 탐지되면, v2 잔재 확인:

```bash
LEGACY_COUNT=$(find "$VAULT/raw" -maxdepth 3 \( -name "graph-report.md" -o -name "analysis.md" \) -type f 2>/dev/null | wc -l | tr -d ' ')
HAS_MARKER=$( [ -f "$VAULT/.rakis-v3-migrated" ] && echo 1 || echo 0 )

if [ "$LEGACY_COUNT" -gt 0 ] && [ "$HAS_MARKER" = "0" ]; then
  cat <<EOS
⚠️  v2 구조가 감지되었습니다 (legacy 파일 $LEGACY_COUNT개).

v3 스킬을 사용하기 전에 먼저 마이그레이션을 실행하세요:

  /rakis:migrate-v3 --dry-run   # 영향 확인
  /rakis:migrate-v3             # 실제 실행

이 단계 없이 v3 스킬을 돌리면 wiki/와 raw/가 불일치 상태가 됩니다.
EOS
  exit 1
fi
```
```

- [ ] **Step 2: help.md·skill-mapping.md 업데이트**

`commands/help.md`와 `commands/skill-mapping.md`의 스킬 목록에서 `source-analyze` 제거, `source-fetch`와 `migrate-v3` 추가. wrap-up·lint·query·ingest는 존치.

- [ ] **Step 3: 커밋**

```bash
git add commands/
git commit -m "feat(v3): setup v2 감지 가드, help/skill-mapping 업데이트"
```

---

## Phase 7 — 스모크 E2E + test.sh 업데이트

### Task 14: 스모크 E2E 러너 작성

**Files:**
- Create: `tests/fixtures/sample-article.md`
- Create: `tests/e2e/smoke.sh`

- [ ] **Step 1: 샘플 입력 파일 생성**

```markdown
<!-- tests/fixtures/sample-article.md -->
# Sample Article for Smoke Test

This is a deterministic fixture used by the v3 smoke test. It contains enough text to trigger the enrich threshold? No — it is intentionally short so that the NotebookLM mock remains inactive by default.

Main concept: **sample-topic** — a placeholder used to verify that wiki-query can retrieve content from a compiled wiki/sources page.
```

- [ ] **Step 2: smoke.sh 작성 (실패 테스트 형태)**

```bash
#!/bin/bash
# tests/e2e/smoke.sh — v3 파이프라인 스모크 E2E
# 실제 wiki-ingest · wiki-query 스킬을 Claude가 실행하는 대신,
# 스킬이 내부적으로 호출할 스크립트(slug/frontmatter/migrate)와 파일 I/O만 검증한다.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP_VAULT=$(mktemp -d)
trap "rm -rf $TMP_VAULT" EXIT

# 1. v3 초기 볼트 셋업
mkdir -p "$TMP_VAULT"/{raw/articles,wiki/sources,wiki/concepts,wiki/projects,outputs}
cat > "$TMP_VAULT/CLAUDE.md" <<'EOF'
# Three-Layer Schema
raw/ wiki/ outputs/
EOF
cat > "$TMP_VAULT/log.md" <<'EOF'
# Log
EOF
cat > "$TMP_VAULT/index.md" <<'EOF'
# Index
## sources
EOF
touch "$TMP_VAULT/.rakis-v3-migrated"

# 2. source-fetch 시뮬레이션 — 로컬 파일 → raw/articles/sample-article/
SLUG=$("$SCRIPT_DIR/scripts/slug.sh" "sample-article.md")
SRC_DIR="$TMP_VAULT/raw/articles/$SLUG"
mkdir -p "$SRC_DIR"
cp "$SCRIPT_DIR/tests/fixtures/sample-article.md" "$SRC_DIR/source.md"
SIZE=$(wc -c < "$SRC_DIR/source.md" | tr -d ' ')
cat > "$SRC_DIR/meta.json" <<EOF
{"type":"article","source_url":"","captured_at":"2026-04-17","contributor":"raki-1203","slug":"$SLUG","size_bytes":$SIZE,"source_file":"source.md"}
EOF

# 3. wiki-ingest 시뮬레이션 — 미처리 소스를 wiki/sources/{slug}.md로 컴파일
WIKI="$TMP_VAULT/wiki/sources/$SLUG.md"
cat > "$WIKI" <<EOF
---
title: "Sample Article"
type: source-summary
sources: ["[[raw/articles/$SLUG]]"]
related: []
created: 2026-04-17
updated: 2026-04-17
description: "sample-topic 테스트 픽스처"
---

## 요약
sample-topic 소개.

## 원본
[[raw/articles/$SLUG/source]]
EOF

# 4. frontmatter 검증
if ! uv run python3 "$SCRIPT_DIR/scripts/frontmatter.py" validate "$WIKI"; then
  echo "❌ frontmatter invalid"
  exit 1
fi

# 5. assertions
[ -f "$SRC_DIR/source.md" ] || { echo "❌ raw/source.md 없음"; exit 1; }
[ -f "$SRC_DIR/meta.json" ] || { echo "❌ raw/meta.json 없음"; exit 1; }
[ -f "$WIKI" ] || { echo "❌ wiki/sources/{slug}.md 없음"; exit 1; }
grep -q "sample-topic" "$WIKI" || { echo "❌ wiki 내용 검증 실패"; exit 1; }
grep -q "^type: source-summary$" "$WIKI" || { echo "❌ type enum 검증 실패"; exit 1; }
grep -q "confidence:" "$WIKI" && { echo "❌ confidence 필드 잔존"; exit 1; } || true

echo "✅ smoke E2E 통과 ($TMP_VAULT)"
```

- [ ] **Step 3: 실행 확인**

Run: `chmod +x tests/e2e/smoke.sh && bash tests/e2e/smoke.sh`
Expected: `✅ smoke E2E 통과`

- [ ] **Step 4: test.sh에 smoke 훅 추가**

`test.sh`의 `TARGET=all` 분기 하단에 추가:

```bash
# ─── v3 smoke E2E ───
if [ "$TARGET" = "all" ] || [ "$TARGET" = "smoke" ]; then
  echo ""
  echo "🧪 v3 Smoke E2E"
  if bash tests/e2e/smoke.sh >/dev/null; then
    pass "smoke E2E"
  else
    fail "smoke E2E — bash tests/e2e/smoke.sh"
  fi
fi
```

- [ ] **Step 5: test.sh 실행**

Run: `bash test.sh deps` (의존성만) 또는 `bash test.sh smoke`
Expected: smoke PASS

- [ ] **Step 6: 커밋**

```bash
git add tests/e2e/ tests/fixtures/sample-article.md test.sh
git commit -m "test(v3): smoke E2E + test.sh 연동"
```

### Task 15: test.sh에 source-analyze 제거 검증 추가

**Files:**
- Modify: `test.sh`

- [ ] **Step 1: 스킬 존재 확인 블록을 수정**

`test.sh`에 있는 스킬 체크 루프 인근에 다음 검사 추가:

```bash
if [ "$TARGET" = "all" ] || [ "$TARGET" = "v3" ]; then
  echo ""
  echo "🔎 v3 단절 검증"
  if [ -d skills/source-analyze ]; then
    fail "source-analyze 스킬이 남아있음 — v3에서는 제거되어야 함"
  else
    pass "source-analyze 제거됨"
  fi
  for s in source-fetch migrate-v3; do
    if [ -d "skills/$s" ]; then
      pass "v3 스킬 존재: $s"
    else
      fail "v3 스킬 누락: $s"
    fi
  done
fi
```

- [ ] **Step 2: 실행 확인**

Run: `bash test.sh v3`
Expected: 모든 항목 PASS

- [ ] **Step 3: 커밋**

```bash
git add test.sh
git commit -m "test(v3): source-analyze 제거 + v3 스킬 존재 검증"
```

---

## Phase 8 — 문서 + 버전 bump + 릴리즈

### Task 16: CHANGELOG.md 작성

**Files:**
- Create: `CHANGELOG.md`

- [ ] **Step 1: CHANGELOG 작성**

```markdown
# Changelog

## [3.0.0] — 2026-04-17

### BREAKING CHANGES

- `/rakis:source-analyze` 스킬 제거. `/rakis:source-fetch` + `/rakis:wiki-ingest` 2단계로 분리.
- Vault 구조 변경: `raw/`는 이제 LLM 분석 산출물을 저장하지 않음. 모든 enrich 결과는 `raw/{type}/{slug}/notebooklm/` 하위로 격리.
- frontmatter `confidence` 필드 제거.
- frontmatter `type` 필드가 enum으로 고정: `source-summary | project | concept | entity | comparison | index`.
- `Home.md` → `wiki/overview.md` 리네이밍.
- `outputs/` 디렉토리 추가 (lint 리포트 · archive-v2 · graph-report 시점 스냅샷).

### Added

- `source-fetch` 스킬: 외부 소스를 raw/에 저장. 임계값 기반 자동 NotebookLM enrich (briefing + study-guide + mindmap).
- `migrate-v3` 스킬: v2 → v3 1회성 자동 마이그레이션 (dry-run 지원).
- `wiki-init` 스킬 v3 스키마 반영 (overview.md · outputs/ · CLAUDE.md 스키마 자동 생성).
- `wiki-query --scope project` 플래그: 현재 프로젝트 범위로 탐색 한정.
- `wiki-lint` outputs/ 저장 + overview.md 통계 섹션 자동 갱신.
- 테스트 계층: 유닛 (slug, frontmatter) + golden (마이그레이션) + smoke E2E.

### Changed

- `wiki-ingest`: raw 전수 스캔 + 증분, index.md 기반 연결. `--full` 플래그로 전체 재컴파일 가능.
- `wiki-query`: overview.md를 index.md 이전에 먼저 참조 (답변형 분기).
- graphify 호출 target: `<vault>` → `<vault>/wiki` (코드 덤프 노이즈 제거).

### Migration

기존 v2.x 사용자는 **반드시** 다음 순서로 업그레이드:

```
/rakis:setup                  # v2 감지 시 자동으로 다음 단계 안내
/rakis:migrate-v3 --dry-run   # 영향 범위 확인
/rakis:migrate-v3             # 실제 실행
rm -rf "<vault>/graphify-out/"
cd "<vault>" && /graphify wiki  # v3 풀 빌드
```

## [2.5.2] — 2026-04-14

(이전 버전은 git history 참조)
```

- [ ] **Step 2: 커밋**

```bash
git add CHANGELOG.md
git commit -m "docs(v3): CHANGELOG.md — v3.0.0 변경사항 + 마이그레이션 가이드"
```

### Task 17: README.md 업데이트

**Files:**
- Modify: `README.md`

- [ ] **Step 1: v3 워크플로 섹션 교체**

기존 "사용 워크플로" 또는 스킬 목록 섹션을 다음으로 교체:

```markdown
## 사용 워크플로 (v3)

### 새 소스 수집 → 위키 반영
```
/rakis:source-fetch https://example.com/article
/rakis:wiki-ingest
```

### 질의
```
/rakis:wiki-query "질문"
/rakis:wiki-query "프로젝트 X에서 Y가 뭐야?" --scope project
```

### 세션 마무리
```
/rakis:wiki-wrap-up
```

### 주간 건강 점검
```
/rakis:wiki-lint
```

### v2 사용자 마이그레이션 (1회)
```
/rakis:migrate-v3 --dry-run
/rakis:migrate-v3
```

## 스킬 목록 (v3)

| 스킬 | 역할 |
|------|------|
| `source-fetch` | URL/repo/PDF를 raw/에 저장 |
| `wiki-ingest` | raw → wiki/ 컴파일 |
| `wiki-query` | 위키 질의 (답변형/탐색형) |
| `wiki-wrap-up` | 세션 학습 기록 |
| `wiki-lint` | 위키 건강 점검 |
| `wiki-init` | 빈 볼트 초기화 |
| `migrate-v3` | v2 → v3 마이그레이션 (1회성) |

## 의존성

- `notebooklm-py` (optional, enrich 용)
- `npx` + `repomix` (repo 수집)
- `gh` CLI (private repo 폴백)
- `graphify` CLI (탐색형 query + 주간 풀 리빌드)
```

- [ ] **Step 2: 커밋**

```bash
git add README.md
git commit -m "docs(v3): README v3 워크플로 + 스킬 목록 갱신"
```

### Task 18: 버전 bump

**Files:**
- Modify: `.claude-plugin/plugin.json`
- Modify: `package.json`

- [ ] **Step 1: 두 파일의 version을 3.0.0으로**

`.claude-plugin/plugin.json`:
```json
"version": "3.0.0"
```

`package.json`:
```json
"version": "3.0.0"
```

- [ ] **Step 2: lint.sh의 버전 일치 검사 확인**

Run: `bash lint.sh 2>&1 | grep "버전"`
Expected: `✅ 버전 일치: 3.0.0`

- [ ] **Step 3: 커밋**

```bash
git add .claude-plugin/plugin.json package.json
git commit -m "chore(v3): bump version to 3.0.0"
```

### Task 19: 최종 통합 테스트

**Files:**
- (없음, 실행만)

- [ ] **Step 1: 전체 lint 실행**

Run: `bash lint.sh`
Expected: 모든 항목 PASS, 실패 0

- [ ] **Step 2: 전체 test 실행 (외부 서비스 필요한 항목은 skip 가능)**

Run: `bash test.sh deps && bash test.sh v3 && bash test.sh smoke`
Expected: PASS

- [ ] **Step 3: golden 테스트**

Run: `bash tests/golden/run_migrate.sh`
Expected: PASS

- [ ] **Step 4: 모든 유닛 테스트**

Run: `bash tests/unit/test_slug.sh && bash tests/unit/test_frontmatter.sh`
Expected: PASS

- [ ] **Step 5: pre-push hook 시뮬레이션**

Run: `bash .githooks/pre-push`
Expected: PASS

### Task 20: RC 개인 볼트 검증 (사용자 수동)

**이 태스크는 사용자가 자기 볼트에서 직접 수행. Claude는 체크리스트만 제공.**

- [ ] **Step 1: 백업**

```bash
cd "$VAULT"
git add -A
git commit -m "pre-migrate-v3 snapshot (v2.5.2)" || cp -R "$VAULT" "$VAULT-backup-v2"
```

- [ ] **Step 2: dry-run**

```
/rakis:migrate-v3 --dry-run
```
출력 확인 — archive 예정 파일·confidence 제거 예정 파일 개수 점검

- [ ] **Step 3: 실제 실행**

```
/rakis:migrate-v3
```

- [ ] **Step 4: graphify 풀 빌드**

```bash
rm -rf "$VAULT/graphify-out/"
cd "$VAULT"
/graphify wiki
```

- [ ] **Step 5: wiki-query 수동 검증**

```
/rakis:wiki-query "최근 30일 사이 추가된 주요 개념"
/rakis:wiki-query "graphify가 뭐야?"
```

모두 정상 응답 + graph 없음 경고 없이 동작해야 함.

- [ ] **Step 6: 문제 발견 시 이슈 등록 또는 복구**

복구:
```bash
git reset --hard HEAD~1   # git 백업 있을 때
# 또는
rm -rf "$VAULT" && cp -R "$VAULT-backup-v2" "$VAULT"
```

### Task 21: 태그 + 릴리즈

**Files:**
- (없음, git 작업)

- [ ] **Step 1: 모든 커밋 푸시**

```bash
git push origin main
```

- [ ] **Step 2: v3.0.0 태그**

```bash
git tag -a v3.0.0 -m "rakis v3.0.0 — Karpathy LLM Wiki alignment"
git push origin v3.0.0
```

- [ ] **Step 3: GitHub 릴리즈 페이지 생성**

```bash
gh release create v3.0.0 \
  --title "v3.0.0 — Karpathy Alignment" \
  --notes-file CHANGELOG.md \
  --target main
```

- [ ] **Step 4: 개인 볼트 log.md 기록**

사용자가 `/rakis:wiki-wrap-up` 실행하여 다음 한 줄을 log.md에 추가:
```
## [2026-04-17] raki-claude-plugins | v3.0.0 릴리즈 — Karpathy LLM Wiki 정렬
```

---

## Self-Review

### Spec coverage 매핑

| Spec 섹션 | 태스크 |
|-----------|--------|
| 섹션 1 아키텍처 | Phase 1~9 전체 (구조 변경 반영) |
| 섹션 2 볼트 구조 — frontmatter | Task 2 (frontmatter.py) |
| 섹션 2 — slug 규칙 | Task 1 (slug.sh) |
| 섹션 2 — wrap-up 예외 | Task 7 (wiki-wrap-up "예외 규칙" 문구) |
| 섹션 3 — source-fetch | Task 4 |
| 섹션 3 — wiki-ingest | Task 5 |
| 섹션 3 — wiki-query | Task 6 |
| 섹션 3 — wiki-wrap-up | Task 7 |
| 섹션 3 — wiki-lint | Task 8 |
| 섹션 3 — setup | Task 13 |
| 섹션 3 — migrate-v3 | Task 10~11 |
| 섹션 3 — graphify 안내 target `<vault>/wiki` | Task 5 Step 2, Task 6 Step 3, Task 7 Step 1, Task 8 Step 2 |
| 섹션 3 — wiki-init 추가 (brainstorming 언급 안 됨) | Task 9 (추가) |
| 섹션 4 시나리오 A/B/C | Task 4,5 (source-fetch/wiki-ingest), Task 7 (wrap-up), Task 8 (lint) |
| 섹션 5 migrate-v3 상세 | Task 10 (migrate_v3.py), Task 11 (SKILL.md) |
| 섹션 6 유닛 테스트 | Task 1,2 + lint.sh v3 확장 (Task 3) |
| 섹션 6 golden 테스트 | Task 10 |
| 섹션 6 스모크 E2E | Task 14 |
| 섹션 6 릴리즈 체크리스트 | Task 16~21 |
| 섹션 6 Rollout | Task 12 (source-analyze 제거), Task 13 (setup 가드) |

누락 없음. wiki-init은 spec 섹션 3에 명시되지 않았으나 기존 v2에 존재하고 v3 스키마 반영 필수이므로 Task 9로 추가.

### Placeholder 점검

- "TBD"/"TODO" 없음 ✅
- 모든 코드 스텝에 완전한 코드/명령어 존재 ✅
- "Similar to Task N" 참조 없음 ✅
- 타입 일관성 (frontmatter.py의 함수명 validate/strip_confidence가 테스트·migrate에서도 동일) ✅

### 주의 사항

- Task 14 smoke.sh는 Claude가 실제로 스킬을 돌리지 않고 **스킬이 사용할 하부 스크립트만 검증**함. 실제 스킬 호출 검증은 Task 20(수동 RC 검증)에서 사람이 수행.
- NotebookLM enrich는 CI에서 `RAKIS_NOTEBOOKLM_MOCK=1`로 스텁되지만, smoke.sh는 길이 임계값 미달 sample-article로 enrich 자체를 건너뛰므로 모의 호출조차 없음. 이는 의도된 범위 축소.
- golden 테스트는 `RAKIS_MIGRATION_DATE=2026-04-17`로 결정론 확보.
