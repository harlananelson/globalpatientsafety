#!/usr/bin/env bash
# monitor_heartbeat.sh — notice when the MONITOR stops running.
#
# The gap this closes: monitor_faers_mobi.sh appends to a log nobody reads. If
# its cron entry is removed, or it exits 3 on every run (a missing binary, a
# broken clone), the result is silence — and silence is exactly what a healthy
# site looks like. The watchdog had no watchdog.
#
# This reads the monitor's own last-run stamp and files a handshake PR when it is
# stale. One PR per outage, closed by the monitor's next healthy run clearing the
# stamp forward; a second stale run comments rather than filing again.
#
# RESIDUAL RISK, stated rather than papered over: this runs from the same cron on
# the same workstation. If the machine is off or crond is dead, this is dead too
# and reports nothing. Only an off-box check can cover that, and there is none.
# What this does cover is the likelier failure: the monitor itself broken or
# unscheduled while the box runs fine.
#
# Usage:
#   bash scripts/monitor_heartbeat.sh            # check, file/comment if stale
#   bash scripts/monitor_heartbeat.sh --dry-run  # report only
set -u
STATE="${GPS_MONITOR_DIR:-$HOME/.claude/gps-monitor}"
STALE_MIN="${GPS_HEARTBEAT_STALE_MIN:-75}"     # cron is */30, so 75 allows one miss
REPO="harlananelson/globalpatientsafety"
GH="${GPS_MONITOR_GH:-gh}"
FLAG="$STATE/heartbeat-pr"
DRY=0; [ "${1:-}" = "--dry-run" ] && DRY=1

last="$(cat "$STATE/last-run" 2>/dev/null || true)"
now=$(date +%s)
if [ -z "$last" ]; then
  age_min=99999; detail="no last-run stamp at all ($STATE/last-run missing)"
else
  age_min=$(( (now - $(date -d "$last" +%s 2>/dev/null || echo 0)) / 60 ))
  detail="last run $last, ${age_min} min ago"
fi

if [ "$age_min" -le "$STALE_MIN" ]; then
  echo "monitor heartbeat OK: $detail"
  [ -f "$FLAG" ] && { echo "clearing stale-flag from a previous outage"; rm -f "$FLAG"; }
  exit 0
fi

echo "monitor heartbeat STALE: $detail (threshold ${STALE_MIN} min)"
tail_log="$(tail -3 "$STATE/monitor.log" 2>/dev/null || echo '(no monitor.log)')"
cron_present=$(crontab -l 2>/dev/null | grep -c monitor_faers_mobi || true)
body="$(printf 'The faers.mobi monitor has not run.\n\n- %s (threshold %s min)\n- cron entries referencing monitor_faers_mobi.sh: %s\n\nLast lines of its log:\n\n```\n%s\n```\n\n**The site itself may be fine — this says the CHECKER is not running, which is indistinguishable from health in the logs.** Check the cron entry, then run `bash scripts/monitor_faers_mobi.sh --dry-run` by hand and read the error.\n\nFiled by `scripts/monitor_heartbeat.sh`.' "$detail" "$STALE_MIN" "$cron_present" "$tail_log")"

[ "$DRY" = 1 ] && { echo "--- would file:"; echo "$body"; exit 1; }

existing="$(cat "$FLAG" 2>/dev/null || true)"
if [ -n "$existing" ] && [ "$("$GH" pr view "$existing" --repo "$REPO" --json state -q .state 2>/dev/null)" = OPEN ]; then
  "$GH" pr comment "$existing" --repo "$REPO" --body "$(printf '<!-- role:monitor -->\nStill stale: %s' "$detail")" >/dev/null \
    && echo "commented on #$existing"
  exit 1
fi

url="$("$GH" pr create --repo "$REPO" --head main --base main \
  --title "Monitor heartbeat: faers.mobi checker has not run" --body "$body" 2>&1 | tail -1)"
num="${url##*/}"
if [[ "$num" =~ ^[0-9]+$ ]]; then echo "$num" > "$FLAG"; echo "filed #$num"; else echo "FAILED to file: $url"; fi
exit 1
