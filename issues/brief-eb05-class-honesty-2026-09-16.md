# Brief honesty: peak EB05 vs EWMA; suppress singleton ATC class

Handshake only. Do not merge. Implement in `/projects/faers-mobi/` (+ signal brief template if shared). Deploy when good.

OpenAI review (2026-09-16) on the worked `tzield × Nausea` brief. Live-confirmed:

## 1. Peak EB05 mislabel (must fix)

`format=brief` Pair stanza: `peak EB05 = 7.81`.

Live `format=series` for the same pair: max quarterly **eb05 = 5.71** (2025Q2); that quarter’s **ewma_eb05 = 7.81**. Pair JSON `eb05` is also **7.8091** (matches EWMA peak, not quarterly peak).

LLMs will quote 7.81 as EB05 with confidence.

**Done-when:**

- Brief (and any “peak EB05” copy) must not call an EWMA (or Adj-only) value “peak EB05” without saying so.
- Prefer: report peak **quarterly EB05** and, if you keep the smoothed number, label it **peak EWMA EB05** (or Adj EB05 — match whatever the engine field actually is).
- Smoke: tzield×Nausea brief numbers match series columns; no “peak EB05 = 7.81” when series peak eb05 is 5.71.

## 2. Singleton ATC class stanza (must fix)

Live `format=class` for tzield×Nausea: `n_class_substances: 1`, `class_wide: false`, hint still says `1 drugs in Other antidiabetics flag Nausea … drug-specific`.

**Done-when:**

- If class has fewer than **3** distinct substances, omit the class_wide / “drug-specific vs class-wide” sentence from brief/PDF (and ideally return a short `class_note` or empty peers with no comparative claim).
- Grammar: “1 drug” not “1 drugs”.

## 3. Indication / product-use in profile top_eb05 (same slice if cheap)

Live `format=profile` top_eb05 leads with **Insulin therapy** (n=4, eb05 367) for Tzield. UI Treats/Low-info filters exist for humans; brief/profile tops do not apply them, so LLMs read “top signal = Insulin therapy.”

**Done-when (if Treats / low-info flags already in the engine):**

- Profile `top_eb05` / brief Profile top line exclude indication-confounded and low-info PTs by default (same spirit as UI defaults), **or** mark them `indication` / `low_info` so the brief cannot present them as bare “Top EB05.”
- If flags are not available without new compute, skip this bullet and note on the PR — do not invent a new classifier.

## Keep

- Hypothesis-not-causation disclaimer
- Bot-UA homepage markdown / text/plain (#72/#74) — do not “fix” by forcing HTML for ChatGPT-User
- No pay gate
- No new `/signals` query params unless needed for an existing filter

## Verify (live)

- tzield×Nausea `format=brief`: peak wording matches series; class comparative sentence absent or non-vacuous
- tzield `format=profile`: top_eb05 does not lead with bare Insulin therapy **or** it is explicitly flagged
- tzield×Nausea JSON still 200; n=319 unchanged

## Out of scope

- Rewriting Weber / trend math
- `llms-full.txt` / more discovery
- Documenting caseid dedup / DiAna (optional one sentence in API.md only if you touch docs anyway)
