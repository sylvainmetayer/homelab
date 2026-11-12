import unittest

import immich_mcp as m


class ImmichMcpTest(unittest.TestCase):
    def test_tools_list_only_reads(self):
        r = m.handle({"id": 1, "method": "tools/list"}, None)
        self.assertEqual(len(r["result"]["tools"]), 7)
        for _, _, method, path in m.TOOLS.values():
            self.assertTrue(method == "GET" or path in m.POST_OK)

    def test_call_routes_to_immich(self):
        seen = []
        call = lambda *a: seen.append(a) or {"ok": 1}
        r = m.handle({"id": 2, "method": "tools/call", "params": {"name": "get_album", "arguments": {"id": "x"}}}, call)
        self.assertEqual(seen, [("GET", "/albums/{id}", {"id": "x"})])
        self.assertIn('"ok"', r["result"]["content"][0]["text"])

    def test_notification_gets_no_reply(self):
        self.assertIsNone(m.handle({"method": "notifications/initialized"}, None))

    def test_post_outside_allowlist_refused(self):
        with self.assertRaises(ValueError):
            m.call_immich("POST", "/albums", {}, "http://x", "k")

    def test_missing_params_is_not_fatal(self):
        r = m.handle({"id": 4, "method": "tools/call"}, None)
        self.assertIn("error", r)

    def test_null_params_on_initialize(self):
        r = m.handle({"id": 5, "method": "initialize", "params": None}, None)
        self.assertEqual(r["result"]["serverInfo"]["name"], "immich-readonly")

    def test_metadata_search_has_no_query(self):
        self.assertNotIn("query", m.TOOLS["search_metadata"][1]["properties"])

    def test_tool_error_is_not_fatal(self):
        def boom(*a):
            raise OSError("down")

        r = m.handle({"id": 3, "method": "tools/call", "params": {"name": "list_albums"}}, boom)
        self.assertTrue(r["result"]["isError"])


if __name__ == "__main__":
    unittest.main()
