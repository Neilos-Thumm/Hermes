#!/usr/bin/env bash
set -euo pipefail

echo "## General / world / politics news (BBC)"
curl -s -L -A "Mozilla/5.0" "https://feeds.bbci.co.uk/news/rss.xml" | python3 -c '
import sys, xml.etree.ElementTree as ET
root = ET.fromstring(sys.stdin.read())
for item in root.findall(".//item")[:15]:
    title = item.findtext("title") or ""
    link = item.findtext("link") or ""
    print(f"- {title} {link}")
'
