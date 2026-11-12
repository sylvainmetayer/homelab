import io
import json
import unittest
from unittest import mock

import papra_mcp as m

DOC = {"document": {"id": "doc_1", "name": "Facture", "content": "texte OCR", "tags": [{"id": "tag_1"}]}}


def fake_urlopen(sent, payload=b"{}"):
    def fake(req, timeout):
        sent.append((req.get_method(), req.full_url, req.data, req.get_header("Authorization"), req.get_header("P-access-token")))
        return io.BytesIO(payload)

    return fake


class PapraMcpTest(unittest.TestCase):
    def test_every_tool_is_allowlisted_and_delete_is_only_tag_removal(self):
        self.assertEqual(len(m.TOOLS), 9)
        for _, _, method, path in m.TOOLS.values():
            m.check_allowed(method, path.replace("{org}", "o").replace("{id}", "d").replace("{tag}", "t"))
        self.assertEqual([p for method, p in m.ALLOWED if method == "DELETE"], [m.ORG + r"/documents/[A-Za-z0-9_-]+/tags/[A-Za-z0-9_-]+"])
        self.assertEqual([t for t, (_, _, method, _) in m.TOOLS.items() if method == "DELETE"], ["remove_tag"])

    def test_refused_calls(self):
        for method, path in [
            ("DELETE", "/organizations/o/documents/d"), ("DELETE", "/organizations/o/documents/trash/d"),
            ("DELETE", "/organizations/o/documents/trash"), ("DELETE", "/organizations/o/tags/t"),
            ("DELETE", "/organizations/o"), ("DELETE", "/organizations/o/documents/d/tags"),
            ("PATCH", "/organizations/o/documents/d"), ("PUT", "/organizations/o/tags/t"),
            ("POST", "/organizations/o/documents"), ("POST", "/organizations/o/documents/d/reprocess"),
            ("POST", "/organizations/o/documents/d/restore"), ("POST", "/organizations/o/restore"),
            ("POST", "/organizations"), ("GET", "/organizations/o/documents/d/file"),
            ("GET", "/organizations/o/api-keys"), ("GET", "/api-keys"), ("DELETE", "/organizations/o/documents/d/tags/t/x"),
        ]:
            with self.assertRaises(ValueError, msg=(method, path)):
                m.check_allowed(method, path)
            with self.assertRaises(ValueError, msg=(method, path)):
                m.call_papra(method, path, {}, "http://x", "k")

    def test_bad_ids_are_refused(self):
        for bad in ["..", ".", "", "a/b", "../x", "a?b", None, 3]:
            for tool in ["get_document", "remove_tag", "add_tag"]:
                _, _, method, path = m.TOOLS[tool]
                for arg in ["organizationId", "id", "tagId"][: 2 if tool == "get_document" else 3]:
                    args = {"organizationId": "o", "id": "d", "tagId": "t", arg: bad}
                    with self.assertRaises(ValueError, msg=(tool, arg, bad)):
                        m.call_papra(method, path, args, "http://x", "k")

    def test_bodies_are_checked(self):
        for tool, args in [
            ("create_tag", {"organizationId": "o", "name": "x", "color": "rouge"}),
            ("create_tag", {"organizationId": "o", "name": "x", "color": "#abcdef", "id": "y"}),
            ("create_tag", {"organizationId": "o", "name": 3, "color": "#abcdef"}),
            ("add_tag", {"organizationId": "o", "id": "d", "tagId": "../x"}),
            ("add_tag", {"organizationId": "o", "id": "d", "tagId": "t", "name": "x"}),
            ("remove_tag", {"organizationId": "o", "id": "d", "tagId": "t", "name": "x"}),
        ]:
            _, _, method, path = m.TOOLS[tool]
            with self.assertRaises(ValueError, msg=(tool, args)):
                m.call_papra(method, path, args, "http://x", "k")

    def test_add_and_remove_tag(self):
        sent = []
        with mock.patch("urllib.request.urlopen", fake_urlopen(sent, b"")):
            _, _, method, path = m.TOOLS["add_tag"]
            r = m.call_papra(method, path, {"organizationId": "o", "id": "d", "tagId": "t"}, "http://h/", "k", {"P-Access-Token": "p"})
            _, _, method, path = m.TOOLS["remove_tag"]
            m.call_papra(method, path, {"organizationId": "o", "id": "d", "tagId": "t"}, "http://h", "k")
        self.assertEqual(r, {"ok": True})
        self.assertEqual(sent[0], ("POST", "http://h/api/organizations/o/documents/d/tags", b'{"tagId": "t"}', "Bearer k", "p"))
        self.assertEqual(sent[1][:3], ("DELETE", "http://h/api/organizations/o/documents/d/tags/t", None))

    def test_search_query_and_no_content(self):
        sent = []
        listing = json.dumps({"documents": [DOC["document"]], "documentsCount": 1}).encode()
        with mock.patch("urllib.request.urlopen", fake_urlopen(sent, listing)):
            call = lambda *a: m.call_papra(*a, "http://h", "k")
            r = m.handle({"id": 1, "method": "tools/call", "params": {"name": "search_documents", "arguments": {
                "organizationId": "o", "searchQuery": "edf bleu", "pageSize": 5}}}, call)
        self.assertEqual(sent[0][1], "http://h/api/organizations/o/documents?searchQuery=edf+bleu&pageSize=5")
        self.assertNotIn("texte OCR", r["result"]["content"][0]["text"])
        self.assertIn("Facture", r["result"]["content"][0]["text"])

    def test_text_tool_returns_only_content(self):
        call = lambda *a: json.loads(json.dumps(DOC))
        r = m.handle({"id": 1, "method": "tools/call", "params": {"name": "get_document_text", "arguments": {}}}, call)
        self.assertEqual(json.loads(r["result"]["content"][0]["text"]), {"content": "texte OCR"})

    def test_notification_gets_no_reply(self):
        self.assertIsNone(m.handle({"method": "notifications/initialized"}, None))

    def test_missing_or_null_params_is_not_fatal(self):
        self.assertIn("error", m.handle({"id": 4, "method": "tools/call"}, None))
        self.assertIn("error", m.handle({"id": 5, "method": "tools/call", "params": None}, None))
        seen = []
        m.handle({"id": 6, "method": "tools/call", "params": {"name": "list_organizations", "arguments": None}},
                 lambda *a: seen.append(a) or {})
        self.assertEqual(seen, [("GET", "/organizations", {})])
        self.assertEqual(m.handle({"id": 7, "method": "initialize", "params": None}, None)["result"]["serverInfo"]["name"], "papra")

    def test_tool_error_is_not_fatal(self):
        def boom(*a):
            raise OSError("down")

        r = m.handle({"id": 3, "method": "tools/call", "params": {"name": "list_tags"}}, boom)
        self.assertTrue(r["result"]["isError"])


if __name__ == "__main__":
    unittest.main()
