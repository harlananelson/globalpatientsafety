#!/usr/bin/env bash
# claims_audit.sh — check what this repo's records CLAIM against what the files DO.
#
# Written 2026-09-18 after commit a4c6e4f logged an orphan-watchdog fix whose edit
# had silently not applied: the claim was written from intent, and nothing checked
# the file. A false decision-log entry is worse than a broken harness — the harness
# fails loudly next run, the log is what a later reader trusts INSTEAD of checking.
#
# Adapted from the faers-mobi seat's tools/dev/claims_audit.sh. Two passes:
#   1. working tree  — does each claimed behaviour exist in the file now?
#   2. per commit    — does each commit contain the change its OWN message announces?
# Pass 2 is the one that catches this repo's actual fault: a working-tree audit
# would have passed once the later commit made the claim true.
#
# Usage: bash scripts/claims_audit.sh
set -u
cd "$(dirname "$0")/.." || exit 2
pass=0; fail=0
ok()   { printf '  ok    %s\n' "$1"; pass=$((pass+1)); }
bad()  { printf '  FAIL  %s\n' "$1"; fail=$((fail+1)); }
claim() { # claim <description> <file> <fixed-string>
  if grep -qF -- "$3" "$2" 2>/dev/null; then ok "$1"; else bad "$1 (no /$3/ in $2)"; fi
}

M=scripts/monitor_faers_mobi.sh
S=scripts/monitor_selftest.py
F=scripts/monitor_failpath_test.sh

echo "1. working tree: does the file do what the record says?"
claim "monitor: AND semantics for check patterns"        $M ' && '
claim "monitor: homepage needs banner AND meta AND brief" $M 'alert-secondary && meta name'
claim "monitor: contract-match compares live surfaces"   $M 'formats-contract-match'
claim "monitor: unknown format must 400"                 $M 'signals-bad-format-400'
claim "monitor: label_status pinned"                     $M 'signals-label-status'
claim "monitor: + decodes as space"                      $M 'signals-plus-decode'
claim "monitor: row flags are booleans"                  $M 'signals-row-flags'
claim "monitor: gh is overridable"                       $M 'GPS_MONITOR_GH'
claim "monitor: git is overridable"                      $M 'GPS_MONITOR_GIT'
claim "monitor: refuses GitHub writes off production"    $M 'refusing GitHub writes'
claim "monitor: PATH is prepended, not replaced"         $M '${PATH:+:$PATH}'
claim "monitor: retry delay configurable"                $M 'GPS_MONITOR_RETRY_SLEEP'
claim "monitor: base URL overridable"                    $M 'GPS_MONITOR_BASE'
claim "selftest: reports INCONCLUSIVE, never NOT CAUGHT" $S 'INCONCLUSIVE'
claim "selftest: deletes EVERY occurrence"               $S 'rx.sub("", body)'
claim "selftest: parses the monitor's own CHECKS table"  $S 'CHECKS=('
claim "failpath: server watches the HARNESS pid"         $F 'def _die_with(owner)'
claim "failpath: harness pid is passed to the server"    $F '"$PORT" "$$"'
claim "failpath: os.kill(owner, 0) liveness probe"       $F 'os.kill(owner, 0)'
claim "failpath: broken-b proxies production"            $F 'urllib.request.urlopen("https://faers.mobi"'
claim "failpath: stubs gh and git explicitly"            $F 'GPS_MONITOR_GH='
claim "protocol: inbound path documented"                issues/inbound-change-protocol.md 'it notifies, this seat files'
claim "protocol: one filer rule"                         issues/inbound-change-protocol.md '## One filer'

n=$(grep -c '^  "' <<<"$(awk '/^CHECKS=\(/,/^\)/' $M)")
if [ "$n" -ge 33 ]; then ok "monitor: $n checks (record says 33)"; else bad "monitor: only $n checks, record says 33"; fi
# 8 helper calls + 1 inline check ("episode cleared"), which is why a
# want/wantnot count alone reported 8 and flagged a record that was right.
# Suspect the check before the record -- the standing lesson of this loop.
a=$(( $(grep -cE '^\s*(want|wantnot) ' $F) + $(grep -c 'PASS episode cleared' $F) ))
if [ "$a" -eq 9 ]; then ok "failpath: $a assertions (record says 9)"; else bad "failpath: $a assertions, record says 9"; fi
if crontab -l 2>/dev/null | grep -q monitor_faers_mobi; then ok "cron entry installed"; else bad "cron entry missing"; fi

echo "2. per commit: does each commit contain the change its message announces?"
# <commit>|<fixed string the message implies>   — the fault a4c6e4f had
while IFS='|' read -r c needle; do
  [ -z "$c" ] && continue
  sha=$(git log --format=%H --grep="$c" -1)
  if [ -z "$sha" ]; then bad "commit matching '$c' not found"; continue
  fi
  if git show "$sha" --format="" -U0 | grep -qF -- "$needle"; then
    ok "'$c' carries /$needle/"
  else
    bad "'$c' does NOT carry /$needle/ — claim made true by a later commit?"
  fi
done <<'EOF'
Monitor: require ALL regexes to match|&&
Monitor: compare the live openapi enum|formats-contract-match
Mutation self-test for the monitor|INCONCLUSIVE
Test the monitor's failure branches|GPS_MONITOR_GH
Actually add the orphan watchdog|def _die_with(owner)
Monitor: pin the 400 on an unknown format|signals-bad-format-400
EOF

echo
echo "pass $pass  fail $fail"
[ "$fail" = 0 ]
