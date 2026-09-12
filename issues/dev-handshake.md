# Development handshake — Career ↔ Linux implementer

Spec only. Do not merge this GPS PR as site code. Implementation stays on the Linux box.

## Roles

| Who | Job | Does not |
|-----|-----|----------|
| **Career** (Grok Bot chat) | Product/spec. Opens one GPS handshake PR per slice. Reviews live faers.mobi. Posts analysis. | Implement in `/projects/faers-mobi/`. Deploy. Merge handshake PRs. |
| **Linux** (Grok Bot on Ubuntu + home Claude) | Implementer. Reads handshake PRs. Works in `/projects/faers-mobi/` (and siblings: aers-mobi, safetysignal). Posts status. Opens a **code** PR on `harlananelson/faers-mobi` when ready for review. | Merge GPS handshake PRs. Deploy until Harlan says. |
| **Harlan** | Approves deploys. Reviews code PRs. Overrides either side. | — |

PRs only, not issues. The Linux bot wakes on pull requests.

## One PR per slice

- A GPS handshake PR is a ticket: one markdown file under `issues/`, plus comments.
- Do not pile a new slice onto a closed-scope ticket. #23 is Tzield search + Novel. Next product work gets a new PR.
- Weekly agent-review / research-ideas PRs (#10–#22) stay Harlan’s. Career does not use those for implementation.

## Where the code lives

| Repo | Role |
|------|------|
| `harlananelson/globalpatientsafety` | Handshake briefs + static globalpatientsafety.com |
| `harlananelson/faers-mobi` | Live faers.mobi Shiny app (private). Code PRs go here. Local tree: `/projects/faers-mobi/` |
| `harlananelson/aers-mobi` | aers.mobi sibling |
| `harlananelson/safetysignal` | Shared signal engine |

## Comment markers

Both agents post as `harlananelson`, so login cannot tell them apart. First line of every bot comment:

```
<!-- role:career -->
```

or

```
<!-- role:linux -->
```

Harlan (human) comments need no marker. Career’s watch loop **ignores** `<!-- role:career -->` comments so it does not echo itself.

## What Linux posts (and when)

Post on the handshake PR, not a new GPS PR, when:

1. Local work landed (what changed, tests, path).
2. Blocked (need a decision or a missing file).
3. A faers-mobi code PR is open (link it).
4. Deployed to https://faers.mobi (what to type to verify).

Not every commit. Do not deploy until Harlan says.

## What Career posts

- New slice → new handshake PR (brief in `issues/`, Done when, out of scope).
- Live-site review after a Linux deploy note.
- Next-slice analysis only after the current slice is live or explicitly parked.

Prefix `<!-- role:career -->`. Keep briefs small. Do not implement `SEARCH_REDESIGN.md` wholesale.

## Product bars (faers.mobi)

1. Usable drug AE report — teplizumab/Tzield reference. **Live 2026-09-12** (typing `tzield` isolates; Novel is `novel`). `?q=` fill still flaky.
2. Named-drug profile — dedicated page or stable `?drug=` URL, not only a Shiny table session.
3. API / LLM — `GET /signals?drug=` (JSON). Document in one markdown file.

Pay gate stays parked until bars 2 and 3 exist. Free for individuals, paid for drug companies. Do not implement billing in a handshake slice.

## Current next slice (after #23)

When starting this work, open a **new** GPS handshake PR. Do not add it to #23.

1. Fix `?q=` fill on load.
2. Dedicated drug page or stable `?drug=teplizumab`.
3. `GET /signals?drug=` on faers.mobi, documented.

## Done when (this protocol PR)

Linux comments `<!-- role:linux -->` that it will follow this file (markers, one PR per slice, code PRs on faers-mobi). Leave this PR open as the channel ticket. Do not merge.
