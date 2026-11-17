#!/usr/bin/env python3
"""Offline checks for the portfolio service. No openFDA or faers.mobi calls.

  cd scripts && python3 -m unittest test_gps_portfolio
"""

import io
import json
import os
import tempfile
import unittest
import urllib.error
import urllib.parse
import zipfile

import gps_portfolio as gp


def product(brand, ingredients, status="Prescription"):
    return {
        "brand_name": brand,
        "marketing_status": status,
        "active_ingredients": [{"name": n, "strength": "1MG"} for n in ingredients],
    }


RAW = {
    "meta": {"last_updated": "2026-11-16"},
    "results": [
        {"application_number": "NDA020839", "sponsor_name": "SANOFI AVENTIS US",
         "products": [product("PLAVIX", ["CLOPIDOGREL BISULFATE"])]},
        {"application_number": "NDA021081", "sponsor_name": "SANOFI-AVENTIS U.S. LLC",
         "products": [product("LANTUS", ["INSULIN GLARGINE RECOMBINANT"]),
                      product("LANTUS SOLOSTAR", ["INSULIN GLARGINE RECOMBINANT"])]},
        {"application_number": "NDA208673", "sponsor_name": "SANOFI AVENTIS US",
         "products": [product("SOLIQUA 100/33", ["INSULIN GLARGINE", "LIXISENATIDE"])]},
        {"application_number": "BLA125418", "sponsor_name": "SANOFI AVENTIS US",
         "products": [product("ZALTRAP", ["ZIV-AFLIBERCEPT"])]},
        {"application_number": "NDA017532", "sponsor_name": "SANOFI AVENTIS US",
         "products": [product("DIABETA", ["GLYBURIDE"])]},
        # Discontinued only: not current.
        {"application_number": "NDA022127", "sponsor_name": "SANOFI",
         "products": [product("RENVELA", ["SEVELAMER CARBONATE"], "Discontinued")]},
        # Generic: ANDA is never listed.
        {"application_number": "ANDA090001", "sponsor_name": "SANOFI GENERICS",
         "products": [product("CLOPIDOGREL", ["CLOPIDOGREL BISULFATE"])]},
        {"application_number": "NDA020955", "sponsor_name": "SANOFI AVENTIS US",
         "products": [product("FERRLECIT", ["SODIUM FERRIC GLUCONATE COMPLEX"])]},
        {"application_number": "BLA125057", "sponsor_name": "ABBVIE INC",
         "products": [product("HUMIRA", ["ADALIMUMAB"])]},
    ],
}


def zipped(raw):
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w") as zf:
        zf.writestr("drug-drugsfda-0001-of-0001.json", json.dumps(raw))
    return buf.getvalue()


class FakeResp:
    def __init__(self, body: bytes, status=200):
        self._body = body
        self.status = status

    def read(self):
        return self._body

    def __enter__(self):
        return self

    def __exit__(self, *a):
        return False


def drug_named(drugs, brand):
    return next(d for d in drugs if brand in d["brand_names"])


class IndexTests(unittest.TestCase):
    def setUp(self):
        self.index = gp.build_index(RAW)

    def test_only_current_nda_bla(self):
        numbers = {a["application_number"] for a in self.index["applications"]}
        self.assertNotIn("NDA022127", numbers)    # discontinued
        self.assertNotIn("ANDA090001", numbers)   # generic
        self.assertIn("BLA125418", numbers)

    def test_substring_match_on_holder_name(self):
        drugs, matched = gp.match_products(self.index, "sanofi")
        self.assertIn("SANOFI-AVENTIS U.S. LLC", matched)
        self.assertNotIn("ABBVIE INC", matched)
        labels = [d["label"] for d in drugs]
        self.assertIn("PLAVIX", labels)
        self.assertNotIn("HUMIRA", labels)

    def test_products_group_by_ingredient(self):
        drugs, _ = gp.match_products(self.index, "Sanofi")
        lantus = drug_named(drugs, "LANTUS")
        self.assertEqual(lantus["ingredients"], ["insulin glargine"])
        self.assertEqual(lantus["brand_names"], ["LANTUS", "LANTUS SOLOSTAR"])
        self.assertEqual(len([d for d in drugs if d["key"] == "insulin glargine"]), 1)

    def test_no_match_is_empty_not_another_company(self):
        drugs, matched = gp.match_products(self.index, "Johnson")
        self.assertEqual((drugs, matched), ([], []))


class NormalizeTests(unittest.TestCase):
    def test_salts_and_suffix(self):
        self.assertEqual(gp.normalize_ingredient("CLOPIDOGREL BISULFATE"), "clopidogrel")
        self.assertEqual(gp.normalize_ingredient("ISATUXIMAB-IRFC"), "isatuximab")
        self.assertEqual(gp.normalize_ingredient("LEVOCETIRIZINE DIHYDROCHLORIDE"), "levocetirizine")
        self.assertEqual(gp.normalize_ingredient("INSULIN GLARGINE RECOMBINANT"), "insulin glargine")

    def test_prefix_kept_so_zaltrap_is_not_eylea(self):
        self.assertEqual(gp.normalize_ingredient("ZIV-AFLIBERCEPT"), "ziv aflibercept")


class RowBelongsTests(unittest.TestCase):
    def setUp(self):
        drugs, _ = gp.match_products(gp.build_index(RAW), "Sanofi")
        self.drugs = drugs

    def keep(self, brand, rows):
        drug = drug_named(self.drugs, brand)
        aliases = gp.ingredient_aliases(rows, drug)
        return [r["drug"] for r in rows if gp.row_belongs(r, drug, aliases)]

    def test_same_family_neighbours_dropped(self):
        rows = [
            {"drug": "lantus", "ingredient": "insulin"},
            {"drug": "insulin glargine", "ingredient": "insulin"},
            {"drug": "humulin s", "ingredient": "insulin"},
            {"drug": "insulin glargine lixisenatide", "ingredient": "insulin;lixisenatide"},
        ]
        self.assertEqual(self.keep("LANTUS", rows), ["lantus", "insulin glargine"])

    def test_salt_free_equal_ingredient_kept(self):
        rows = [{"drug": "apo-clopidogrel", "ingredient": "clopidogrel"},
                {"drug": "aspirin clopidogrel", "ingredient": "aspirin;clopidogrel"}]
        self.assertEqual(self.keep("PLAVIX", rows), ["apo-clopidogrel"])

    def test_synonym_learned_from_brand_row(self):
        rows = [
            {"drug": "diabeta", "ingredient": "glibenclamide"},
            {"drug": "daonil", "ingredient": "glibenclamide"},
            {"drug": "glyburide metformin", "ingredient": "metformin"},
        ]
        self.assertEqual(self.keep("DIABETA", rows), ["diabeta", "daonil"])

    def test_coarser_family_not_learned_as_synonym(self):
        drug = drug_named(self.drugs, "LANTUS")
        rows = [{"drug": "lantus", "ingredient": "insulin"}]
        self.assertEqual(gp.ingredient_aliases(rows, drug), set())

    def test_zaltrap_keeps_only_zaltrap_rows(self):
        rows = [{"drug": "zaltrap", "ingredient": "aflibercept"},
                {"drug": "eylea", "ingredient": "aflibercept"}]
        self.assertEqual(self.keep("ZALTRAP", rows), ["zaltrap"])

    def test_family_bucket_not_learned_from_one_brand_row(self):
        rows = [
            {"drug": "ferrlecit", "ingredient": "iron"},
            {"drug": "ferinject", "ingredient": "iron"},
            {"drug": "venofer", "ingredient": "iron"},
            {"drug": "ferrous sulfate", "ingredient": "iron"},
        ]
        self.assertEqual(self.keep("FERRLECIT", rows), ["ferrlecit"])

    def test_combination_needs_the_whole_set(self):
        rows = [{"drug": "suliqua", "ingredient": "insulin;lixisenatide"},
                {"drug": "lixisenatide", "ingredient": "lixisenatide"}]
        # insulin glargine + lixisenatide: faers resolves glargine to the insulin
        # family, so the set differs; the reported name decides.
        self.assertEqual(self.keep("SOLIQUA 100/33", rows), [])
        rows2 = [{"drug": "insulin glargine lixisenatide", "ingredient": "insulin;lixisenatide"}]
        self.assertEqual(self.keep("SOLIQUA 100/33", rows2), ["insulin glargine lixisenatide"])


def faers_opener(table, calls=None):
    """Answer faers.mobi URLs from {drug_name: rows | int status}."""
    def opener(req, timeout=0):
        url = req.full_url
        name = urllib.parse.parse_qs(urllib.parse.urlsplit(url).query)["drug"][0]
        if calls is not None:
            calls.append(name)
        value = table.get(name, [])
        if isinstance(value, int):
            raise urllib.error.HTTPError(url, value, "err", {}, io.BytesIO(b""))
        return FakeResp(json.dumps(value).encode("utf-8"))
    return opener


SIG = {"event": "Haemorrhage", "n": 40, "eb05": 12.5, "trend": "Rising", "novel": "known"}


class FillAndServeTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.cache = gp.SignalCache(os.path.join(self.tmp.name, "signals"))
        self.index = gp.build_index(RAW)
        idx_path = os.path.join(self.tmp.name, "drugsfda_index.json")
        with open(idx_path, "w") as fh:
            json.dump(self.index, fh)
        self.store = gp.DrugsFdaStore(idx_path, opener=self._no_network)

    def tearDown(self):
        self.tmp.cleanup()

    @staticmethod
    def _no_network(*a, **k):
        raise AssertionError("page request must not touch the network")

    def fill(self, table, calls=None):
        return gp.refresh(self.index, self.cache, sponsor="Sanofi", pause_s=0,
                          opener=faers_opener(table, calls), log=lambda s: None)

    def doc(self):
        status, ctype, body = gp.handle_query({"sponsor": "Sanofi", "format": "json"},
                                              "", self.store, self.cache)
        self.assertEqual(status, 200)
        return json.loads(body)

    def test_unfilled_drugs_are_pending_not_empty(self):
        doc = self.doc()
        self.assertEqual({d["state"] for d in doc["drugs"]}, {"pending"})

    def test_failure_is_not_checked_and_retried(self):
        stats = self.fill({"clopidogrel": 504})
        self.assertGreaterEqual(stats["failed"], 1)
        plavix = next(d for d in self.doc()["drugs"] if d["label"] == "PLAVIX")
        self.assertEqual(plavix["state"], "not_checked")
        self.assertEqual(plavix["top_signals"] if "top_signals" in plavix else [], [])
        calls = []
        self.fill({"clopidogrel": [dict(SIG, drug="plavix", ingredient="clopidogrel")]}, calls)
        self.assertIn("clopidogrel", calls)   # failed entry retried despite being new
        plavix = next(d for d in self.doc()["drugs"] if d["label"] == "PLAVIX")
        self.assertEqual(plavix["state"], "signals")
        self.assertEqual(plavix["top_signals"][0]["event"], "Haemorrhage")

    def test_failed_recheck_keeps_good_rows(self):
        good = [dict(SIG, drug="plavix", ingredient="clopidogrel")]
        self.fill({"clopidogrel": good})
        gp.refresh(self.index, self.cache, sponsor="Sanofi", pause_s=0, max_age_days=0,
                   opener=faers_opener({"clopidogrel": 504}), log=lambda s: None)
        plavix = next(d for d in self.doc()["drugs"] if d["label"] == "PLAVIX")
        self.assertEqual(plavix["state"], "signals")
        key = next(d["key"] for d in gp.match_products(self.index, "Sanofi")[0]
                   if d["label"] == "PLAVIX")
        self.assertIn("last_error", self.cache.get(key))

    def test_unwritable_cache_raises(self):
        blocker = os.path.join(self.tmp.name, "blocker")
        open(blocker, "w").close()
        cache = gp.SignalCache(os.path.join(blocker, "signals"))   # parent is a file
        with self.assertRaises(OSError):
            cache.put({"key": "x", "ok": True, "rows": []})

    def test_unknown_label_and_trend_counted_separately(self):
        rows = [dict(SIG, drug="plavix", ingredient="clopidogrel", novel="?", trend="")]
        self.fill({"clopidogrel": rows})
        plavix = next(d for d in self.doc()["drugs"] if d["label"] == "PLAVIX")
        self.assertEqual((plavix["events_novel"], plavix["events_label_unknown"]), (0, 1))
        self.assertEqual((plavix["events_rising"], plavix["events_trend_unknown"]), (0, 1))

    def test_small_n_pairs_not_shown(self):
        rows = [dict(SIG, drug="plavix", ingredient="clopidogrel", event="Tiny", n=4, eb05=900.0),
                dict(SIG, drug="plavix", ingredient="clopidogrel")]
        self.fill({"clopidogrel": rows})
        plavix = next(d for d in self.doc()["drugs"] if d["label"] == "PLAVIX")
        self.assertEqual([t["event"] for t in plavix["top_signals"]], ["Haemorrhage"])

    def test_min_n_sent_to_faers(self):
        self.assertIn("min_n=10", gp.faers_url("clopidogrel"))

    def test_fresh_entries_skipped(self):
        self.fill({})
        calls = []
        stats = self.fill({}, calls)
        self.assertEqual(calls, [])
        self.assertEqual(stats["fresh"], stats["drugs"])

    def test_empty_answer_is_none_isolated(self):
        self.fill({})
        states = {d["label"]: d["state"] for d in self.doc()["drugs"]}
        self.assertEqual(states["PLAVIX"], "none_isolated")

    def test_only_neighbours_is_other_products_only(self):
        self.fill({"insulin glargine": [dict(SIG, drug="humulin s", ingredient="insulin")]})
        lantus = next(d for d in self.doc()["drugs"] if "LANTUS" in d["brand_names"])
        self.assertEqual(lantus["state"], "other_products_only")
        self.assertNotIn("Haemorrhage", json.dumps(lantus.get("top_signals", [])))

    def test_count_shown_is_n_when_no_n_unique(self):
        self.fill({"clopidogrel": [dict(SIG, drug="plavix", ingredient="clopidogrel")]})
        _s, _c, body = gp.handle_query({"sponsor": "Sanofi", "format": "brief"}, "",
                                       self.store, self.cache)
        text = body.decode("utf-8")
        self.assertIn("n 40", text)
        self.assertNotIn("reports 40", text)
        self.assertIn("not a count of distinct reports", text)

    def test_html_carries_disclaimer_and_reported_name(self):
        self.fill({"clopidogrel": [dict(SIG, drug="plavix", ingredient="clopidogrel")]})
        _s, ctype, body = gp.handle_query({"sponsor": "Sanofi"}, "text/html",
                                          self.store, self.cache)
        page = body.decode("utf-8")
        self.assertTrue(ctype.startswith("text/html"))
        self.assertIn("not this company's product alone", page)
        self.assertIn("reported as plavix", page)
        self.assertIn('href="/pipeline"', page)
        self.assertIn("https://faers.mobi/?q=clopidogrel", page)

    def test_paging(self):
        doc = json.loads(gp.handle_query({"sponsor": "Sanofi", "limit": "2", "format": "json"},
                                         "", self.store, self.cache)[2])
        self.assertEqual(doc["n_returned"], 2)
        self.assertEqual(doc["next_offset"], 2)


class ValidateTests(unittest.TestCase):
    def test_bad_params(self):
        self.assertEqual(gp.validate({"format": "xml"})["status"], 400)
        self.assertEqual(gp.validate({"limit": "0"})["status"], 400)
        self.assertEqual(gp.validate({"limit": "abc"})["status"], 400)
        self.assertEqual(gp.validate({"offset": "-1"})["status"], 400)
        self.assertEqual(gp.validate({"sponsor": "ab"})["status"], 400)

    def test_json_without_sponsor_is_400(self):
        store = gp.DrugsFdaStore("/nonexistent/x.json", opener=FillAndServeTests._no_network)
        status, _c, _b = gp.handle_query({"format": "json"}, "", store, gp.SignalCache("/nonexistent"))
        self.assertEqual(status, 400)


class StoreTests(unittest.TestCase):
    def test_download_builds_index(self):
        with tempfile.TemporaryDirectory() as tmp:
            store = gp.DrugsFdaStore(os.path.join(tmp, "i.json"),
                                     opener=lambda req, timeout=0: FakeResp(zipped(RAW)))
            index = store.get()
            self.assertEqual(index["last_updated"], "2026-11-16")
            self.assertTrue(os.path.exists(os.path.join(tmp, "i.json")))

    def test_outage_is_503_and_backs_off(self):
        calls = []

        def down(req, timeout=0):
            calls.append(1)
            raise urllib.error.URLError("down")

        with tempfile.TemporaryDirectory() as tmp:
            store = gp.DrugsFdaStore(os.path.join(tmp, "i.json"), opener=down)
            cache = gp.SignalCache(os.path.join(tmp, "s"))
            for _ in range(3):
                status, _c, body = gp.handle_query({"sponsor": "Sanofi", "format": "json"},
                                                   "", store, cache)
                self.assertEqual(status, 503)
                self.assertNotIn("drugs", json.loads(body))
            self.assertEqual(len(calls), 1)   # later requests did not re-download

    def test_openapi_path_shape(self):
        spec = gp.openapi_path()
        self.assertEqual(spec["get"]["operationId"], "getPortfolioSafety")


if __name__ == "__main__":
    unittest.main()
