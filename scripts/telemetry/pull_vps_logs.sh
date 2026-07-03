#!/usr/bin/env bash
# Pull nginx + shiny-server logs from the Hetzner VPS and pre-aggregate them
# for the weekly telemetry review (see weekly_telemetry_review.sh).
#
# Raw logs contain visitor IPs — they stay local and are gitignored
# (logs/telemetry/). Only the LLM-written report is reviewable/commitable.
set -euo pipefail

VPS="root@5.78.69.136"
BASE_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
STAMP="$(date +%Y-%m-%d)"
RAW_DIR="$BASE_DIR/logs/telemetry/raw/$STAMP"
SUMMARY="$BASE_DIR/logs/telemetry/summary-$STAMP.txt"

mkdir -p "$RAW_DIR"

# Grab everything nginx + shiny-server have (rotated files included; ~2 weeks).
ssh -o BatchMode=yes "$VPS" \
  "tar czf - --ignore-failed-read /var/log/nginx /var/log/shiny-server 2>/dev/null" \
  | tar xzf - -C "$RAW_DIR" --strip-components=2
gunzip -f "$RAW_DIR"/nginx/*.gz 2>/dev/null || true

# ---- Aggregate nginx access logs (combined format) ----------------------
ACCESS_FILES=$(ls "$RAW_DIR"/nginx/*access*log* 2>/dev/null || true)
{
  echo "# VPS telemetry summary — pulled $STAMP"
  echo "# Raw files: $(ls "$RAW_DIR"/nginx 2>/dev/null | tr '\n' ' ')"
  echo

  if [ -n "$ACCESS_FILES" ]; then
    echo "## Requests per day"
    awk -F'[][]' '{split($2,a,":"); print a[1]}' $ACCESS_FILES | sort | uniq -c | sort -k2 | tail -14
    echo

    echo "## Top 50 request paths (excluding static assets)"
    awk '{print $7}' $ACCESS_FILES \
      | grep -vE '\.(css|js|png|jpg|jpeg|gif|svg|ico|woff2?|ttf|map)(\?|$)' \
      | sort | uniq -c | sort -rn | head -50
    echo

    echo "## Top 30 404 paths"
    awk '$9 == 404 {print $7}' $ACCESS_FILES | sort | uniq -c | sort -rn | head -30
    echo

    echo "## Status code distribution"
    awk '{print $9}' $ACCESS_FILES | sort | uniq -c | sort -rn
    echo

    echo "## Top 30 external referrers"
    awk -F'"' '{print $4}' $ACCESS_FILES \
      | grep -viE '^-$|globalpatientsafety|faers\.mobi|aers\.mobi' \
      | sort | uniq -c | sort -rn | head -30
    echo

    echo "## Top 20 user agents"
    awk -F'"' '{print $6}' $ACCESS_FILES | sort | uniq -c | sort -rn | head -20
    echo

    echo "## Unique client IPs per day (rough traffic volume; IPs not listed)"
    awk -F'[][]' '{split($2,a,":"); day=a[1]} {split($0,b," "); print day, b[1]}' $ACCESS_FILES \
      | sort -u | awk '{print $1}' | sort | uniq -c | sort -k2 | tail -14
  else
    echo "!! No nginx access logs found — check log paths on the VPS."
  fi

  echo
  echo "## Recent shiny-server app errors (last 200 lines across app logs)"
  grep -ihE "error|warning" "$RAW_DIR"/shiny-server/*.log 2>/dev/null | tail -200 || echo "(none found)"
} > "$SUMMARY"

echo "$SUMMARY"
