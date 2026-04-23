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
