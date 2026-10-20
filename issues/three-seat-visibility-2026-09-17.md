# Three-seat loop: Career visibility + Linux ship + Codex rubric

Protocol only. **Do not implement on faers.mobi.** Do not merge as site code.

Harlan (2026-09-17): more work landed on faers-mobi (Codex review loop, inbound semantics fixes, evaluation suite). Career is useful as a **visibility and assessment** layer. Codex runs a looped review. Need a clear back-and-forth on GitHub.

Companion to #24 (Career↔Linux) and #64 (framework). Extends `issues/inbound-change-protocol.md`.

## Seats

| Seat | Who | Bus | Does | Does not |
|------|-----|-----|------|----------|
| **Career** (this Grok Bot) | Product / visibility | GPS PRs + comments `<!-- role:career -->` | Open handshake slices; live-verify with body numbers; file **inbound** tickets from faers-mobi notifications; independent smoke of O-suite claims; ping Harlan only on live bar / regression / his-only blocker | Code in `/projects/faers-mobi/`; open PRs on faers-mobi; wake Codex’s tmux; deploy |
| **Linux / faers-mobi** | Implementer | faers-mobi commits + `<!-- role:linux -->` on GPS PRs; `reports/evaluation/DEPLOY-LOG.md` | Implement slices; deploy; post live numbers; notify before inbound restarts; run `notify_rescore.py` → `NOTIFY-CODEX.md` | Open GPS handshake PRs (out of project scope — Career files); merge GPS PRs |
| **Codex** | Rubric reviewer | Human relays `NOTIFY-CODEX.md`; optional GPS comment `<!-- role:codex -->` | Frozen `score.py` O-suite; human rubric R; reassessment after deploy; evidence in `reports/evaluation/` | Silent production deploys without notification; weaken frozen assertions |

Harlan remains owner: merges when he wants, relays Codex when needed, decides pay gate.

## How Career talks back and forth

1. **Outbound product work (unchanged):** Career opens `handshake/…` PR → Linux implements → Linux `<!-- role:linux -->` deploy note → Career live-verifies `<!-- role:career -->` → ping Harlan if product bar.
2. **Inbound (faers-mobi originates):** Linux notifies (DEPLOY-LOG + ping path) → **Career files** `handshake/inbound-<slug>` and checks old behaviour if still live → deploy → Career verifies. Do not leave Grok with nothing to poll.
3. **After every scored improvement:** Linux runs notify_rescore → Harlan (or Career, if asked) pastes `NOTIFY-CODEX.md` into the Codex session → Codex rescores → optional `<!-- role:codex -->` on the GPS inbound/product PR with O (and R if reviewed) + artefact paths.
4. **Career assessment comment shape** (on the GPS PR, not a new product slice):

```
<!-- role:career -->
Visibility: live smoke …
Assessment: matches / does not match Linux claim …
Codex: waiting on relay of NOTIFY-CODEX.md | seen rescore-vN …
Next: none | open inbound-… | …
```

5. **No fourth bus.** Not Slack, not tmux from Career, not inventing a Codex webhook. GitHub PR comments + evaluation files only.

## Why

faers-mobi DEPLOY-LOG (2026-09-17): Grok watcher only sees work once a GPS PR exists; Codex has no callback API. Three seats + role tags keep the long handshake alive without copy-paste chaos.

## Linux / Codex please ack

- `<!-- role:linux -->` — will notify Career path (GPS) before non-urgent inbound deploys; will keep NOTIFY-CODEX.md fresh after scored changes.
- Codex (via Harlan paste or `<!-- role:codex -->`) — will treat Career live-verify as independent of self-reported 100/100.

## Out of scope

- Pay gate
- Weakening RUBRIC.md
- Auto-waking Codex
