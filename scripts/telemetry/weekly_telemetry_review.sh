#!/usr/bin/env bash
# Weekly telemetry loop: pull VPS logs, then have a headless Claude analyze
# them and write logs/telemetry/report-YYYY-MM-DD.md. Installed in crontab
# (Mondays); safe to run by hand any time.
set -euo pipefail
export PATH="$HOME/.local/bin:/usr/local/bin:/usr/bin:/bin"

BASE_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
STAMP="$(date +%Y-%m-%d)"
REPORT="$BASE_DIR/logs/telemetry/report-$STAMP.md"
RUN_LOG="$BASE_DIR/logs/telemetry/cron-$STAMP.log"

mkdir -p "$BASE_DIR/logs/telemetry"
exec >>"$RUN_LOG" 2>&1
echo "=== telemetry review run $(date -Is) ==="

SUMMARY="$("$BASE_DIR/scripts/telemetry/pull_vps_logs.sh")"
echo "summary: $SUMMARY"

PROMPT_FILE="$(mktemp)"
trap 'rm -f "$PROMPT_FILE"' EXIT
{
  cat "$BASE_DIR/prompts/telemetry_review_prompt.md"
  echo
  echo "This week's summary file: $SUMMARY"
  echo "Write the report to: $REPORT"
} > "$PROMPT_FILE"

"$HOME/projects/grok/call-claude.sh" \
  --thorough \
  --cwd "$BASE_DIR/logs/telemetry" \
  --prompt-file "$PROMPT_FILE" \
  --out "$REPORT.stdout"

if [ -s "$REPORT" ]; then
  echo "report written: $REPORT"
else
  # Model answered on stdout instead of writing the file — keep that as the report.
  mv "$REPORT.stdout" "$REPORT"
  echo "report captured from stdout: $REPORT"
fi
