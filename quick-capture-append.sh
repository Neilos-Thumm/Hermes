#!/usr/bin/env bash
set -euo pipefail

MSG=$(cat)
if [ -z "$MSG" ]; then
  echo "ERROR: empty message" >&2
  exit 1
fi

DATE_STR=$(date +"%B|%-d|%Y")
IFS='|' read -r MONTH DAY YEAR <<< "$DATE_STR"

case "$DAY" in
  11|12|13) SUFFIX="th" ;;
  *1) SUFFIX="st" ;;
  *2) SUFFIX="nd" ;;
  *3) SUFFIX="rd" ;;
  *) SUFFIX="th" ;;
esac

FILE_DATE="${MONTH} ${DAY}${SUFFIX} ${YEAR}"
VAULT_DIR="$HOME/Documents/ai/Obsidian_Claude/Journal/Daily
TARGET="${VAULT_DIR}/${FILE_DATE}.md"

if [ ! -f "$TARGET" ]; then
  mkdir -p "$VAULT_DIR"
  printf '#### Scratch\n\n### To-do\n- [ ] %s\n##### Journal\n-\n\n###### Tomorrow'"'"'s Plan\n-\n' "$MSG" > "$TARGET"
  echo "Added to ${FILE_DATE}'s to-do (new file)."
  exit 0
fi

# Primary: insert directly below the LAST checkbox-format line ("- [ ] " or "- [x] "),
# regardless of section headings. Fallback 1: before the first "##### Journal" heading
# (covers a file with no checkbox lines yet, e.g. a hand-made file). Fallback 2: end of file.
awk -v msg="$MSG" '
  {
    lines[++n] = $0
    if ($0 ~ /^- \[.\] /) last_cb = n
    if ($0 ~ /^##### Journal/ && journal_line == 0) journal_line = n
  }
  END {
    insert_after = last_cb
    if (!insert_after && journal_line) insert_after = journal_line - 1
    if (!insert_after) insert_after = n
    for (i = 1; i <= n; i++) {
      print lines[i]
      if (i == insert_after) print "- [ ] " msg
    }
    if (n == 0) print "- [ ] " msg
  }
' "$TARGET" > "${TARGET}.tmp" && mv "${TARGET}.tmp" "$TARGET"

echo "Added to ${FILE_DATE}'s to-do."
