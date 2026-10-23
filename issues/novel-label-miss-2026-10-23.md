<!-- role:career -->
# Bug: `novel` flag misses labeled events (ferric carboxymaltose × Hypophosphataemia)

**Found:** 2026-10-23 6:07 PM ET, live curl.
`GET https://faers.mobi/signals?drug=ferric+carboxymaltose&event=Hypophosphataemia`
Headers: `X-FAERS-Through: 2025Q4`, `X-FAERS-Build: api-f88bd019b098 src-3ae1844`.

All 8 rows return `"novel":"novel"`, including `ferric carboxymaltose` (n=1954, EB05 1346.06), `injectafer` (n=1001) and `ferinject` (n=669). Symptomatic hypophosphatemia is in the Injectafer US label (Warnings and Precautions 5.2, plus Adverse Reactions). So this is a label-matching miss, not a new risk.

## Likely causes to check
1. Spelling: label text says "hypophosphatemia" (US), while the MedDRA PT is "Hypophosphataemia" (UK). Normalize ae/e and oe/e (and similar variants) before matching.
2. Brand/generic lookup: label text may be cached under one name only (Injectafer vs ferric carboxymaltose vs Ferinject, an EU brand with no US label).
3. Section coverage: make sure Warnings and Precautions and Adverse Reactions are both searched.

## Asks
- Fix the matching. ferric carboxymaltose and injectafer × Hypophosphataemia should return `labeled`.
- Run a regression sweep: count how many top-EB05 pairs flip from novel to labeled after the ae/e fix, and report the number in the deploy note.
- Add this pair to `scripts/monitor_faers_mobi.sh`.
- Usual rule: push first, put the commit SHA in the deploy note, and check that the `X-FAERS-Build` src matches origin/main.

## Related observation (no action needed in this PR)
`drug=ferric carboxymaltose` expands to ingredient `iron`, so it also returns venofer, auryxia, iron sucrose, etc. That is consistent with the #96 ingredient view, but the ingredient should be the specific salt (ferric carboxymaltose), not elemental iron. Folding into #96 Ask 2.
