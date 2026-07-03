# Weekly telemetry review — globalpatientsafety.com suite

You are reviewing one week of server telemetry for the pharmacovigilance site
suite: globalpatientsafety.com (Rhino/Shiny portal + static articles),
faers.mobi (FAERS signal browser), aers.mobi (historical AERS), and
picodag.globalpatientsafety.com.

## Inputs

- The newest `logs/telemetry/summary-YYYY-MM-DD.txt` file (pre-aggregated
  nginx + shiny-server stats). Raw logs are in `logs/telemetry/raw/<date>/`
  if you need to drill into something specific.
- The previous week's report in `logs/telemetry/report-*.md` (if any) — use
  it to note trends, and do not re-recommend items already recommended there
  unless the evidence changed.

## What to produce

Write a markdown report to the output path you were given, with sections:

1. **Traffic overview** — volume, trend vs prior report, notable days.
2. **What users are doing** — most-visited pages/apps/articles; which portal
   tools get used; anything surprising.
3. **Friction signals** — 404s worth fixing, error/warning patterns in
   shiny-server logs, apps that error or restart, referrers that suggest a
   broken inbound link.
4. **Recommendations** — at most 5, ranked, each with the specific evidence
   line(s) from the summary that motivates it, and the concrete change
   (file/app/config) it implies. Skip generic advice; every item must trace
   to something in this week's data.

## Rules

- Report only; do NOT modify site code, deploy anything, or open issues.
- Ignore obvious bot/scanner noise (wp-login.php probes, .env scans, etc.)
  except to note the volume once.
- If the summary shows no meaningful human traffic, say so plainly — a short
  honest report beats an inflated one.
