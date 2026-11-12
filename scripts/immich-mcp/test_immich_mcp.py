import threading
import unittest
from http.server import BaseHTTPRequestHandler, HTTPServer

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

    def test_redirect_is_an_error_and_keeps_the_credentials_home(self):
        # Une 3xx ne doit pas rejouer la clé d'API ni le jeton Pangolin ailleurs.
        received = []

        class Elsewhere(BaseHTTPRequestHandler):
            def do_GET(self):
                received.append(self.headers.get("x-api-key"))
                self.send_response(200)
                self.end_headers()
                self.wfile.write(b"{}")

            def log_message(self, *args):
                pass

        elsewhere = HTTPServer(("127.0.0.1", 0), Elsewhere)

        class Redirect(BaseHTTPRequestHandler):
            def do_GET(self):
                self.send_response(302)
                self.send_header("Location", f"http://127.0.0.1:{elsewhere.server_address[1]}/x")
                self.end_headers()

            def log_message(self, *args):
                pass

        redirect = HTTPServer(("127.0.0.1", 0), Redirect)
        for server in (elsewhere, redirect):
            threading.Thread(target=server.serve_forever, daemon=True).start()
        try:
            with self.assertRaisesRegex(RuntimeError, "HTTP 302 : http://127.0.0.1"):
                m.call_immich("GET", "/albums", {}, f"http://127.0.0.1:{redirect.server_address[1]}", "k")
        finally:
            for server in (elsewhere, redirect):
                server.shutdown()
                server.server_close()
        self.assertEqual(received, [])


if __name__ == "__main__":
    unittest.main()
