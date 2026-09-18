#!/usr/bin/env bash
# monitor_faers_mobi.sh — probe faers.mobi and file a handshake PR when it breaks.
#
# Runs from cron on the workstation (see install note at the bottom). Every check
# is a live request the handshake tickets #31–#82 promised would keep working
# (incl. bot-home / static-brief freshness stamps from the 2026-09-18 rebuild).
# A failure is not "HTTP != 200"; it is status, content-type, or a body marker
# that the ticket's Verify section named.
#
# On failure  : open ONE handshake PR per episode (branch handshake/monitor-alert-<ts>)
#               with the failing checks, so the faers-mobi implementer (Linux watcher)
#               picks it up like any other slice. Later runs in the same episode add a
#               comment only when the set of failing checks changes.
# On recovery : comment "recovered" on that PR so the owner seat can merge it.
#
# State lives in $GPS_MONITOR_DIR (default ~/.claude/gps-monitor): a shallow clone
# used only for the alert branch, the current episode's PR number, the last failing
# set, and a log. Nothing here touches the project working tree.
#
# Usage:
#   scripts/monitor_faers_mobi.sh            # probe + file/comment as needed
#   scripts/monitor_faers_mobi.sh --dry-run  # probe, print report, no GitHub writes
#   scripts/monitor_faers_mobi.sh --status   # last run, last result, open episode

set -u
# Cron gives a bare PATH, so these must be present. PREPEND rather than replace:
# replacing it silently overrode the stubbed gh/git in monitor_failpath_test.sh,
# which then filed a real PR (#87, 2026-09-17) against a healthy production site.
export PATH="$HOME/.local/bin:$HOME/.nix-profile/bin:/nix/var/nix/profiles/default/bin:/usr/local/bin:/usr/bin:/bin${PATH:+:$PATH}"

BASE="${GPS_MONITOR_BASE:-https://faers.mobi}"
# Overridable so monitor_failpath_test.sh can substitute recording stubs. PATH
# alone cannot do that: this script prepends its own dirs, which shadowed the
# stubs and filed a real PR (#87, 2026-09-17) while pointed at a fake site.
GH="${GPS_MONITOR_GH:-gh}"
GIT="${GPS_MONITOR_GIT:-git}"
REPO="harlananelson/globalpatientsafety"
STATE="${GPS_MONITOR_DIR:-$HOME/.claude/gps-monitor}"
LOG="$STATE/monitor.log"
CLONE="$STATE/repo"
EPISODE_FILE="$STATE/episode-pr"
FAILSET_FILE="$STATE/last-failset"
LASTRUN_FILE="$STATE/last-run"
LASTRESULT_FILE="$STATE/last-result"
DRY=0; STATUS=0
for a in "$@"; do case "$a" in --dry-run) DRY=1;; --status) STATUS=1;; esac; done
mkdir -p "$STATE"

if [ "$STATUS" = 1 ]; then
  echo "last run   : $(cat "$LASTRUN_FILE" 2>/dev/null || echo never)"
  echo "last result: $(cat "$LASTRESULT_FILE" 2>/dev/null || echo none)"
  echo "episode PR : $(cat "$EPISODE_FILE" 2>/dev/null || echo none)"
  [ -f "$LASTRUN_FILE" ] && echo "age        : $(( ( $(date +%s) - $(date -d "$(cat "$LASTRUN_FILE")" +%s) ) / 60 )) min"
  exit 0
fi

for t in curl "$GH" "$GIT" jq; do command -v "$t" >/dev/null || { echo "$(date -Is) FATAL: $t not on PATH" | tee -a "$LOG"; exit 3; }; done

# ---------------------------------------------------------------------------
# Checks. Fields: name | method | path | user-agent | expected status |
#                 content-type prefix | body regex (ERE, empty = none)
# Heavy formats (brief/profile/class/series/pdf) sit behind limit_req 1 r/s,
# so requests run serially with a pause; treat that as part of the contract.
# ---------------------------------------------------------------------------
CHECKS=(
  "home-human|GET|/|Mozilla/5.0|200|text/html|alert-secondary && meta name=\"description\" && format=brief"
  "home-bot-chatgpt|GET|/|ChatGPT-User|200|text/|format=brief"
  "home-bot-perplexity|GET|/|PerplexityBot|200|text/|format=brief"
  "home-bot-claude|GET|/|ClaudeBot|200|text/|format=brief"
  "bot-home-md|GET|/bot-home.md|curl|200|text/|format=brief"
  "bot-home-fresh|GET|/bot-home.md|curl|200|text/|\(cached 20[0-9]{2}-"
  "static-brief-fresh|GET|/examples/tzield-nausea-brief.txt|curl|200|text/|Built 20[0-9]{2}-"
  "api-html|GET|/api|curl|200|text/html|How to query"
  "api-html-slash|GET|/api/|curl|200|text/html|How to query"
  "api-md|GET|/api.md|curl|200|text/plain|GET /signals"
  "API-md-upper|GET|/API.md|curl|200|text/plain|GET /signals"
  "llms-txt|GET|/llms.txt|curl|200|text/plain|format=brief"
  "openapi|GET|/openapi.json|curl|200|application/json|\"/signals\""
  "chatgpt-md|GET|/chatgpt.md|curl|200|text/plain|openapi.json"
  "mcp-md|GET|/mcp.md|curl|200|text/plain|server.py"
  "mcp-get|GET|/mcp|curl|200|text/|MCP"
  "mcp-initialize|MCP|/mcp|curl|200|application/json|\"serverInfo\""
  "mcp-server-py|GET|/mcp/server.py|curl|200|text/|def "
  "signals-json|GET|/signals?drug=tzield&event=Nausea|curl|200|application/json|\"n\":[0-9]+.*\"eb05\":[0-9.]+"
  "signals-headers|HEAD|/signals?event=rash&sort=n&limit=5|curl|200|application/json|"
  "signals-series|GET|/signals?drug=tzield&event=Nausea&format=series|curl|200|application/json|\"quarter\" && 20[0-9]{2}Q[1-4] && \"eb05\""
  "signals-profile-drug|GET|/signals?drug=tzield&format=profile|curl|200|application/json|n_pairs"
  "signals-profile-event|GET|/signals?event=Nausea&format=profile|curl|200|application/json|faers_through"
  "signals-class|GET|/signals?drug=tzield&event=Nausea&format=class|curl|200|application/json|class_wide"
  "signals-label|GET|/signals?drug=tzield&event=Nausea&format=label|curl|200|application/json|novel"
  "signals-brief-pair|GET|/signals?drug=tzield&event=Nausea&format=brief|curl|200|text/|RWE brief && sum n=[0-9]+ && Data through 20[0-9]{2}Q[1-4]"
  "signals-brief-event|GET|/signals?event=Nausea&format=brief|curl|200|text/|Data through"
  "signals-pdf|GET|/signals?drug=tzield&event=Nausea&format=pdf|curl|200|application/pdf|"
  "signals-row-flags|GET|/signals?drug=tzield&limit=1|curl|200|application/json|\"indication\":(true|false).*\"low_info\":(true|false)"
  "signals-class-flags|GET|/signals?drug=tzield&event=Nausea&format=class|curl|200|application/json|\"low_info\":(true|false)"
  "signals-label-status|GET|/signals?drug=tzield&event=Nausea&format=label|curl|200|application/json|\"label_status\":\"(cached|empty|missing)\""
  "signals-plus-decode|GET|/signals?event=ischaemic+stroke&limit=1|curl|200|application/json|Ischaemic stroke"
  "signals-bad-format-400|GET|/signals?drug=tzield&event=Nausea&format=bogus|curl|400|application/json|\"allowed\":\\[\"json\""
  "formats-contract-match|GET|/openapi.json|curl|200|application/json|"
  "well-known-404|GET|/.well-known/ai-plugin.json|curl|404||"
)

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
FAILS=(); PASSES=0
probe() {
  local name="$1" method="$2" path="$3" ua="$4" want="$5" ct="$6" re="$7"
  local out="$TMP/$name.body" hdr="$TMP/$name.hdr" code ctype
  local -a cmd=(curl -sS --max-time 45 -A "$ua" -o "$out" -D "$hdr" -w '%{http_code}')
  case "$method" in
    HEAD) cmd+=(-I) ;;
    MCP)  cmd+=(-X POST -H 'Content-Type: application/json' -H 'Accept: application/json, text/event-stream'
                -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26","capabilities":{},"clientInfo":{"name":"gps-monitor","version":"0"}}}') ;;
  esac
  code="$("${cmd[@]}" "$BASE$path" 2>"$TMP/$name.err")" || code="000"
  ctype="$(grep -i '^content-type:' "$hdr" 2>/dev/null | tail -1 | cut -d' ' -f2- | tr -d '\r')"
  local why=""
  [ "$code" = "$want" ] || why="status $code (want $want)"
  [ -z "$why" ] && [ -n "$ct" ] && [[ "$ctype" != "$ct"* ]] && why="content-type '$ctype' (want $ct*)"
  if [ -z "$why" ] && [ -n "$re" ] && [ "$method" != HEAD ]; then
    # " && " separates regexes that must ALL match. Without this, a regex
    # containing "|" reads as alternation and the check passes when only one
    # half holds -- three checks were silently that weak until 2026-09-18.
    local part rest="$re"
    while [ -n "$rest" ]; do
      case "$rest" in
        *" && "*) part="${rest%%" && "*}"; rest="${rest#*" && "}" ;;
        *) part="$rest"; rest="" ;;
      esac
      grep -q -E "$part" "$out" || { why="body missing /$part/ ($(wc -c <"$out")B)"; break; }
    done
  fi
  if [ -z "$why" ] && [ "$name" = signals-headers ]; then
    grep -qi '^x-total-count:' "$hdr" || why="no X-Total-Count header"
    grep -qi '^x-faers-through:' "$hdr" || why="no X-FAERS-Through header"
  fi
  if [ -z "$why" ] && [ "$name" = formats-contract-match ]; then
    # The production divergence this exists for: the validator and the published
    # schema disagreeing on the live box, however that arose. Compares the two
    # SERVED surfaces, not two files in a repo.
    curl -sS --max-time 45 -o "$TMP/$name.err400" "$BASE/signals?drug=tzield&event=Nausea&format=__monitor_probe__" 2>/dev/null
    why="$(python3 - "$out" "$TMP/$name.err400" <<'PYEOF'
import json,sys
try:
    d=json.load(open(sys.argv[1]))
    ps=d["paths"]["/signals"]["get"]["parameters"]
    ps=[d["components"]["parameters"][p["$ref"].split("/")[-1]] if "$ref" in p else p for p in ps]
    enum=[p for p in ps if p.get("name")=="format"][0]["schema"].get("enum")
    allowed=json.load(open(sys.argv[2])).get("allowed")
    if not enum: print("openapi format enum missing")
    elif not allowed: print("400 body has no allowed list")
    elif sorted(enum)!=sorted(allowed):
        print("contract drift: openapi %s vs validator %s" % (sorted(enum), sorted(allowed)))
except Exception as e:
    print("contract check failed: %s" % e)
PYEOF
)"
  fi
  if [ -z "$why" ] && [ "$name" = signals-json ]; then
    grep -q '"n":0[,}]' "$out" && why="tzield x Nausea n=0"
  fi
  # Silence-looks-like-health: nightly build_bot_home.sh (03:17 UTC) regenerates
  # /bot-home.md and /examples/tzield-nausea-brief.txt. Both keep returning 200
  # with plausible content if cron dies — only the freshness stamps catch it.
  # 48h tolerates one missed run. GPS #82 Linux ask 2026-09-18.
  if [ -z "$why" ] && [ "$name" = bot-home-fresh ]; then
    why="$(python3 - "$out" <<'PYEOF'
import re, sys, datetime
text = open(sys.argv[1], encoding="utf-8", errors="replace").read()
m = re.search(r"\(cached (20\d{2}-\d{2}-\d{2})\)", text)
if not m:
    print("no (cached YYYY-MM-DD) stamp")
    raise SystemExit
day = datetime.datetime.strptime(m.group(1), "%Y-%m-%d").replace(tzinfo=datetime.timezone.utc)
age_h = (datetime.datetime.now(datetime.timezone.utc) - day).total_seconds() / 3600.0
if age_h > 48:
    print("cached stamp %.1fh old (want <=48h); nightly rebuild likely stopped; site 200 is not health" % age_h)
PYEOF
)"
  fi
  if [ -z "$why" ] && [ "$name" = static-brief-fresh ]; then
    why="$(python3 - "$out" <<'PYEOF'
import re, sys, datetime
text = open(sys.argv[1], encoding="utf-8", errors="replace").read()
m = re.search(r"Built (20\d{2}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z)", text)
if not m:
    print("no Built ISO timestamp")
    raise SystemExit
built = datetime.datetime.strptime(m.group(1), "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=datetime.timezone.utc)
age_h = (datetime.datetime.now(datetime.timezone.utc) - built).total_seconds() / 3600.0
if age_h > 48:
    print("Built stamp %.1fh old (want <=48h); nightly rebuild likely stopped; site 200 is not health" % age_h)
PYEOF
)"
  fi
  if [ -n "$why" ]; then echo "$why"; else echo OK; fi
}

for spec in "${CHECKS[@]}"; do
  IFS='|' read -r name method path ua want ct re <<<"$spec"
  r="$(probe "$name" "$method" "$path" "$ua" "$want" "$ct" "$re")"
  if [ "$r" != OK ]; then
    sleep "${GPS_MONITOR_RETRY_SLEEP:-20}"   # one retry: a blip during a Shiny recycle is not an incident
    r="$(probe "$name" "$method" "$path" "$ua" "$want" "$ct" "$re")"
  fi
  if [ "$r" = OK ]; then PASSES=$((PASSES+1)); else FAILS+=("$name|$method $path|$r"); fi
  sleep "${GPS_MONITOR_PACE:-1.2}"  # heavy worker limit_req is 1 r/s burst 3
done

NOW="$(date -Is)"; echo "$NOW" >"$LASTRUN_FILE"
TOTAL=${#CHECKS[@]}; NFAIL=${#FAILS[@]}
FAILSET="$(printf '%s\n' "${FAILS[@]}" | cut -d'|' -f1 | sort | tr '\n' ' ')"
echo "$NOW pass=$PASSES fail=$NFAIL ${FAILSET}" | tee -a "$LOG"
[ "$NFAIL" = 0 ] && echo "OK $PASSES/$TOTAL" >"$LASTRESULT_FILE" || echo "FAIL $NFAIL/$TOTAL: $FAILSET" >"$LASTRESULT_FILE"

report() {
  echo "| check | request | result |"; echo "|---|---|---|"
  for f in "${FAILS[@]}"; do IFS='|' read -r n q w <<<"$f"; echo "| \`$n\` | \`$q\` | $w |"; done
}
[ "$DRY" = 1 ] && { echo "--- dry run: $PASSES/$TOTAL pass"; [ "$NFAIL" -gt 0 ] && report; exit $(( NFAIL > 0 )); }

# Belt and braces after #87: filing against the real repo while pointed at a
# fake site is never intended, whatever PATH happens to hold.
if [ "$BASE" != "https://faers.mobi" ] && [ -z "${GPS_MONITOR_ALLOW_WRITES:-}" ]; then
  echo "$NOW refusing GitHub writes: BASE=$BASE is not production" | tee -a "$LOG"
  exit $(( NFAIL > 0 ))
fi

EPISODE="$(cat "$EPISODE_FILE" 2>/dev/null || true)"
if [ -n "$EPISODE" ]; then
  st="$("$GH" pr view "$EPISODE" --repo "$REPO" --json state -q .state 2>/dev/null || echo UNKNOWN)"
  [ "$st" = OPEN ] || { rm -f "$EPISODE_FILE" "$FAILSET_FILE"; EPISODE=""; }
fi

# ---- recovery -------------------------------------------------------------
if [ "$NFAIL" = 0 ]; then
  if [ -n "$EPISODE" ]; then
    "$GH" pr comment "$EPISODE" --repo "$REPO" --body "$(printf '<!-- role:monitor -->\nRecovered %s: all %d/%d checks pass. Owner seat: merge or close this PR.' "$NOW" "$PASSES" "$TOTAL")" >/dev/null \
      && echo "$NOW commented recovery on #$EPISODE" | tee -a "$LOG"
    rm -f "$EPISODE_FILE" "$FAILSET_FILE"
  fi
  exit 0
fi

# ---- failure: comment on the open episode if the failing set changed --------
if [ -n "$EPISODE" ]; then
  if [ "$FAILSET" != "$(cat "$FAILSET_FILE" 2>/dev/null)" ]; then
    "$GH" pr comment "$EPISODE" --repo "$REPO" --body "$(printf '<!-- role:monitor -->\nStill failing %s, set changed (%d/%d pass):\n\n%s' "$NOW" "$PASSES" "$TOTAL" "$(report)")" >/dev/null \
      && echo "$NOW commented change on #$EPISODE" | tee -a "$LOG"
    echo "$FAILSET" >"$FAILSET_FILE"
  fi
  exit 1
fi

# ---- failure: open a new episode PR ----------------------------------------
TS="$(date +%Y%m%d-%H%M)"; BR="handshake/monitor-alert-$TS"; FILE="issues/monitor-alert-$TS.md"
if [ ! -d "$CLONE/.git" ]; then
  "$GIT" clone -q --depth 1 "https://github.com/$REPO.git" "$CLONE" || { echo "$NOW FATAL clone" | tee -a "$LOG"; exit 3; }
fi
(
  cd "$CLONE" || exit 3
  "$GIT" fetch -q --depth 1 origin main && "$GIT" checkout -q -B "$BR" origin/main || exit 3
  {
    echo "# Monitor alert $TS: faers.mobi check failures"
    echo
    echo "Handshake. Filed automatically by \`scripts/monitor_faers_mobi.sh\` (globalpatientsafety, cron on the workstation)."
    echo "Implement the fix in \`/projects/faers-mobi/\`, recycle the layer that owns it, and post live body numbers here."
    echo "Do not merge; the owner seat merges after the monitor comments \"Recovered\"."
    echo
    echo "## Failing checks ($NFAIL of $TOTAL) at $NOW"
    echo
    report
    echo
    echo "## Passing"
    echo
    echo "$PASSES checks passed on the same run, each retried once after 20 s before being counted."
    echo
    echo "## Which layer (from the implementer handoff)"
    echo
    echo "| Symptom | Layer | Recycle |"
    echo "|---|---|---|"
    echo "| \`/signals\` JSON hangs or 0 bytes | cheap JSON \`:3841\` | \`systemctl restart faers-signals-api\` |"
    echo "| brief / pdf / profile / class / series hang | heavy \`:3843\` | \`systemctl restart faers-signals-heavy\` |"
    echo "| static \`/api\`, \`/api.md\`, \`/llms.txt\`, \`/openapi.json\`, bot homepage, \`/mcp\` | nginx | \`nginx -t && systemctl reload nginx\` |"
    echo "| homepage HTML / banner / head | Shiny UI | \`restart.txt\`; kill only the SockJS whose cwd is the faers-mobi dir |"
    echo "| \`bot-home-fresh\` / \`static-brief-fresh\` stamp >48h | VPS cron \`scripts/build_bot_home.sh\` (03:17 UTC) | restore cron; site 200 with plausible content is not health |"
    echo
    echo "## If bot-home / static-brief freshness failed"
    echo
    echo "The site is probably fine and serving 200; the nightly rebuild is what has stopped, so the bot homepage and static brief are going stale."
    echo
    echo "## Keep"
    echo
    echo "- No new \`/signals\` params, no pay gate, no \`/api/v1/\`"
    echo "- Fix the cause, not the check: if a check is wrong, say so here and the owner seat edits the monitor"
  } >"$FILE"
  "$GIT" add "$FILE" && "$GIT" -c user.name="gps-monitor" -c user.email="4999279+harlananelson@users.noreply.github.com" commit -q -m "Monitor alert $TS: $NFAIL faers.mobi check(s) failing" \
    && "$GIT" push -q -u origin "$BR"
) || { echo "$NOW FATAL branch/push" | tee -a "$LOG"; exit 3; }

PRURL="$("$GH" pr create --repo "$REPO" --head "$BR" --base main \
  --title "Monitor alert $TS: $NFAIL faers.mobi check(s) failing" \
  --body "$(printf 'Handshake, filed by the site monitor. Do not merge until it comments Recovered.\n\nFailing (%d/%d):\n\n%s\n\nSpec: `%s`' "$NFAIL" "$TOTAL" "$(report)" "$FILE")" 2>&1 | tail -1)"
PRNUM="${PRURL##*/}"
if [[ "$PRNUM" =~ ^[0-9]+$ ]]; then
  echo "$PRNUM" >"$EPISODE_FILE"; echo "$FAILSET" >"$FAILSET_FILE"
  echo "$NOW opened #$PRNUM $PRURL" | tee -a "$LOG"
else
  echo "$NOW FATAL pr create: $PRURL" | tee -a "$LOG"; exit 3
fi
exit 1

# Install (once), every 30 min, never stacked:
#   */30 * * * * flock -n $HOME/.claude/gps-monitor/lock $HOME/projects/globalpatientsafety/scripts/monitor_faers_mobi.sh >> $HOME/.claude/gps-monitor/cron.log 2>&1
