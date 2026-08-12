#!/usr/bin/env bash
set -euo pipefail

echo "## Tech (Hacker News top stories)"
IDS=$(curl -s "https://hacker-news.firebaseio.com/v0/topstories.json" | jq -r '.[0:8][]')
for ID in $IDS; do
  curl -s "https://hacker-news.firebaseio.com/v0/item/${ID}.json" \
    | jq -r 'select(.title != null) | "- \(.title) (\(.score) pts) \(.url // ("https://news.ycombinator.com/item?id=" + (.id|tostring)))"'
done

echo
echo "## General / major world news (BBC)"
curl -s -L -A "Mozilla/5.0" "https://feeds.bbci.co.uk/news/rss.xml" | python3 -c '
import sys, xml.etree.ElementTree as ET
root = ET.fromstring(sys.stdin.read())
for item in root.findall(".//item")[:8]:
    title = item.findtext("title") or ""
    link = item.findtext("link") or ""
    print(f"- {title} {link}")
'
