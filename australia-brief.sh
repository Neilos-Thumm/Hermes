#!/usr/bin/env bash
set -euo pipefail

echo "## ABC News (Around Australia)"
curl -s -L -A "Mozilla/5.0" "https://www.abc.net.au/news/feed/104333858/rss.xml" | python3 -c '
import re, sys, xml.etree.ElementTree as ET
root = ET.fromstring(sys.stdin.read())
for item in root.findall(".//item")[:15]:
    title = item.findtext("title") or ""
    desc = item.findtext("description") or ""
    desc = re.sub(r"<[^>]+>", "", desc)
    desc = re.sub(r"\s+", " ", desc).strip()
    print(f"- {title}: {desc}")
'

echo
echo "## Guardian Australia"
curl -s -L -A "Mozilla/5.0" "https://www.theguardian.com/australia-news/rss" | python3 -c '
import re, sys, xml.etree.ElementTree as ET
root = ET.fromstring(sys.stdin.read())
count = 0
for item in root.findall(".//item"):
    if count >= 15:
        break
    title = item.findtext("title") or ""
    link = item.findtext("link") or ""
    # Guardian australia-news RSS mixes hard news with opinion columns,
    # podcasts, and video clips -- roughly half the feed on a normal day.
    # Opinion/franchise pieces reliably end their title "... | <byline>";
    # the dedicated opinion vertical is under /commentisfree/; audio/video
    # items are tagged in the title itself. Skip all three mechanically
    # rather than trusting the summarizer to filter non-news out of a pool
    # that is ~half non-news.
    if " | " in title:
        continue
    if "/commentisfree/" in link:
        continue
    if re.search(r"\b(podcast|video)\s*$", title, re.IGNORECASE):
        continue
    desc = item.findtext("description") or ""
    # description is the full article body wrapped in a promo block, not a
    # short summary -- the genuine one-sentence dek is the first <p> only,
    # everything after it (the "get our breaking news email" list, the rest
    # of the article body, "Continue reading...") is noise or bloat.
    m = re.search(r"<p>(.*?)</p>", desc)
    lead = m.group(1) if m else desc
    lead = re.sub(r"<[^>]+>", "", lead)
    lead = re.sub(r"\s+", " ", lead).strip()
    print(f"- {title}: {lead}")
    count += 1
'
