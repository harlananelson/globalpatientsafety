#!/usr/bin/env python3
"""Offline checks for the pipeline service. No ClinicalTrials.gov calls."""

import io
import json
import unittest
import urllib.error
import urllib.parse

import gps_pipeline as gp


FIXTURE = {
    "totalCount": 2,
    "nextPageToken": "tok",
    "studies": [
        {
            "protocolSection": {
                "identificationModule": {
                    "nctId": "NCT05231668",
                    "briefTitle": "A real title",
                },
                "statusModule": {"overallStatus": "RECRUITING"},
                "sponsorCollaboratorsModule": {"leadSponsor": {"name": "Sanofi"}},
                "conditionsModule": {"conditions": ["Osteogenesis Imperfecta"]},
                "designModule": {"phases": ["PHASE2"]},
                "armsInterventionsModule": {
                    "interventions": [{"name": "SAR439459"}, {"name": "Placebo"}]
                },
            }
        },
        {
            "protocolSection": {
                "identificationModule": {"nctId": "NOT-AN-ID", "briefTitle": "drop me"},
                "statusModule": {"overallStatus": "COMPLETED"},
                "sponsorCollaboratorsModule": {"leadSponsor": {"name": "Sanofi"}},
                "designModule": {"phases": ["PHASE3"]},
            }
        },
    ],
}


class FakeResp(io.BytesIO):
    status = 200

    def __enter__(self):
        return self

    def __exit__(self, *args):
        return False


def opener_ok(req, timeout=0):
    return FakeResp(json.dumps(FIXTURE).encode())


def opener_down(req, timeout=0):
    raise TimeoutError("timed out")


def opener_500(req, timeout=0):
    raise urllib.error.HTTPError(req.full_url, 503, "down", hdrs=None, fp=io.BytesIO(b""))


class PipelineTests(unittest.TestCase):
    def setUp(self):
        gp._cache.clear()

    def test_drops_invented_ids_and_counts_the_real_one(self):
        doc = gp.shape_payload(FIXTURE, "Sanofi", "2026-10-10T00:00:00Z")
        self.assertEqual([s["nct_id"] for s in doc["studies"]], ["NCT05231668"])
        self.assertEqual(doc["n_studies"], 2)
        self.assertEqual(doc["n_returned"], 1)
        self.assertEqual(doc["sponsor_matched"], "Sanofi")
        self.assertIn("NCT05231668", doc["studies"][0]["url"])
        self.assertNotIn("NOT-AN-ID", json.dumps(doc))

    def test_unknown_sponsor_is_empty_200(self):
        empty = {"totalCount": 0, "studies": []}

        def opener(req, timeout=0):
            return FakeResp(json.dumps(empty).encode())

        status, ctype, body = gp.handle_query({"sponsor": "NoSuchCoZZZ"}, "", opener)
        self.assertEqual(status, 200)
        doc = json.loads(body)
        self.assertEqual(doc["n_studies"], 0)
        self.assertEqual(doc["studies"], [])
        self.assertNotRegex(body.decode(), r"NCT\d{8}")

    def test_timeout_is_503_and_not_an_empty_success(self):
        status, ctype, body = gp.handle_query(
            {"sponsor": "Sanofi", "format": "json"}, "", opener_down
        )
        self.assertEqual(status, 503)
        doc = json.loads(body)
        self.assertIn("error", doc)
        self.assertNotIn("studies", doc)
        self.assertNotRegex(body.decode(), r"NCT\d{8}")

    def test_upstream_5xx_is_502(self):
        status, _ctype, body = gp.handle_query({"sponsor": "Sanofi"}, "", opener_500)
        self.assertEqual(status, 502)
        self.assertIn("error", json.loads(body))

    def test_html_accept_has_a_labelled_form_and_a_real_table(self):
        status, ctype, body = gp.handle_query(
            {"sponsor": "Sanofi"}, "text/html", opener_ok
        )
        self.assertEqual(status, 200)
        self.assertTrue(ctype.startswith("text/html"))
        text = body.decode()
        self.assertIn('for="sponsor"', text)
        self.assertIn("<table>", text)
        self.assertIn("<caption>", text)
        self.assertIn('scope="col"', text)
        self.assertIn("NCT05231668", text)
        self.assertIn('id="main"', text)
        self.assertIn('lang="en"', text)

    def test_brief_is_plain_text_and_names_the_disclaimer(self):
        status, ctype, body = gp.handle_query(
            {"sponsor": "Sanofi", "format": "brief"}, "", opener_ok
        )
        self.assertEqual(status, 200)
        self.assertTrue(ctype.startswith("text/plain"))
        text = body.decode()
        self.assertIn("NCT05231668", text)
        self.assertIn("Not efficacy", text)
        self.assertNotIn("NOT-AN-ID", text)

    def test_bad_format_and_limit(self):
        status, _c, body = gp.handle_query({"sponsor": "Sanofi", "format": "pdf"}, "", opener_ok)
        self.assertEqual(status, 400)
        self.assertIn("brief", body.decode())
        status, _c, body = gp.handle_query({"sponsor": "Sanofi", "limit": "9999"}, "", opener_ok)
        self.assertEqual(status, 400)

    def test_missing_sponsor_json_is_400_and_html_is_the_form(self):
        status, _c, body = gp.handle_query({"format": "json"}, "", opener_ok)
        self.assertEqual(status, 400)
        status, ctype, body = gp.handle_query({}, "text/html", opener_ok)
        self.assertEqual(status, 200)
        self.assertIn("<form", body.decode())
        self.assertNotRegex(body.decode(), r"NCT\d{8}")

    def test_default_status_is_ongoing_and_all_is_unfiltered(self):
        seen = []

        def opener(req, timeout=0):
            seen.append(req.full_url)
            return FakeResp(json.dumps({"totalCount": 0, "studies": []}).encode())

        status, _c, body = gp.handle_query(
            {"sponsor": "Sanofi", "format": "json", "limit": "5"}, "", opener
        )
        self.assertEqual(status, 200)
        self.assertIn("filter.overallStatus=RECRUITING", seen[0])
        self.assertIn("ACTIVE_NOT_RECRUITING", seen[0])
        self.assertIn("AREA%5BLeadSponsorName%5D", seen[0])
        self.assertIn("%22Sanofi%22", seen[0])
        self.assertNotIn("query.spons", seen[0])
        doc = json.loads(body)
        self.assertTrue(doc["status_default"])
        self.assertIn("RECRUITING", doc["status_filter"])

        seen.clear()
        status, ctype, body = gp.handle_query(
            {"sponsor": "Sanofi", "format": "brief", "limit": "5"}, "", opener
        )
        self.assertEqual(status, 200)
        self.assertTrue(ctype.startswith("text/plain"))
        self.assertIn("Scope: ongoing studies.", body.decode())

        seen.clear()
        status, _c, body = gp.handle_query(
            {"sponsor": "Sanofi", "status": "ALL", "format": "json", "limit": "5"},
            "", opener,
        )
        self.assertEqual(status, 200)
        self.assertNotIn("overallStatus", seen[0])
        doc = json.loads(body)
        self.assertFalse(doc["status_default"])
        self.assertIsNone(doc["status_filter"])

        status, _c, body = gp.handle_query(
            {"sponsor": "Sanofi", "status": "NOPE"}, "", opener
        )
        self.assertEqual(status, 400)
        self.assertIn("ALL", body.decode())

    def test_zero_result_html_is_not_an_error_page(self):
        def opener(req, timeout=0):
            return FakeResp(json.dumps({"totalCount": 0, "studies": []}).encode())

        status, _c, body = gp.handle_query(
            {"sponsor": "NoSuchCoZZZ", "format": "html"}, "", opener
        )
        self.assertEqual(status, 200)
        text = body.decode()
        self.assertIn("No studies found for NoSuchCoZZZ", text)
        self.assertIn("as lead sponsor", text)
        self.assertNotIn("<table>", text)

    def _mixed(self):
        def study(nct, lead, collaborators=None, title="T"):
            module = {"leadSponsor": {"name": lead}}
            if collaborators:
                module["collaborators"] = [{"name": name} for name in collaborators]
            return {
                "protocolSection": {
                    "identificationModule": {"nctId": nct, "briefTitle": title},
                    "statusModule": {"overallStatus": "RECRUITING"},
                    "sponsorCollaboratorsModule": module,
                    "designModule": {"phases": ["PHASE3"]},
                }
            }
        return {
            "totalCount": 4,
            "studies": [
                study("NCT00000001", "Sanofi", title="Plain"),
                study("NCT00000002", "Sanofi Pasteur, a Sanofi Company", title="Family"),
                study("NCT00000003", "Regeneron Pharmaceuticals", ["Sanofi"], title="Collab"),
                study("NCT00000004", "Karolinska Institutet", title="Neither"),
            ],
        }

    def test_default_role_keeps_family_leads_only(self):
        doc = gp.shape_payload(self._mixed(), "Sanofi", "2026-10-11T00:00:00Z")
        self.assertEqual(doc["role_filter"], "lead")
        self.assertEqual(
            sorted(s["nct_id"] for s in doc["studies"]),
            ["NCT00000001", "NCT00000002"],
        )
        self.assertEqual({s["role"] for s in doc["studies"]}, {"lead"})
        self.assertEqual(doc["n_returned"], 2)
        # Registry total stays totalCount. The live request asks LeadSponsorName
        # so that total is already the lead-only count.
        self.assertEqual(doc["n_studies"], 4)
        self.assertNotIn("Regeneron", json.dumps(doc["studies"]))

    def test_role_any_restores_every_row_and_labels_it(self):
        seen = []

        def opener(req, timeout=0):
            seen.append(req.full_url)
            return FakeResp(json.dumps(self._mixed()).encode())

        status, _c, body = gp.handle_query(
            {"sponsor": "Sanofi", "role": "any", "format": "json", "status": "ALL"},
            "", opener,
        )
        self.assertEqual(status, 200)
        self.assertIn("query.spons=Sanofi", seen[0])
        self.assertNotIn("filter.advanced", seen[0])
        doc = json.loads(body)
        self.assertEqual(doc["role_filter"], "any")
        self.assertEqual(doc["n_studies"], 4)
        roles = {s["nct_id"]: s["role"] for s in doc["studies"]}
        self.assertEqual(roles["NCT00000001"], "lead")
        self.assertEqual(roles["NCT00000002"], "lead")
        self.assertEqual(roles["NCT00000003"], "collaborator")
        self.assertEqual(roles["NCT00000004"], "collaborator")

    def test_role_collaborator_uses_collaborator_area(self):
        seen = []

        def opener(req, timeout=0):
            seen.append(urllib.parse.unquote(req.full_url))
            return FakeResp(json.dumps(self._mixed()).encode())

        status, _c, body = gp.handle_query(
            {"sponsor": "Sanofi", "role": "collaborator", "format": "brief", "status": "ALL"},
            "", opener,
        )
        self.assertEqual(status, 200)
        self.assertIn('AREA[CollaboratorName]"Sanofi"', seen[0])
        self.assertNotIn("query.spons", seen[0])
        text = body.decode()
        self.assertIn("Collaborator only", text)
        self.assertIn("NCT00000003", text)
        self.assertNotIn("NCT00000001", text)
        self.assertIn("collaborator", text)

    def test_unknown_role_is_400(self):
        status, _c, body = gp.handle_query(
            {"sponsor": "Sanofi", "role": "both"}, "", opener_ok
        )
        self.assertEqual(status, 400)
        self.assertIn("collaborator", body.decode())

    def test_html_names_the_lead_role(self):
        status, _c, body = gp.handle_query(
            {"sponsor": "Sanofi", "format": "html"}, "", opener_ok
        )
        text = body.decode()
        self.assertEqual(status, 200)
        self.assertIn('for="role"', text)
        self.assertIn("Lead sponsor only", text)
        self.assertIn("<th scope=\"col\">Role</th>", text)


if __name__ == "__main__":
    unittest.main()
