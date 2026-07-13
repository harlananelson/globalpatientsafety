# Attkisson Health-Topic Monitor

Monitors Sharyl Attkisson's podcast for health/drug/vaccine topics that map to a
**FAERS/VAERS disproportionality analysis this site can actually run**, and feeds the
analyzable ones into the article queue.

## Source (what works, what doesn't)

- **Monitor feed (open, machine-readable):** `https://anchor.fm/s/dab6618/podcast/rss`
  — *The Sharyl Attkisson Podcast* (Anchor/Spotify host; 327+ episodes, ~weekly). This feed
  is fetchable; her website and `sharylattkisson.com/feed/` are **Cloudflare-blocked (403)** to
  automated fetchers, so do NOT rely on the site directly.
- **Second show:** *Full Measure After Hours* (separate feed; add later if wanted).
- **Transcripts:** the podcast feed carries **titles + descriptions only, no transcripts.** Her
  TV "(WATCH)" segments have transcripts on the site but those are behind Cloudflare. Full audio
  transcripts would require Whisper (heavier; not currently set up). Topic detection from
  title+description is the current method.

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

## Seen-episodes log (dedupe)

Latest scanned episode: **#337** (2026-07-10). The weekly routine appends newly-seen episode
numbers here so it doesn't re-flag the same ones.

## Monitor routine

A weekly cloud routine (`gps-attkisson-monitor`) reads the feed, flags health episodes against the
filter above, and opens a PR ("Attkisson monitor: YYYY-MM-DD") with analyzable episodes + candidate
analyses — same PR-boundary pattern as `gps-weekly-research`. Analyzable items graduate into the
main `ARTICLE_QUEUE.md` when you pick them up interactively (where the parquet check happens).
