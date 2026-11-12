import io
import json
import unittest
from unittest import mock

import homebox_mcp as m

ITEM = {
    "id": "i1", "name": "Perceuse", "quantity": 1, "notes": "n", "locationId": "l1",
    "entityType": {"id": "t1", "isLocation": False}, "tags": [{"id": "g1"}], "parent": {"id": "p1"},
    "fields": [], "attachments": [{"id": "a"}], "createdAt": "x",
}


class HomeboxMcpTest(unittest.TestCase):
    def test_every_tool_is_allowlisted_and_no_delete(self):
        self.assertEqual(len(m.TOOLS), 7)
        for _, _, method, path in m.TOOLS.values():
            self.assertNotEqual(method, "DELETE")
            m.check_allowed(method, path.replace("{id}", "x"))
        self.assertNotIn("DELETE", [method for method, _ in m.ALLOWED])

    def test_refused_calls(self):
        for method, path in [
            ("DELETE", "/entities/x"), ("DELETE", "/tags/x"), ("DELETE", "/entities/x/attachments/y"),
            ("PUT", "/tags/x"), ("POST", "/tags"), ("POST", "/entities/x/duplicate"),
            ("POST", "/actions/wipe-inventory"), ("PATCH", "/entities/x"), ("GET", "/users/self/api-keys"),
            ("PUT", "/entities/x/attachments/y"),
        ]:
            with self.assertRaises(ValueError, msg=(method, path)):
                m.call_homebox(method, path, {}, "http://x", "k")

    def test_update_merges_into_current(self):
        b = m.merge_update(ITEM, {"quantity": 3})
        self.assertEqual((b["quantity"], b["name"], b["notes"]), (3, "Perceuse", "n"))
        self.assertEqual((b["tagIds"], b["parentId"], b["entityTypeId"]), (["g1"], "p1", "t1"))
        self.assertNotIn("attachments", b)

    def test_update_refuses_unknown_field_and_locations(self):
        with self.assertRaises(ValueError):
            m.merge_update(ITEM, {"archived": True})
        with self.assertRaises(ValueError):
            m.merge_update({**ITEM, "entityType": {"id": "t", "isLocation": True}}, {"name": "x"})

    def test_put_reads_then_sends_merged_body(self):
        sent = []

        def fake(req, timeout):
            sent.append((req.get_method(), req.full_url, req.data, req.get_header("Authorization")))
            return io.BytesIO(json.dumps(ITEM).encode())

        with mock.patch("urllib.request.urlopen", fake):
            m.call_homebox("PUT", "/entities/{id}", {"id": "i1", "quantity": 2}, "http://h", "k")
        self.assertEqual([s[0] for s in sent], ["GET", "PUT"])
        self.assertEqual(json.loads(sent[1][2])["quantity"], 2)
        self.assertEqual(sent[1][1], "http://h/api/v1/entities/i1")
        self.assertEqual(sent[1][3], "Bearer k")

    def test_create_refuses_other_fields(self):
        with self.assertRaises(ValueError):
            m.call_homebox("POST", "/entities", {"name": "x", "entityTypeId": "loc"}, "http://x", "k")

    def test_call_routes(self):
        seen = []
        call = lambda *a: seen.append(a) or {"ok": 1}
        r = m.handle({"id": 2, "method": "tools/call", "params": {"name": "get_item", "arguments": {"id": "x"}}}, call)
        self.assertEqual(seen, [("GET", "/entities/{id}", {"id": "x"})])
        self.assertIn('"ok"', r["result"]["content"][0]["text"])

    def test_notification_gets_no_reply(self):
        self.assertIsNone(m.handle({"method": "notifications/initialized"}, None))

    def test_missing_params_is_not_fatal(self):
        self.assertIn("error", m.handle({"id": 4, "method": "tools/call"}, None))

    def test_tool_error_is_not_fatal(self):
        def boom(*a):
            raise OSError("down")

        r = m.handle({"id": 3, "method": "tools/call", "params": {"name": "list_tags"}}, boom)
        self.assertTrue(r["result"]["isError"])


if __name__ == "__main__":
    unittest.main()
