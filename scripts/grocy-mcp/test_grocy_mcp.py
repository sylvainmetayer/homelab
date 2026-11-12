import io
import json
import unittest
from unittest import mock

import grocy_mcp as m


def fake_urlopen(sent, payload=b"{}"):
    def fake(req, timeout):
        sent.append((req.get_method(), req.full_url, req.data, req.get_header("Grocy-api-key"), req.get_header("P-access-token")))
        return io.BytesIO(payload)

    return fake


class GrocyMcpTest(unittest.TestCase):
    def test_every_tool_is_allowlisted_and_no_delete(self):
        self.assertEqual(len(m.TOOLS), 11)
        for _, _, method, path in m.TOOLS.values():
            self.assertNotEqual(method, "DELETE")
            m.check_allowed(method, path.replace("{id}", "1"))
        self.assertNotIn("DELETE", [method for method, _ in m.ALLOWED])

    def test_refused_calls(self):
        for method, path in [
            ("DELETE", "/objects/shopping_list/1"), ("DELETE", "/objects/products/1"),
            ("PUT", "/objects/products/1"), ("POST", "/objects/products"), ("POST", "/objects/chores"),
            ("GET", "/objects/users"), ("GET", "/users"), ("POST", "/stock/products/1/consume"),
            ("POST", "/stock/shoppinglist/clear"), ("POST", "/chores/1/undo/2"), ("PATCH", "/chores/1"),
            ("PUT", "/objects/shopping_list"), ("POST", "/objects/shopping_list/1"),
        ]:
            with self.assertRaises(ValueError, msg=(method, path)):
                m.call_grocy(method, path, {}, "http://x", "k")

    def test_bad_ids_are_refused(self):
        for oid in ["..", ".", "", "a/b", "1/../2", "-1", True, None]:
            for method, path in [("GET", "/chores/{id}"), ("PUT", "/objects/shopping_list/{id}"), ("POST", "/chores/{id}/execute")]:
                with self.assertRaises(ValueError, msg=(method, oid)):
                    m.call_grocy(method, path, {"id": oid}, "http://x", "k")

    def test_bodies_are_checked(self):
        for method, path, args in [
            ("POST", "/objects/shopping_list", {"done": True}),
            ("POST", "/objects/shopping_list", {"note": "lait", "id": 3}),
            ("POST", "/objects/shopping_list", {"amount": True}),
            ("POST", "/objects/shopping_list", {"product_id": "3"}),
            ("POST", "/objects/shopping_list", {}),
            ("PUT", "/objects/shopping_list/{id}", {"id": 1}),
            ("PUT", "/objects/shopping_list/{id}", {"id": 1, "shopping_list_id": 2, "x": 1}),
            ("POST", "/chores/{id}/execute", {"id": 1, "skipped": True}),
        ]:
            with self.assertRaises(ValueError, msg=(method, path, args)):
                m.call_grocy(method, path, args, "http://x", "k")

    def test_done_goes_as_integer(self):
        sent = []
        with mock.patch("urllib.request.urlopen", fake_urlopen(sent, b"")):
            r = m.call_grocy("PUT", "/objects/shopping_list/{id}", {"id": 7, "done": True}, "http://h/", "k", {"P-Access-Token": "t"})
        self.assertEqual(r, {"ok": True})
        method, url, data, key, tok = sent[0]
        self.assertEqual((method, url, json.loads(data), key, tok), ("PUT", "http://h/api/objects/shopping_list/7", {"done": 1}, "k", "t"))

    def test_complete_chore_without_fields(self):
        sent = []
        with mock.patch("urllib.request.urlopen", fake_urlopen(sent)):
            m.call_grocy("POST", "/chores/{id}/execute", {"id": 2}, "http://h", "k")
        self.assertEqual((sent[0][0], sent[0][1], sent[0][2]), ("POST", "http://h/api/chores/2/execute", b"{}"))

    def test_get_query(self):
        sent = []
        with mock.patch("urllib.request.urlopen", fake_urlopen(sent)):
            m.call_grocy("GET", "/stock/volatile", {"due_soon_days": 3}, "http://h", "k")
        self.assertEqual(sent[0][1], "http://h/api/stock/volatile?due_soon_days=3")

    def test_call_routes(self):
        seen = []
        call = lambda *a: seen.append(a) or {"ok": 1}
        r = m.handle({"id": 2, "method": "tools/call", "params": {"name": "get_chore", "arguments": {"id": 4}}}, call)
        self.assertEqual(seen, [("GET", "/chores/{id}", {"id": 4})])
        self.assertIn('"ok"', r["result"]["content"][0]["text"])

    def test_notification_gets_no_reply(self):
        self.assertIsNone(m.handle({"method": "notifications/initialized"}, None))

    def test_missing_or_null_params_is_not_fatal(self):
        self.assertIn("error", m.handle({"id": 4, "method": "tools/call"}, None))
        self.assertIn("error", m.handle({"id": 5, "method": "tools/call", "params": None}, None))
        seen = []
        m.handle({"id": 6, "method": "tools/call", "params": {"name": "stock", "arguments": None}}, lambda *a: seen.append(a))
        self.assertEqual(seen, [("GET", "/stock", {})])
        self.assertEqual(m.handle({"id": 7, "method": "initialize", "params": None}, None)["result"]["serverInfo"]["name"], "grocy")

    def test_non_string_tool_name_is_not_fatal(self):
        self.assertIn("error", m.handle({"id": 8, "method": "tools/call", "params": {"name": ["x"]}}, None))

    def test_long_answer_is_marked_truncated(self):
        r = m.handle({"id": 9, "method": "tools/call", "params": {"name": "stock"}}, lambda *a: {"x": "a" * 200000})
        self.assertTrue(r["result"]["content"][0]["text"].endswith("[... tronqué]"))

    def test_tool_error_is_not_fatal(self):
        def boom(*a):
            raise OSError("down")

        r = m.handle({"id": 3, "method": "tools/call", "params": {"name": "stock"}}, boom)
        self.assertTrue(r["result"]["isError"])


if __name__ == "__main__":
    unittest.main()
