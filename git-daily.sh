#!/usr/bin/env bash
set -euo pipefail

GITHUB_TOKEN=$(hermes config get GITHUB_TOKEN 2>/dev/null)
if [ -z "${GITHUB_TOKEN:-}" ]; then
  echo "ERROR: hermes config get GITHUB_TOKEN returned empty" >&2
  exit 1
fi

CUTOFF=$(date -u -v-24H +%Y-%m-%dT%H:%M:%SZ)

curl -s -H "Authorization: Bearer ${GITHUB_TOKEN}" \
  "https://api.github.com/users/Neilos-Thumm/events?per_page=30" \
| jq -r --arg cutoff "$CUTOFF" '
    [ .[]
      | select(.type == "PushEvent")
      | select(.created_at > $cutoff)
    ]
    | if length == 0 then "NO_PUSHES"
      else .[] | "\(.repo.name): \(.payload.commits[].message)"
      end
  '
