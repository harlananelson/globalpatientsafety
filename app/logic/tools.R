# Tool registry for the globalpatientsafety.com portal.
#
# Add a tool by appending to the TOOLS tibble below. The portal module renders
# every row as a card. Set `status` to one of:
#   "live"        — a working link
#   "beta"        — works but may break
#   "coming_soon" — placeholder (no link, greyed out)

box::use(
  tibble[tibble, tribble],
)

#' @export
TOOLS <- tribble(
  ~name,                ~status,       ~url,                                       ~tagline,
  "faers.mobi",         "live",        "https://faers.mobi",
    "Current FAERS (2018-2024): time-stratified Bayesian and frequentist disproportionality. Watch semaglutide + gallbladder events, GLP-1 class effects, and recent signals evolve over quarters.",
  "aers.mobi",          "beta",        "https://aers.mobi",
    "Historical AERS (2004-2012): classic safety-signal case studies. Includes the Vioxx / myocardial infarction era and other pre-FAERS reports.",
  "pico-dag",           "live",        "https://picodag.globalpatientsafety.com",
    "PICO question -> UMLS concept graph -> code lists + data-pull specification. Compresses the front end of clinical research from weeks to an afternoon.",
  "VAERS vaccine safety", "coming_soon", NA_character_,
    "CDC VAERS (1990-present): same Bayesian + frequentist signal detection applied to vaccines. COVID-19, influenza, and all other vaccine types across 35 years of reports.",
  "Signal methods",     "coming_soon", NA_character_,
    "Reference documentation for the four disproportionality methods implemented across the apps: GPS/EBGM, PRR, ROR, BCPNN/IC.",
  "MAUDE device safety", "coming_soon", NA_character_,
    "FDA MAUDE (medical device adverse events) with the same time-stratified analysis used for drugs."
)
