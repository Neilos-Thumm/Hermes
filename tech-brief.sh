#!/usr/bin/env bash
set -euo pipefail

echo "## Hacker News top stories (broad tech/startup/AI pool)"
IDS=$(curl -s "https://hacker-news.firebaseio.com/v0/topstories.json" | jq -r '.[0:25][]')
for ID in $IDS; do
  curl -s "https://hacker-news.firebaseio.com/v0/item/${ID}.json" \
    | jq -r 'select(.title != null) | "- \(.title) (\(.score) pts) \(.url // ("https://news.ycombinator.com/item?id=" + (.id|tostring)))"'
done

echo
echo "## TechCrunch (mainstream tech/industry news)"
curl -s -L -A "Mozilla/5.0" "https://techcrunch.com/feed/" | python3 -c '
import sys, xml.etree.ElementTree as ET
root = ET.fromstring(sys.stdin.read())
for item in root.findall(".//item")[:15]:
    title = item.findtext("title") or ""
    link = item.findtext("link") or ""
    print(f"- {title} {link}")
'
