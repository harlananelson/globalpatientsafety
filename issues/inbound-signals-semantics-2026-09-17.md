# Inbound: /signals novelty, indication and query-parsing semantics (59274bf → d83b2c0)

**Inbound change, filed after the fact.** First ticket under
`issues/inbound-change-protocol.md`. It originated in faers-mobi from an
independent Codex review, was deployed before any check by this seat, and is
filed here so the change has a reviewable record and the Grok reviewer — which
is reached through pull requests — has something to poll. Already live; **the
old behaviour is gone and cannot be re-checked**, which is the cost this
protocol exists to avoid repeating.

Deployed `d83b2c0`, restarted **2026-09-17 20:11:51 UTC**. VPS code byte-identical
to the faers-mobi working tree (md5 `f402bc8e20ce51eb6c0a80d0caf1eed8`). Behaviour
last changed by `59274bf` (20:03 UTC).

## The five changes

| # | Before | After | Touches |
|---|---|---|---|
| 1 | `+` in a query string was not decoded as a space: `event=ischaemic+stroke` → **0 rows**, `%20` → **654** | both → **654** | — |
| 2 | **1,335 of 2,001** cached label rows were empty placeholders (no set_id, no text) and reported `novel` for every event on **585,273 flagged pairs** | those report `?`; `format=label` carries `label_status` = cached / empty / missing | #79 novelty surface |
| 3 | novelty was a literal substring match | 70% word overlap + MedDRA synonyms. On 4,000 sampled pairs: novel **2,453 → 611**, 1,611 → `?`, 231 → known, **no known → novel**. nilotinib × Acute MI now `known` | #79 |
| 4 | `indication` matched Limitations-of-Use and negated sentences, so `indication=hide` hid semaglutide × Pancreatitis and empagliflozin × Diabetic ketoacidosis | those flag `false`; rivaroxaban, ezetimibe, cyclophosphamide, methadone, lidocaine still flag. Over ~6,000 sampled pairs: clears 4, adds 0 | #81 hide filter |
| 5 | `format=class` emitted `indication:{}` / `low_info:{}` | booleans | **regression introduced by #81** |

**The consequential one is #2 with #3.** Anything read from the `novel` column
before 2026-09-17 was partly reading empty label rows. Any draft or brief resting
on a pre-2026-09-17 novelty claim needs re-checking.

## Verified live by this seat (2026-09-17, after deploy)

- `+` and `%20` both 654 for ischaemic stroke
- `format=label` → `label_status: cached`; nilotinib × Acute MI `known`
- semaglutide × Pancreatitis `indication:false`; rivaroxaban × Ischaemic stroke `true`; xarelto × Ischaemic stroke `false`
- `format=class` emits booleans
- **Merged assertions still hold:** tzield 153 rows, `indication=hide&low_info=hide` → exactly the 113 rows with neither flag (same set, none leaked, eb05 desc), tzield × Nausea **n=319**
- Monitor 31/31 pass

## Evidence and tests (faers-mobi repo)

- `reports/evaluation/EVIDENCE-v1.md` — clozapine subtype, placeholder-label, nilotinib alias tables; brief-export surfaces
- `tests/testthat/test-signals-api-semantics.R` — 18 assertions pinning `+` decoding, boolean flags out of `compact_pairs`, and the Limitations-of-Use rule
- `reports/evaluation/DEPLOY-LOG.md` — local deploy detail; the durable cross-repo record is this repo's `DECISION_LOG.md`
- Reviewer's frozen suite: **30/100 → 100/100**

## For the reviewer

The question worth an independent pass is **#3 and #4, where the meaning changed**,
not #1 or #5, which are unambiguous repairs:

1. Is 70% word overlap + synonym expansion the right novelty rule, or does it now
   call `known` things that are genuinely unlabelled? The 231 novel → known
   transitions are the set to sample.
2. Does the Limitations-of-Use exclusion drop any true indication? It cleared 4 in
   6,000 and added 0, which is a small enough delta to enumerate by hand.
3. Is `?` the right surface for a placeholder label, or should the pair be omitted?

## Keep

- No new `/signals` params, no pay gate
- Deploys held while the Codex reviewer's pass is open, so this is a stable target
