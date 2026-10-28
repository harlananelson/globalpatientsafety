# Global Patient Safety Copilot agent

A workplace Copilot agent grounded in this project's catalog: clearing-house
architecture, tool suite, signal data flow, extract R/SQL, MedDRA use, and
Signal & Noise methods.

Adapted from `patientexperience/copilot/` (same packer machinery).

Rebuild the knowledge files when those sources change, then replace the files
on the published agent.

## Why `.txt` archives

Microsoft 365 Copilot Agent Builder (the **New agent** flow in the Copilot desktop
or web app) does not accept `.md` as an embedded knowledge type. Plain text (`.txt`)
is accepted. This folder:

1. Copies the needed study documents (markdown, R, SQL, Quarto) into `.txt`.
2. Packs them with txtarchive `--split-output` so each part stays inside Copilot's
   size and file-count limits.

The uploads are **plain text**, not a zip. Parse as txtarchive:

1. `# TABLE OF CONTENTS` / `DOCUMENT INDEX` = names, not bodies.
2. `# FILE N: …` then `BEGIN DOCUMENT: …` starts a document.
3. Search all parts; a name in part 1 may live in a later part.

### Limits

| Surface | Limit |
|---|---|
| Agent Builder | 20 embedded files; `.txt` up to 512 MB; instructions 8,000 characters; description 1,000; name 30 |
| Copilot Studio | Same instructions cap; up to 500 files |

## Create the agent (first time)

1. From the repo root:

   ```bash
   python tools/pack_copilot_knowledge.py
   ```

   Output: `copilot/knowledge/gps-copilot-archive_partN.txt`.

2. Microsoft 365 Copilot → **New agent** → **Skip to configure**.

3. Paste:

   | Field | File | Cap |
   |---|---|---|
   | Name | `GPS Clearing House` | 30 |
   | Description | `copilot/description.txt` | 1,000 |
   | Instructions | `copilot/instructions.txt` | 8,000 |

4. **Knowledge** → upload every `copilot/knowledge/gps-copilot-archive_part*.txt`.
   Wait until files leave "Preparing".

5. Turn **Only use specified sources** on.

6. Paste starter prompts from `copilot/starter-prompts.txt`.

7. Try: *How does FAERS XML become the signals.parquet that faers.mobi searches?*

8. **Share** with the organization.

## Refresh

```bash
python tools/pack_copilot_knowledge.py
```

Remove the old `gps-copilot-archive_part*.txt` knowledge files and upload the new set.
`copilot/pack-report.txt` lists the current parts and flags any over the token budget.
If the part count drops, delete leftover higher-numbered parts in the agent UI.

## What is packed

CLAUDE.md; decision log; noise-PT and signal-disconnection notes; article and
tool registries; this repo's `scripts/*.R` (site builder and MedDRA ingest);
Quarto article sources; R extract/transform code from sibling `faers-pipeline`
and `signal-compute`; and any `.sql` / `.R` you drop in `sql/` or `extracts/`
(this repo's home for extract queries). The file list is the table in
`copilot/pack.yaml` — add a new document there when it is written, then repack.

Not packed: rendered HTML/PDF, `static_site/`, telemetry logs, licensed MedDRA
`.asc`/parquet, private correspondence, renv, the archived Rhino app.

The packer is the `copilot-pack` package (a private package; install it from your own copy);
`tools/pack_copilot_knowledge.py` is a shim over it. Built output is git-ignored and is built where
it is used. On a machine approved for PHI, copy `copilot/pack.local.example.yaml` to `copilot/pack.local.yaml` to add
material that must not be committed.
