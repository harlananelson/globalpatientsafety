# Synonym multi-token guard (novelty overmatch)

Handshake only. Do not merge as site code. Implement in `/projects/faers-mobi/` (API + UI). Deploy when good.

Follows GPS #82 reviewer pass. Linux finding: `reports/evaluation/FINDING-synonym-overmatch.md` (faers-mobi fed5378). MedDRA/UMLS synonyms include single-word fragments (`failure`, `inflammation`, …) guarded only by `nchar >= 5`; at 60% overlap they match almost any long label → over-calling `known`. Same flaw in UI `.event_in_label_expanded`.

## Scope

1. **API** `event_matches_label` (or equivalent): trim synonyms; require **≥2 informative tokens** (tokens of 3+ chars, not stop words) before synonym fallback. Single-word synonyms must not drive `known`.
2. **UI** `.event_in_label_expanded`: same guard (keep API/UI aligned).
3. Trim stray whitespace on synonym strings.
4. Regression test(s) pinning: a one-word synonym alone does not match; multi-word synonyms like `heart failure` still can.

**Do not** change the 70% PT word-overlap rule, placeholder `?` / `label_status`, or LoU indication filter in this slice.

## Verify (live)

- Re-run or cite the 4k-style comparison: known count drops only via the single-token path (Linux’s 337→322 class of result)
- Spot: pairs that were correctly known via multi-word synonyms stay known
- tzield×Nausea still n=319; `+`/`%20` stroke still 654
- Monitor / semantics tests still pass
- Optional: `<!-- role:linux -->` notes which of the 15 sample overcalls flipped

## Keep

- No new `/signals` query params
- No pay gate
- Codex may rescore after deploy (NOTIFY-CODEX.md)

## Out of scope

- API label alias fallback (tasigna→nilotinib)
- Related-label evidence field for subtypes
- Refetching 1,335 placeholder labels (faers-pipeline)
