#!/usr/bin/env bash
set -euo pipefail

HERMES_SRC="$HOME/.hermes/hermes-agent"

# --- Estimated cost, last 24h (best-effort; local DB query, no network) ---
COST_USD=$(cd "$HERMES_SRC" && ./venv/bin/python -c "
from hermes_state import SessionDB
from agent.insights import InsightsEngine
db = SessionDB()
engine = InsightsEngine(db)
report = engine.generate(days=1)
print(f\"{report['overview'].get('estimated_cost', 0.0):.4f}\")
db.close()
" 2>/dev/null || echo "")

if [ -z "$COST_USD" ]; then
  COST_LINE="Est. cost (24h): unavailable"
else
  FX_RATE=$(curl -s --max-time 5 "https://api.frankfurter.dev/v1/latest?base=USD&symbols=AUD" 2>/dev/null | jq -r '.rates.AUD // empty' 2>/dev/null || echo "")
  if [ -n "$FX_RATE" ]; then
    COST_AUD=$(awk -v u="$COST_USD" -v r="$FX_RATE" 'BEGIN { printf "%.4f", u * r }')
    COST_LINE="Est. cost (24h): \$${COST_USD} USD (~\$${COST_AUD} AUD)"
  else
    COST_LINE="Est. cost (24h): \$${COST_USD} USD (AUD conversion unavailable)"
  fi
fi

# --- Gateway status ---
if hermes gateway status 2>&1 | grep -q "supervised by launchd"; then
  GW_ICON="OK"
else
  GW_ICON="DOWN"
fi

# --- Cron job health ---
CRON_OUTPUT=$(hermes cron list 2>&1)
TOTAL_JOBS=$(echo "$CRON_OUTPUT" | grep -cE '^  [0-9a-f]{12} ' || true)
FAILED_JOBS=$(echo "$CRON_OUTPUT" | grep -c "Execution: failed" || true)
FAILED_NAMES=$(echo "$CRON_OUTPUT" | awk '
  /Name:/ { name=$2 }
  /Execution: failed/ { print name }
')

# --- Errors logged today (local log, not a network call) ---
TODAY=$(date +%Y-%m-%d)
ERROR_COUNT=$(grep -c "^${TODAY}.*ERROR" "$HOME/.hermes/logs/agent.log" 2>/dev/null || echo 0)

# --- Build report ---
REPORT="Hermes Daily Health Check — ${TODAY}

Gateway: ${GW_ICON}
Cron jobs: $((TOTAL_JOBS - FAILED_JOBS))/${TOTAL_JOBS} healthy"
if [ "$FAILED_JOBS" -gt 0 ]; then
  REPORT="${REPORT}
  Failed: ${FAILED_NAMES}"
fi
REPORT="${REPORT}
Errors logged today: ${ERROR_COUNT}
${COST_LINE}"

# --- Write to vault ---
VAULT_DIR="PATH"
mkdir -p "$VAULT_DIR"
cat >"${VAULT_DIR}/${TODAY}.md" <<EOF
---
date: ${TODAY}
job: hermes-health
tags: [Hermes, health]
---

${REPORT}
EOF

echo "$REPORT"
