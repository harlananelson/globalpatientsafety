# Article registry for globalpatientsafety.com
#
# Read by scripts/build_static_site.R as the article source of truth. The `id`
# field must match the rendered HTML stem: app/static/{id}.html
#
# status: one of published or draft. Only `published` rows are built, and a
# published row with no matching HTML fails scripts/check_site_consistency.R.
#
# (The `id` used to also name a Shiny view module; that app is archived —
# see archive/rhino-app/README.md.)

box::use(
  tibble[tribble],
)

#' @export
ARTICLES <- tribble(
  ~id, ~title, ~subtitle, ~date, ~status, ~featured,
  # Featured: AEMS data primer — methodology-first face of the site (good
  # landing if MedDRA/MSSO or other licensors visit after a subscription ask).
  "aems",
  "Inside the AEMS Data: What 4.8 Million Reports Do and Don't Tell You",
  "The FDA's Adverse Event Monitoring System, the quarterly public data behind our analyses, and why the strongest raw 'signal' is usually an artifact — not a discovery.",
  "2026-07-14", "published", TRUE,
  "aav_gene_therapy_liver",
  "The Liver Is the Limit: Elevidys's Boxed Warning Is an AAV Class Effect",
  "Reading the fatal-hepatotoxicity boxed warning against the whole gene-therapy class in FAERS — the hepatic signal appears in every intravenously infused AAV (Elevidys, Zolgensma, Hemgenix, Roctavian) and vanishes in the two liver-sparing products (Luxturna, Casgevy). It tracks the delivery route, not the product.",
  "2026-07-21", "draft", FALSE,
  "glp1_alopecia",
  "A Moving Target: The GLP-1 Hair-Loss Signal Won't Hold Still",
  "Reproducing the claim that 'only semaglutide and tirzepatide flag for alopecia' quarter by quarter in FAERS — and watching Ozempic's signal fade while Zepbound's climbs, with the weight-loss confound left honestly unresolved.",
  "2026-07-14", "draft", FALSE,
  "carbidopa_levodopa_b6",
  "A Warning Built on 14 Cases: Does FAERS See the Carbidopa/Levodopa B6-Seizure Signal?",
  "The seizure the FDA warned about is invisible in disproportionality — but Vitamin B6 deficiency, the mechanism behind it, is one of the drug's loudest, most stable FAERS signals, years before the warning.",
  "2026-07-12", "draft", FALSE,
  "christine_cotton",
  "Tested Against VAERS: Christine Cotton's Safety Claims and the Post-Market Record",
  "The categories of adverse event the French biostatistician flagged in Pfizer's Comirnaty trial — cardiac, reproductive/menstrual, thrombotic, stroke — tested against the VAERS signal database with the project's 4-method consensus filter.",
  "2026-06-13", "published", FALSE,
  "shingles",
  "Independent Reanalysis: COVID/Shingles Vaccine Signals Amid FDA Publication Blocks",
  "Cardiac, neurological, and thrombotic signals in VAERS for nine COVID-19 vaccines and three shingles products — applied with the project's standard 4-method consensus filter.",
  "2026-05-12", "published", FALSE,
  "covid_vaccine",
  "COVID-19 Vaccine Safety Signals in VAERS",
  "Bayesian disproportionality analysis across nine vaccine products — TTS, myocarditis, neurological, and allergic signals with first-detection dates.",
  "2026-05-04", "published", FALSE
)
