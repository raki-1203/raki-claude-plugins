# rakis 플러그인 setup 시스템 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** raki-claude-plugins 가 새 맥에 처음 설치될 때 외부 의존성(notebooklm-py, gh, graphify, node)을 한 번에 안내·설치할 수 있도록 `/rakis-setup` 명령과 SessionStart hook 안내를 추가한다.

**Architecture:** SessionStart hook이 마커 파일(`${CLAUDE_PLUGIN_DATA}/.setup-done`) 부재를 감지하여 첫 세션에 한 번 안내를 출력. 사용자가 `/rakis-setup`을 실행하면 Claude가 의존성을 점검·설치한 뒤 마커를 생성. PPT/DOCX 처리 기능은 source-analyze에서 제거.

**Tech Stack:** Bash, JSON (Claude Code plugin hook 스키마), Markdown (slash command + skill 문서).

**Spec:** [`docs/superpowers/specs/2026-04-11-rakis-plugin-setup-design.md`](../specs/2026-04-11-rakis-plugin-setup-design.md)

---

## 파일 구조

### 신규
- `hooks/hooks.json` — SessionStart hook 정의
- `commands/rakis-setup.md` — `/rakis-setup` 슬래시 명령 (Claude에게 전달되는 지시문)

### 수정
- `skills/source-analyze/SKILL.md` — PPT/PPTX, DOCX 처리 모든 부분 제거
- `README.md` — Setup 섹션 추가
- `test.sh` — `test_deps` 함수에서 graphify를 `skip` → `fail`로 변경 (필수 의존성으로 승격)

### 변경 안 함
- `lint.sh` — 새 디렉토리(`hooks/`, `commands/`) 검증 추가는 v2 후보. v1은 수동 확인.
- `.claude-plugin/plugin.json` — 변경 불필요
- 다른 스킬들

---

## Task 1: source-analyze SKILL.md에서 PPT/DOCX 제거

먼저 source-analyze 정리부터. 이게 끝나야 setup이 거짓말 안 하게 된다.

**Files:**
- Modify: `skills/source-analyze/SKILL.md`

- [ ] **Step 1: 현재 라인 번호 확인**

```bash
grep -n "PPT\|DOCX\|pptx\|docx" skills/source-analyze/SKILL.md
```

수정 전 정확한 위치를 확인. 이후 step의 라인 번호가 안 맞으면 수정 후 grep 결과 기준으로 따라간다.

- [ ] **Step 2: description 필드에서 PPT/문서 표현 제거**

`skills/source-analyze/SKILL.md` 라인 3 (description) 에서 `, PPT, 문서 등` 부분을 삭제하고 자연스럽게 다듬는다.

변경 전:
```
description: "다양한 소스(GitHub repo, 블로그, 논문 PDF, YouTube, LinkedIn, X, PPT, 문서 등)를 자동 분석하여 ..."
```

변경 후:
```
description: "다양한 소스(GitHub repo, 블로그, 논문 PDF, YouTube, LinkedIn, X 등)를 자동 분석하여 ..."
```

(그 뒤 본문은 그대로)

- [ ] **Step 3: "소스 유형 자동 감지" 표에서 PPT/PPTX, DOCX 행 삭제**

`skills/source-analyze/SKILL.md`의 다음 두 줄을 찾아서 삭제:

```markdown
| **PPT/PPTX** | `.ppt`, `.pptx` | 텍스트 (변환 필요) | `python-pptx` → 마크다운 변환 → 텍스트 업로드 |
| **DOCX** | `.docx` | 텍스트 (변환 필요) | `python-docx` → 마크다운 변환 → 텍스트 업로드 |
```

표의 다른 행(GitHub repo, 웹 URL, YouTube, PDF, 이미지, LinkedIn, X/Twitter, 로컬 텍스트/마크다운)은 모두 그대로 유지.

- [ ] **Step 4: "PPT/PPTX 변환" 코드 블록 삭제**

`skills/source-analyze/SKILL.md`에서 다음 블록 전체를 삭제 (헤더 + 코드 블록):

````markdown
**PPT/PPTX 변환**:
```bash
python3 -c "
from pptx import Presentation
import sys
prs = Presentation(sys.argv[1])
for i, slide in enumerate(prs.slides):
    print(f'## 슬라이드 {i+1}')
    for shape in slide.shapes:
        if shape.has_text_frame:
            print(shape.text)
    print()
" {파일경로} > /tmp/converted-{파일명}.md
```
````

- [ ] **Step 5: "DOCX 변환" 코드 블록 삭제**

`skills/source-analyze/SKILL.md`에서 다음 블록 전체 삭제:

````markdown
**DOCX 변환**:
```bash
python3 -c "
from docx import Document
import sys
doc = Document(sys.argv[1])
for p in doc.paragraphs:
    print(p.text)
for table in doc.tables:
    for row in table.rows:
        print('| ' + ' | '.join(cell.text for cell in row.cells) + ' |')
" {파일경로} > /tmp/converted-{파일명}.md
```
````

- [ ] **Step 6: "에러 처리 요약" 표에서 PPT/DOCX 행 삭제**

다음 줄을 찾아서 삭제:

```markdown
| PPT/DOCX 변환 실패 | python-pptx/python-docx 설치 안내 |
```

- [ ] **Step 7: 잔존 PPT/DOCX 언급이 없는지 재확인**

```bash
grep -in "ppt\|docx\|pptx" skills/source-analyze/SKILL.md
```

기대: 출력 없음 (혹은 description의 영문 약자가 빠진 것이 확인됨).

만약 어떤 줄이 남아있다면, 그 줄이 PPT/DOCX 처리 기능을 말하는지 다른 맥락(예: "powerpoint" 같은 표현)인지 판단 후 처리.

- [ ] **Step 8: lint.sh 실행 — 구조 검증 통과 확인**

```bash
./lint.sh
```

기대 출력: `✅ 모든 테스트 통과` (FAIL 0). 라인 수 제한(500), description 길이, references 일관성 모두 통과해야 한다.

- [ ] **Step 9: 커밋**

```bash
git add skills/source-analyze/SKILL.md
git commit -m "refactor: source-analyze에서 PPT/DOCX 처리 기능 제거

시스템 python3 의존이 깨지기 쉽고 사용 빈도가 낮아 v1 범위에서 제외.
필요해지면 v2에서 'uv run --with' ephemeral 실행으로 재도입 예정."
```

---

## Task 2: SessionStart hook 정의

마커 파일이 없을 때 한 줄 안내를 stdout에 출력하는 가벼운 hook을 작성한다. 실제 의존성 점검은 `/rakis-setup`이 한다.

**Files:**
- Create: `hooks/hooks.json`

- [ ] **Step 1: hooks/ 디렉토리 생성**

```bash
mkdir -p hooks
```

- [ ] **Step 2: hooks/hooks.json 작성**

`hooks/hooks.json`:
```json
{
  "description": "rakis 플러그인 SessionStart 안내",
  "hooks": {
    "SessionStart": [
      {
        "matcher": "startup",
        "hooks": [
          {
            "type": "command",
            "command": "test -f \"${CLAUDE_PLUGIN_DATA}/.setup-done\" || echo '[rakis] 처음 사용이시네요. /rakis-setup 을 먼저 실행해주세요.'",
            "timeout": 5
          }
        ]
      }
    ]
  }
}
```

- [ ] **Step 3: JSON 문법 유효성 확인**

```bash
python3 -c "import json; json.load(open('hooks/hooks.json'))" && echo "JSON OK"
```

기대 출력: `JSON OK`

- [ ] **Step 4: hook 셸 명령을 수동으로 검증 — 마커 없는 경우**

마커 파일이 없는 임시 디렉토리를 만들어서 hook 명령을 그대로 실행:

```bash
TMPDIR=$(mktemp -d)
CLAUDE_PLUGIN_DATA="$TMPDIR" bash -c 'test -f "${CLAUDE_PLUGIN_DATA}/.setup-done" || echo "[rakis] 처음 사용이시네요. /rakis-setup 을 먼저 실행해주세요."'
rm -rf "$TMPDIR"
```

기대 출력:
```
[rakis] 처음 사용이시네요. /rakis-setup 을 먼저 실행해주세요.
```

- [ ] **Step 5: hook 셸 명령을 수동으로 검증 — 마커 있는 경우**

마커 파일을 만들어둔 상태에서 같은 명령을 실행:

```bash
TMPDIR=$(mktemp -d)
touch "$TMPDIR/.setup-done"
CLAUDE_PLUGIN_DATA="$TMPDIR" bash -c 'test -f "${CLAUDE_PLUGIN_DATA}/.setup-done" || echo "[rakis] 처음 사용이시네요. /rakis-setup 을 먼저 실행해주세요."'
echo "exit=$?"
rm -rf "$TMPDIR"
```

기대 출력:
```
exit=0
```

(아무 메시지도 출력되지 않고 종료 코드 0)

- [ ] **Step 6: lint.sh 통과 확인**

```bash
./lint.sh
```

기대: `✅ 모든 테스트 통과`. lint.sh는 hooks/ 디렉토리를 별도로 검증하지 않으므로 영향 없음 — 그래도 회귀 확인.

- [ ] **Step 7: 커밋**

```bash
git add hooks/hooks.json
git commit -m "feat: rakis 플러그인 SessionStart hook 추가

마커 파일 ${CLAUDE_PLUGIN_DATA}/.setup-done 이 없으면 첫 세션에
/rakis-setup 을 실행하라는 한 줄 안내를 출력. 마커가 있으면 조용."
```

---

## Task 3: `/rakis-setup` 슬래시 명령 작성

Claude에게 전달되는 지시문 형식의 마크다운 파일을 만든다. 명령이 호출되면 Claude가 이 파일 본문을 따라 의존성 점검 → 사용자 동의 → 설치 → 마커 생성 흐름을 수행한다.

**Files:**
- Create: `commands/rakis-setup.md`

- [ ] **Step 1: commands/ 디렉토리 생성**

```bash
mkdir -p commands
```

- [ ] **Step 2: commands/rakis-setup.md 작성**

`commands/rakis-setup.md`:
````markdown
---
description: rakis 플러그인의 외부 의존성을 점검하고 누락된 도구를 설치합니다
---

# /rakis-setup

당신은 raki-claude-plugins 플러그인의 의존성 셋업을 수행합니다. 다음 절차를 정확히 따라주세요.

## 단계 1: 전제조건 점검

다음을 순서대로 확인하세요.

### brew

```bash
command -v brew
```

- 성공 → 다음 단계로
- 실패 → 사용자에게 다음 메시지를 출력하고 **즉시 중단** (마커 만들지 마세요):
  > brew(Homebrew)가 필요합니다. 다음 명령을 직접 실행한 뒤, `/rakis-setup`을 다시 실행해주세요.
  >
  > ```
  > /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  > ```

### uv

```bash
command -v uv
```

- 성공 → 다음 단계로
- 실패 → 사용자에게 "uv를 자동 설치할까요?"라고 묻고, 동의 시:
  ```bash
  curl -LsSf https://astral.sh/uv/install.sh | sh
  ```
  설치 후 PATH 갱신을 위해 사용자에게 새 셸 또는 `source ~/.zshrc`(또는 동등) 안내. 거부 시 setup 중단 (마커 만들지 마세요).

## 단계 2: 의존성 점검

다음 도구들의 설치 여부를 `command -v`로 확인하세요.

| 도구 | 체크 명령 | 설치 명령 |
|------|----------|----------|
| `notebooklm-py` | `command -v notebooklm` | `uv tool install notebooklm-py --with playwright` |
| `node`/`npm` | `command -v npm` | `brew install node` |
| `gh` | `command -v gh` | `brew install gh` |
| `graphify` | `command -v graphify` | `uv tool install graphifyy --python 3.13` |

> **graphify 패키지명 주의**: PyPI 패키지명은 `graphifyy` (오타 아님, y가 두 개), 설치 후 명령어는 `graphify` (y 한 개).

결과를 다음 형식으로 출력하세요:

```
[필수]
  uv               ✓
  notebooklm-py    ✗   uv tool install notebooklm-py --with playwright
  node             ✓
  gh               ✗   brew install gh
  graphify         ✗   uv tool install graphifyy --python 3.13
```

모든 항목이 ✓이면 단계 3을 건너뛰고 단계 6으로 가세요. ("이미 모두 설치되어 있습니다" 출력 + 마커 생성)

## 단계 3: 사용자 선택

빠진 게 있으면 다음과 같이 묻고 답을 기다리세요:

```
필수 N개 누락. 어떻게 진행할까요?
[a] 모두 설치
[c] 항목별 선택
[s] 건너뛰기 (마커는 만듦, 이후 안내 안 함)
```

## 단계 4: 설치 실행

사용자 선택에 따라:
- **[a] 모두 설치**: 빠진 도구를 위 표 순서대로 설치 명령 실행
- **[c] 항목별 선택**: 각 빠진 도구에 대해 하나씩 "설치할까요?" 묻고 동의 항목만 설치
- **[s] 건너뛰기**: 아무것도 설치하지 않고 단계 6으로 (마커는 생성)

각 설치 명령은 Bash 도구로 직접 실행. Claude Code의 권한 prompt가 사용자에게 한 번 더 확인을 받습니다.

설치 중 하나라도 실패하면, **마커를 만들지 말고** 사용자에게 어떤 게 실패했는지 보고한 뒤 종료. 다음에 `/rakis-setup`을 다시 실행하면 빠진 것만 다시 시도합니다.

## 단계 5: 인터랙티브 인증 안내

이번 setup에서 `notebooklm-py`가 새로 설치되었다면, 마지막에 다음 메시지를 출력:

> notebooklm 인증이 필요합니다. 다음 명령을 직접 실행해주세요 (브라우저에서 Google 로그인이 열립니다):
>
> ```
> ! notebooklm login
> ```

(자동 실행 금지 — 인터랙티브 브라우저 로그인이라 자동화 불가)

## 단계 6: 마커 생성

모든 필수 단계가 완료되었거나 사용자가 [s] 건너뛰기를 선택한 경우:

```bash
mkdir -p "${CLAUDE_PLUGIN_DATA}"
touch "${CLAUDE_PLUGIN_DATA}/.setup-done"
```

## 단계 7: 결과 요약

다음 형식으로 사용자에게 요약 출력:

```
=== rakis-setup 완료 ===

새로 설치됨:
  ✓ notebooklm-py
  ✓ gh
  ✓ graphify

이미 있던 것:
  ✓ uv
  ✓ node

다음에 할 일:
  ! notebooklm login
```

빠진 항목이 있다면 별도 표시. 마커 생성 여부도 명시.

## Idempotent 보장

`/rakis-setup`은 언제 다시 실행해도 안전합니다:
- 마커가 있어도 점검을 다시 수행. 모두 ✓이면 "이미 setup 완료" 출력 후 즉시 종료.
- 일부만 설치된 부분 상태 → 빠진 것만 다시 시도.
````

- [ ] **Step 3: 파일이 의도한 대로 작성됐는지 확인**

```bash
head -5 commands/rakis-setup.md
wc -l commands/rakis-setup.md
```

기대: 첫 줄이 `---`로 시작 (frontmatter), description 필드 존재. 라인 수는 약 100~130줄 정도.

- [ ] **Step 4: lint.sh 실행**

```bash
./lint.sh
```

기대: `✅ 모든 테스트 통과`. lint.sh는 commands/ 를 검증하지 않으므로 영향 없지만 회귀 확인 목적.

- [ ] **Step 5: 커밋**

```bash
git add commands/rakis-setup.md
git commit -m "feat: /rakis-setup 슬래시 명령 추가

플러그인 외부 의존성(notebooklm-py, node, gh, graphify)을 점검하고
사용자 동의 후 자동 설치. 마커 파일로 첫 1회 안내 후 조용히 동작."
```

---

## Task 4: README.md에 Setup 섹션 추가

**Files:**
- Modify: `README.md`

- [ ] **Step 1: 현재 README.md의 Installation 섹션 확인**

```bash
grep -n "## Installation\|## Setup\|## Vault" README.md
```

기대: `## Installation` 라인 번호와 그 다음 섹션의 라인 번호 확인. Setup 섹션은 Installation 다음 / Vault Structure(또는 Setup 환경변수 설명) 앞에 들어가야 한다.

- [ ] **Step 2: Setup 섹션 추가**

`README.md`의 `## Installation` 섹션 바로 다음, 기존 환경변수 설명(`## Setup`)이 있다면 그것을 대체하지 말고 그 안에 추가. 기존 README의 `## Setup` 섹션은 vault 환경변수만 설명하고 있음. 이걸 그대로 두고, 그 안 또는 위에 의존성 setup 안내 추가.

변경 결과는 다음과 같이 되어야 한다 (`## Setup` 섹션 전체):

````markdown
## Setup

### 1. 의존성 설치

플러그인 설치 후 한 번만 실행해주세요:

```
/rakis-setup
```

`source-analyze`, `project-graph` 등 일부 스킬에 필요한 외부 도구(notebooklm-py, gh, graphify, node)를 점검하고, 누락된 것을 동의 후 설치합니다.

전제조건: macOS, Homebrew. brew가 없으면 setup 시작 시 안내합니다.

### 2. Obsidian Vault 경로

Set your vault path as an environment variable:

```bash
export OBSIDIAN_VAULT_PATH="$HOME/Library/Mobile Documents/com~apple~CloudDocs/Documents/Vault"
```

Or the plugin will auto-detect the default iCloud path.
````

(원래 Setup 섹션의 vault 환경변수 안내는 "2. Obsidian Vault 경로" 하위로 옮긴다.)

- [ ] **Step 3: 변경 결과 확인**

```bash
sed -n '/## Setup/,/## Vault Structure/p' README.md
```

기대: 위 형식대로 출력.

- [ ] **Step 4: 커밋**

```bash
git add README.md
git commit -m "docs: README에 /rakis-setup 안내 추가"
```

---

## Task 5: test.sh — graphify를 필수 의존성으로 변경

graphify가 필수가 됐으므로 통합 테스트에서도 미설치를 `skip`이 아닌 `fail`로 처리해야 한다.

**Files:**
- Modify: `test.sh:57-62`

- [ ] **Step 1: 현재 코드 확인**

```bash
grep -n "graphify" test.sh
```

기대: 라인 57~62 부근에 다음 블록이 있음:

```bash
  # graphify
  if command -v graphify &>/dev/null; then
    pass "graphify CLI 설치됨"
  else
    skip "graphify 미설치 — 구조 분석 테스트 건너뜀"
  fi
```

- [ ] **Step 2: skip을 fail로 변경**

`test.sh` 해당 블록을 다음과 같이 수정:

```bash
  # graphify
  if command -v graphify &>/dev/null; then
    pass "graphify CLI 설치됨"
  else
    fail "graphify 미설치 — uv tool install graphifyy --python 3.13"
  fi
```

- [ ] **Step 3: 변경 확인**

```bash
grep -A1 "# graphify" test.sh
```

기대: `fail "graphify 미설치 ...` 가 보임.

- [ ] **Step 4: test.sh deps 만 실행해서 통과 확인**

```bash
./test.sh deps
```

기대: 현재 맥에 graphify가 이미 설치되어 있으므로 (이전에 `command -v graphify`로 `/Users/raki-1203/.local/bin/graphify` 확인 완료) `✅ graphify CLI 설치됨` 출력. 전체 PASS.

- [ ] **Step 5: 커밋**

```bash
git add test.sh
git commit -m "test: graphify 미설치를 skip → fail로 변경

graphify는 project-graph와 source-analyze 양쪽의 필수 의존성이 되었으므로
미설치 시 통합 테스트가 실패해야 한다."
```

---

## Task 6: 최종 통합 검증

전체 변경이 일관되게 동작하는지 확인.

- [ ] **Step 1: lint.sh 전체 실행**

```bash
./lint.sh
```

기대: `✅ 모든 테스트 통과`. FAIL 0.

- [ ] **Step 2: test.sh deps 만 실행**

```bash
./test.sh deps
```

기대: 모든 의존성 PASS (notebooklm, gh, npx, graphify 등).

- [ ] **Step 3: hook 명령을 다시 한 번 검증 (이번에는 실제 설치 위치 기준)**

플러그인이 로컬 개발 모드라면 `${CLAUDE_PLUGIN_DATA}`가 채워지지 않을 수 있으므로 임시 디렉토리로 검증:

```bash
TMPDIR=$(mktemp -d)
echo "--- 마커 없는 경우 ---"
CLAUDE_PLUGIN_DATA="$TMPDIR" bash -c 'test -f "${CLAUDE_PLUGIN_DATA}/.setup-done" || echo "[rakis] 처음 사용이시네요. /rakis-setup 을 먼저 실행해주세요."'
echo "--- 마커 있는 경우 ---"
touch "$TMPDIR/.setup-done"
CLAUDE_PLUGIN_DATA="$TMPDIR" bash -c 'test -f "${CLAUDE_PLUGIN_DATA}/.setup-done" || echo "[rakis] 처음 사용이시네요. /rakis-setup 을 먼저 실행해주세요."'
echo "exit=$?"
rm -rf "$TMPDIR"
```

기대 출력:
```
--- 마커 없는 경우 ---
[rakis] 처음 사용이시네요. /rakis-setup 을 먼저 실행해주세요.
--- 마커 있는 경우 ---
exit=0
```

- [ ] **Step 4: source-analyze SKILL.md에 잔존 PPT/DOCX 언급이 없는지 최종 확인**

```bash
grep -in "ppt\|docx\|pptx\|python-pptx\|python-docx" skills/source-analyze/SKILL.md
```

기대: 출력 없음.

- [ ] **Step 5: git log 확인**

```bash
git log --oneline -10
```

기대: 이 plan에서 만든 5개의 커밋이 순서대로 보임 (Task 1 → Task 5).

- [ ] **Step 6: (선택) 이 세션 안에서 `/rakis-setup` 실제 호출 테스트**

새 Claude Code 세션을 열어서 실제로 `/rakis-setup`이 명령으로 인식되는지 확인. 슬래시 명령이 `/rakis-setup`인지 `/rakis:setup`인지는 플러그인 슬래시 명령 네임스페이스 규칙에 따라 다를 수 있음. 만약 호출 형식이 다르다면 다음을 수정:
- `hooks/hooks.json`의 안내 메시지에서 명령 이름
- `README.md`의 명령 이름
- `commands/rakis-setup.md`의 헤더(필요 시)

이 step에서 발견된 차이는 별도 후속 커밋으로 처리 (`fix: /rakis-setup 호출 형식 정정`).

---

## v2 후보 (이번 plan에서는 안 함)

- `lint.sh`에 `hooks/`, `commands/` 디렉토리 검증 추가 (JSON 문법, 필수 필드 등)
- `plugin.json` 버전 추적 → 의존성 추가 시 자동 재안내
- Linux / Windows 지원
- `/rakis-setup --recheck`, `--yes` 옵션
- PPT/DOCX 처리 재도입 (`uv run --with python-pptx`)
- 의존성 매트릭스를 별도 manifest 파일로 분리
