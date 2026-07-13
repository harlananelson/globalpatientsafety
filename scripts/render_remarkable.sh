#!/usr/bin/env bash
# Render articles to reMarkable Paper Pro-sized PDFs and optionally upload them to
# the reMarkable cloud /globalpatientsafety folder.
#
# reMarkable Paper Pro screen is 4:3 (2160x1620 px @ 229 ppi) = 179.6 x 239.6 mm.
# No standard paper size matches that aspect, so we render via Quarto's typst
# format, then patch the generated .typ page directive to the exact canvas and
# recompile with `quarto typst`.
#
# Two gotchas this handles (both cost real debugging once):
#   1. Quarto picks the SYSTEM R (/usr/lib/R, no rmarkdown) unless QUARTO_R points
#      at the nix R. We force QUARTO_R="$(which R)".
#   2. The project renv .Rprofile hides the nix packages; rendering a COPY from
#      /tmp (outside the repo) sidesteps renv entirely. Article data paths are
#      absolute, so location doesn't matter.
#
# Requires the dev shell (quarto + nix R with rmarkdown/knitr/arrow/gt):
#   nix develop --command bash scripts/render_remarkable.sh [--upload]
set -euo pipefail

RM_W="179.6mm"; RM_H="239.6mm"
PROJ="$(cd "$(dirname "$0")/.." && pwd)"
OUT="/tmp/rm_pdfs"; mkdir -p "$OUT"
export QUARTO_R="$(command -v R)"
echo "QUARTO_R=$QUARTO_R"

# id (qmd basename in articles/)  =>  reMarkable document name
ARTICLE_IDS=(
  "carbidopa-levodopa-b6-seizures"
  "glp1-alopecia"
  "aav-gene-therapy-liver"
  "aems-analysis"
)
declare -A TITLES=(
  ["carbidopa-levodopa-b6-seizures"]="Carbidopa-Levodopa B6 Seizures (FAERS)"
  ["glp1-alopecia"]="GLP-1 Alopecia Signal (FAERS)"
  ["aav-gene-therapy-liver"]="AAV Gene Therapy Liver (FAERS)"
  ["aems-analysis"]="Inside the AEMS Data"
)

for id in "${ARTICLE_IDS[@]}"; do
  title="${TITLES[$id]}"
  echo "== rendering $id =="
  cp "$PROJ/articles/$id.qmd" "$OUT/$id.qmd"
  ( cd "$OUT" && quarto render "$id.qmd" --to typst -M keep-typ:true >/dev/null 2>&1 )
  sed -i "s/  paper: \"us-letter\",/  width: $RM_W, height: $RM_H,/" "$OUT/$id.typ"
  ( cd "$OUT" && quarto typst compile "$id.typ" "$title.pdf" >/dev/null 2>&1 )
  printf '  -> %s.pdf (%s)\n' "$title" "$(du -h "$OUT/$title.pdf" | cut -f1)"
done

if [[ "${1:-}" == "--upload" ]]; then
  echo "== uploading to reMarkable /globalpatientsafety =="
  for id in "${ARTICLE_IDS[@]}"; do
    title="${TITLES[$id]}"
    nix run nixpkgs#rmapi -- put "$OUT/$title.pdf" /globalpatientsafety/ 2>&1 \
      | grep -viE "unpack|warning:|response|Unauthorized|download|fetched|copying|this path|^$" | tail -1
  done
fi
echo "Done. PDFs in $OUT"
