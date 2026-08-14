#!/usr/bin/env bash
set -euo pipefail

MSG=$(cat)
if [ -z "$MSG" ]; then
  echo "ERROR: empty message" >&2
  exit 1
fi

# Block ID base shared by every line's Daily entry and its Weekly embed
# reference (epoch seconds + PID keeps it unique even if two messages land
# in the same second); each line gets its own "-<index>" suffix below.
BLOCK_ID="t$(date +%s)-$$"

DATE_STR=$(date +"%B|%-d|%Y")
IFS='|' read -r MONTH DAY YEAR <<<"$DATE_STR"

case "$DAY" in
11 | 12 | 13) SUFFIX="th" ;;
*1) SUFFIX="st" ;;
*2) SUFFIX="nd" ;;
*3) SUFFIX="rd" ;;
*) SUFFIX="th" ;;
esac

FILE_DATE="${MONTH} ${DAY}${SUFFIX} ${YEAR}"

# Split the message on real newlines (Shift+Enter in Discord), one task per
# non-blank line. Trailing \r stripped for CRLF safety; whitespace-only
# lines are skipped so a stray blank line doesn't become an empty task.
CLEAN_LINES=()
while IFS= read -r RAW_LINE || [ -n "$RAW_LINE" ]; do
  RAW_LINE="${RAW_LINE%$'\r'}"
  if [[ "$RAW_LINE" =~ ^[[:space:]]*$ ]]; then
    continue
  fi
  CLEAN_LINES+=("$RAW_LINE")
done <<<"$MSG"

if [ "${#CLEAN_LINES[@]}" -eq 0 ]; then
  echo "ERROR: empty message" >&2
  exit 1
fi

LINE_COUNT=${#CLEAN_LINES[@]}
DAILY_LINES=()
CARD_LINES=()
i=0
for LINE in "${CLEAN_LINES[@]}"; do
  i=$((i + 1))
  ID="${BLOCK_ID}-${i}"
  DAILY_LINES+=("- [ ] ${LINE} ^${ID}")
  CARD_LINES+=("- [ ] ![[${FILE_DATE}#^${ID}]]")
done

# macOS/BSD awk's "-v var=value" chokes on a literal newline inside value
# ("newline in string"), so multi-line payloads are joined with the ASCII
# record separator (0x1E) instead of "\n" for the trip through -v, then
# split back apart on that same byte inside awk.
SEP=$'\x1e'
DAILY_BLOCK=""
CARD_BLOCK=""
for idx in "${!DAILY_LINES[@]}"; do
  if [ "$idx" -gt 0 ]; then
    DAILY_BLOCK+="$SEP"
    CARD_BLOCK+="$SEP"
  fi
  DAILY_BLOCK+="${DAILY_LINES[$idx]}"
  CARD_BLOCK+="${CARD_LINES[$idx]}"
done

if [ "$LINE_COUNT" -eq 1 ]; then
  ITEM_WORD="Added"
else
  ITEM_WORD="Added ${LINE_COUNT} items"
fi

VAULT_DIR="yourvault"
TARGET="${VAULT_DIR}/${FILE_DATE}.md"

if [ ! -f "$TARGET" ]; then
  mkdir -p "$VAULT_DIR"
  {
    printf -- '---\ntags:\n  - journal\n---\n#### Scratch\n\n### To-do\n'
    printf '%s\n' "${DAILY_LINES[@]}"
    printf -- '##### Journal\n-\n\n###### Tomorrow'"'"'s Plan\n-\n'
  } >"$TARGET"
  DAILY_RESULT="${ITEM_WORD} to ${FILE_DATE}'s to-do (new file)."
else
  # Primary: insert directly below the LAST checkbox-format line ("- [ ] " or "- [x] "),
  # regardless of section headings. Fallback 1: before the first "##### Journal" heading
  # (covers a file with no checkbox lines yet, e.g. a hand-made file). Fallback 2: end of file.
  awk -v block="$DAILY_BLOCK" -v sep="$SEP" '
    {
      lines[++n] = $0
      if ($0 ~ /^- \[.\] /) last_cb = n
      if ($0 ~ /^##### Journal/ && journal_line == 0) journal_line = n
    }
    END {
      insert_after = last_cb
      if (!insert_after && journal_line) insert_after = journal_line - 1
      if (!insert_after) insert_after = n
      nblk = split(block, blk, sep)
      for (i = 1; i <= n; i++) {
        print lines[i]
        if (i == insert_after) {
          for (k = 1; k <= nblk; k++) print blk[k]
        }
      }
      if (n == 0) {
        for (k = 1; k <= nblk; k++) print blk[k]
      }
    }
  ' "$TARGET" >"${TARGET}.tmp" && mv "${TARGET}.tmp" "$TARGET"

  DAILY_RESULT="${ITEM_WORD} to ${FILE_DATE}'s to-do."
fi

# ---- Weekly kanban board (Journal/Weekly/) ----
# Week label = "W<n> <year>". Weeks start Sunday. The year is decided by that
# week's Thursday (not the message's own calendar date) so every day in the
# same Sunday-Saturday span always resolves to the same file, even across a
# Dec/Jan boundary.
WEEKLY_DIR="yourvault"
TODAY_WEEKDAY=$(date +%A)
DOW_NUM=$(date +%w)
WEEK_SUNDAY=$(date -v-"${DOW_NUM}"d +%Y-%m-%d)
WEEK_THURSDAY=$(date -j -v+4d -f "%Y-%m-%d" "$WEEK_SUNDAY" +%Y-%m-%d)
WEEK_YEAR=$(date -j -f "%Y-%m-%d" "$WEEK_THURSDAY" +%Y)

JAN1="${WEEK_YEAR}-01-01"
JAN1_DOW=$(date -j -f "%Y-%m-%d" "$JAN1" +%w)
JAN1_NOON_EPOCH=$(date -j -f "%Y-%m-%d %H:%M:%S" "${JAN1} 12:00:00" +%s)
WEEK1_START_EPOCH=$((JAN1_NOON_EPOCH - JAN1_DOW * 86400))
WEEK_SUNDAY_NOON_EPOCH=$(date -j -f "%Y-%m-%d %H:%M:%S" "${WEEK_SUNDAY} 12:00:00" +%s)
DIFF_DAYS=$(((WEEK_SUNDAY_NOON_EPOCH - WEEK1_START_EPOCH) / 86400))
WEEK_NUM=$((DIFF_DAYS / 7 + 1))

mkdir -p "$WEEKLY_DIR"
WEEK_FILE="${WEEKLY_DIR}/W${WEEK_NUM} ${WEEK_YEAR}.md"
DAYS=(Sunday Monday Tuesday Wednesday Thursday Friday Saturday)

# Weekly cards are a single checkbox wrapping a block-reference embed of the
# actual Daily line, not a copy of the text. Daily is the only place the task
# is ever toggled; the Weekly board is a live read-through of that same line
# (see BLOCK_ID above) — nothing here needs to stay "in sync" because there's
# only one real checkbox.
if [ ! -f "$WEEK_FILE" ]; then
  {
    printf -- '---\nkanban-plugin: board\n---\n\n'
    for d in "${DAYS[@]}"; do
      printf -- '## %s\n\n' "$d"
      if [ "$d" = "$TODAY_WEEKDAY" ]; then
        printf '%s\n' "${CARD_LINES[@]}"
        printf -- '\n'
      fi
    done
    printf -- '%%%% kanban:settings\n```\n{"kanban-plugin":"board","list-collapse":[false,false,false,false]}\n```\n%%%%\n'
  } >"$WEEK_FILE"
  WEEKLY_RESULT="${ITEM_WORD} to W${WEEK_NUM} ${WEEK_YEAR} (${TODAY_WEEKDAY}, new file)."
else
  # Insert directly below the last "- [ ] " line inside today's day section.
  # Fallback 1: right after the day's own "## <Day>" heading (an empty
  # section, no cards yet). Fallback 2: end of file (heading missing).
  awk -v block="$CARD_BLOCK" -v sep="$SEP" -v target="$TODAY_WEEKDAY" '
    {
      n++
      lines[n] = $0
      if ($0 ~ /^## /) {
        cur = $0
        sub(/^## /, "", cur)
        if (cur == target) heading_line = n
      } else if (cur == target && $0 ~ /^- \[.\] /) {
        last_cb = n
      }
    }
    END {
      insert_after = last_cb
      if (!insert_after) insert_after = heading_line
      if (!insert_after) insert_after = n
      nblk = split(block, blk, sep)
      for (i = 1; i <= n; i++) {
        print lines[i]
        if (i == insert_after) {
          for (k = 1; k <= nblk; k++) print blk[k]
        }
      }
      if (n == 0) {
        for (k = 1; k <= nblk; k++) print blk[k]
      }
    }
  ' "$WEEK_FILE" >"${WEEK_FILE}.tmp" && mv "${WEEK_FILE}.tmp" "$WEEK_FILE"
  WEEKLY_RESULT="${ITEM_WORD} to W${WEEK_NUM} ${WEEK_YEAR} (${TODAY_WEEKDAY})."
fi

echo "$DAILY_RESULT"
echo "$WEEKLY_RESULT"
