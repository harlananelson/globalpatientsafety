# Inbound: novelty / indication / query decode / class flags (retrospective)

Handshake only. Do not merge as site code. **Already deployed** on faers.mobi (`59274bf` family, 2026-09-17 ~20:03 UTC) before a GPS ticket existed — this PR is the missing record per `issues/inbound-change-protocol.md`.

Origin: Codex review loop on faers-mobi, not a Career outbound slice.

## What changed (from faers-mobi DEPLOY-LOG)

| Area | Before | After |
|------|--------|--------|
| Query `+` | `event=ischaemic+stroke` → 0 rows | `+` decodes as space (same as `%20`) |
| Placeholder labels | `novel` + `label_cached: true` with empty text | `?` / `label_status` empty\|missing\|cached |
| Novelty match | whole-PT substring | word overlap + MedDRA synonyms (UI rule) |
| Indication flag | matched Limitations of Use / negations | limitations + negated sentences excluded |
| `format=class` flags | `{}` after #81 | booleans via `flag_pairs` |

## Career visibility smoke (2026-09-17)

- `event=ischaemic+stroke` and `event=ischaemic%20stroke` both return rows
- `format=class` tzield×Nausea: `indication` / `low_info` are **bool**
- `format=label` tzield×Nausea: `label_status=cached`, `novel=known`, n=319
- Evaluation: `NOTIFY-CODEX.md` / rescore artefacts on faers-mobi (Codex reassessment via Harlan relay)

## Keep

- No further API shape change from this PR
- Pay gate parked
- Codex continues frozen suite; do not weaken assertions

## Verify

Already live — this ticket closes the process hole. Linux `<!-- role:linux -->` can confirm commit list + point at DEPLOY-LOG. Career assessment above stands unless Linux corrects numbers.
