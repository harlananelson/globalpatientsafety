#!/usr/bin/env python3
"""Mutation self-test for monitor_faers_mobi.sh — can each check fail, and for the right reason?

Adapted from the faers-mobi seat's tools/dev/mutation_check.py (2026-09-18). That
one reintroduces each defect the repo has actually had and confirms the tests
fail. A monitor cannot mutate production, so this mutates the OTHER side: it
fetches each check's real response, deletes the text the check's pattern matches,
and confirms the pattern then rejects the body.

Why this exists: on 2026-09-18 three checks were silently alternations, because
the check table is "|"-delimited and the pattern is the last field. `home-human`
would have passed with the machine-client banner gone — the one thing it watches.
Inspection did not find that. Asking whether a check can fail did.

Their finding about the METHOD matters more than the result, and is honoured here:
a mutation that is a no-op proves nothing, and a false NOT CAUGHT sends you to
rewrite a test that was fine. So when deleting the matched text leaves the pattern
still matching, this reports INCONCLUSIVE, never NOT CAUGHT. Suspect the mutation
before the check.

Usage:
    python3 scripts/monitor_selftest.py            # every check that has a pattern
    python3 scripts/monitor_selftest.py home-human # one check
"""
import re
import subprocess
import sys

BASE = "https://faers.mobi"
MONITOR = __file__.rsplit("/", 1)[0] + "/monitor_faers_mobi.sh"


def load_checks():
    """Parse the CHECKS table out of the monitor, so the two cannot drift apart."""
    src = open(MONITOR).read()
    table = src.split("CHECKS=(", 1)[1].split("\n)", 1)[0]
    out = []
    for line in table.splitlines():
        line = line.strip()
        if not line.startswith('"'):
            continue
        # Bash double-quoted string: \" is a quote and \\ is one backslash.
        # Getting this wrong made the first run report BAD REGEX for a check
        # that grep -E matches fine -- the harness, not the check.
        body = line[1:line.rindex('"')].replace('\\"', '"').replace('\\\\', '\\')
        parts = body.split("|")
        # the pattern is everything after the 6th field: it may contain "|"
        name, method, path, ua, want, ct = parts[:6]
        pattern = "|".join(parts[6:])
        out.append((name, method, path, ua, want, ct, pattern))
    return out


def fetch(method, path, ua):
    cmd = ["curl", "-sS", "--max-time", "45", "-A", ua]
    if method == "MCP":
        cmd += ["-X", "POST", "-H", "Content-Type: application/json",
                "-H", "Accept: application/json, text/event-stream",
                "-d", '{"jsonrpc":"2.0","id":1,"method":"initialize","params":'
                      '{"protocolVersion":"2025-03-26","capabilities":{},'
                      '"clientInfo":{"name":"gps-selftest","version":"0"}}}']
    elif method == "HEAD":
        cmd += ["-I"]
    cmd.append(BASE + path)
    return subprocess.run(cmd, capture_output=True, text=True, errors="replace").stdout


def main():
    only = sys.argv[1] if len(sys.argv) > 1 else None
    caught = inconclusive = skipped = failed = 0
    for name, method, path, ua, want, ct, pattern in load_checks():
        if only and name != only:
            continue
        if not pattern or method == "HEAD":
            skipped += 1
            continue
        body = fetch(method, path, ua)
        parts = [p for p in pattern.split(" && ")] if " && " in pattern else [pattern]
        for part in parts:
            label = f"{name} :: /{part}/"
            try:
                rx = re.compile(part)
            except re.error as e:
                print(f"BAD REGEX      {label}  ({e})")
                failed += 1
                continue
            if not rx.search(body):
                # the check would be failing live right now, not a self-test result
                print(f"LIVE MISMATCH  {label}  (pattern absent from the real body)")
                failed += 1
                continue
            # Delete EVERY occurrence: the question is whether the check fails
            # when this evidence is gone, not when one copy of it is. Deleting a
            # single occurrence left 17 of 34 parts "still matching" on the first
            # run -- a weak mutation reporting as an inconclusive check.
            mutated = rx.sub("", body)
            if mutated == body:
                print(f"INCONCLUSIVE   {label}  (mutation was a no-op)")
                inconclusive += 1
            elif rx.search(mutated):
                # deleting one occurrence left another: the mutation is too weak
                # to prove anything. NOT the same as the check being weak.
                print(f"INCONCLUSIVE   {label}  (still matches after deleting every occurrence)")
                inconclusive += 1
            else:
                print(f"CAUGHT         {label}")
                caught += 1
    print(f"\ncaught {caught}  inconclusive {inconclusive}  failed {failed}  skipped {skipped}")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
