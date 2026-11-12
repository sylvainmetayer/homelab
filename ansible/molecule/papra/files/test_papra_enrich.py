"""Tests de papra_enrich.py (rôle papra), lancés par verify.yml du scénario
avec le python3 de l'hôte de test : un faux Papra et une fausse passerelle IA
sur 127.0.0.1, aucun appel réseau sortant. À la main : copier ce fichier à
côté de ansible/roles/papra/files/papra_enrich.py, puis
python3 -I -m unittest discover -s . -p 'test_*.py'.
"""

import copy
import datetime
import json
import tempfile
import threading
import unittest
import urllib.error
from http.server import BaseHTTPRequestHandler, HTTPServer
from unittest import mock

import papra_enrich as pe

ORG = "/api/organizations/org_test"
OLD = "2026-01-05T10:00:00.000Z"
NEW = (datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(hours=1)).isoformat().replace("+00:00", "Z")
TAGS = [
    {"id": f"tag_{name.lower()}", "name": name}
    for name in ("Facture", "Energie", "Sante", "Identite", "Banque-Finances", "Impots", "Travail-RH", "IA-faite")
]
DEFINITIONS = [
    {"id": "cpd_montant", "name": "Montant", "type": "number"},
    {"id": "cpd_fin", "name": "Fin de validité", "type": "date"},
]
ANSWER = {"montant": 42.5, "fin_validite": "2028-01-31", "tags": ["Energie", "Sante", "Inconnu", "IA-faite"]}


def tag(name):
    return next(t for t in TAGS if t["name"] == name)


def document(doc_id, tags, created=OLD, content=None, montant=None, fin=None):
    return {
        "id": doc_id, "createdAt": created, "tags": [tag(name) for name in tags],
        "content": f"Texte de {doc_id}, total 42,50 EUR" if content is None else content,
        "customProperties": [
            {"key": "montant", "name": "Montant", "type": "number", "value": montant},
            {"key": "fin", "name": "Fin de validité", "type": "date", "value": fin},
        ],
    }


DOCUMENTS = [
    document("doc_ok", ["Facture"]),
    document("doc_sante", ["Facture", "Sante"]),
    document("doc_identite", ["Identite"]),
    document("doc_sans_tag", []),
    document("doc_recent", ["Facture"], created=NEW),
    document("doc_saisi", ["Facture"], montant=10, fin="2030-05-01T00:00:00.000Z"),
    document("doc_fait", ["Facture", "IA-faite"]),
    document("doc_vide", ["Facture"], content="  "),
    document("doc_long", ["Facture"], content="x" * 5000),
]


class Fake(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def reply(self, status, payload=None):
        data = b"" if payload is None else json.dumps(payload).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def handle_any(self):
        state = self.server.state
        length = int(self.headers.get("Content-Length") or 0)
        body = json.loads(self.rfile.read(length)) if length else None
        path = self.path.split("?")[0]
        if path == "/redirect":
            self.send_response(302)
            self.send_header("Location", state["location"])
            self.send_header("Content-Length", "0")
            self.end_headers()
            return
        state["requests"].append((self.command, self.path, body, self.headers["Authorization"]))
        if path == "/v1/chat/completions":
            if state["ai_status"] != 200:
                return self.reply(state["ai_status"], {"error": "budget"})
            content = state.get("ai_content", "Voici :\n" + json.dumps(ANSWER))
            return self.reply(200, {"choices": [{"message": {"content": content}, "finish_reason": "length"}],
                                    "usage": {"total_tokens": 3650}})
        if path == f"{ORG}/tags":
            return self.reply(200, {"tags": state["tags"]})
        if path == f"{ORG}/custom-properties":
            return self.reply(200, {"propertyDefinitions": DEFINITIONS})
        if path == f"{ORG}/documents":
            page = 0 if "pageIndex=0" in self.path else 1
            listed = [{k: v for k, v in doc.items() if k != "content"} for doc in state["documents"]]
            return self.reply(200, {"documents": listed if page == 0 else [], "documentsCount": len(listed)})
        for doc in state["documents"]:
            if path == f"{ORG}/documents/{doc['id']}":
                return self.reply(200, {"document": doc})
            if self.command != "GET" and path.startswith(f"{ORG}/documents/{doc['id']}/"):
                return self.reply(state["write_status"].get(doc["id"], 204))
        return self.reply(404, {"error": "not found"})

    do_GET = do_POST = do_PUT = handle_any


class EnrichTest(unittest.TestCase):
    def setUp(self):
        self.server = HTTPServer(("127.0.0.1", 0), Fake)
        self.server.state = {"requests": [], "ai_status": 200, "tags": copy.deepcopy(TAGS),
                             "documents": copy.deepcopy(DOCUMENTS), "write_status": {}}
        threading.Thread(target=self.server.serve_forever, daemon=True).start()
        self.addCleanup(self.server.server_close)
        self.addCleanup(self.server.shutdown)
        url = f"http://127.0.0.1:{self.server.server_address[1]}"
        patcher = mock.patch.object(pe, "papra_url", return_value=url)
        patcher.start()
        self.addCleanup(patcher.stop)
        self.config = {
            "container": "papra", "organization_id": "org_test",
            "papra_api_key": "papra-test-key", "ai_api_key": "gateway-test-key",
            "ai_base_url": f"{url}/v1", "model": "claude-haiku-5-5",
            "excluded_tags": ["Sante", "Identite", "Banque-Finances", "Impots", "Travail-RH"],
            "done_tag": "IA-faite", "amount_property": "Montant", "expiry_property": "Fin de validité",
            "batch_size": 20, "max_chars": 1000, "skip_chars": 4000,
        }

    def run_pass(self, dry_run=False, limit=20):
        with mock.patch("builtins.print"):
            pe.run(self.config, dry_run, limit)

    def requests(self, method=None, prefix=""):
        return [r for r in self.server.state["requests"] if (method is None or r[0] == method) and r[1].startswith(prefix)]

    def ai_calls(self):
        return self.requests("POST", "/v1/chat/completions")

    def touched(self, doc_id):
        return [r for r in self.server.state["requests"] if f"/documents/{doc_id}" in r[1]]

    def test_only_eligible_documents_reach_the_model(self):
        self.run_pass()
        sent = "\n".join(r[2]["messages"][1]["content"] for r in self.ai_calls())
        self.assertEqual(len(self.ai_calls()), 2, sent)
        self.assertIn("Texte de doc_ok", sent)
        self.assertIn("Texte de doc_saisi", sent)
        # Tag exclu, sans tag, importé il y a moins de 24 h, déjà traité : pas même relu.
        for doc_id in ("doc_sante", "doc_identite", "doc_sans_tag", "doc_recent", "doc_fait"):
            self.assertEqual(self.touched(doc_id), [], doc_id)
        # Sans texte, ou trop long : relu, jamais envoyé ni marqué.
        for doc_id in ("doc_vide", "doc_long"):
            self.assertEqual([r[0] for r in self.touched(doc_id)], ["GET"], doc_id)
        # Les exclus et la marque ne sont jamais proposés au modèle.
        allowed = json.loads(self.ai_calls()[0][2]["messages"][1]["content"].split("\n")[0].split(" : ", 1)[1])
        self.assertEqual(allowed, ["Energie", "Facture"])

    def test_empty_answer_stops_the_pass_and_marks_nothing(self):
        # Réflexion qui mange max_tokens : contenu vide, rien ne doit être marqué IA-faite.
        self.server.state["ai_content"] = ""
        with self.assertRaisesRegex(RuntimeError, "sans objet JSON"):
            self.run_pass()
        self.assertEqual(len(self.ai_calls()), 1)
        self.assertEqual([r for r in self.requests() if r[0] != "GET" and r[1].startswith(ORG)], [])

    def test_request_has_no_temperature(self):
        # Les modèles Claude 5 refusent `temperature` (HTTP 400, 12/11/2026).
        self.run_pass()
        self.assertTrue(all("temperature" not in r[2] for r in self.ai_calls()))

    def test_fills_empty_fields_and_existing_tags_only(self):
        self.run_pass()
        writes = [(r[0], r[1].removeprefix(ORG), r[2]) for r in self.requests() if r[0] != "GET" and r[1].startswith(ORG)]
        self.assertEqual(writes, [
            # La marque d'abord.
            ("POST", "/documents/doc_ok/tags", {"tagId": "tag_ia-faite"}),
            ("POST", "/documents/doc_ok/tags", {"tagId": "tag_energie"}),
            ("PUT", "/documents/doc_ok/custom-properties/cpd_montant", {"value": 42.5}),
            ("PUT", "/documents/doc_ok/custom-properties/cpd_fin", {"value": "2028-01-31"}),
            # Montant et Fin de validité déjà saisis : rien d'écrasé, seulement la marque et le tag.
            ("POST", "/documents/doc_saisi/tags", {"tagId": "tag_ia-faite"}),
            ("POST", "/documents/doc_saisi/tags", {"tagId": "tag_energie"}),
        ])
        self.assertEqual({r[3] for r in self.requests(prefix=ORG)}, {"Bearer papra-test-key"})
        self.assertEqual({r[3] for r in self.ai_calls()}, {"Bearer gateway-test-key"})

    def test_text_is_truncated(self):
        self.server.state["documents"] = [document("doc_ok", ["Facture"], content="y" * 3000)]
        self.run_pass()
        self.assertEqual(self.ai_calls()[0][2]["messages"][1]["content"].count("y"), 1000)

    def test_missing_excluded_tag_stops_before_sending(self):
        self.server.state["tags"] = [t for t in TAGS if t["name"] != "Identite"]
        with self.assertRaisesRegex(RuntimeError, "Identite"):
            self.run_pass()
        self.assertEqual(self.ai_calls(), [])
        self.assertEqual(self.requests(prefix=f"{ORG}/documents"), [])

    def test_missing_done_tag_stops_before_sending(self):
        self.server.state["tags"] = [t for t in TAGS if t["name"] != "IA-faite"]
        with self.assertRaisesRegex(RuntimeError, "IA-faite"):
            self.run_pass()
        self.assertEqual(self.ai_calls(), [])

    def test_gateway_error_stops_the_pass(self):
        self.server.state["ai_status"] = 429
        with self.assertRaises(urllib.error.HTTPError):
            self.run_pass()
        self.assertEqual(len(self.ai_calls()), 1)
        self.assertEqual([r for r in self.requests() if r[0] != "GET" and r[1].startswith(ORG)], [])

    def test_a_document_papra_refuses_does_not_stop_the_pass(self):
        self.server.state["write_status"] = {"doc_ok": 400}
        self.run_pass()
        self.assertEqual(len(self.ai_calls()), 2)
        self.assertIn(("POST", f"{ORG}/documents/doc_saisi/tags", {"tagId": "tag_ia-faite"}),
                      [r[:3] for r in self.requests()])

    def test_main_exits_cleanly_on_gateway_error(self):
        self.server.state["ai_status"] = 429
        with tempfile.NamedTemporaryFile("w", suffix=".json", encoding="utf-8") as f:
            json.dump(self.config, f)
            f.flush()
            with mock.patch("sys.argv", ["papra_enrich.py", "--config", f.name]), \
                    mock.patch("builtins.print") as printed:
                self.assertEqual(pe.main(), 1)
        self.assertIn("HTTP 429", printed.call_args.args[0])
        self.assertNotIn("Texte de", printed.call_args.args[0])
        self.assertEqual(len(self.ai_calls()), 1)

    def test_a_redirect_is_an_error_and_keeps_the_bearer_home(self):
        target = HTTPServer(("127.0.0.1", 0), Fake)
        target.state = {"requests": []}
        threading.Thread(target=target.serve_forever, daemon=True).start()
        self.addCleanup(target.server_close)
        self.addCleanup(target.shutdown)
        self.server.state["location"] = f"http://127.0.0.1:{target.server_address[1]}{ORG}/tags"
        with self.assertRaises(urllib.error.HTTPError) as caught:
            pe.call(f"http://127.0.0.1:{self.server.server_address[1]}/redirect", "papra-test-key")
        self.assertEqual(caught.exception.code, 302)
        self.assertEqual(target.state["requests"], [])

    def test_dry_run_writes_nothing(self):
        self.run_pass(dry_run=True)
        self.assertEqual(len(self.ai_calls()), 2)
        self.assertEqual([r for r in self.requests() if r[0] != "GET" and r[1].startswith(ORG)], [])

    def test_limit_counts_documents_sent(self):
        self.run_pass(limit=1)
        self.assertEqual(len(self.ai_calls()), 1)


class ParseTest(unittest.TestCase):
    def test_amount(self):
        self.assertEqual([pe.amount(v) for v in (12, 3.5, "12", True, float("nan"), None)], [12, 3.5, None, None, None, None])

    def test_expiry(self):
        self.assertEqual([pe.expiry(v) for v in ("2027-02-28", "28/02/2027", None, 5)], ["2027-02-28", None, None, None])


if __name__ == "__main__":
    unittest.main()
