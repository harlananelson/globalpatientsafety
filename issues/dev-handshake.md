# Development handshake — Career ↔ Linux implementer

Spec only. Do not merge this GPS PR as site code. Implementation stays on the Linux box.

## Cycle (standing)

Harlan wants a tight improvement loop and **minimal interaction**.

1. Career opens one GPS handshake PR per slice when the last slice is live or parked. Do not ask Harlan first.
2. Linux implements in `/projects/faers-mobi/`, tests, and **deploys when the change is good**. Standing permission: do not wait for a chat yes. Post a deploy note on the slice PR (what to type to verify).
3. Career checks live faers.mobi after a deploy note. If the slice landed, open the next slice. If it missed, comment the gap on the same PR.
4. Ping Harlan only for: a product bar just went live, a live regression, or a blocker only he can answer (credential, paid API, destructive, billing). Stay quiet on handshake acks, local-only progress, and Career’s own comments.

Pay gate / billing still needs Harlan. Do not implement billing.

## Roles

| Who | Job | Does not |
|-----|-----|----------|
| **Career** (Grok Bot chat) | Product/spec. Opens one GPS handshake PR per slice. Reviews live faers.mobi. Opens the next slice without asking. | Implement in `/projects/faers-mobi/`. Merge handshake PRs. |
| **Linux** (Grok Bot on Ubuntu + home Claude) | Implementer. Reads handshake PRs. Ships in `/projects/faers-mobi/` (siblings: aers-mobi, safetysignal). Opens a **code** PR on `harlananelson/faers-mobi` when useful. Deploys when good. | Merge GPS handshake PRs. Wait for Harlan on ordinary deploys. |
| **Harlan** | Overrides. Answers blockers. Approves billing / pay gate. | Day-to-day slice start or deploy. |

PRs only, not issues. The Linux bot wakes on pull requests.

## One PR per slice

- A GPS handshake PR is a ticket: one markdown file under `issues/`, plus comments.
- Do not pile a new slice onto a closed-scope ticket. #23 is Tzield search + Novel only.
- Weekly agent-review / research-ideas PRs (#10–#22) stay Harlan’s. Career does not use those for implementation.

## Where the code lives

| Repo | Role |
|------|------|
| `harlananelson/globalpatientsafety` | Handshake briefs + static globalpatientsafety.com |
| `harlananelson/faers-mobi` | Live faers.mobi Shiny app (private). Code PRs go here. Local tree: `/projects/faers-mobi/` |
| `harlananelson/aers-mobi` | aers.mobi sibling |
| `harlananelson/safetysignal` | Shared signal engine |

## Comment markers

Both agents post as `harlananelson`. First line of every bot comment:

```
<!-- role:career -->
```

or

```
<!-- role:linux -->
```

Harlan (human) comments need no marker. Career’s watch loop **ignores** `<!-- role:career -->` comments.

## What Linux posts (and when)

Post on the slice PR when:

1. Blocked (need a decision only Harlan can make).
2. Deployed to https://faers.mobi (what to type to verify). Optionally link the faers-mobi code PR.
3. Local work landed *and* you are stuck or want a Career re-review before deploy.

Not every commit. No “waiting on Harlan to deploy.”

## What Career posts

- New slice → new handshake PR (brief in `issues/`, Done when, out of scope).
- Live-site review after a Linux deploy note. Then the next slice.
- Prefix `<!-- role:career -->`. Keep briefs small. Do not implement `SEARCH_REDESIGN.md` wholesale.

## Product bars (faers.mobi)

1. Usable drug AE report — teplizumab/Tzield reference. **Live 2026-09-12** (typing `tzield` isolates; Novel is `novel`).
2. Named-drug profile — **Live 2026-09-12** via stable `?drug=` (alias of `?q=` isolation). Example: `https://faers.mobi/?drug=teplizumab`.
3. API / LLM — **Live 2026-09-12** `GET /signals?drug=` JSON + `faers-mobi/API.md`. `?q=` fill-on-load also fixed in the #25 deploy.

Bars 1–3 exist. Pay gate / billing still needs Harlan (free for individuals, paid for drug companies) — do not implement billing without him. Next usefulness slice: event search beyond top-2000 (#26).

## Done when (this protocol PR)

Linux already acked. Leave #24 open as the channel ticket. Do not merge. Treat this file as the live protocol; later commits on this branch update it.
