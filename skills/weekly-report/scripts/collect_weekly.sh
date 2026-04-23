#!/usr/bin/env bash
# collect_weekly.sh — workspace 하위 git 레포의 주간 활동을 JSON으로 수집
# Usage: collect_weekly.sh [--since YYYY-MM-DD] [--until YYYY-MM-DD] [--root <dir>]
set -euo pipefail

for tool in git gh jq yq; do
  if ! command -v $tool >/dev/null 2>&1; then
    echo "Error: '$tool' not installed. Run '/rakis:setup' or 'brew install $tool'." >&2
    exit 2
  fi
done

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

REPOS_JSON="[]"

# gh 두 계정 토큰 로딩 (없어도 계속 진행, 해당 계정 레포만 skip됨)
KT_TOKEN=$(gh auth token --user hr-son_ktopen 2>/dev/null || echo "")
PERSONAL_TOKEN=$(gh auth token --user raki-1203 2>/dev/null || echo "")

SKIPPED_JSON="[]"

repo_count=$(find "$ROOT" -maxdepth 2 -type d -name ".git" | wc -l | tr -d ' ')

if [ -d "$ROOT/.git" ]; then
  # CWD 자체가 git 레포인 경우 (focus mode)
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

for dir in "${REPO_DIRS[@]}"; do
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

  # 활동 여부는 Task 4에서 종합 판단. 일단 커밋 데이터만 포함하여 누적.
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

  # 활동 없음 = 커밋 0 + PR 0 + 이슈 0 → 리포트에서 드롭
  activity_count=$(echo "$repo_json" | jq '[.commits, .prs_done, .prs_open, .issues_closed, .issues_open] | map(length) | add')
  if [ "$activity_count" -eq 0 ]; then
    continue
  fi

  REPOS_JSON=$(echo "$REPOS_JSON" | jq --argjson r "$repo_json" '. + [$r]')
done

jq -n \
  --arg since "$SINCE" --arg until "$UNTIL" --arg week "$WEEK" \
  --argjson repos "$REPOS_JSON" \
  --argjson skipped "$SKIPPED_JSON" \
  '{since: $since, until: $until, week_number: $week,
    repos: $repos, skipped_repos: $skipped}'
