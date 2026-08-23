#!/usr/bin/env bash
set -euo pipefail

echo "## Bangkok Post (Thailand section)"
curl -s -L -A "Mozilla/5.0" "https://www.bangkokpost.com/rss/data/thailand.xml" | python3 -c '
import re, sys, xml.etree.ElementTree as ET
root = ET.fromstring(sys.stdin.read())
for item in root.findall(".//item")[:15]:
    title = item.findtext("title") or ""
    desc = item.findtext("description") or ""
    desc = re.sub(r"<[^>]+>", "", desc).strip()
    link = item.findtext("link") or ""
    print(f"- {title}: {desc} {link}")
'

echo
echo "## Khaosod English"
curl -s -L -A "Mozilla/5.0" "https://www.khaosodenglish.com/feed/" | python3 -c '
import html, re, sys, xml.etree.ElementTree as ET
root = ET.fromstring(sys.stdin.read())
for item in root.findall(".//item")[:15]:
    title = item.findtext("title") or ""
    desc = item.findtext("description") or ""
    desc = re.sub(r"<[^>]+>", "", desc)
    desc = html.unescape(desc)
    desc = re.sub(r"The post .* appeared first on Khaosod English\.", "", desc)
    desc = re.sub(r"\s+", " ", desc).strip()
    link = item.findtext("link") or ""
    print(f"- {title}: {desc} {link}")
'
