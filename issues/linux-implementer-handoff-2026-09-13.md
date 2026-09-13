# Linux implementer handoff (2026-09-13)

For the next agent in this loop. Handshake repo is `harlananelson/globalpatientsafety`. Product is `/home/harlan/projects/faers-mobi/`. Production is https://faers.mobi.

You are **Linux**. Career is the other Grok bot. Comments start with `<!-- role:linux -->`. **Never merge GPS handshake PRs.** Never merge weekly research-ideas / agent-review PRs. Pay gate / Stripe **parked** until Harlan asks.

## Loop

1. Watch `harlananelson/globalpatientsafety` PRs (watcher below).
2. Classify: product slice vs protocol-only vs pay gate.
3. Product slices: implement in **faers-mobi**, deploy, post live **body** numbers. Do not pile leftover sentences onto a new PR unless Career says same slice.
4. Protocol-only: ack, do not implement, do not deploy.
5. Handshake PRs stay **open**. Harlan/Career close them.

Watcher (restart if it died at 10h):

```bash
python3 /home/harlan/.grok/long-running-background-tasks/watch_new_prs.py --loop --poll-interval 30
```

Stdout is only ACTION_REQUIRED / FAILED. Log: `~/.grok/pr-watch/watch.log`.

## Live product (as of 2026-09-13)

faers-mobi `main` **`6df62f6`**. Handshake PRs **#32–#71** open, unmerged. Latest product slice **#71**.

| Check | Expect |
|---|---|
| `GET /signals?drug=tzield&event=Nausea` | 200, **n=319**, eb05 7.8091, through-quarter **2025Q4** |
| `GET /api` | 200 `text/html` — How to query faers.mobi, not Shiny |
| `GET /api.md` and `/API.md` | 200 `text/plain`, same body |
| Homepage | LLM banner + plain `<p>` after h4 with GET /signals + `/api`; `<meta name="description">`; `href="/api"` |
| Hosted MCP | `https://faers.mobi/mcp` POST JSON-RPC; GET is help text |
| GitHub description `harlananelson/faers-mobi` | `FAERS signal detection (faers.mobi) — Shiny UI + GET /signals` (not VAERS) |

Done-when is **numbers in the body**, not HTTP 200. (GPS #58: 200 markdown that dumped ~2416 drug names.)

## Recycle (name the layer)

VPS `root@5.78.69.136`. Standing scp to `/srv/shiny-server/faers-mobi/`, `chown shiny`. **Do not deploy `renv/activate.R`.** Do not touch aers-mobi.

| Layer | When | How |
|---|---|---|
| Cheap JSON `:3841` | `GET /signals` JSON hangs, 0 bytes | `systemctl restart faers-signals-api` |
| Heavy `:3843` | brief/pdf/profile/class/series hangs | `systemctl restart faers-signals-heavy` |
| nginx | static `/api`, `/api.md`, robots, OpenAPI | `nginx -t && systemctl reload nginx` (backup `sites-enabled/faers-mobi` first) |
| Shiny UI | homepage HTML/banner/head | write `restart.txt`; **kill SockJS whose `/proc/pid/cwd` is `/srv/shiny-server/faers-mobi` only**. Never grep `faers-mobi`+`SockJS` (that SIGTERM’d the deploy script). Never `systemctl restart shiny-server` to unpeg API. |

JSON and heavy are **two R processes**. A brief storm must not leave JSON at 0 bytes (#67). `limit_req` 1 r/s burst 3 on heavy. Brief elapsed cap 20s.

## Handshake map (do not re-do)

| PR | Kind | Status |
|---|---|---|
| #64 | Protocol: Career/Linux seats | Comparison posted; do not import HDL filer/operator |
| #65 | Protocol: LLM memo | REST+OpenAPI+MCP exist; do not add `soc=` etc. |
| #66 | Banner above table | Live |
| #67 | API stay-alive | Two workers live |
| #68 | Protocol: pay segments / $200k | No Stripe/keys |
| #69 | `/api.md` + head links | Live |
| #70 | First extracted paragraph + meta description + GitHub blurb | Live |
| #71 | HTML `/api` companion | Live 2026-09-13 |

## Do not

- Build another API / `/api/v1/` / Plumber / WebMCP (look only if ChatGPT **opens the page and scrapes**; hosted MCP already exists).
- Pay gate, Stripe, API keys, 100 req/day cap.
- Commit licensed MedDRA; no secrets; do not overwrite `~/data/diana/meddra_hierarchy.parquet` without a real ASCII zip.
- Pile leftover-sentence tickets. Same-PR leftover is OK if Career says so (#70 meta).
- Merge handshake PRs.

## Career test for humans

https://faers.mobi/api (HTML) then https://faers.mobi/api.md (plain). Success = quoting `GET /signals`, not the DataTable. ChatGPT browse sandbox / index lag is out of scope.

## Related docs (do not fork)

- `~/projects/AI/designs/gps-handshake-vs-hdl-harness-2026-09-13.md`
- `~/projects/AI/designs/h100-code-agents-omop-umls-jumpbox-2026-09-13.md` — CRS box is on-prem `iuhlwolfap1122`, not an Azure VM
- faers-mobi `CLAUDE.md` is **stale** (still says VAERS); do not trust it over this file
