# Agent collaboration framework (Career + Linux)

Protocol only. **Do not implement on faers.mobi.** Do not merge this GPS PR as site code.

Harlan asked Career to reach Linux, get consensus on what worked across handshake PRs #23–#63, and write a framework for future work. Career drafted; Linux amended (`<!-- role:linux -->` on this PR). Career folded those amends below. Consensus = both role tags on this PR.

## What we just did

~41 handshake PRs in one night (2026-09-12 → 13). Career spec’d; Linux shipped in `/projects/faers-mobi/`; live faers.mobi was the scoreboard; Harlan was only at gates (GitHub write, keep-going-not-pay, leftovers-but-not-billing). Longest Harlan has had agents run without stop.

## What enabled it (eight enablers — both sides)

1. **Durable tickets, not a shared chat.** A GitHub PR wakes both sides after idle. Chat dies; compaction kills chat memory; the PR does not.
2. **One slice per PR, never merge handshake PRs.** Each wake is a closed job. No pile-ons. Do not put UI + OpenAPI + MCP on the same handshake.
3. **Role tags.** `<!-- role:career -->` / `<!-- role:linux -->` so watchers ignore their own posts. Stops comment echo. (They do **not** quiet a new-PR watcher that re-emits already-acked handshakes on session resume — that is an implementer-side watcher bug: persist seen IDs across sessions.)
4. **Ship when good.** Standing deploy. Human is not the deploy button.
5. **Verify on prod before the next ticket.** Live URL **and** asserted body numbers (not status codes alone). Closes the loop.
6. **Ping the human only at gates.** Live bar, regression, or Harlan-only blocker. Not acks. Keep-going chatter is not a gate.
7. **Hard outs of scope** on every ticket (don’t merge GPS PRs, pay gate parked, no new compute, no licensed MedDRA unless named). Removes the “should I also…?” stall.
8. **Stop when a person wouldn’t notice.** Leftover-sentence PRs are the failure mode — **unless the human named that leftover** (e.g. #61 from #60’s test plan). Named leftovers get a ticket; a second “scrub the scrub” does not.

## What kept Linux from looping or stalling

- A **new-PR watcher** (not chat). Each GPS handshake is a closed job: ack → ship in `/projects/faers-mobi/` → deploy → hit the live URL → deploy note with those URLs → wait.
- **Done-when numbers**, not “200 OK.” Example: #58 first pass was 200 markdown that dumped 2,416 drug names and labeled Top n as “Nausea”; the test plan’s “top n otezla” is what made that fail. Status codes lie.
- **Hard outs on every ticket** as above.

## Spec size

Just right when it has: product tree, one wanted, live URL + expected numbers, out of scope.

Missing more often than “too thin”:

- **Which process to recycle** (API systemd / MCP HTTP / Shiny SockJS / static nginx only). Defaulting to “restart everything” fights a small VPS.
- **Body assertions**, not only HTTP 200. Say the field: `novel=known`, `n=319`, Top n otezla, filename `rwe-brief-Nausea.pdf`.
- Event-only vs pair: say Class/Series stay off when you mean it (#60 did this; keep it).

Do not add a second markdown file per slice. The PR body is the ticket.

## Standing deploy (keep it)

Do not wait for a chat yes. Regret is only the **how**, not the permission:

- `touch restart.txt` does not recycle Shiny. Write a date, kill **only** the product SockJS (here: `cd /srv/shiny-server/faers-mobi`), never a sibling app (aers-mobi).
- A recycle grep that matches the deploy script’s own text will SIGTERM the deploy (hit on #62).
- Static docs (`API.md`, `openapi.json`, `llms.txt`) need scp + nginx alias, not an API restart.
- Do not deploy `renv/activate.R`.

Standing deploy includes a **short recycle recipe** in the implementer tree (or the handshake names which layer). Permission without a recipe is how the wrong app almost got recycled.

Implementer commits on the **product tree main** (here: `faers-mobi` main). Handshake repo is not the product. Optional product-repo PR is optional unless the human wants review there.

## Never again (Career / Spec agent)

- Do not open leftover-docs tickets to keep the streak alive. Named leftovers from a prior Done-when are allowed; scrubbing the scrub is not.
- Do not treat “200 markdown” as landed without the Done-when numbers in the **body**.
- Do not ask the implementer to merge GPS handshake PRs or to wait on the human for ordinary deploys.
- Do not specify a new statistic, OpenFDA scrape, or MedDRA zip unless the human named it.

## Notes from this run

- **httpuv is single-threaded.** Broad event `format=brief` / `pdf` / `profile` can take ~15s. Not a protocol issue; don’t spec “instant.”
- **GPS handshake PRs stay open on purpose.** Implementer will not close or merge them. Do not add “tidy the PR list” as a slice.

## Framework (use on the next project)

Copy this. Change the two agent names, the implementer tree, and the live scoreboard.

### Roles

| Who | Job | Does not |
|-----|-----|----------|
| **Spec agent** | Opens one handshake PR per slice. Reviews the live scoreboard (body, not only status). Opens the next slice without asking. | Implement in the product tree. Merge handshake PRs. |
| **Implementer** | Reads the handshake PR. Ships in the product tree. Deploys when good (with recycle recipe / named layer). Posts a deploy note (how to verify, with numbers). Optional: a **code** PR on the product repo. | Merge handshake PRs. Wait for the human on ordinary deploys. |
| **Human** | Overrides. Answers blockers. Approves money / secrets / destructive work. | Day-to-day slice start or deploy. |

### Channel

- PRs (or another durable ticket both agents already watch). Not issues-only, not chat.
- Handshake repo can be separate from the product repo.
- Both bots may post as the same GitHub user: **first line of every bot comment is a role HTML comment.**
- Watchers **ignore their own role.** New-PR watchers must **persist seen IDs across sessions** (implementer-side).

### Ticket shape (PR body is the ticket — no second markdown file)

```
# <slice name>
Handshake for `<product tree>`. Do not merge this handshake PR. Deploy when good.
<previous slice> is live. Do not pile this onto it.

## Problem
<one paragraph>

## Wanted
<numbered, no new compute unless named>

## Recycle / deploy layer
<API systemd | MCP HTTP | Shiny SockJS only | static docs nginx | …>

## Done when
- <live URL + expected **body** numbers / fields / filenames>
- Deploy note with those URLs and numbers.

## Out of scope
<money, merge, extras, MedDRA, new scrapes>
```

### Cycle

1. Spec agent opens one handshake PR when the last slice is live or parked. Do not ask the human first.
2. Implementer ships, tests, **deploys when good** (correct layer only). Post a deploy note (what to type to verify, with body expectations).
3. Spec agent checks the live scoreboard (**body** beats status). If landed → next slice. If missed → comment the gap on the **same** PR.
4. Ping the human only for: product bar live, live regression, or a blocker only they can answer.
5. **Stop** when the next change is a leftover sentence a person would not notice — unless the human named that leftover.

### Standing rules

- One handshake PR per slice. Never merge handshake PRs as product code.
- Standing deploy permission. Do not wait for a chat yes. Handshake names which layer to recycle, or “static docs only.”
- Done-when is a live URL **and** asserted numbers in the body. Live body beats live status; live scoreboard beats memory.
- Implementer deploys from the product tree. Handshake repo is not the product.
- Watchers ignore their own role tag. New-PR watchers persist seen IDs across sessions.
- Money / secrets / destructive: human only.
- Do not open leftover-docs tickets to keep the streak alive (named leftovers excepted once).
- Do not tidy / close / merge the open handshake PR list as a “slice.”

### Failure modes (we hit these)

- **Echo:** two bots reply to each other. Fix: role tags + ignore-self.
- **Watcher re-fire after compaction:** already-acked handshakes re-emitted. Fix: persist seen PR IDs (implementer).
- **Slice creep:** “while you’re there.” Fix: out of scope + new PR.
- **Leftover-sentence streak:** footer, docs scrub, enum typo. Fix: stop rule (+ named-leftover exception).
- **Status-only verify:** 200 with wrong body. Fix: Done-when body assertions.
- **Wrong recycle:** restart everything / wrong app / deploy-script self-SIGTERM / restarting for static docs. Fix: named layer + short recipe in product tree.
- **Unverified next:** opening the next ticket from a deploy note without hitting the live URL. Fix: verify first.
- **Human in the inner loop:** asking “deploy?” or “next slice?” Fix: standing permission + ping rules.

## Done when (this protocol PR)

- [x] Linux posts `<!-- role:linux -->` amends or “agree.”
- [x] Career folds amends into this file (same PR).
- Leave open as a companion to #24. Do not merge. Do not deploy anything to faers.mobi.
