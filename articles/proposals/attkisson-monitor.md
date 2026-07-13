# Attkisson Health-Topic Monitor

Monitors Sharyl Attkisson's podcast for health/drug/vaccine topics that map to a
**FAERS/VAERS disproportionality analysis this site can actually run**, and feeds the
analyzable ones into the article queue.

## Source (what works, what doesn't)

- **PRIMARY — Substack full-text RSS:** `https://sharylattkisson.substack.com/feed`
  (*Sharyl's Substack*, free/"Everyone", 22k+ subs). **Carries the FULL article text**
  (`content:encoded`), so topic detection scans the whole body, not just the title — the printed
  version of her reporting. Open, not Cloudflare-blocked. Also an undocumented JSON API:
  `/api/v1/archive?sort=new&limit=N` (post metadata) and `/api/v1/posts/<slug>` (full `body_html`).
  Prefer the RSS feed; the API is a fallback for pulling a single post's body.
- **SECONDARY — podcast RSS:** `https://anchor.fm/s/dab6618/podcast/rss` (*The Sharyl Attkisson
  Podcast*, 327+ eps). Titles + descriptions only, NO transcripts. Use to catch audio-only
  episodes not mirrored on Substack.
- **Do NOT rely on** `sharylattkisson.com` / its `/feed/` — **Cloudflare-blocked (403)** to
  automated fetchers. Her TV "(WATCH)" segment transcripts live there, behind that wall; the
  Substack full text is the accessible substitute (no Whisper needed).
- Second show *Full Measure After Hours* (separate podcast feed; add later if wanted).

## The analyzability filter

Most of her health content is health *politics* (CDC schedule changes, lawsuits, indictments,
EMF/cell towers) — **not** analyzable here. Flag an episode as **analyzable** only when it names:

1. a specific **drug or vaccine** that appears in the FAERS (drug) or VAERS (vaccine) signals
   parquet, **AND**
2. a specific **adverse event / condition** that exists as a MedDRA Preferred Term.

Then it maps to the site's 4-method disproportionality engine (EB05 ≥ 2.0, ≥2 of 4 methods).
Verify the drug/event actually exist in the parquet before drafting (per the queue's step 2).

## First-pass scan (2026-07-13)

| Topic (her coverage) | Analyzable? | Candidate analysis |
|---|---|---|
| **Ivermectin** (Bowden/Ivermectin, Kory, "Ivermectin OTC") | **Yes — strong** | FAERS: 12,466 ivermectin reports. Neurotoxicity EB05 20 (4/4); and a striking cluster of *Product use in unapproved indication* / *Drug ineffective for unapproved indication* signals that literally capture the off-label COVID-era use. Candidate: "What FAERS actually recorded during the ivermectin-for-COVID era." |
| **COVID vaccine → myocarditis** | **Yes — done, extendable** | VAERS. Already covered in the Christine Cotton article; could extend to newer quarters / other cardiac PTs. |
| **MMR / childhood vaccines → autism** | **Weak / heavily caveated** | VAERS has the vaccines, but "autism"/neurodevelopmental PTs are rare, confounded, and disproportionality is methodologically fraught here. Only worth it as a careful "what disproportionality can and cannot say about this claim" piece. |
| CDC vaccine schedule removed (ep 337) | Indirect | Not a drug/event pair; could prompt a VAERS signal review of specific vaccines affected. |
| Monkeypox smuggling (ep 334); AAP lawsuit (324); Morens indictment (328); EMF/cell towers (323) | No | Policy / not a drug-safety signal / not in FAERS-VAERS. |

**Realistic expectation:** her feed yields roughly one strong analyzable topic per stretch of
several episodes; the monitor's value is catching those without reading every episode.

## Seen log (dedupe)

- **Substack — latest scanned post:** `shhh-heres-cdcs-now-removed-revised` (2026-07-06).
- **Podcast — latest scanned episode:** **#337** (2026-07-10).

The weekly routine advances both watermarks and appends newly-seen slugs/episode numbers so it
doesn't re-flag the same items. (Substack posts and podcast episodes often mirror each other —
dedupe on topic, not just source, to avoid double-flagging the same story.)

## Monitor routine

A weekly cloud routine (`gps-attkisson-monitor`, Sat 14:00 UTC) reads the Substack full-text feed
(primary) + podcast feed (secondary), scans the full post body for a drug/vaccine + event, flags
analyzable items against the filter above, and opens a PR ("Attkisson monitor: YYYY-MM-DD") with
candidate analyses — same PR-boundary pattern as `gps-weekly-research`. Analyzable items graduate
into the main `ARTICLE_QUEUE.md` when picked up interactively (where the parquet check happens).
