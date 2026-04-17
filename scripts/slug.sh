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
