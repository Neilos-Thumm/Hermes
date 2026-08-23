#!/usr/bin/env bash
set -euo pipefail

echo "## General / world / politics news (BBC)"
curl -s -L -A "Mozilla/5.0" "https://feeds.bbci.co.uk/news/rss.xml" | python3 -c '
import re, sys, xml.etree.ElementTree as ET
root = ET.fromstring(sys.stdin.read())
for item in root.findall(".//item")[:15]:
    title = item.findtext("title") or ""
    desc = item.findtext("description") or ""
    desc = re.sub(r"<[^>]+>", "", desc)
    desc = re.sub(r"\s+", " ", desc).strip()
    link = item.findtext("link") or ""
    print(f"- {title}: {desc} {link}")
'
