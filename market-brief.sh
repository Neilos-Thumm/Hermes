#!/usr/bin/env bash
set -euo pipefail

echo "## Index snapshot"
for SYM_LABEL in "^GSPC:S&P 500" "^IXIC:Nasdaq Composite" "^DJI:Dow Jones" "^AXJO:ASX 200"; do
  SYM="${SYM_LABEL%%:*}"
  LABEL="${SYM_LABEL##*:}"
  ENC=$(python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1]))" "$SYM")
  curl -s -A "Mozilla/5.0" "https://query1.finance.yahoo.com/v8/finance/chart/${ENC}?interval=1d&range=5d" \
  | jq -r --arg label "$LABEL" '
      .chart.result[0].meta as $m
      | ($m.regularMarketPrice - $m.chartPreviousClose) as $chg
      | ($chg / $m.chartPreviousClose * 100) as $pct
      | "- \($label): \($m.regularMarketPrice) (\(if $chg >= 0 then "+" else "" end)\(($chg*100|round)/100)  \(if $pct >= 0 then "+" else "" end)\(($pct*100|round)/100)%)"
    '
done

echo
echo "## Market news"
curl -s -L -A "Mozilla/5.0" "http://feeds.marketwatch.com/marketwatch/topstories/" | python3 -c '
import sys, xml.etree.ElementTree as ET
root = ET.fromstring(sys.stdin.read())
for item in root.findall(".//item")[:8]:
    title = item.findtext("title") or ""
    link = item.findtext("link") or ""
    print(f"- {title} {link}")
'
