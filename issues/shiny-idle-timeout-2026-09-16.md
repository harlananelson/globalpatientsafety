# Raise Shiny idle_timeout (stop worker-spawn churn)

Handshake only. Do not merge. Implement in `/projects/faers-mobi/` (and the live shiny-server config on the box). Deploy when good.

Harlan (2026-09-16): do the idle-timeout path, **not** an nginx IP block.

Linux Claude log (2026-09-16): a rotating-IP scraper (spoofed iPhone 13.2.3 Safari, Tencent clouds 43.x / 101.32 / 170.106) hits the **homepage** hundreds of times per day. Each hit spawns a Shiny worker that loads arrow/parquet, burns CPU, exits after the 5s default idle timeout. Genuine human traffic is small. Bot-UA markdown homepage (#72) is working. One transient Datatables 502 recovered.

## Scope

Raise `shiny-server` `idle_timeout` (and/or equivalent “one worker serves consecutive hits”) so homepage hits reuse a process instead of spawn-per-request.

Linux picks the number. A starting point: minutes, not 5 seconds (e.g. 60–300s). Recycle shiny-server. Do **not** block Tencent / iPhone UAs in this slice.

Optional log note: if nginx still has combined-format without host, not required here.

## Keep

- Mozilla `/` → Shiny HTML
- Bot UAs `/` → machine homepage (markdown or text/plain from #74)
- `GET /signals?drug=tzield&event=Nausea` → 200 n=319
- No `/signals` shape change
- No pay gate

## Verify (live)

- Homepage 200 (human + ChatGPT-User)
- `/signals?drug=tzield&event=Nausea` 200 n=319
- After recycle: worker is not spawning a new R process on every homepage hit (Linux checks `shiny-server` / process table, not Career)

## Out of scope

- nginx deny of Tencent CIDRs / iPhone UA
- GPS #73 exact event PT
- GPS #74 text/plain MIME (separate open slices)
- `/api/` trailing-slash 500
