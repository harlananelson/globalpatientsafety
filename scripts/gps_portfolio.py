#!/usr/bin/env python3
"""Portfolio safety endpoint for globalpatientsafety.com.

The pipeline page answers "what is this company studying?".
This page answers "what does FAERS show for the drugs this company sells now?".

GET /portfolio?sponsor=Sanofi
  format omitted + Accept: text/html  -> HTML (the human page)
  format omitted otherwise             -> JSON
  format=json | brief | html
  limit / offset                       -> page through the product list

Products come from Drugs@FDA (openFDA bulk download, refreshed daily):
NDA and BLA applications whose application-holder name contains the query
and that have at least one product marked Prescription or Over-the-counter.
Generics (ANDA) are not listed.

Signals come from GET https://faers.mobi/signals, one active ingredient at a
time. A FAERS signal belongs to the active ingredient across every
manufacturer, not to this company's product alone. No statistic is computed
here.

A page request NEVER calls faers.mobi. faers.mobi answers one /signals call
in a few seconds and returns 504 under parallel load, so a live fan-out over a
company's 30-80 drugs is not possible. A separate fill job does it serially:

  python3 scripts/gps_portfolio.py --refresh --sponsor Sanofi   # one company
  python3 scripts/gps_portfolio.py --refresh                    # every company

Each drug is written to its own cache file with checked_at, so the job can
stop and resume. A drug the job has not reached is "pending"; one whose call
failed is "not_checked". Neither is ever shown as "no signals".

  python3 scripts/gps_portfolio.py --bind 127.0.0.1 --port 3847 --cache-dir DIR
"""

from __future__ import annotations

import argparse
import hashlib
import io
import json
import os
import re
import sys
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
import zipfile
from difflib import get_close_matches
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from typing import Any, Callable

PAGE_TITLE = "Portfolio safety"
PATH = "/portfolio"

DRUGSFDA_URL = "https://download.open.fda.gov/drug/drugsfda/drug-drugsfda-0001-of-0001.json.zip"
FAERS_URL = os.environ.get("GPS_PORTFOLIO_FAERS_URL", "https://faers.mobi/signals")
FAERS_HUMAN = "https://faers.mobi/?q="
SOURCE_PRODUCTS = "Drugs@FDA via openFDA bulk download"
SOURCE_SIGNALS = "faers.mobi/signals"
USER_AGENT = "globalpatientsafety-portfolio/1 (+https://globalpatientsafety.com/portfolio)"
DISCLAIMER = (
    "FAERS disproportionality is a statistical hypothesis from spontaneous reports, "
    "not evidence that a drug causes an event. Each signal is one reported drug name and "
    "one event; this page pools every reported name that resolves to the active ingredient, "
    "under any brand or manufacturer, so it is not this company's product alone."
)
SCOPE_TEXT = (
    "Products are FDA NDA and BLA applications whose application holder name contains "
    "the query, with at least one product marked Prescription or Over-the-counter in "
    "Drugs@FDA. Generics (ANDA) are not listed. A drug a company co-markets under "
    "another company's application is listed under that other company."
)
NOVEL_TEXT = (
    "Novel means the event was not matched in the cached FDA label text. "
    "It does not mean a previously unknown risk. ? means no usable cached label."
)
COUNT_TEXT = (
    "reports is the distinct FAERS case count when faers.mobi publishes it; "
    "otherwise n is shown, the sum of observed counts over flagged quarters. "
    "Rolling windows overlap, so n is not a count of distinct reports."
)

CURRENT_STATUSES = ("Prescription", "Over-the-counter")
# Salt and hydrate words dropped before comparing a Drugs@FDA ingredient with
# the ingredient faers.mobi resolves to (clopidogrel bisulfate -> clopidogrel).
SALT_WORDS = frozenset("""
    acetate acetonide anhydrous besylate bisulfate bitartrate bromide calcium carbonate
    chloride citrate dihydrate dihydrochloride dimesylate dipropionate disodium fumarate
    gluconate hcl hemifumarate hemihydrate hyclate hydrobromide hydrochloride lactate
    magnesium maleate malate mesylate monohydrate monosodium nitrate oxalate pamoate
    phosphate potassium propionate recombinant sodium succinate sulfate tartrate tosylate
    trihydrate valerate
""".split())
# A biologic's 4-letter FDA suffix (isatuximab-irfc) is not part of the
# substance name. A 3-letter prefix (ziv-aflibercept, ado-trastuzumab) IS kept:
# it separates Zaltrap from Eylea, and dropping it merged their FAERS rows.
BIO_SUFFIX = re.compile(r"-[a-z]{4}$")

DEFAULT_LIMIT = 20
MAX_LIMIT = 100
TOP_N = 5
# One depth for every drug. faers.mobi leaves `trend` blank on every row when
# limit is 400 or more (measured 2026-11-17: 300 filled, 400 blank), so stay at 300.
FAERS_ROWS = 300
# Harlan 2026-11-17: top signals need n >= 10. Sent to faers.mobi as min_n so
# the 300-row window is spent on such pairs, and re-applied when reading the
# cache so an entry fetched without it cannot show a smaller pair.
# n is faers.mobi's overlapping-window sum, not a count of distinct reports.
MIN_N = 10
FAERS_TIMEOUT_S = 60
FILL_PAUSE_S = 2.0
FILL_MAX_AGE_DAYS = 30
DRUGSFDA_TTL_S = 24 * 3600
DRUGSFDA_RETRY_S = 15 * 60
DRUGSFDA_TIMEOUT_S = 60
KEEP_FIELDS = ("drug", "reported_drug", "ingredient", "event", "n", "n_unique",
               "eb05", "trend", "novel")

Opener = Callable[..., Any]


class UpstreamError(Exception):
    def __init__(self, status: int, message: str) -> None:
        super().__init__(message)
        self.status = status
        self.message = message


def _now() -> str:
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())


def _fold(text: str) -> str:
    """Casefold and reduce punctuation to single spaces for name matching."""
    return re.sub(r"\s+", " ", re.sub(r"[^0-9a-z]+", " ", text.casefold())).strip()


def normalize_ingredient(name: str) -> str:
    text = BIO_SUFFIX.sub("", name.strip().casefold())
    words = [w for w in _fold(text).split() if w not in SALT_WORDS]
    return " ".join(words) if words else _fold(name)


# ---------------------------------------------------------------- Drugs@FDA

def build_index(raw: dict[str, Any]) -> dict[str, Any]:
    """Keep NDA/BLA applications with at least one currently marketed product."""
    apps = []
    for app in raw.get("results") or []:
        if not isinstance(app, dict):
            continue
        number = str(app.get("application_number") or "")
        if not (number.startswith("NDA") or number.startswith("BLA")):
            continue
        sponsor = str(app.get("sponsor_name") or "").strip()
        if not sponsor:
            continue
        products = []
        for prod in app.get("products") or []:
            if not isinstance(prod, dict):
                continue
            status = str(prod.get("marketing_status") or "")
            if status not in CURRENT_STATUSES:
                continue
            ingredients = []
            for item in prod.get("active_ingredients") or []:
                if isinstance(item, dict) and item.get("name"):
                    ingredients.append(str(item["name"]).strip())
            if not ingredients:
                continue
            products.append({
                "brand_name": str(prod.get("brand_name") or "").strip(),
                "ingredients": ingredients,
                "marketing_status": status,
            })
        if products:
            apps.append({
                "application_number": number,
                "sponsor_name": sponsor,
                "products": products,
            })
    meta = raw.get("meta") or {}
    return {
        "last_updated": str(meta.get("last_updated") or ""),
        "applications": apps,
        "sponsors": sorted({a["sponsor_name"] for a in apps}),
    }


def _write_json(path: str, data: Any, strict: bool = False) -> None:
    """Atomic write. strict=True raises, so a fill never logs ok and stores nothing."""
    tmp = f"{path}.{os.getpid()}.tmp"
    try:
        os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
        with open(tmp, "w", encoding="utf-8") as fh:
            json.dump(data, fh)
        os.replace(tmp, path)
    except OSError:
        if strict:
            raise
        # The Drugs@FDA index still serves from memory.


class DrugsFdaStore:
    """The Drugs@FDA index, loaded from a cache file or downloaded once a day.

    When a download fails, the next attempt waits DRUGSFDA_RETRY_S, so an
    openFDA outage does not make every request wait on a 60 s download.
    """

    def __init__(self, cache_path: str, opener: Opener | None = None,
                 url: str = DRUGSFDA_URL) -> None:
        self.cache_path = cache_path
        self.opener = opener or urllib.request.urlopen
        self.url = url
        self._index: dict[str, Any] | None = None
        self._loaded_at = 0.0
        self._failed_at = 0.0
        self._failure: UpstreamError | None = None
        self._lock = threading.Lock()

    def _download(self) -> dict[str, Any]:
        req = urllib.request.Request(self.url, headers={"User-Agent": USER_AGENT})
        try:
            with self.opener(req, timeout=DRUGSFDA_TIMEOUT_S) as resp:
                blob = resp.read()
        except urllib.error.HTTPError as exc:
            exc.close()
            raise UpstreamError(503, f"Drugs@FDA download returned HTTP {exc.code}") from exc
        except (TimeoutError, urllib.error.URLError) as exc:
            raise UpstreamError(503, "Drugs@FDA download did not respond") from exc
        try:
            with zipfile.ZipFile(io.BytesIO(blob)) as zf:
                names = [n for n in zf.namelist() if n.endswith(".json")]
                if not names:
                    raise UpstreamError(503, "Drugs@FDA download held no JSON file")
                raw = json.loads(zf.read(names[0]))
        except (zipfile.BadZipFile, json.JSONDecodeError) as exc:
            raise UpstreamError(503, "Drugs@FDA download could not be read") from exc
        index = build_index(raw)
        if not index["applications"]:
            raise UpstreamError(503, "Drugs@FDA download held no marketed NDA or BLA products")
        return index

    def _read_cache(self) -> tuple[dict[str, Any], float] | None:
        try:
            mtime = os.path.getmtime(self.cache_path)
            with open(self.cache_path, encoding="utf-8") as fh:
                index = json.load(fh)
        except (OSError, json.JSONDecodeError):
            return None
        if not isinstance(index, dict) or not index.get("applications"):
            return None
        return index, mtime

    def get(self) -> dict[str, Any]:
        with self._lock:
            now = time.time()
            if self._index is not None and now - self._loaded_at < DRUGSFDA_TTL_S:
                return self._index
            cached = self._read_cache()
            if cached and now - cached[1] < DRUGSFDA_TTL_S:
                self._index, self._loaded_at = cached
                return self._index
            stale = self._index if self._index is not None else (cached[0] if cached else None)
            if self._failure is not None and now - self._failed_at < DRUGSFDA_RETRY_S:
                if stale is not None:
                    return stale
                raise self._failure
            try:
                index = self._download()
            except UpstreamError as exc:
                self._failure, self._failed_at = exc, now
                # A stale index is better than none; the payload carries its date.
                if stale is not None:
                    self._index = stale
                    return stale
                raise
            self._failure = None
            _write_json(self.cache_path, index)
            self._index, self._loaded_at = index, now
            return index


def group_products(apps: list[dict[str, Any]]) -> list[dict[str, Any]]:
    """One row per active-ingredient set across the given applications."""
    groups: dict[tuple[str, ...], dict[str, Any]] = {}
    for app in apps:
        for prod in app["products"]:
            key = tuple(sorted({normalize_ingredient(n) for n in prod["ingredients"]}))
            group = groups.setdefault(key, {
                "ingredients_raw": set(), "brand_names": set(), "applications": set(),
                "sponsor_names": set(), "marketing_status": set(),
            })
            group["ingredients_raw"].update(prod["ingredients"])
            if prod["brand_name"]:
                group["brand_names"].add(prod["brand_name"])
            group["applications"].add(app["application_number"])
            group["sponsor_names"].add(app["sponsor_name"])
            group["marketing_status"].add(prod["marketing_status"])
    drugs = []
    for key, group in groups.items():
        brands = sorted(group["brand_names"])
        drugs.append({
            "key": "+".join(key),
            "ingredients": list(key),
            "ingredients_raw": sorted(group["ingredients_raw"]),
            "brand_names": brands,
            "applications": sorted(group["applications"]),
            "sponsor_names": sorted(group["sponsor_names"]),
            "marketing_status": sorted(group["marketing_status"]),
            "label": " / ".join(brands[:3]) if brands else " + ".join(key),
        })
    drugs.sort(key=lambda d: (d["label"].casefold(), d["key"]))
    return drugs


def match_products(index: dict[str, Any], sponsor: str) -> tuple[list[dict[str, Any]], list[str]]:
    """The sponsor's current products, one row per active-ingredient set."""
    query = _fold(sponsor)
    apps = [a for a in index.get("applications") or []
            if query and query in _fold(a["sponsor_name"])]
    return group_products(apps), sorted({a["sponsor_name"] for a in apps})


# ---------------------------------------------------------------- matching

def faers_query_names(drug: dict[str, Any]) -> list[str]:
    """Names to try on faers.mobi, in order.

    The salt-free ingredient(s) first, then brand names. A brand's first word
    (LANTUS SOLOSTAR -> lantus) is the last resort, since FAERS reporters
    rarely write the device.
    """
    names: list[str] = [" ".join(drug["ingredients"])]
    for brand in drug["brand_names"][:2]:
        names.append(_fold(brand))
    for brand in drug["brand_names"][:2]:
        first = _fold(brand).split(" ")[0] if _fold(brand) else ""
        if len(first) >= 4:
            names.append(first)
    out: list[str] = []
    for name in names:
        if name and name not in out:
            out.append(name)
    return out


def _row_ingredients(row: dict[str, Any]) -> set[str]:
    raw = str(row.get("ingredient") or "")
    return {normalize_ingredient(x) for x in raw.split(";") if x.strip()}


def _row_names(row: dict[str, Any]) -> str:
    return (" " + _fold(str(row.get("drug") or "")) + " "
            + _fold(str(row.get("reported_drug") or "")) + " ")


def _names_this_drug(names: str, drug: dict[str, Any]) -> bool:
    """The reported drug string names all our ingredients, or one of our brands."""
    if all(f" {ing} " in names for ing in drug["ingredients"]):
        return True
    for brand in drug["brand_names"]:
        folded = _fold(brand)
        first = folded.split(" ")[0] if folded else ""
        if folded and f" {folded} " in names:
            return True
        if len(first) >= 4 and f" {first} " in names:
            return True
    return False


def _is_coarser(alias: str, wanted: set[str]) -> bool:
    """insulin is a coarser family than insulin glargine: not a usable synonym."""
    words = set(alias.split())
    return any(words <= set(w.split()) for w in wanted)


def ingredient_aliases(rows: list[dict[str, Any]], drug: dict[str, Any]) -> set[str]:
    """Synonyms faers.mobi uses for our ingredient (glyburide -> glibenclamide).

    Learned from rows whose reported name is exactly our ingredient or a brand
    of ours. A coarser family name (insulin for insulin glargine) is refused.
    """
    wanted = set(drug["ingredients"])
    if len(wanted) != 1:
        return set()
    exact = {f" {i} " for i in wanted}
    for brand in drug["brand_names"]:
        folded = _fold(brand)
        exact.add(f" {folded} ")
        first = folded.split(" ")[0] if folded else ""
        if len(first) >= 4:
            exact.add(f" {first} ")
    aliases: set[str] = set()
    for row in rows:
        got = _row_ingredients(row)
        if len(got) != 1:
            continue
        name = " " + _fold(str(row.get("drug") or "")) + " "
        if name in exact:
            alias = next(iter(got))
            if alias not in wanted and not _is_coarser(alias, wanted):
                aliases.add(alias)
    return {a for a in aliases if _alias_is_specific(a, rows, drug)}


def _alias_is_specific(alias: str, rows: list[dict[str, Any]], drug: dict[str, Any]) -> bool:
    """Refuse a family bucket learned from one brand row (ferrlecit -> iron).

    glibenclamide rows are mostly reported as glibenclamide / glyburide /
    diabeta; iron rows are ferinject, venofer, ferrous sulfate. Accept the
    alias only when at least half the distinct reported names under it say the
    alias, our ingredient, or one of our brands.
    """
    names = {_fold(str(r.get("drug") or "")) for r in rows
             if _row_ingredients(r) == {alias}}
    if not names:
        return False
    hits = sum(1 for n in names
               if f" {alias} " in f" {n} " or _names_this_drug(f" {n} ", drug))
    return hits * 2 >= len(names)


def _names_our_brand(names: str, drug: dict[str, Any]) -> bool:
    for brand in drug["brand_names"]:
        folded = _fold(brand)
        first = folded.split(" ")[0] if folded else ""
        if folded and f" {folded} " in names:
            return True
        if len(first) >= 4 and f" {first} " in names:
            return True
    return False


def row_belongs(row: dict[str, Any], drug: dict[str, Any],
                aliases: set[str] | None = None) -> bool:
    """True when a faers.mobi row is about this drug, not a neighbour.

    faers.mobi isolates by same-substance family, so "insulin glargine" also
    returns Humulin rows (ingredient "insulin"), and "lixisenatide" returns the
    insulin glargine + lixisenatide combination. Rules:
      - resolved ingredient set equals ours (or a learned synonym) -> keep
      - resolved to a different number of ingredients -> drop (another product)
      - resolved to another substance -> drop
      - resolved to a coarser family, or not resolved -> keep only when the
        reported name says our ingredient(s) or one of our brands
    """
    wanted = set(drug["ingredients"])
    got = _row_ingredients(row)
    if got and got == wanted:
        return True
    if got and len(got) != len(wanted):
        return False
    if aliases and len(got) == 1 and next(iter(got)) in aliases:
        return True
    if got and not all(_is_coarser(g, wanted) for g in got):
        # Another substance, unless the reporter named our own brand
        # (Ferrlecit reported as "ferrlecit" resolves to the iron bucket).
        return _names_our_brand(_row_names(row), drug)
    return _names_this_drug(_row_names(row), drug)


# ---------------------------------------------------------------- faers.mobi

def faers_url(name: str, rows: int = FAERS_ROWS) -> str:
    query = {
        "drug": name,
        "indication": "hide",
        "low_info": "hide",
        "medication_error": "hide",
        "min_n": str(MIN_N),
        "sort": "eb05",
        "order": "desc",
        "limit": str(rows),
    }
    return FAERS_URL + "?" + urllib.parse.urlencode(query)


def fetch_faers(name: str, opener: Opener | None = None) -> list[dict[str, Any]]:
    url = faers_url(name)
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT, "Accept": "application/json"})
    open_ = opener or urllib.request.urlopen
    try:
        with open_(req, timeout=FAERS_TIMEOUT_S) as resp:
            raw = resp.read().decode("utf-8")
    except urllib.error.HTTPError as exc:
        exc.close()
        raise UpstreamError(502, f"faers.mobi returned HTTP {exc.code}") from exc
    except (TimeoutError, urllib.error.URLError) as exc:
        raise UpstreamError(503, "faers.mobi did not respond") from exc
    try:
        rows = json.loads(raw)
    except json.JSONDecodeError as exc:
        raise UpstreamError(502, "faers.mobi returned a response that was not JSON") from exc
    if not isinstance(rows, list):
        raise UpstreamError(502, "faers.mobi returned an unexpected response")
    return [{k: r.get(k) for k in KEEP_FIELDS if k in r} for r in rows if isinstance(r, dict)]


def _merge(*lists: list[dict[str, Any]]) -> list[dict[str, Any]]:
    seen: set[tuple[str, str]] = set()
    out = []
    for rows in lists:
        for row in rows:
            key = (str(row.get("drug")), str(row.get("event")))
            if key not in seen:
                seen.add(key)
                out.append(row)
    out.sort(key=lambda r: -r["eb05"] if isinstance(r.get("eb05"), (int, float)) else 0.0)
    return out


def gather_rows(drug: dict[str, Any], opener: Opener | None = None,
                pause_s: float = 0.0) -> tuple[list[dict[str, Any]], str]:
    """faers.mobi rows for one drug, and the name(s) that produced them.

    This is the only function that talks to faers.mobi, so a better source
    (an exact-ingredient export from faers-mobi) can replace it in one place.

    Single ingredient: the first name that returns rows any of which belong
    to this drug. Combination: merge the ingredient query and the brand first
    word, since each catches reporter spellings the other misses.
    UpstreamError propagates: one failed call makes the drug not_checked.
    """
    names = faers_query_names(drug)
    calls = 0

    def get(name: str) -> list[dict[str, Any]]:
        nonlocal calls
        if calls and pause_s:
            time.sleep(pause_s)
        calls += 1
        return fetch_faers(name, opener=opener)

    if len(drug["ingredients"]) > 1:
        firsts = [n for n in names[1:] if " " not in n]
        picks = [names[0]] + firsts[:1]
        found = [get(n) for n in picks]
        rows = _merge(*found)
        used = [n for n, r in zip(picks, found) if r]
        if rows:
            return rows, " + ".join(used)
        for name in names:
            if name in picks:
                continue
            rows = get(name)
            if rows:
                return rows, name
        return [], names[0]
    first_rows: list[dict[str, Any]] = []
    first_name = names[0]
    for name in names:
        rows = get(name)
        if not rows:
            continue
        if not first_rows:
            first_rows, first_name = rows, name
        aliases = ingredient_aliases(rows, drug)
        if any(row_belongs(r, drug, aliases) for r in rows):
            return rows, name
    return first_rows, first_name


def summarize_drug(drug: dict[str, Any], rows: list[dict[str, Any]],
                   query_name: str = "") -> dict[str, Any]:
    aliases = ingredient_aliases(rows, drug)
    kept = [r for r in rows if row_belongs(r, drug, aliases)
            and isinstance(r.get("n"), (int, float)) and r["n"] >= MIN_N]
    seen: set[str] = set()
    top = []
    for row in kept:  # rows arrive ranked by EB05; first row per event wins
        event = str(row.get("event") or "")
        if not event or event in seen:
            continue
        seen.add(event)
        top.append({
            "event": event,
            "n_unique": row.get("n_unique"),
            "n": row.get("n"),
            "eb05": row.get("eb05"),
            "trend": row.get("trend") or None,
            "novel": row.get("novel") or None,
            "reported_drug": row.get("reported_drug") or row.get("drug"),
        })
    def events_where(test: Callable[[dict[str, Any]], bool]) -> int:
        return len({str(r.get("event")) for r in kept if test(r)})

    novel = events_where(lambda r: r.get("novel") == "novel")
    label_unknown = events_where(lambda r: r.get("novel") not in ("novel", "known"))
    rising = events_where(lambda r: r.get("trend") in ("Accelerating", "Rising", "New"))
    trend_unknown = events_where(lambda r: not r.get("trend"))
    if not rows:
        state = "none_isolated"
    elif not kept:
        state = "other_products_only"
    else:
        state = "signals"
    link_name = (query_name or faers_query_names(drug)[0]).split(" + ")[0]
    return {
        "state": state,
        "faers_query": query_name or None,
        "faers_aliases": sorted(aliases),
        "faers_rows": len(rows),
        "faers_rows_kept": len(kept),
        "events": len(seen),
        "events_novel": novel,
        "events_label_unknown": label_unknown,
        "events_rising": rising,
        "events_trend_unknown": trend_unknown,
        "top_signals": top[:TOP_N],
        "faers_link": FAERS_HUMAN + urllib.parse.quote(link_name),
    }


STATE_TEXT = {
    "signals": "Isolated FAERS signals for this ingredient.",
    "none_isolated": (
        "faers.mobi isolated nothing for this name. That is not the same as no "
        "adverse events: the name may not resolve, or no pair passed the signal threshold."
    ),
    "other_products_only": (
        "faers.mobi returned rows only for related products (same substance family), "
        "not this ingredient. None are shown."
    ),
    "not_checked": "The last faers.mobi call for this drug failed. Nothing is shown.",
    "pending": "Not checked yet. The serial fill job has not reached this drug.",
}


# ---------------------------------------------------------------- signal cache

class SignalCache:
    """One JSON file per ingredient set: raw faers.mobi rows plus checked_at."""

    def __init__(self, directory: str) -> None:
        self.directory = directory

    def _path(self, key: str) -> str:
        digest = hashlib.sha1(key.encode("utf-8")).hexdigest()
        return os.path.join(self.directory, digest[:2], digest + ".json")

    def get(self, key: str) -> dict[str, Any] | None:
        try:
            with open(self._path(key), encoding="utf-8") as fh:
                entry = json.load(fh)
        except (OSError, json.JSONDecodeError):
            return None
        return entry if isinstance(entry, dict) and entry.get("key") == key else None

    def put(self, entry: dict[str, Any]) -> None:
        _write_json(self._path(entry["key"]), entry, strict=True)


def checked_entry(drug: dict[str, Any], opener: Opener | None = None,
                  pause_s: float = 0.0) -> dict[str, Any]:
    entry: dict[str, Any] = {"key": drug["key"], "checked_at": _now(), "checked_ts": time.time()}
    try:
        rows, used = gather_rows(drug, opener=opener, pause_s=pause_s)
    except UpstreamError as exc:
        entry.update({"ok": False, "error": exc.message})
        return entry
    entry.update({"ok": True, "rows": rows, "query": used})
    return entry


def resolve(drug: dict[str, Any], cache: SignalCache) -> dict[str, Any]:
    """Merge a drug with its cached faers.mobi result. Never calls faers.mobi."""
    row = dict(drug)
    entry = cache.get(drug["key"])
    fallback_link = FAERS_HUMAN + urllib.parse.quote(faers_query_names(drug)[0])
    if entry is None:
        row.update({"state": "pending", "checked_at": None, "faers_link": fallback_link})
        return row
    row["checked_at"] = entry.get("checked_at")
    if not entry.get("ok"):
        row.update({"state": "not_checked", "error": entry.get("error"),
                    "faers_link": fallback_link})
        return row
    row.update(summarize_drug(drug, entry.get("rows") or [], entry.get("query") or ""))
    return row


def refresh(index: dict[str, Any], cache: SignalCache, sponsor: str = "",
            max_age_days: float = FILL_MAX_AGE_DAYS, pause_s: float = FILL_PAUSE_S,
            opener: Opener | None = None, log: Callable[[str], None] = print,
            max_drugs: int = 0) -> dict[str, int]:
    """Serially fill the signal cache. Skips entries younger than max_age_days.

    Failed entries are retried on the next run whatever their age.
    """
    if sponsor:
        drugs, _ = match_products(index, sponsor)
    else:
        drugs = group_products(index.get("applications") or [])
    stats = {"drugs": len(drugs), "fresh": 0, "checked": 0, "failed": 0}
    cutoff = time.time() - max_age_days * 86400
    for drug in drugs:
        old = cache.get(drug["key"])
        if old and old.get("ok") and float(old.get("checked_ts") or 0) >= cutoff:
            stats["fresh"] += 1
            continue
        if max_drugs and stats["checked"] + stats["failed"] >= max_drugs:
            break
        if stats["checked"] + stats["failed"]:
            time.sleep(pause_s)
        entry = checked_entry(drug, opener=opener, pause_s=pause_s)
        if not entry["ok"] and old and old.get("ok"):
            # Keep the older good rows; record the failed re-check beside them.
            entry = dict(old, last_error=entry["error"], last_error_at=entry["checked_at"])
            cache.put(entry)
            stats["failed"] += 1
            log(f"FAIL  {drug['label'][:40]:40} {entry['last_error']} (kept rows from {old.get('checked_at')})")
            continue
        cache.put(entry)
        if entry["ok"]:
            stats["checked"] += 1
            log(f"ok    {drug['label'][:40]:40} {entry['query']!r} rows={len(entry['rows'])}")
        else:
            stats["failed"] += 1
            log(f"FAIL  {drug['label'][:40]:40} {entry['error']}")
    return stats


# ---------------------------------------------------------------- request

def validate(args: dict[str, str]) -> dict[str, Any]:
    sponsor = re.sub(r"\s+", " ", (args.get("sponsor") or "").strip())
    fmt = (args.get("format") or "").strip().lower()
    if fmt not in ("", "json", "brief", "html"):
        return {"status": 400, "error": "unknown format", "allowed": ["json", "brief", "html"]}
    out: dict[str, Any] = {"sponsor": sponsor, "format": fmt}
    for name, default, low, top in (("limit", DEFAULT_LIMIT, 1, MAX_LIMIT), ("offset", 0, 0, None)):
        raw = (args.get(name) or "").strip()
        if raw == "":
            out[name] = default
            continue
        try:
            value = int(raw)
        except ValueError:
            return {"status": 400, "error": f"{name} must be an integer"}
        if value < low or (top is not None and value > top):
            allowed = f"{low}..{top}" if top is not None else f">= {low}"
            return {"status": 400, "error": f"{name} out of range", "allowed": [allowed]}
        out[name] = value
    if len(sponsor) > 200:
        return {"status": 400, "error": "sponsor is too long"}
    if sponsor and len(_fold(sponsor)) < 3:
        return {"status": 400, "error": "sponsor must have at least 3 letters or digits"}
    return out


def suggestions_for(sponsor: str, index: dict[str, Any]) -> list[str]:
    return get_close_matches(sponsor.upper(), index.get("sponsors") or [], n=5, cutoff=0.6)


def build_doc(sponsor: str, limit: int, offset: int, index: dict[str, Any],
              cache: SignalCache) -> dict[str, Any]:
    drugs, matched = match_products(index, sponsor)
    page = [resolve(d, cache) for d in drugs[offset:offset + limit]]
    by_state: dict[str, int] = {}
    for row in page:
        by_state[row["state"]] = by_state.get(row["state"], 0) + 1
    return {
        "sponsor_query": sponsor,
        "matched_sponsors": matched,
        "retrieved_at": _now(),
        "drugsfda_last_updated": index.get("last_updated") or None,
        "source_products": SOURCE_PRODUCTS,
        "source_signals": SOURCE_SIGNALS,
        "n_drugs": len(drugs),
        "n_returned": len(page),
        "offset": offset,
        "limit": limit,
        "next_offset": offset + limit if offset + limit < len(drugs) else None,
        "by_state": by_state,
        "faers_filters": f"indication=hide&low_info=hide&medication_error=hide&min_n={MIN_N}&sort=eb05",
        "faers_rows_per_query": FAERS_ROWS,
        "scope": SCOPE_TEXT,
        "novel_meaning": NOVEL_TEXT,
        "count_meaning": COUNT_TEXT,
        "drugs": page,
        "disclaimer": DISCLAIMER,
    }


def _esc(text: Any) -> str:
    return (str(text).replace("&", "&amp;").replace("<", "&lt;")
            .replace(">", "&gt;").replace('"', "&quot;"))


def _num(value: Any) -> str:
    if isinstance(value, float):
        return f"{value:.1f}"
    if isinstance(value, int):
        return str(value)
    return "—"


def _count_text(sig: dict[str, Any]) -> str:
    if sig.get("n_unique") is not None:
        return f"reports {sig['n_unique']}"
    return f"n {_num(sig.get('n'))}"


def html_document(title: str, body: str, notice: str = "") -> str:
    alert = f'<p class="notice" role="status">{_esc(notice)}</p>' if notice else ""
    return f"""<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>{_esc(title)}</title>
  <meta name="description" content="Machine path: GET {PATH}?sponsor= returns JSON, and format=brief returns markdown. {_esc(DISCLAIMER)}">
  <link rel="alternate" type="text/markdown" href="{PATH}.md">
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
    main {{ max-width: 1100px; margin: 0 auto; padding: 1.5rem 1rem 3rem; }}
    h1 {{ font-weight: 500; }}
    label {{ display: block; font-weight: 600; margin: .8rem 0 .25rem; }}
    input {{ font: inherit; padding: .4rem .5rem; width: min(100%, 28rem); box-sizing: border-box; border: 1px solid #334155; border-radius: 4px; background: #fff; color: #1a2332; }}
    button {{ font: inherit; margin-top: 1rem; background: #0f4c6e; color: #fff; border: 0; border-radius: 4px; padding: .5rem 1rem; }}
    .table-wrap {{ overflow-x: auto; }}
    table {{ border-collapse: collapse; width: 100%; margin-top: 1rem; background: #fff; }}
    th, td {{ border: 1px solid #cbd5e1; padding: .4rem .5rem; text-align: left; vertical-align: top; }}
    th {{ background: #e7eef3; }}
    td ul {{ margin: 0; padding-left: 1.1rem; }}
    .muted {{ color: #475569; }}
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
  <a href="/pipeline">Pipeline analysis</a>
  <a href="{PATH}" aria-current="page">{PAGE_TITLE}</a>
  <a href="/articles">Articles</a>
  <a href="/api">API</a>
</nav>
<div class="llm-access">
  <strong>LLM / API access.</strong>
  <a href="/api">API</a> ·
  <a href="/llms.txt">llms.txt</a> ·
  <a href="{PATH}.md">Markdown</a>
</div>
<main id="main" tabindex="-1">
  <h1>{_esc(title)}</h1>
  {alert}
  {body}
</main>
<footer>
  <p>{_esc(DISCLAIMER)} {_esc(SCOPE_TEXT)} <a href="/accessibility">Accessibility</a></p>
</footer>
</body>
</html>
"""


def form_html(sponsor: str = "", index: dict[str, Any] | None = None) -> str:
    options = ""
    if index:
        options = "\n".join(f'<option value="{_esc(n)}"></option>' for n in index.get("sponsors") or [])
    return f"""
<form method="get" action="{PATH}">
  <label for="sponsor">Company (FDA application holder)</label>
  <input id="sponsor" name="sponsor" list="sponsor-list" value="{_esc(sponsor)}" autocomplete="off" required minlength="3">
  <datalist id="sponsor-list">
    {options}
  </datalist>
  <div><button type="submit">Show portfolio safety</button></div>
</form>
"""


def _page_href(sponsor: str, offset: int, limit: int) -> str:
    query = {"sponsor": sponsor, "offset": str(offset)}
    if limit != DEFAULT_LIMIT:
        query["limit"] = str(limit)
    return PATH + "?" + urllib.parse.urlencode(query)


def results_html(doc: dict[str, Any], index: dict[str, Any]) -> str:
    sponsor = doc["sponsor_query"]
    if doc["n_drugs"] == 0:
        hints = suggestions_for(sponsor, index)
        hint_html = ""
        if hints:
            links = ", ".join(
                f'<a href="{_esc(PATH + "?" + urllib.parse.urlencode({"sponsor": h}))}">{_esc(h)}</a>'
                for h in hints
            )
            hint_html = f"<p>Did you mean {links}?</p>"
        body = form_html(sponsor, index) + (
            f"<p>No currently marketed NDA or BLA products found for {_esc(sponsor)}.</p>{hint_html}"
            "<p>The name has to appear in the application holder name Drugs@FDA stores, "
            "for example JANSSEN rather than Johnson &amp; Johnson. Nothing was filled in "
            "from another company. Vaccines and blood products licensed by CBER are often "
            "not in Drugs@FDA.</p>"
        )
        return html_document(f"No products found for {sponsor}", body)
    rows = []
    for drug in doc["drugs"]:
        if drug["state"] == "signals":
            items = []
            for sig in drug["top_signals"]:
                items.append(
                    f"<li>{_esc(sig['event'])} — EB05 {_esc(_num(sig['eb05']))}, "
                    f"{_esc(_count_text(sig))}, {_esc(sig['trend'] or 'trend —')}, "
                    f"{_esc(sig['novel'] or 'label —')}"
                    f' <span class="muted">(reported as {_esc(sig["reported_drug"])})</span></li>'
                )
            signals_html = "<ul>" + "".join(items) + "</ul>"
        else:
            signals_html = f'<span class="muted">{_esc(STATE_TEXT[drug["state"]])}</span>'
        rows.append(
            "<tr>"
            f"<td>{_esc(drug['label'])}</td>"
            f"<td>{_esc(', '.join(drug['ingredients_raw']))}</td>"
            f"<td>{_esc(', '.join(drug['applications']))}</td>"
            f"<td>{signals_html}</td>"
            f"<td>{_esc((drug.get('checked_at') or '—')[:10])}</td>"
            f'<td><a href="{_esc(drug["faers_link"])}">faers.mobi</a></td>'
            "</tr>"
        )
    pager = []
    if doc["offset"] > 0:
        prev = max(0, doc["offset"] - doc["limit"])
        pager.append(f'<a href="{_esc(_page_href(sponsor, prev, doc["limit"]))}">Previous</a>')
    if doc["next_offset"] is not None:
        pager.append(f'<a href="{_esc(_page_href(sponsor, doc["next_offset"], doc["limit"]))}">Next</a>')
    pager_html = f"<p>{' · '.join(pager)}</p>" if pager else ""
    states = ", ".join(f"{k} {v}" for k, v in sorted(doc["by_state"].items()))
    body = form_html(sponsor, index) + f"""
<p>Matched application holder(s): {_esc(", ".join(doc["matched_sponsors"]))}.
Drugs@FDA updated {_esc(doc["drugsfda_last_updated"] or "unknown")}.</p>
<p>Showing drugs {doc["offset"] + 1}–{doc["offset"] + doc["n_returned"]} of {doc["n_drugs"]},
one row per active ingredient (or combination). On this page: {_esc(states)}.</p>
<p>{_esc(SCOPE_TEXT)}</p>
<p>Signals: up to {TOP_N} events per drug, highest EB05 first, from the top {FAERS_ROWS} faers.mobi pairs
for the ingredient with n of at least {MIN_N}, with indication, low-information and medication-error events hidden.
{_esc(COUNT_TEXT)} {_esc(NOVEL_TEXT)}</p>
<div class="table-wrap">
<table>
  <caption>FAERS signals for current {_esc(sponsor)} products</caption>
  <thead>
    <tr>
      <th scope="col">Product</th>
      <th scope="col">Active ingredient(s)</th>
      <th scope="col">Application</th>
      <th scope="col">Top signals: event — EB05, count, trend, label status</th>
      <th scope="col">Checked</th>
      <th scope="col">Detail</th>
    </tr>
  </thead>
  <tbody>
    {''.join(rows)}
  </tbody>
</table>
</div>
{pager_html}
"""
    return html_document(f"{PAGE_TITLE}: {sponsor}", body)


def brief_text(doc: dict[str, Any]) -> str:
    lines = [
        f"# {PAGE_TITLE}: {doc['sponsor_query']}",
        "",
        DISCLAIMER,
        SCOPE_TEXT,
        NOVEL_TEXT,
        COUNT_TEXT,
        "",
        f"Retrieved: {doc['retrieved_at']}",
        f"Drugs@FDA updated: {doc['drugsfda_last_updated'] or 'unknown'}",
        f"Sources: {doc['source_products']}; {doc['source_signals']}",
        f"Drugs: {doc['n_drugs']} (showing {doc['n_returned']} from offset {doc['offset']})",
    ]
    if doc["matched_sponsors"]:
        lines.append("Matched application holder(s): " + ", ".join(doc["matched_sponsors"]))
    if doc["n_drugs"] == 0:
        lines += ["", f"No currently marketed NDA or BLA products found for {doc['sponsor_query']}."]
        return "\n".join(lines) + "\n"
    lines += ["", "## Drugs"]
    for drug in doc["drugs"]:
        lines.append(f"- {drug['label']} ({', '.join(drug['ingredients_raw'])}) — "
                     f"{', '.join(drug['applications'])} — checked {drug.get('checked_at') or 'never'}")
        if drug["state"] == "signals":
            for sig in drug["top_signals"]:
                lines.append(f"  - {sig['event']}: EB05 {_num(sig['eb05'])}, {_count_text(sig)}, "
                             f"{sig['trend'] or 'trend —'}, {sig['novel'] or 'label —'} "
                             f"(reported as {sig['reported_drug']})")
        else:
            lines.append("  " + STATE_TEXT[drug["state"]])
        lines.append("  " + drug["faers_link"])
    if doc["next_offset"] is not None:
        lines += ["", f"More: offset={doc['next_offset']}"]
    lines += ["", DISCLAIMER]
    return "\n".join(lines) + "\n"


def _json(status: int, payload: dict[str, Any]) -> tuple[int, str, bytes]:
    return status, "application/json; charset=utf-8", json.dumps(payload).encode("utf-8")


def handle_query(query: dict[str, str], accept: str, store: DrugsFdaStore,
                 cache: SignalCache) -> tuple[int, str, bytes]:
    checked = validate(query)
    if "error" in checked:
        return _json(int(checked["status"]), {
            "error": checked["error"], "allowed": checked.get("allowed"),
            "disclaimer": DISCLAIMER,
        })
    sponsor = checked["sponsor"]
    fmt = checked["format"]
    want_html = fmt == "html" or (fmt == "" and "text/html" in accept.lower())
    if not sponsor and fmt in ("json", "brief"):
        return _json(400, {"error": "sponsor is required", "disclaimer": DISCLAIMER})
    try:
        index = store.get()
    except UpstreamError as exc:
        if want_html or not sponsor:
            page = html_document(
                "Drugs@FDA is unavailable", form_html(sponsor) +
                "<p>No product list is shown. This site does not invent products "
                "when Drugs@FDA cannot be loaded.</p>",
                notice=exc.message,
            )
            return exc.status, "text/html; charset=utf-8", page.encode("utf-8")
        return _json(exc.status, {"error": exc.message, "sponsor_query": sponsor,
                                  "disclaimer": DISCLAIMER})
    if not sponsor:
        page = html_document(PAGE_TITLE, form_html("", index) + (
            "<p>Type a company. The list shows FDA application holder names. "
            "The page lists that company's currently marketed NDA and BLA products, "
            "then shows what FAERS isolates for each active ingredient. "
            "For what the company is still testing, use "
            '<a href="/pipeline">Pipeline analysis</a>.</p>'
            f"<p>{_esc(SCOPE_TEXT)}</p><p>{_esc(DISCLAIMER)}</p>"
        ))
        return 200, "text/html; charset=utf-8", page.encode("utf-8")
    doc = build_doc(sponsor, checked["limit"], checked["offset"], index, cache)
    if fmt == "brief":
        return 200, "text/plain; charset=utf-8", brief_text(doc).encode("utf-8")
    if want_html:
        return 200, "text/html; charset=utf-8", results_html(doc, index).encode("utf-8")
    return _json(200, doc)


def openapi_path() -> dict[str, Any]:
    """The /portfolio entry merged into the site's openapi.json."""
    return {
        "get": {
            "operationId": "getPortfolioSafety",
            "summary": "FAERS signals for one company's currently marketed drugs",
            "description": " ".join((DISCLAIMER, SCOPE_TEXT, NOVEL_TEXT, COUNT_TEXT)),
            "parameters": [
                {"name": "sponsor", "in": "query", "required": True,
                 "description": (
                     "Matched as a substring of the Drugs@FDA application holder name, "
                     "ignoring case and punctuation. Not expanded to other companies."
                 ),
                 "schema": {"type": "string", "minLength": 3}},
                {"name": "limit", "in": "query", "required": False,
                 "description": "Drugs per page (one per active-ingredient set).",
                 "schema": {"type": "integer", "minimum": 1, "maximum": MAX_LIMIT,
                            "default": DEFAULT_LIMIT}},
                {"name": "offset", "in": "query", "required": False,
                 "schema": {"type": "integer", "minimum": 0, "default": 0}},
                {"name": "format", "in": "query", "required": False,
                 "schema": {"type": "string", "enum": ["json", "brief", "html"]}},
            ],
            "responses": {
                "200": {"description": (
                    "Drugs with a per-drug state: signals, none_isolated, "
                    "other_products_only, not_checked (the last faers.mobi call failed), "
                    "or pending (not checked yet)"
                )},
                "400": {"description": "Missing sponsor or a bad parameter"},
                "503": {"description": "Drugs@FDA could not be loaded"},
            },
        }
    }


def default_cache_dir() -> str:
    return os.environ.get(
        "GPS_PORTFOLIO_CACHE_DIR",
        os.path.join(os.path.dirname(os.path.abspath(__file__)), "cache", "portfolio"),
    )


def make_handler(store: DrugsFdaStore, cache: SignalCache) -> type[BaseHTTPRequestHandler]:
    class Handler(BaseHTTPRequestHandler):
        protocol_version = "HTTP/1.1"

        def log_message(self, fmt: str, *args: Any) -> None:
            return

        def do_GET(self) -> None:  # noqa: N802
            parsed = urllib.parse.urlsplit(self.path)
            if parsed.path.rstrip("/") != PATH:
                self._send(404, "application/json; charset=utf-8",
                           json.dumps({"error": "not found"}).encode("utf-8"))
                return
            query = {k: v[-1] for k, v in
                     urllib.parse.parse_qs(parsed.query, keep_blank_values=True).items()}
            status, ctype, body = handle_query(query, self.headers.get("Accept", ""), store, cache)
            self._send(status, ctype, body)

        def _send(self, status: int, ctype: str, body: bytes) -> None:
            self.send_response(status)
            self.send_header("Content-Type", ctype)
            self.send_header("Content-Length", str(len(body)))
            self.send_header("Cache-Control", "public, max-age=300")
            self.send_header("X-Content-Type-Options", "nosniff")
            self.end_headers()
            self.wfile.write(body)

    return Handler


def _safe_warm(store: DrugsFdaStore) -> None:
    try:
        store.get()
    except UpstreamError:
        pass


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--bind", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=3847)
    parser.add_argument("--cache-dir", default=None,
                        help="Drugs@FDA index and signal cache (default $GPS_PORTFOLIO_CACHE_DIR)")
    parser.add_argument("--openapi-path", action="store_true",
                        help="Print the /portfolio OpenAPI path object and exit")
    parser.add_argument("--refresh", action="store_true",
                        help="Serially fill the signal cache from faers.mobi and exit")
    parser.add_argument("--sponsor", default="", help="With --refresh: one company only")
    parser.add_argument("--max-age-days", type=float, default=FILL_MAX_AGE_DAYS)
    parser.add_argument("--pause", type=float, default=FILL_PAUSE_S,
                        help="Seconds between faers.mobi calls during --refresh")
    parser.add_argument("--max-drugs", type=int, default=0,
                        help="With --refresh: stop after checking this many drugs")
    parser.add_argument("--call", metavar="SPONSOR",
                        help="Print the brief for one sponsor from the cache and exit")
    args = parser.parse_args(argv)
    if args.openapi_path:
        print(json.dumps(openapi_path(), indent=2))
        return 0
    cache_dir = args.cache_dir or default_cache_dir()
    store = DrugsFdaStore(os.path.join(cache_dir, "drugsfda_index.json"))
    cache = SignalCache(os.path.join(cache_dir, "signals"))
    if args.refresh:
        stats = refresh(store.get(), cache, sponsor=args.sponsor,
                        max_age_days=args.max_age_days, pause_s=args.pause,
                        max_drugs=args.max_drugs)
        print(json.dumps(stats))
        return 0 if stats["failed"] == 0 else 1
    if args.call:
        _s, _c, body = handle_query({"sponsor": args.call, "format": "brief"}, "", store, cache)
        sys.stdout.write(body.decode("utf-8"))
        return 0
    # Warm the index so the first visitor does not wait on the download.
    threading.Thread(target=lambda: _safe_warm(store), daemon=True).start()
    server = ThreadingHTTPServer((args.bind, args.port), make_handler(store, cache))
    print(f"gps-portfolio listening on http://{args.bind}:{args.port}{PATH}", flush=True)
    server.serve_forever()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
