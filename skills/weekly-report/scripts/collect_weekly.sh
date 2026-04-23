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
