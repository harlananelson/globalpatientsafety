#!/usr/bin/env python3
"""ClinicalTrials.gov pipeline endpoint for globalpatientsafety.com.

GET /pipeline?sponsor=Sanofi
  format omitted + Accept: text/html  -> HTML (the human page)
  format omitted otherwise             -> JSON
  format=json | brief | html
  role omitted                         -> lead sponsor only
  role=collaborator | any              -> collaborator only, or either

Registry facts only. Study ids are copied from the API response.
A timeout or a 5xx from ClinicalTrials.gov is 503/502, never an empty 200.

  python3 scripts/gps_pipeline.py --bind 127.0.0.1 --port 3843
"""

from __future__ import annotations

import argparse
import json
import re
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
from collections import Counter
from difflib import get_close_matches
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from typing import Any, Callable

CT_URL = "https://clinicaltrials.gov/api/v2/studies"
SOURCE = "clinicaltrials.gov/api/v2"
DISCLAIMER = (
    "Registry facts from ClinicalTrials.gov. Not efficacy or safety conclusions."
)
NCT_RE = re.compile(r"^NCT[0-9]{8}$")
USER_AGENT = "globalpatientsafety-pipeline/1 (+https://globalpatientsafety.com/pipeline)"

STATUSES = (
    "RECRUITING",
    "ENROLLING_BY_INVITATION",
    "NOT_YET_RECRUITING",
    "ACTIVE_NOT_RECRUITING",
    "COMPLETED",
    "SUSPENDED",
    "TERMINATED",
    "WITHDRAWN",
    "UNKNOWN",
    "AVAILABLE",
    "NO_LONGER_AVAILABLE",
    "TEMPORARILY_NOT_AVAILABLE",
    "APPROVED_FOR_MARKETING",
    "WITHHELD",
)
PHASES = ("EARLY_PHASE1", "PHASE1", "PHASE2", "PHASE3", "PHASE4", "NA")
# What a pipeline page means by "currently studying" when no status was asked for.
ONGOING = (
    "RECRUITING",
    "ENROLLING_BY_INVITATION",
    "NOT_YET_RECRUITING",
    "ACTIVE_NOT_RECRUITING",
)
STATUS_RANK = {name: i for i, name in enumerate(STATUSES)}
PHASE_RANK = {name: i for i, name in enumerate(
    ("PHASE4", "PHASE3", "PHASE2", "PHASE1", "EARLY_PHASE1", "NA")
)}

# Seed list for the picker. Free text still works; names are not expanded
# into competitors.
ROLES = ("lead", "collaborator", "any")
ROLE_TEXT = {
    "lead": (
        "Lead sponsor only. The name has to appear in the lead sponsor, "
        "including a company-family name such as Sanofi Pasteur. "
        "Collaborator-only trials are not included."
    ),
    "collaborator": (
        "Collaborator only. The name has to appear on a collaborator, "
        "and the lead sponsor is someone else."
    ),
    "any": (
        "Lead or collaborator. This is the ClinicalTrials.gov sponsor search."
    ),
}
SPONSORS = (
    "Pfizer", "Sanofi", "Novartis", "Roche", "Genentech",
    "Johnson & Johnson", "Janssen", "Merck", "AstraZeneca",
    "GlaxoSmithKline", "Eli Lilly", "Novo Nordisk", "Amgen", "AbbVie",
    "Bristol-Myers Squibb", "Gilead", "Bayer", "Boehringer Ingelheim",
    "Takeda", "Regeneron", "Biogen", "Moderna", "BioNTech", "Vertex",
    "CSL Behring", "Teva", "Astellas", "Daiichi Sankyo", "Eisai", "Otsuka",
    "UCB", "Ipsen", "Servier", "Alnylam", "Incyte", "Alexion", "BeiGene",
    "Sandoz", "Organon", "Viatris", "Horizon Therapeutics", "Seagen",
    "Genmab", "argenx", "Ionis", "BioMarin", "Sarepta", "Insmed",
    "Ultragenyx", "Blueprint Medicines",
)

DEFAULT_LIMIT = 50
MAX_LIMIT = 200
TIMEOUT_S = 20
CACHE_TTL_S = 600

Opener = Callable[..., Any]
_cache: dict[str, tuple[float, dict[str, Any]]] = {}
_cache_lock = threading.Lock()


class UpstreamError(Exception):
    def __init__(self, status: int, message: str) -> None:
        super().__init__(message)
        self.status = status
        self.message = message


def _now() -> str:
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())


def _as_list(value: Any) -> list[str]:
    if value is None:
        return []
    if isinstance(value, str):
        return [value] if value else []
    if isinstance(value, list):
        out = []
        for item in value:
            if isinstance(item, str) and item:
                out.append(item)
            elif isinstance(item, dict) and item.get("name"):
                out.append(str(item["name"]))
        return out
    return []


def _name_has(name: str, query: str) -> bool:
    """True when the registry name contains the query, ignoring case."""
    folded = query.casefold()
    return bool(folded) and folded in name.casefold()


def _study_role(lead: str, collaborators: list[str], query: str) -> str:
    if _name_has(lead, query):
        return "lead"
    if any(_name_has(name, query) for name in collaborators):
        return "collaborator"
    return ""


def shape_study(raw: dict[str, Any], sponsor_query: str) -> dict[str, Any] | None:
    """Copy one study. Return None when the registry did not send an NCT id."""
    ps = raw.get("protocolSection") or {}
    nct = str((ps.get("identificationModule") or {}).get("nctId") or "")
    if not NCT_RE.match(nct):
        return None
    status_mod = ps.get("statusModule") or {}
    design = ps.get("designModule") or {}
    module = ps.get("sponsorCollaboratorsModule") or {}
    sponsor = module.get("leadSponsor") or {}
    collaborators = []
    for item in module.get("collaborators") or []:
        if isinstance(item, dict) and item.get("name"):
            collaborators.append(str(item["name"]))
    lead = str(sponsor.get("name") or "")
    ident = ps.get("identificationModule") or {}
    conditions = _as_list((ps.get("conditionsModule") or {}).get("conditions"))
    interventions = []
    for item in (ps.get("armsInterventionsModule") or {}).get("interventions") or []:
        if isinstance(item, dict) and item.get("name"):
            interventions.append(str(item["name"]))
        elif isinstance(item, str) and item:
            interventions.append(item)
    phases = _as_list(design.get("phases"))
    return {
        "nct_id": nct,
        "title": str(ident.get("briefTitle") or ""),
        "status": str(status_mod.get("overallStatus") or ""),
        "phases": phases,
        "conditions": conditions,
        "interventions": interventions,
        "lead_sponsor": lead,
        "role": _study_role(lead, collaborators, sponsor_query),
        "url": f"https://clinicaltrials.gov/study/{nct}",
    }


def _sort_key(study: dict[str, Any]) -> tuple:
    phases = study["phases"] or ["NA"]
    phase_rank = min(PHASE_RANK.get(p, 9) for p in phases)
    return (
        STATUS_RANK.get(study["status"], 50),
        phase_rank,
        study["title"].lower(),
        study["nct_id"],
    )


def shape_payload(payload: dict[str, Any], sponsor_query: str, retrieved_at: str,
                   role_filter: str = "lead") -> dict[str, Any]:
    studies = []
    for raw in payload.get("studies") or []:
        if not isinstance(raw, dict):
            continue
        study = shape_study(raw, sponsor_query)
        if study is not None:
            studies.append(study)
    # n_studies stays the registry totalCount. The request has to ask
    # ClinicalTrials.gov for this role, or that total still counts the
    # other role.
    if role_filter == "any":
        for study in studies:
            if study["role"] not in ("lead", "collaborator"):
                study["role"] = "collaborator"
    else:
        studies = [study for study in studies if study["role"] == role_filter]
    studies.sort(key=_sort_key)
    by_phase: Counter[str] = Counter()
    by_status: Counter[str] = Counter()
    sponsors: Counter[str] = Counter()
    for study in studies:
        by_status[study["status"] or "UNKNOWN"] += 1
        sponsors[study["lead_sponsor"]] += 1 if study["lead_sponsor"] else 0
        labels = study["phases"] or ["NA"]
        for label in labels:
            by_phase[label] += 1
    matched = [name for name, _n in sponsors.most_common() if name]
    exact = [name for name in matched if name.casefold() == sponsor_query.casefold()]
    total = payload.get("totalCount")
    try:
        n_studies = int(total) if total is not None else len(studies)
    except (TypeError, ValueError):
        n_studies = len(studies)
    return {
        "sponsor_query": sponsor_query,
        "role_filter": role_filter,
        "sponsor_matched": (exact or matched or [None])[0],
        "matched_sponsors": matched,
        "retrieved_at": retrieved_at,
        "source": SOURCE,
        "n_studies": n_studies,
        "n_returned": len(studies),
        "counts_of": "returned",
        "sort": "recruiting_then_later_phase",
        "by_phase": dict(by_phase),
        "by_status": dict(by_status),
        "next_page_token": payload.get("nextPageToken") or None,
        "studies": studies,
        "disclaimer": DISCLAIMER,
    }


def suggestions_for(sponsor: str) -> list[str]:
    hits = get_close_matches(sponsor, SPONSORS, n=5, cutoff=0.55)
    low = sponsor.casefold()
    for name in SPONSORS:
        folded = name.casefold()
        if low and (low in folded or folded in low) and name not in hits:
            hits.append(name)
    return hits[:5]


def _essie_phrase(text: str) -> str:
    """Quote a sponsor so Essie treats it as one phrase, not separate words."""
    cleaned = text.replace('"', " ").replace("[", " ").replace("]", " ")
    cleaned = re.sub(r"\s+", " ", cleaned).strip()
    return '"' + cleaned + '"'


def ct_request_url(sponsor: str, status: str, phase: str, limit: int,
                   page_token: str, role: str = "lead") -> str:
    # query.spons matches lead, collaborator, and organization name.
    # The default asks only LeadSponsorName, so totalCount matches the rows.
    # A quoted phrase still matches a family name that contains it
    # ("Sanofi" matches "Sanofi Pasteur, a Sanofi Company").
    query = {
        "pageSize": str(limit),
        "countTotal": "true",
        "fields": ",".join((
            "NCTId", "BriefTitle", "OverallStatus", "Phase",
            "LeadSponsorName", "CollaboratorName", "Condition", "InterventionName",
        )),
    }
    phrase = _essie_phrase(sponsor)
    advanced = []
    if role == "lead":
        advanced.append(f"AREA[LeadSponsorName]{phrase}")
    elif role == "collaborator":
        advanced.append(f"AREA[CollaboratorName]{phrase}")
    else:
        query["query.spons"] = sponsor
    if status:
        query["filter.overallStatus"] = status
    if phase:
        advanced.append(f"AREA[Phase]{phase}")
    if advanced:
        query["filter.advanced"] = " AND ".join(advanced)
    if page_token:
        query["pageToken"] = page_token
    return CT_URL + "?" + urllib.parse.urlencode(query)


def fetch_payload(sponsor: str, status: str, phase: str, limit: int,
                  page_token: str, opener: Opener | None = None,
                  role: str = "lead") -> dict[str, Any]:
    url = ct_request_url(sponsor, status, phase, limit, page_token, role)
    key = url
    now = time.time()
    with _cache_lock:
        hit = _cache.get(key)
        if hit and now - hit[0] < CACHE_TTL_S:
            return hit[1]
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT, "Accept": "application/json"})
    open_ = opener or urllib.request.urlopen
    try:
        with open_(req, timeout=TIMEOUT_S) as resp:
            raw = resp.read().decode("utf-8")
            code = getattr(resp, "status", 200)
    except urllib.error.HTTPError as exc:
        # 4xx from the registry is still an upstream failure for us: do not
        # turn it into an empty success.
        exc.close()
        status_out = 503 if exc.code == 429 else 502
        raise UpstreamError(status_out, f"ClinicalTrials.gov returned HTTP {exc.code}") from exc
    except (TimeoutError, urllib.error.URLError) as exc:
        raise UpstreamError(503, "ClinicalTrials.gov did not respond") from exc
    if code >= 500:
        raise UpstreamError(502, f"ClinicalTrials.gov returned HTTP {code}")
    try:
        payload = json.loads(raw)
    except json.JSONDecodeError as exc:
        raise UpstreamError(502, "ClinicalTrials.gov returned a response that was not JSON") from exc
    if not isinstance(payload, dict):
        raise UpstreamError(502, "ClinicalTrials.gov returned an unexpected response")
    with _cache_lock:
        _cache[key] = (time.time(), payload)
    return payload


def validate(args: dict[str, str]) -> dict[str, Any] | UpstreamError | dict[str, Any]:
    """Return a query dict, or an error dict with status 400."""
    sponsor = re.sub(r"\s+", " ", (args.get("sponsor") or "").strip())
    status = (args.get("status") or "").strip().upper()
    phase = (args.get("phase") or "").strip().upper()
    # ALL is an explicit "do not filter". Empty means the ongoing default.
    token = (args.get("pagetoken") or args.get("page_token") or "").strip()
    fmt = (args.get("format") or "").strip().lower()
    role = (args.get("role") or "").strip().lower()
    if fmt not in ("", "json", "brief", "html"):
        return {"status": 400, "error": "unknown format", "allowed": ["json", "brief", "html"]}
    if role == "":
        role = "lead"
    elif role not in ROLES:
        return {"status": 400, "error": "unknown role", "allowed": list(ROLES)}
    if status and status != "ALL" and status not in STATUSES:
        return {"status": 400, "error": "unknown status", "allowed": ["ALL", *STATUSES]}
    if phase and phase not in PHASES:
        return {"status": 400, "error": "unknown phase", "allowed": list(PHASES)}
    raw_limit = (args.get("limit") or "").strip()
    if raw_limit == "":
        limit = DEFAULT_LIMIT
    else:
        try:
            limit = int(raw_limit)
        except ValueError:
            return {"status": 400, "error": "limit must be an integer",
                    "allowed": [f"1..{MAX_LIMIT}"]}
        if limit < 1 or limit > MAX_LIMIT:
            return {"status": 400, "error": f"limit must be from 1 to {MAX_LIMIT}",
                    "allowed": [f"1..{MAX_LIMIT}"]}
    if len(sponsor) > 200:
        return {"status": 400, "error": "sponsor is too long"}
    return {
        "sponsor": sponsor,
        "status": status,
        "phase": phase,
        "limit": limit,
        "page_token": token,
        "format": fmt,
        "role": role,
    }


def _esc(text: str) -> str:
    return (text.replace("&", "&amp;").replace("<", "&lt;")
            .replace(">", "&gt;").replace('"', "&quot;"))


def _status_options(selected: str) -> str:
    parts = [
        '<option value=""' + ("" if selected else " selected") + ">Ongoing</option>",
        '<option value="ALL"' + (" selected" if selected == "ALL" else "") + ">Any status</option>",
    ]
    for value in STATUSES:
        sel = " selected" if value == selected else ""
        parts.append(f'<option value="{_esc(value)}"{sel}>{_esc(value)}</option>')
    return "\n".join(parts)


def _options(values: tuple[str, ...], selected: str) -> str:
    parts = ['<option value="">Any</option>']
    for value in values:
        sel = " selected" if value == selected else ""
        parts.append(f'<option value="{_esc(value)}"{sel}>{_esc(value)}</option>')
    return "\n".join(parts)


def _datalist() -> str:
    return "\n".join(f'<option value="{_esc(name)}"></option>' for name in SPONSORS)


def html_document(title: str, body: str, notice: str = "") -> str:
    alert = ""
    if notice:
        alert = (
            '<p class="notice" role="status">' + _esc(notice) + "</p>"
        )
    return f"""<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>{_esc(title)}</title>
  <meta name="description" content="Machine path: GET /pipeline?sponsor= returns JSON, and format=brief returns markdown. {DISCLAIMER}">
  <link rel="alternate" type="text/markdown" href="/pipeline.md">
  <link rel="alternate" href="/llms.txt" title="llms.txt">
  <link rel="service-desc" type="application/json" href="/openapi.json">
  <link rel="icon" href="/favicon.ico">
  <style>
    body {{ font-family: Inter, -apple-system, system-ui, sans-serif; background: #f8fafc; color: #1a2332; margin: 0; }}
    a {{ color: #0b4f6a; }}
    .skip-link {{ position: absolute; left: 0; top: -3rem; background: #fff; color: #0b4f6a; padding: .5rem 1rem; z-index: 5; }}
    .skip-link:focus {{ top: 0; }}
    nav {{ background: #1a2332; color: #fff; padding: .75rem 1.25rem; }}
    nav a {{ color: #d7eef8; margin-right: 1rem; }}
    .llm-access {{ background: #e7eef3; color: #1a2332; padding: .75rem 1.25rem; }}
    .llm-access a {{ color: #0b4f6a; }}
    main {{ max-width: 960px; margin: 0 auto; padding: 1.5rem 1.25rem 3rem; }}
    h1 {{ font-weight: 500; }}
    label {{ display: block; font-weight: 600; margin: .8rem 0 .25rem; }}
    input, select {{ font: inherit; padding: .4rem .5rem; width: min(100%, 28rem); border: 1px solid #334155; border-radius: 4px; background: #fff; color: #1a2332; }}
    button {{ font: inherit; margin-top: 1rem; background: #0f4c6e; color: #fff; border: 0; border-radius: 4px; padding: .5rem 1rem; }}
    table {{ border-collapse: collapse; width: 100%; margin-top: 1rem; background: #fff; }}
    th, td {{ border: 1px solid #cbd5e1; padding: .4rem .5rem; text-align: left; vertical-align: top; }}
    th {{ background: #e7eef3; }}
    .notice {{ background: #fff7ed; border: 1px solid #9a3412; padding: .75rem 1rem; }}
    footer {{ color: #334155; padding: 1rem 1.25rem 2rem; }}
    footer a {{ color: #0b4f6a; }}
    :focus-visible {{ outline: 3px solid #0b4f6a; outline-offset: 2px; }}
    nav :focus-visible {{ outline-color: #b9e2f5; }}
  </style>
</head>
<body>
<a class="skip-link" href="#main">Skip to content</a>
<nav aria-label="Site">
  <a href="/">Global Patient Safety</a>
  <a href="/pipeline" aria-current="page">Pipeline analysis</a>
  <a href="/articles">Articles</a>
  <a href="/api">API</a>
</nav>
<div class="llm-access">
  <strong>LLM / API access.</strong>
  <a href="/api">API</a> ·
  <a href="/llms.txt">llms.txt</a> ·
  <a href="/mcp.md">MCP</a> ·
  <a href="/pipeline.md">Markdown</a>
</div>
<main id="main" tabindex="-1">
  <h1>{_esc(title)}</h1>
  {alert}
  {body}
</main>
<footer>
  <p>{_esc(DISCLAIMER)} <a href="/accessibility">Accessibility</a></p>
</footer>
</body>
</html>
"""


def _role_options(selected: str) -> str:
    options = (
        ("lead", "Lead sponsor"),
        ("collaborator", "Collaborator"),
        ("any", "Lead or collaborator"),
    )
    parts = []
    for value, label in options:
        sel = " selected" if value == selected else ""
        parts.append(f'<option value="{value}"{sel}>{label}</option>')
    return "\n".join(parts)


def form_html(sponsor: str = "", status: str = "", phase: str = "",
              role: str = "lead") -> str:
    return f"""
<form method="get" action="/pipeline">
  <label for="sponsor">Company or sponsor</label>
  <input id="sponsor" name="sponsor" list="sponsor-list" value="{_esc(sponsor)}" autocomplete="off" required>
  <datalist id="sponsor-list">
    {_datalist()}
  </datalist>
  <label for="role">Sponsor role</label>
  <select id="role" name="role">
    {_role_options(role)}
  </select>
  <label for="status">Status</label>
  <select id="status" name="status">
    {_status_options(status)}
  </select>
  <label for="phase">Phase</label>
  <select id="phase" name="phase">
    {_options(PHASES, phase)}
  </select>
  <div><button type="submit">Show pipeline</button></div>
</form>
"""


def _suggest_href(name: str, role: str) -> str:
    query = {"sponsor": name}
    if role != "lead":
        query["role"] = role
    return "/pipeline?" + urllib.parse.urlencode(query)


def results_html(doc: dict[str, Any], status: str, phase: str) -> str:
    sponsor = doc["sponsor_query"]
    role = doc.get("role_filter") or "lead"
    if doc["n_studies"] == 0:
        hints = suggestions_for(sponsor)
        hint_html = ""
        if hints:
            links = ", ".join(
                f'<a href="{_esc(_suggest_href(name, role))}">{_esc(name)}</a>'
                for name in hints
            )
            hint_html = f"<p>Did you mean {links}?</p>"
        where = {
            "lead": " as lead sponsor",
            "collaborator": " as a collaborator",
            "any": " as lead or collaborator",
        }[role]
        body = form_html(sponsor, status, phase, role) + (
            f"<p>No studies found for {_esc(sponsor)}{where}.</p>{hint_html}"
            "<p>The name has to match the sponsor string ClinicalTrials.gov stores. "
            "Nothing was filled in from another company.</p>"
            f"<p>{_esc(ROLE_TEXT[role])}</p>"
        )
        return html_document(f"No studies found for {sponsor}", body)
    matched = ", ".join(doc["matched_sponsors"]) or doc["sponsor_query"]
    rows = []
    for study in doc["studies"]:
        phases = ", ".join(study["phases"]) or "NA"
        cond = ", ".join(study["conditions"])
        drugs = ", ".join(study["interventions"])
        rows.append(
            "<tr>"
            f'<td><a href="{_esc(study["url"])}">{_esc(study["nct_id"])}</a></td>'
            f'<td>{_esc(study["title"])}</td>'
            f'<td>{_esc(study["status"])}</td>'
            f'<td>{_esc(phases)}</td>'
            f'<td>{_esc(cond)}</td>'
            f'<td>{_esc(drugs)}</td>'
            f'<td>{_esc(study["role"])}</td>'
            "</tr>"
        )
    phase_bits = ", ".join(f"{k} {v}" for k, v in sorted(doc["by_phase"].items())) or "none"
    status_bits = ", ".join(f"{k} {v}" for k, v in sorted(doc["by_status"].items())) or "none"
    body = form_html(sponsor, status, phase, role) + f"""
<p>{_esc(ROLE_TEXT[role])}</p>
<p>Matched sponsor(s): {_esc(matched)}. Data pulled {_esc(doc["retrieved_at"])}.
Showing {doc["n_returned"]} of {doc["n_studies"]} matching studies.
{"Ongoing studies only. Choose Any status to include completed and stopped trials." if doc.get("status_default") else "Phase and status counts below are for the studies shown."}</p>
<p>By phase (shown): {_esc(phase_bits)}</p>
<p>By status (shown): {_esc(status_bits)}</p>
<table>
  <caption>ClinicalTrials.gov studies for {_esc(sponsor)}</caption>
  <thead>
    <tr>
      <th scope="col">NCT id</th>
      <th scope="col">Title</th>
      <th scope="col">Status</th>
      <th scope="col">Phase</th>
      <th scope="col">Conditions</th>
      <th scope="col">Interventions</th>
      <th scope="col">Role</th>
    </tr>
  </thead>
  <tbody>
    {''.join(rows)}
  </tbody>
</table>
"""
    return html_document(f"Pipeline analysis: {sponsor}", body)


def brief_text(doc: dict[str, Any]) -> str:
    lines = [
        f"# Clinical pipeline: {doc['sponsor_query']}",
        "",
        DISCLAIMER,
        "",
        f"Retrieved: {doc['retrieved_at']}",
        f"Source: {doc['source']}",
        f"Matching studies: {doc['n_studies']}",
        f"Showing: {doc['n_returned']} (recruiting first, then later phase)",
        "Scope: ongoing studies." if doc.get("status_default") else "Scope: the status filter in the query.",
        ROLE_TEXT[doc.get("role_filter") or "lead"],
    ]
    if doc["matched_sponsors"]:
        lines.append("Matched sponsor(s): " + ", ".join(doc["matched_sponsors"]))
    if doc["n_studies"] == 0:
        hints = suggestions_for(doc["sponsor_query"])
        lines.append("")
        lines.append(f"No studies found for {doc['sponsor_query']}.")
        if hints:
            lines.append("Did you mean: " + ", ".join(hints))
        return "\n".join(lines) + "\n"
    lines.append("")
    lines.append("## Phase counts (studies shown)")
    for key, value in sorted(doc["by_phase"].items()):
        lines.append(f"- {key}: {value}")
    lines.append("")
    lines.append("## Status counts (studies shown)")
    for key, value in sorted(doc["by_status"].items()):
        lines.append(f"- {key}: {value}")
    lines.append("")
    lines.append("## Studies")
    for study in doc["studies"]:
        phases = ",".join(study["phases"]) or "NA"
        lines.append(
            f"- {study['nct_id']} — {study['title']} — {study['status']} — {phases} — {study['role']}"
        )
        if study["conditions"]:
            lines.append("  Conditions: " + "; ".join(study["conditions"]))
        if study["interventions"]:
            lines.append("  Interventions: " + "; ".join(study["interventions"]))
        lines.append("  " + study["url"])
    lines.append("")
    lines.append(DISCLAIMER)
    return "\n".join(lines) + "\n"


def error_body(status: int, message: str, sponsor: str, fmt: str, accept: str,
               role: str = "lead") -> tuple[int, str, bytes]:
    payload = {
        "error": message,
        "source": SOURCE,
        "sponsor_query": sponsor,
        "disclaimer": DISCLAIMER,
    }
    want_html = fmt == "html" or (fmt == "" and "text/html" in accept)
    if want_html and status != 400:
        page = html_document(
            "ClinicalTrials.gov is unavailable",
            form_html(sponsor, role=role) + (
                "<p>No study list is shown. This site does not invent NCT ids "
                "when the registry cannot be reached.</p>"
            ),
            notice=message,
        )
        return status, "text/html; charset=utf-8", page.encode("utf-8")
    return status, "application/json; charset=utf-8", json.dumps(payload).encode("utf-8")


def handle_query(query: dict[str, str], accept: str,
                 opener: Opener | None = None) -> tuple[int, str, bytes]:
    checked = validate(query)
    if "error" in checked:
        body = json.dumps({
            "error": checked["error"],
            "allowed": checked.get("allowed"),
            "source": SOURCE,
            "disclaimer": DISCLAIMER,
        }).encode("utf-8")
        return int(checked["status"]), "application/json; charset=utf-8", body
    sponsor = checked["sponsor"]
    fmt = checked["format"]
    if not sponsor:
        if fmt in ("json", "brief"):
            return error_body(400, "sponsor is required", "", fmt, accept)
        page = html_document(
            "Pipeline analysis",
            form_html() + (
                "<p>Pick a company, or type the sponsor name ClinicalTrials.gov uses. "
                "The list is a shortcut. A name that is not in the list is still searched as you typed it. "
                "The default list is ongoing studies. "
                "The default role is lead sponsor. Collaborator-only trials stay out unless you change the role.</p>"
            ),
        )
        return 200, "text/html; charset=utf-8", page.encode("utf-8")
    if checked["status"] == "ALL":
        status_param = ""
        status_default = False
    elif checked["status"] == "":
        status_param = ",".join(ONGOING)
        status_default = True
    else:
        status_param = checked["status"]
        status_default = False
    try:
        payload = fetch_payload(
            sponsor, status_param, checked["phase"], checked["limit"],
            checked["page_token"], opener=opener, role=checked["role"],
        )
    except UpstreamError as exc:
        return error_body(exc.status, exc.message, sponsor, fmt, accept, checked["role"])
    doc = shape_payload(payload, sponsor, _now(), checked["role"])
    # Filters echo so a client can see they were applied. They are not study facts.
    doc["status_filter"] = status_param or None
    doc["status_default"] = status_default
    doc["phase_filter"] = checked["phase"] or None
    doc["limit"] = checked["limit"]
    use_html = fmt == "html" or (fmt == "" and "text/html" in accept.lower())
    if fmt == "brief":
        return 200, "text/plain; charset=utf-8", brief_text(doc).encode("utf-8")
    if use_html:
        page = results_html(doc, checked["status"], checked["phase"])
        return 200, "text/html; charset=utf-8", page.encode("utf-8")
    return 200, "application/json; charset=utf-8", json.dumps(doc).encode("utf-8")


def openapi_spec() -> dict[str, Any]:
    return {
        "openapi": "3.0.3",
        "info": {
            "title": "Global Patient Safety pipeline",
            "version": "1",
            "description": DISCLAIMER + " FAERS signals stay on https://faers.mobi/signals.",
        },
        "servers": [{"url": "https://globalpatientsafety.com"}],
        "paths": {
            "/pipeline": {
                "get": {
                    "operationId": "getPipeline",
                    "summary": "ClinicalTrials.gov studies for one sponsor",
                    "parameters": [
                        {"name": "sponsor", "in": "query", "required": True,
                         "description": (
                             "Matched against the lead sponsor name unless role says otherwise. "
                             "A family name that contains the query counts. "
                             "Not expanded to other companies."
                         ),
                         "schema": {"type": "string"}},
                        {"name": "role", "in": "query", "required": False,
                         "description": (
                             "Default lead. collaborator is collaborator-only. "
                             "any is lead or collaborator, the ClinicalTrials.gov sponsor search."
                         ),
                         "schema": {"type": "string", "enum": list(ROLES), "default": "lead"}},
                        {"name": "status", "in": "query", "required": False,
                         "description": "Omitted means ongoing studies. ALL means every status.",
                         "schema": {"type": "string", "enum": ["ALL", *list(STATUSES)]}},
                        {"name": "phase", "in": "query", "required": False,
                         "schema": {"type": "string", "enum": list(PHASES)}},
                        {"name": "limit", "in": "query", "required": False,
                         "schema": {"type": "integer", "minimum": 1, "maximum": MAX_LIMIT,
                                    "default": DEFAULT_LIMIT}},
                        {"name": "pageToken", "in": "query", "required": False,
                         "schema": {"type": "string"}},
                        {"name": "format", "in": "query", "required": False,
                         "schema": {"type": "string", "enum": ["json", "brief", "html"]}},
                    ],
                    "responses": {
                        "200": {"description": "Studies, an empty match, HTML, or a brief"},
                        "400": {"description": "Missing sponsor or a bad filter"},
                        "502": {"description": "ClinicalTrials.gov returned an error"},
                        "503": {"description": "ClinicalTrials.gov did not respond"},
                    },
                }
            }
        },
    }


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, fmt: str, *args: Any) -> None:
        return

    def do_GET(self) -> None:  # noqa: N802
        parsed = urllib.parse.urlsplit(self.path)
        if parsed.path.rstrip("/") != "/pipeline":
            self._send(404, "application/json; charset=utf-8",
                       json.dumps({"error": "not found"}).encode("utf-8"))
            return
        query = {k: v[-1] for k, v in urllib.parse.parse_qs(parsed.query, keep_blank_values=True).items()}
        # parse_qs lowercases nothing; accept pageToken
        if "pageToken" in query and "pagetoken" not in query:
            query["pagetoken"] = query["pageToken"]
        accept = self.headers.get("Accept", "")
        status, ctype, body = handle_query(query, accept)
        self._send(status, ctype, body)

    def _send(self, status: int, ctype: str, body: bytes) -> None:
        self.send_response(status)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "public, max-age=300")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.end_headers()
        self.wfile.write(body)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--bind", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=3843)
    parser.add_argument("--openapi", action="store_true",
                        help="Print the OpenAPI document and exit")
    args = parser.parse_args(argv)
    if args.openapi:
        print(json.dumps(openapi_spec(), indent=2))
        return 0
    server = ThreadingHTTPServer((args.bind, args.port), Handler)
    print(f"gps-pipeline listening on http://{args.bind}:{args.port}/pipeline", flush=True)
    server.serve_forever()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
