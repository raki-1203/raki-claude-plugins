# Weekly Report Skill Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 매주 목요일 회의 전, 워크스페이스의 모든 git 레포에서 본인이 한 작업을 수집·요약한 주간 보고서 초안을 생성하는 `/rakis:weekly-report` 스킬을 구현한다.

**Architecture:** 수집(bash 스크립트)과 요약(Claude LLM)을 분리. `collect_weekly.sh`가 git/gh로 결정적 수집 → JSON 출력 → SKILL.md가 Claude에게 JSON을 의미 단위로 그룹핑하라고 지시 → 마크다운 생성 → 터미널 출력 + `~/workspace/weekly-reports/YYYY-W##.md` 저장.

**Tech Stack:** bash, `git`, `gh` CLI, `jq`, `yq`. Plugin: `rakis@raki-claude-plugins`. 대상 플랫폼: macOS.

**Spec:** `docs/superpowers/specs/2026-04-23-weekly-report-design.md`

---

## File Structure

**Create:**
- `skills/weekly-report/SKILL.md` — Claude 실행 지시서
- `skills/weekly-report/scripts/collect_weekly.sh` — bash 수집 스크립트

**Modify:**
- `commands/setup.md` — 의존성 점검에 `jq`, `yq` 추가
- `commands/help.md` — 스킬 목록에 `weekly-report` 추가 및 상세 섹션 추가
- `commands/skill-mapping.md` — 글로벌 CLAUDE.md용 매핑 테이블에 `weekly-report` 추가

**Unchanged:** `.claude-plugin/plugin.json` (스킬 등록 불필요 — `skills/*/SKILL.md` 자동 인식)

---

## Task 1: 스킬 디렉토리 및 collect 스크립트 스캐폴드 생성

**Files:**
- Create: `skills/weekly-report/SKILL.md` (frontmatter만)
- Create: `skills/weekly-report/scripts/collect_weekly.sh` (실행 권한 + 최소 스텁)

- [ ] **Step 1: 디렉토리 생성**

```bash
cd ~/workspace/raki-claude-plugins
mkdir -p skills/weekly-report/scripts
```

- [ ] **Step 2: SKILL.md 스캐폴드 작성**

파일 `skills/weekly-report/SKILL.md`:

```markdown
---
name: weekly-report
description: "주간 업무 보고서 초안을 자동 생성. 목요일 회의 전 '/rakis:weekly-report' 또는 '주간보고 만들어줘'라고 할 때 사용. CWD 아래 모든 git 레포에서 지난 7일간 본인 커밋/PR/이슈를 수집·요약해 마크다운으로 출력한다."
version: 1.0.0
license: MIT
---

# weekly-report — 주간 업무 보고서 생성

_(구현 중 — Task 5에서 채움)_
```

- [ ] **Step 3: collect_weekly.sh 스텁 작성**

파일 `skills/weekly-report/scripts/collect_weekly.sh`:

```bash
#!/usr/bin/env bash
# collect_weekly.sh — workspace 하위 git 레포의 주간 활동을 JSON으로 수집
# Usage: collect_weekly.sh [--since YYYY-MM-DD] [--until YYYY-MM-DD] [--root <dir>]
set -euo pipefail

SINCE=""
UNTIL=""
ROOT="$PWD"

while [[ $# -gt 0 ]]; do
  case $1 in
    --since) SINCE="$2"; shift 2 ;;
    --until) UNTIL="$2"; shift 2 ;;
    --root)  ROOT="$2";  shift 2 ;;
    *) echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done

[ -z "$SINCE" ] && SINCE=$(date -v-7d +%Y-%m-%d)
[ -z "$UNTIL" ] && UNTIL=$(date +%Y-%m-%d)
WEEK=$(date -j -f "%Y-%m-%d" "$UNTIL" +%G-W%V 2>/dev/null || date +%G-W%V)

echo "TODO: implement collection" >&2
jq -n --arg since "$SINCE" --arg until "$UNTIL" --arg week "$WEEK" \
  '{since: $since, until: $until, week_number: $week, repos: [], skipped_repos: []}'
```

실행 권한:
```bash
chmod +x skills/weekly-report/scripts/collect_weekly.sh
```

- [ ] **Step 4: 스텁 실행 검증**

```bash
bash skills/weekly-report/scripts/collect_weekly.sh | jq .
```
Expected output:
```json
{
  "since": "2026-04-16",
  "until": "2026-04-23",
  "week_number": "2026-W17",
  "repos": [],
  "skipped_repos": []
}
```

`jq: parse error` 나오면 JSON 조립이 잘못된 것 — 다시 점검.

- [ ] **Step 5: 커밋**

```bash
git add skills/weekly-report/
git commit -m "feat(weekly-report): 스킬 스캐폴드와 수집 스크립트 스텁 추가"
```

---

## Task 2: 레포 순회 및 커밋 수집 로직

**Files:**
- Modify: `skills/weekly-report/scripts/collect_weekly.sh`

- [ ] **Step 1: 레포 순회 + 커밋 수집 구현**

Task 1의 `echo "TODO"` 부분을 아래로 교체:

```bash
REPOS_JSON="[]"

for dir in "$ROOT"/*/; do
  [ -d "$dir/.git" ] || continue

  repo_name=$(basename "$dir")
  remote=$(git -C "$dir" remote get-url origin 2>/dev/null || echo "")
  [ -z "$remote" ] && continue  # 원격 없는 레포는 gh 조회 불가 → skip

  # owner/repo 파싱 (SSH/HTTPS 둘 다 지원)
  # git@github.com:axd-arena/kt-innovation-hub-2.git → axd-arena/kt-innovation-hub-2
  # https://github.com/foo/bar.git → foo/bar
  owner_repo=$(echo "$remote" | sed -E 's#(git@[^:]+:|https?://[^/]+/)##; s#\.git$##')
  owner=$(echo "$owner_repo" | cut -d/ -f1)
  repo=$(echo "$owner_repo" | cut -d/ -f2)

  me_email=$(git -C "$dir" config user.email || echo "")
  [ -z "$me_email" ] && continue

  # 본인 커밋 수집 (--all로 실험 브랜치 포함, --no-merges로 머지 커밋 제외)
  commits=$(git -C "$dir" log --all --no-merges \
    --author="$me_email" \
    --since="$SINCE 00:00:00" \
    --until="$UNTIL 23:59:59" \
    --format='%H%x09%s%x09%ad%x09%D' --date=short 2>/dev/null \
    | jq -Rs 'split("\n") | map(select(length>0)) | map(split("\t")) |
              map({sha: .[0][0:7], subject: .[1], date: .[2], branch: .[3]})')
  commits="${commits:-[]}"

  # 활동 여부는 Task 4에서 종합 판단. 일단 커밋 데이터만 포함하여 누적.
  repo_json=$(jq -n \
    --arg name "$repo_name" \
    --arg remote "$remote" \
    --arg owner "$owner" \
    --arg me "$me_email" \
    --argjson commits "$commits" \
    '{name: $name, remote: $remote, owner: $owner, me: $me,
      commits: $commits, prs_done: [], prs_open: [],
      issues_closed: [], issues_open: []}')

  REPOS_JSON=$(echo "$REPOS_JSON" | jq --argjson r "$repo_json" '. + [$r]')
done

jq -n \
  --arg since "$SINCE" --arg until "$UNTIL" --arg week "$WEEK" \
  --argjson repos "$REPOS_JSON" \
  '{since: $since, until: $until, week_number: $week,
    repos: $repos, skipped_repos: []}'
```

- [ ] **Step 2: 실행 검증**

```bash
cd ~/workspace/kt
bash ~/workspace/raki-claude-plugins/skills/weekly-report/scripts/collect_weekly.sh | jq '.repos | map({name, commit_count: (.commits | length)})'
```

Expected: 본인 이메일로 지난 7일 커밋이 있는 레포들의 커밋 수가 나와야 함. 커밋 0개인 레포도 일단 리스트에 포함됨 (Task 4에서 필터링).

점검 포인트:
- `owner/repo` 파싱이 모든 remote 형식에서 올바른지: `jq '.repos | map({name, owner})'`
- `me_email`이 레포마다 올바르게 다르게 나오는지 (`workspace/KT/*`는 `hr.son@kt.com`)

- [ ] **Step 3: 커밋**

```bash
git add skills/weekly-report/scripts/collect_weekly.sh
git commit -m "feat(weekly-report): 레포 순회 및 커밋 수집 구현"
```

---

## Task 3: PR/이슈 수집 + 다중 계정 fallback

**Files:**
- Modify: `skills/weekly-report/scripts/collect_weekly.sh`

- [ ] **Step 1: 토큰 로딩 블록을 스크립트 상단에 추가**

파싱 블록 이후, 레포 루프 이전에 삽입:

```bash
# gh 두 계정 토큰 로딩 (없어도 계속 진행, 해당 계정 레포만 skip됨)
KT_TOKEN=$(gh auth token --user hr-son_ktopen 2>/dev/null || echo "")
PERSONAL_TOKEN=$(gh auth token --user raki-1203 2>/dev/null || echo "")

SKIPPED_JSON="[]"

# 헬퍼: primary 토큰으로 먼저 시도, 실패 시 secondary
# 인자: $1=owner $2=repo $3=subcommand(pr|issue) $4..=gh args
gh_with_fallback() {
  local owner=$1 repo=$2 sub=$3; shift 3

  local primary secondary
  case $owner in
    raki-1203|heegene-msft|kimcy)
      primary="$PERSONAL_TOKEN"; secondary="$KT_TOKEN" ;;
    *)
      primary="$KT_TOKEN"; secondary="$PERSONAL_TOKEN" ;;
  esac

  local result
  if [ -n "$primary" ]; then
    result=$(GH_TOKEN="$primary" gh "$sub" list -R "$owner/$repo" "$@" 2>/dev/null) && { echo "$result"; return 0; }
  fi
  if [ -n "$secondary" ]; then
    result=$(GH_TOKEN="$secondary" gh "$sub" list -R "$owner/$repo" "$@" 2>/dev/null) && { echo "$result"; return 0; }
  fi
  return 1
}
```

- [ ] **Step 2: 레포 루프 안에 PR/이슈 수집 추가**

Task 2의 커밋 수집 이후, `repo_json` 조립 이전에 추가:

```bash
# PR 수집 (search로 updated 기준 필터)
prs_raw=$(gh_with_fallback "$owner" "$repo" pr \
  --author "@me" --state all \
  --search "updated:>=$SINCE" \
  --json number,title,body,state,mergedAt,isDraft,url 2>/dev/null) || {
    SKIPPED_JSON=$(echo "$SKIPPED_JSON" | jq \
      --arg name "$repo_name" --arg reason "gh access denied (both accounts)" \
      '. + [{name: $name, reason: $reason}]')
    continue
  }
  prs_raw="${prs_raw:-[]}"

  prs_done=$(echo "$prs_raw" | jq '[.[] | select(.state == "MERGED" or .state == "CLOSED")]')
  prs_open=$(echo "$prs_raw" | jq '[.[] | select(.state == "OPEN") | {number, title, draft: .isDraft}]')

  # 이슈 수집
  issues_raw=$(gh_with_fallback "$owner" "$repo" issue \
    --assignee "@me" --state all \
    --search "updated:>=$SINCE" \
    --json number,title,state,closedAt,url 2>/dev/null || echo "[]")

  issues_closed=$(echo "$issues_raw" | jq '[.[] | select(.state == "CLOSED")]')
  issues_open=$(echo "$issues_raw"   | jq '[.[] | select(.state == "OPEN")]')
```

그리고 Task 2의 `repo_json` 조립 블록에서 `prs_done: []`, `prs_open: []`, `issues_closed: []`, `issues_open: []` 자리에 각각 `$prs_done`, `$prs_open`, `$issues_closed`, `$issues_open`를 `--argjson`으로 바인딩하도록 교체:

```bash
repo_json=$(jq -n \
  --arg name "$repo_name" \
  --arg remote "$remote" \
  --arg owner "$owner" \
  --arg me "$me_email" \
  --argjson commits "$commits" \
  --argjson prs_done "$prs_done" \
  --argjson prs_open "$prs_open" \
  --argjson issues_closed "$issues_closed" \
  --argjson issues_open "$issues_open" \
  '{name: $name, remote: $remote, owner: $owner, me: $me,
    commits: $commits, prs_done: $prs_done, prs_open: $prs_open,
    issues_closed: $issues_closed, issues_open: $issues_open}')
```

그리고 최종 JSON 출력에서 `skipped_repos: []`를 `--argjson skipped "$SKIPPED_JSON"`로 바인딩하여 `skipped_repos: $skipped` 넣기.

- [ ] **Step 3: 실행 검증**

```bash
cd ~/workspace/kt
bash ~/workspace/raki-claude-plugins/skills/weekly-report/scripts/collect_weekly.sh \
  | jq '.repos | map({name, prs_done: (.prs_done | length), prs_open: (.prs_open | length), issues_open: (.issues_open | length)})'
```

Expected:
- 본인이 활동한 레포는 prs_done/prs_open 숫자가 나와야 함
- 개인 레포(raki-1203/*)도 `PERSONAL_TOKEN`으로 접근 성공
- 권한 없는 레포는 `.skipped_repos`에 포함되어야 함:
  ```bash
  ... | jq '.skipped_repos'
  ```

- [ ] **Step 4: 커밋**

```bash
git add skills/weekly-report/scripts/collect_weekly.sh
git commit -m "feat(weekly-report): PR/이슈 수집과 다중 계정 fallback 구현"
```

---

## Task 4: 활동 필터링과 엣지 케이스 처리

**Files:**
- Modify: `skills/weekly-report/scripts/collect_weekly.sh`

- [ ] **Step 1: 의존성 사전 체크 블록 추가**

스크립트 최상단 `set -euo pipefail` 바로 아래:

```bash
for tool in git gh jq yq; do
  if ! command -v $tool >/dev/null 2>&1; then
    echo "Error: '$tool' not installed. Run '/rakis:setup' or 'brew install $tool'." >&2
    exit 2
  fi
done
```

- [ ] **Step 2: CWD 레포 감지 에러 처리**

레포 루프 이전에:

```bash
repo_count=$(find "$ROOT" -maxdepth 2 -type d -name ".git" | wc -l | tr -d ' ')

# CWD 자체가 git 레포인 경우 (focus mode)
if [ -d "$ROOT/.git" ]; then
  # ROOT 자체를 처리 대상으로 두고 루프 한 번만 돌도록 처리
  REPO_DIRS=("$ROOT")
elif [ "$repo_count" -eq 0 ]; then
  echo "Error: '$ROOT' 아래에 git 레포가 없습니다. workspace 루트에서 실행하세요." >&2
  exit 3
else
  REPO_DIRS=()
  for d in "$ROOT"/*/; do
    [ -d "$d/.git" ] && REPO_DIRS+=("$d")
  done
fi
```

그리고 기존 `for dir in "$ROOT"/*/; do ... continue; ...done` 루프를 `for dir in "${REPO_DIRS[@]}"; do` 로 변경.

- [ ] **Step 3: 활동 없는 레포 필터링**

루프 말미에서 repo_json을 누적하기 전에:

```bash
# 활동 없음 = 커밋 0 + PR 0 + 이슈 0 → 리포트에서 드롭
activity_count=$(echo "$repo_json" | jq '[.commits, .prs_done, .prs_open, .issues_closed, .issues_open] | map(length) | add')
if [ "$activity_count" -eq 0 ]; then
  continue
fi

REPOS_JSON=$(echo "$REPOS_JSON" | jq --argjson r "$repo_json" '. + [$r]')
```

- [ ] **Step 4: 검증 — 활동 없는 레포 제외 확인**

```bash
cd ~/workspace/kt
bash ~/workspace/raki-claude-plugins/skills/weekly-report/scripts/collect_weekly.sh | jq '.repos | length'
```

Expected: 13개보다 적어야 함 (지난 7일 활동 있는 레포만).

또한 CWD 오용 확인:
```bash
cd /tmp && bash ~/workspace/raki-claude-plugins/skills/weekly-report/scripts/collect_weekly.sh
# Expected: "Error: ... git 레포가 없습니다 ..." 메시지 + exit 3
```

- [ ] **Step 5: 커밋**

```bash
git add skills/weekly-report/scripts/collect_weekly.sh
git commit -m "feat(weekly-report): 활동 필터링 및 엣지 케이스 처리 추가"
```

---

## Task 5: SKILL.md 본문 작성 (인자 파싱 + 스크립트 호출)

**Files:**
- Modify: `skills/weekly-report/SKILL.md` (Task 1의 플레이스홀더 교체)

- [ ] **Step 1: SKILL.md 전체 본문 작성**

```markdown
---
name: weekly-report
description: "주간 업무 보고서 초안을 자동 생성. 목요일 회의 전 '/rakis:weekly-report' 또는 '주간보고 만들어줘'라고 할 때 사용. CWD 아래 모든 git 레포에서 지난 7일간 본인 커밋/PR/이슈를 수집·요약해 마크다운으로 출력한다."
version: 1.0.0
license: MIT
---

# weekly-report — 주간 업무 보고서 생성

CWD 아래 git 레포들에서 지난 7일간의 본인 활동을 수집하여 주간 보고서 초안(마크다운)을 만들고, 터미널에 출력 + 파일로 저장한다.

## 인자 (선택)

```
/rakis:weekly-report [--since YYYY-MM-DD] [--until YYYY-MM-DD] [--force]
```

- `--since`, `--until`: 기본값은 각각 7일 전, 오늘. 필요시 재정의
- `--force`: 같은 주 리포트 파일이 있어도 덮어쓰기 (기본은 `-2`, `-3` 서픽스로 저장)

## 절차

### 1. 인자 파싱

`$ARGUMENTS`에서 `--since`, `--until`, `--force`를 파싱. 없으면 기본값 사용.

### 2. 수집 스크립트 실행

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/weekly-report/scripts/collect_weekly.sh" \
  [--since $SINCE] [--until $UNTIL] \
  --root "$PWD"
```

- stdout을 JSON으로 캡처
- exit 2 (의존성 누락) → `/rakis:setup` 실행 안내 후 중단
- exit 3 (CWD에 레포 없음) → 사용자에게 "workspace 루트에서 실행하세요" 안내 후 중단

### 3. 활동 판정

- `.repos`가 빈 배열이면 → "이번 주 기록된 활동이 없습니다" 메시지 + 파일 저장 없이 중단

### 4. 요약 생성 (Task 6 참조)

JSON의 각 레포에 대해 이번주 성과 / 다음주 계획 후보 bullet을 만든다.

### 5. 마크다운 조립 (Task 7 참조)

### 6. 출력 + 저장

- 터미널에 전체 마크다운 출력
- `~/workspace/weekly-reports/{week_number}.md`에 저장 (디렉토리 없으면 `mkdir -p`)
- 이미 있으면 `-2`, `-3`... 서픽스 붙임 (`--force`면 덮어씀)
- 저장된 절대경로를 마지막 한 줄로 출력
```

- [ ] **Step 2: SKILL.md 점검**

```bash
head -20 skills/weekly-report/SKILL.md
```
frontmatter가 올바른 YAML인지, description에 트리거 문구가 들어있는지 확인.

- [ ] **Step 3: 커밋**

```bash
git add skills/weekly-report/SKILL.md
git commit -m "feat(weekly-report): SKILL.md 절차 프레임 작성"
```

---

## Task 6: SKILL.md — 요약 생성 지시 섹션 추가

**Files:**
- Modify: `skills/weekly-report/SKILL.md`

- [ ] **Step 1: 요약 섹션 추가**

Task 5의 "### 4. 요약 생성 (Task 6 참조)" 자리에 아래를 삽입:

```markdown
### 4. 요약 생성

JSON `.repos` 배열을 순회하며 레포별로 아래를 수행:

#### 4-A. 이번주 성과 bullet 생성

입력: `.commits`, `.prs_done`, `.issues_closed`

규칙:
1. **PR 우선**: `prs_done` 각 PR → "PR 제목 (#번호)" 형태로 bullet 하나. 머지된 건 일반 표기, close된 건 "[close] ..." 표기
2. **중복 커밋 제거**: PR에 속한 커밋은 중복 bullet로 만들지 않음. PR의 URL/번호로부터 연관 커밋을 추정하거나, 커밋 subject가 PR title의 부분 집합이면 드롭 (완전 정확할 필요 없음 — 중복 인상만 피하면 됨)
3. **직접 커밋 요약**: PR에 속하지 않은 커밋 중에서 아래는 드롭:
    - `wip`, `WIP`, `fix typo`, `lint`, `chore: format`, `style:`로 시작, `Merge branch` 등 **의미 없는 메시지**
    - subject가 10자 미만
4. **남은 커밋**: 의미 단위로 묶어 1~2개 bullet로 요약 (많으면 핵심만). 예: `세션 관리 로직 / 에러 핸들링 / 테스트 추가` 3개 커밋을 "세션 관리 로직 구현" 한 bullet로 묶음
5. **이슈**: `issues_closed` 각 항목 → "이슈 해결: 제목 (#번호)" bullet

bullet이 하나도 안 나오면 이번주 성과 섹션은 "_(활동 기록 없음)_" 표기.

#### 4-B. 다음주 계획 후보 bullet 생성

입력: `.prs_open`, `.issues_open`

규칙 (요약하지 않고 그대로 나열):
- `prs_open` 각 PR → "[진행중] 제목 (#번호)" (`draft: true`면 "[초안] ...")
- `issues_open` 각 이슈 → "[이슈] 제목 (#번호)"

bullet 하나도 없으면 "_(미완료 항목 없음)_" 표기.
```

- [ ] **Step 2: 점검**

SKILL.md를 다시 읽어, 4-A/4-B 규칙이 JSON 스키마 필드(`commits`, `prs_done`, `prs_open`, `issues_closed`, `issues_open`)와 완전히 일치하는지 확인.

- [ ] **Step 3: 커밋**

```bash
git add skills/weekly-report/SKILL.md
git commit -m "feat(weekly-report): 요약 생성 규칙 추가"
```

---

## Task 7: SKILL.md — 마크다운 조립 및 출력/저장 지시

**Files:**
- Modify: `skills/weekly-report/SKILL.md`

- [ ] **Step 1: 조립/저장 섹션 교체**

Task 5의 "### 5. 마크다운 조립 (Task 7 참조)" 자리에 아래를 삽입:

````markdown
### 5. 마크다운 조립

출력 형식:

```markdown
# 주간 업무 기록 - {week_number} ({since} ~ {until})

## {repo.name}

**이번주 성과**
- ...

**다음주 계획 후보**
- ...

## {repo.name}
...

---
_스킵된 레포: {comma-joined list with reason}_
```

규칙:
- 활동 있는 레포만 섹션으로 포함 (수집 스크립트에서 이미 필터링됨)
- `skipped_repos`가 비어있지 않으면 마지막 `---` 아래 한 줄로 표기
- 비어있으면 마지막 `---` 라인 생략

### 6. 터미널 출력 + 파일 저장

- 마크다운 전체를 터미널에 출력 (사용자가 복붙할 수 있도록)
- 저장 경로: `$HOME/workspace/weekly-reports/{week_number}.md`
  - 디렉토리 없으면 `mkdir -p`
  - 파일 존재 + `--force` 없음 → `{week_number}-2.md`, `{week_number}-3.md`... 로 증분 저장
  - `--force` 있음 → 그대로 덮어쓰기
- 저장 후 절대경로를 마지막 한 줄에 출력:
  > 저장 완료: /Users/raki-1203/workspace/weekly-reports/2026-W17.md
````

- [ ] **Step 2: SKILL.md 전체 점검**

```bash
cat skills/weekly-report/SKILL.md
```

전체 흐름 (인자 파싱 → 스크립트 실행 → 활동 판정 → 요약 → 조립 → 출력/저장)이 끊김없이 이어지는지 확인. 중간에 Task Nx 참조 플레이스홀더가 남아있으면 제거.

- [ ] **Step 3: 커밋**

```bash
git add skills/weekly-report/SKILL.md
git commit -m "feat(weekly-report): 마크다운 조립 및 저장 규칙 추가"
```

---

## Task 8: /rakis:setup에 jq, yq 의존성 추가

**Files:**
- Modify: `commands/setup.md`

- [ ] **Step 1: 의존성 테이블에 항목 추가**

`commands/setup.md`를 열고 단계 2의 도구 테이블을 찾아 아래 두 줄을 추가:

```markdown
| `jq` | `command -v jq` | `brew upgrade jq 2>/dev/null \|\| brew install jq` |
| `yq` | `command -v yq` | `brew upgrade yq 2>/dev/null \|\| brew install yq` |
```

기존 `gh` 줄 바로 아래에 끼워넣는 것을 권장.

- [ ] **Step 2: 결과 출력 예시 템플릿 업데이트**

같은 파일에서 설치 결과 출력 예시 블록에 `jq`, `yq`도 포함되도록 업데이트:

```
[필수]
  uv               ✓
  notebooklm-py    ✓
  node             ✓
  gh               ✓
  jq               ✓
  yq               ✓
  graphify         ✓
```

- [ ] **Step 3: 검증**

```bash
grep -E "jq|yq" commands/setup.md | head -10
```

두 도구가 체크 테이블과 출력 예시 양쪽에 추가됐는지 확인.

- [ ] **Step 4: 커밋**

```bash
git add commands/setup.md
git commit -m "feat(setup): weekly-report 스킬 의존성 jq, yq 추가"
```

---

## Task 9: help.md와 skill-mapping.md에 weekly-report 등록

**Files:**
- Modify: `commands/help.md`
- Modify: `commands/skill-mapping.md`

- [ ] **Step 1: help.md 인식 스킬 목록에 추가**

`commands/help.md`의 "인식하는 스킬명" 섹션에 `weekly-report`를 기존 스킬 리스트에 추가:

```markdown
- `wiki-query`, `wiki-ingest`, `source-fetch`, `migrate-v3`, `wiki-wrap-up`, `wiki-lint`, `wiki-init`, `weekly-report`
```

- [ ] **Step 2: help.md 전체 개요 출력에 weekly-report 항목 추가**

help.md의 "단계 A: 전체 개요 출력" 블록에서 스킬 목록 표가 있는 부분에 새 행을 추가. 이미 있는 항목들의 문체와 맞춘다:

```markdown
| `rakis:weekly-report` | 주간 업무 보고서 초안 생성 (git/gh 기반) |
```

- [ ] **Step 3: help.md 단계 B 상세 섹션 추가**

단계 B (스킬명 1개일 때 상세 출력)에 `weekly-report` 케이스를 추가. 다른 스킬의 상세 케이스 블록을 참고해 같은 형식으로:

```markdown
### weekly-report

**언제 사용**: 매주 목요일 회의 전, 지난 7일 작업 내역 정리가 귀찮을 때

**실행**:
    /rakis:weekly-report
    /rakis:weekly-report --since 2026-04-15 --until 2026-04-22

**동작**:
1. 현재 디렉토리 아래 git 레포들을 순회
2. 각 레포에서 본인 커밋/PR/이슈 수집 (지난 7일)
3. 의미 단위로 묶어서 "이번주 성과" + "다음주 계획 후보" bullet 생성
4. 터미널 출력 + `~/workspace/weekly-reports/YYYY-W##.md` 저장

**요구사항**: `gh`, `jq`, `yq` (없으면 `/rakis:setup` 실행)
```

- [ ] **Step 4: skill-mapping.md에 한 줄 추가**

`commands/skill-mapping.md`의 스킬 표에 다음 행을 추가 (위치: 적절한 섹션에):

```markdown
| 주간 업무 보고서 생성 | `rakis:weekly-report` |
```

기존 위키 섹션 바깥에 별도 섹션으로 두거나, "기타 유틸" 같은 소섹션으로 묶는 것이 깔끔. 파일 구조를 보고 자연스러운 위치에 배치.

- [ ] **Step 5: 커밋**

```bash
git add commands/help.md commands/skill-mapping.md
git commit -m "feat(weekly-report): help.md와 skill-mapping.md에 weekly-report 등록"
```

---

## Task 10: 실사용 스모크 테스트 및 프롬프트 튜닝

**Files:** (필요 시) `skills/weekly-report/SKILL.md`, `skills/weekly-report/scripts/collect_weekly.sh`

- [ ] **Step 1: 실제 워크스페이스에서 스크립트 단독 실행**

```bash
cd ~/workspace/kt
bash ~/workspace/raki-claude-plugins/skills/weekly-report/scripts/collect_weekly.sh | jq > /tmp/wr.json
cat /tmp/wr.json | jq '{week_number, repo_count: (.repos | length), skipped: .skipped_repos}'
```

점검:
- [ ] `week_number`가 올바른가? (2026-04-23 실행 시 `2026-W17`)
- [ ] `repo_count`가 상식적인가? (본인이 이번주 작업한 레포 개수)
- [ ] `skipped_repos`에 예상치 못한 레포가 들어가지 않는가?

문제 발생 시 `collect_weekly.sh`를 수정 후 다시 실행.

- [ ] **Step 2: 스킬 호출 통한 end-to-end 검증**

Claude Code에서:

```
/rakis:weekly-report
```

점검:
- [ ] 터미널 출력이 이미지 참고 형식(프로젝트 섹션 + bullet)에 맞는가?
- [ ] `~/workspace/weekly-reports/2026-W17.md`가 생성됐는가?
- [ ] 이번주 성과 bullet이 노이즈(`wip`, `typo`)를 제거하고 의미 단위로 묶였는가?
- [ ] 다음주 계획 후보에 현재 open PR/이슈가 나타나는가?

- [ ] **Step 3: 2회 연속 실행 시 `-2.md` 생성 확인**

```
/rakis:weekly-report
```
Expected: `2026-W17-2.md`로 저장됐다는 메시지.

그리고:
```
/rakis:weekly-report --force
```
Expected: `2026-W17.md`를 덮어썼다는 메시지.

- [ ] **Step 4: 품질 이슈 튜닝**

결과에서 아래가 발생하면 SKILL.md의 4-A 규칙을 수정:
- 노이즈 커밋이 살아남음 → 드롭 규칙 강화
- 관련 커밋이 잘 묶이지 않음 → 그룹핑 기준 예시 추가
- PR과 커밋이 중복 표기 → 중복 제거 기준 강화

수정 후 다시 `/rakis:weekly-report` 실행해 재검증.

- [ ] **Step 5: 최종 커밋**

튜닝 변경이 있으면:
```bash
git add skills/weekly-report/
git commit -m "fix(weekly-report): 실사용 피드백 반영 (요약 품질 튜닝)"
```

- [ ] **Step 6: CHANGELOG.md 업데이트 및 버전 bump**

`CHANGELOG.md` 상단에 추가:

```markdown
## 3.4.0 - 2026-04-23

### Added
- `rakis:weekly-report` 스킬: 주간 업무 보고서 자동 생성 (git commits + GitHub PR/이슈 기반)
- `/rakis:setup`에 `jq`, `yq` 의존성 추가
```

`package.json`과 `.claude-plugin/plugin.json`의 `version`을 `3.4.0`으로 수정:

```bash
# package.json
# "version": "3.3.0" → "3.4.0"

# .claude-plugin/plugin.json
# "version": "3.3.0" → "3.4.0"
```

커밋:

```bash
git add CHANGELOG.md package.json .claude-plugin/plugin.json
git commit -m "chore: bump version to 3.4.0 (weekly-report 스킬 추가)"
```

---

## Notes

**작업 순서**: Task 1→10은 순차 의존성이 있음 (특히 1→2→3→4는 같은 파일 점진 확장, 5→6→7도 마찬가지). 한 번에 여러 태스크를 건너뛰어 작업하지 말 것.

**테스트 부재에 대한 보완**: 자동화 테스트 대신 Task 10의 스모크 테스트가 검증 역할. 실제 데이터로 한 번 돌려보고 결과 마크다운을 눈으로 확인하는 게 유일한 검증.

**커밋 메시지 스타일**: CLAUDE.md의 git-workflow 규칙(`feat:`, `fix:`, `chore:`)을 따름. 한국어 메시지 OK (기존 rakis 커밋이 한국어인지 영어인지 확인 후 맞출 것).
