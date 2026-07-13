# Series framing (sketch): "Signal & Noise"

A methodology series for globalpatientsafety.com. Sketch for review — not built yet. When approved
it can become a `/methods` nav landing page (same mechanism as the AEMS tab) that indexes the
installments, and each article carries a small "part of the Signal & Noise series" banner.

## Name

**Primary:** **Signal & Noise — Reading FDA Adverse-Event Data**
(hook + plain-English descriptor; "signal" is the pharmacovigilance term of art, "noise" is the
whole point of the series.)

Alternatives if you'd rather: *Field Notes on FDA Safety Data* · *The Disproportionality Field Guide*
· *What the Reports Can't Tell You* · *Reading the Reports*.

## Positioning (the one-line premise)

> The same openness that makes FDA's adverse-event data valuable makes it easy to fool yourself.
> This is a working statistician's field guide to reading FAERS and VAERS **without** getting
> fooled — one real signal, one trap, one fix at a time.

## Standing intro — short banner (top of each installment)

> **Signal & Noise** is a series on *how to read* FDA adverse-event data, not on what any drug does
> to any patient. Each piece takes one current signal and uses it to show one way the data misleads —
> and the cheap check that catches it. Methods, not medicine; questions, not verdicts.

## Standing intro — landing-page version (fuller)

> FAERS and VAERS are public, enormous, and free — and that is exactly why they are so easy to
> misuse. Anyone can compute a disproportionality score; almost no one stops to ask whether the
> number means what it seems to. This series is written from the methods seat, not the clinic. It is
> by a statistician, not a physician, and it makes no claims about whether a drug *causes* anything.
> What it does is smaller and more durable: take one real, often newsworthy safety signal, show the
> naive reading, and then show the one check — a trajectory, a comparison, a date — that changes the
> answer. Every installment ends with a rule you can carry to the next signal. The house method never
> changes (four disproportionality measures — GPS/EBGM, PRR, ROR, BCPNN/IC — with a fixed rule of
> EB05 ≥ 2 and at least two of four agreeing), so the only variable is the trap being illustrated.

## The shape of every installment

1. **The hook** — a real signal or public claim (often something in the news).
2. **The naive read** — what the number says at face value; why it's tempting.
3. **The check that breaks it** — trajectory / class comparison / a known date / observed counts.
4. **The rule** — the transferable lesson, stated so it applies to the *next* signal.

Fixed constraints stated once: 4-method rule, "can and cannot show" caveat, confounding-by-indication
named plainly, observed counts beside every EB05.

## Installment lineup (gotcha → example → working title → status)

| # | The gotcha (the lesson) | Worked example | Working title | Status |
|---|---|---|---|---|
| 1 | **Survivability ≠ causation** — a signal can "survive" a whole class on notoriety alone; the emergence *timing* refutes it (a publication/label date = natural experiment). | GLP-1s → NAION | *When a Signal "Survives" the Class but the Calendar Says Notoriety* | verified, queued #2 — **best flagship** |
| 2 | **The raw leaderboard lies** — top-EB05 pairs are dominated by indication, route, litigation, and definitional effects. | AEMS top signals | *Inside the AEMS Data* (already a page) | drafted (AEMS tab) — retrofit into series |
| 3 | **Signals are non-stationary** — single-quarter claims move with prescribing volume + media; plot the trajectory. | GLP-1 → alopecia | *A Moving Target* | drafted, in review |
| 4 | **The rare outcome is invisible; the mechanism is loud** — look upstream of the fatal endpoint. | carbidopa/levodopa → B6/seizure; AAV → liver | *A Warning Built on 14 Cases* / *The Liver Is the Limit* | drafted, in review |
| 5 | **Don't cherry-pick the max quarter** — it manufactures signals for rare-event drugs; use latest-quarter + trajectory. | (method note, drawn from #1/#4) | *The Quarter You Choose* | idea |
| 6 | **Protopathic / reverse causation** — the disease causes the prescription, then "signals" as an effect. | pancreatic carcinoma on a weight-loss drug | *Which Way Does the Arrow Point?* | idea |
| 7 | **Coding & step-change artifacts** — a 1→175 single-quarter jump is a coding/reporting event, not biology. | Ozempic "cyclic vomiting syndrome" | *The Overnight Epidemic* | idea |

(#5–7 are thin method notes today; they can be short pieces or folded into the fuller ones.)

## How it changes the backlog

Nothing gets rewritten — most drafts already carry a methodology thread. The series just makes it the
explicit through-line: the drug is the example, the method is the product. Publish order can stay as
the queue has it (shingles is a clinical-example piece that can *also* wear a series banner if it
teaches a lesson — e.g. live-vs-recombinant as a "use a within-class comparison as its own control"
method note).

## If you like it — next steps (not done yet)

- Pick the name.
- Build a `/methods` (or `/signal-and-noise`) static landing page: the fuller intro + the installment
  table, wired into the top nav like AEMS. One `.qmd` + one nav line + a STANDALONE_PAGES row.
- Add the short banner partial to each series `.qmd`.
- Draft installment #1 (NAION) first, under the banner, as the series opener.
