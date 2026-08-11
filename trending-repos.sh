#!/usr/bin/env bash
set -euo pipefail

GITHUB_TOKEN=$(hermes config get GITHUB_TOKEN 2>/dev/null)
if [ -z "${GITHUB_TOKEN:-}" ]; then
  echo "ERROR: hermes config get GITHUB_TOKEN returned empty" >&2
  exit 1
fi

SINCE=$(date -u -v-7d +%Y-%m-%d)

RESPONSE=$(curl -s -H "Authorization: Bearer ${GITHUB_TOKEN}" \
  -H "Accept: application/vnd.github+json" \
  "https://api.github.com/search/repositories?q=created:>${SINCE}&sort=stars&order=desc&per_page=10")

if echo "$RESPONSE" | jq -e '.message' >/dev/null 2>&1; then
  echo "ERROR: GitHub API error: $(echo "$RESPONSE" | jq -r '.message')" >&2
  exit 1
fi

echo "$RESPONSE" | jq -r '
  .items[]
  | "\(.full_name) | ★\(.stargazers_count) | \(.language // "unknown") | \(.description // "no description") | \(.html_url)"
'
