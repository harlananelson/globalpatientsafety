# Article registry for globalpatientsafety.com
#
# Each row is one published article. The `id` field must match the
# view module name: app/view/article_{id}.R
#
# status: "published" | "draft"

box::use(
  tibble[tribble],
)

#' @export
ARTICLES <- tribble(
  ~id,               ~title,                                         ~subtitle,                                                ~date,          ~status,   ~featured,
  "shingles",
    "Independent Reanalysis: COVID/Shingles Vaccine Signals Amid FDA Publication Blocks",
    "Cardiac, neurological, and thrombotic signals in VAERS for nine COVID-19 vaccines and three shingles products — applied with the project's standard 4-method consensus filter.",
    "2026-05-12",    "published",  TRUE,
  "covid_vaccine",
    "COVID-19 Vaccine Safety Signals in VAERS",
    "Bayesian disproportionality analysis across nine vaccine products — TTS, myocarditis, neurological, and allergic signals with first-detection dates.",
    "2026-05-04",    "published",  FALSE
)
