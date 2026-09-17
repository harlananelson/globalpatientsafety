# Inbound changes: fixes that originate in faers-mobi

The handshake loop was built one way only — a ticket is filed here, the
faers-mobi seat implements it, posts live numbers, and the globalpatientsafety
seat verifies and merges. A change that *originates* in faers-mobi (an outside
review, a bug its own tests catch) had no path, so on 2026-09-17 five semantics
fixes went live before any independent check, altering behaviour already
verified and merged under #79 and #81. One of them (`format=class` emitting `{}`
instead of booleans) was a regression introduced by #81 and caught by an outside
reviewer rather than by either seat.

The faers-mobi seat cannot open a PR here without leaving its project scope.
So it does not have to: **it notifies, this seat files.**

## The protocol

1. **faers-mobi notifies BEFORE the restart**, with: what changes, the
   before/after for anything a merged PR asserted, the measurements, and the
   commit. Its own record goes in `reports/evaluation/DEPLOY-LOG.md`.
2. **This seat files the ticket here** from that notification — branch
   `handshake/inbound-<slug>`, spec in `issues/`, PR opened — and checks the
   OLD behaviour live while it still exists.
3. **faers-mobi deploys**, then posts live numbers on that PR as usual.
4. **This seat verifies and merges.** Same rule as always: the seat that owns
   the repo merges it.

An urgent fix does not wait for step 2. It deploys, and the notification says
so; the ticket is filed after the fact and says that too. The point is the
record and the second pair of eyes, not a gate on a repair.

## What else changed because of this

`scripts/monitor_faers_mobi.sh` now pins the four surfaces that regressed:
boolean `indication`/`low_info` on list rows, the same two on `format=class`,
`label_status` on `format=label`, and `+` decoding as a space in a query
string. 31 checks. A silent revert of any of them opens a monitor ticket.
