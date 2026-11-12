import json
import threading
import unittest
from http.server import BaseHTTPRequestHandler, HTTPServer

import immich_mcp as m

A, B = "00000000-0000-4000-8000-000000000001", "00000000-0000-4000-8000-000000000002"
P = ["10000000-0000-4000-8000-00000000000%d" % i for i in range(1, 6)]
WRITE_TOOLS = ["create_album", "update_album", "add_assets", "remove_assets", "merge_albums"]
DEAD = "http://127.0.0.1:1"  # un appel refusé ne doit jamais l'atteindre


class Fake:
    """Un Immich en mémoire : albums {id: {albumName, description, assets{id: nom}}} ; garde la liste des écritures."""

    def __init__(self, albums, lossy=False):
        self.albums, self.writes, self.lossy = albums, [], lossy

    def __call__(self, method, path, args):
        if (method, path) == ("GET", "/albums"):
            return [dict(id=i, albumName=a["albumName"], assetCount=len(a["assets"])) for i, a in self.albums.items()]
        if (method, path) == ("GET", "/albums/{id}"):
            a = self.albums[args["id"]]
            return {"id": args["id"], "albumName": a["albumName"], "description": a.get("description"), "assetCount": len(a["assets"])}
        if (method, path) == ("GET", "/assets/{id}"):
            return {"originalFileName": "f-" + args["id"][-1] + ".jpg"}
        if (method, path) == ("POST", "/search/metadata"):
            names = self.albums[args["albumIds"][0]]["assets"]
            return {"assets": {"items": [{"id": i, "originalFileName": n} for i, n in names.items()], "nextPage": None}}
        self.writes.append((method, path, args))
        if path == "/albums/{id}/assets":
            if self.lossy:
                return [{"id": i, "success": False, "error": "no_permission"} for i in args["ids"]]
            a = self.albums[args["id"]]["assets"]
            if method == "PUT":
                a.update({i: "f-" + i[-1] + ".jpg" for i in args["ids"]})
            else:
                for i in args["ids"]:
                    a.pop(i, None)
            return [{"id": i, "success": True} for i in args["ids"]]
        if (method, path) == ("DELETE", "/albums/{id}"):
            del self.albums[args["id"]]
        return {"ok": True}


def tool(call, name, args, write=True):
    r = m.handle({"id": 1, "method": "tools/call", "params": {"name": name, "arguments": args}}, call, write)["result"]
    if r.get("isError"):
        return True, r["content"][0]["text"]
    return False, json.loads(r["content"][0]["text"])


def two_albums(**kw):
    return Fake({A: {"albumName": "Vacances", "assets": {P[0]: "f-1.jpg", P[1]: "f-2.jpg"}},
                 B: {"albumName": " vacances ", "assets": {P[1]: "f-2.jpg", P[2]: "f-3.jpg"}}}, **kw)


class ImmichMcpTest(unittest.TestCase):
    def test_tools_list_only_reads(self):
        r = m.handle({"id": 1, "method": "tools/list"}, None)
        names = [t["name"] for t in r["result"]["tools"]]
        self.assertEqual(len(names), 9)
        self.assertEqual(set(names) & set(WRITE_TOOLS), set())
        for _, _, method, path in m.TOOLS.values():
            self.assertIn(method + " " + path, m.READ)

    def test_call_routes_to_immich(self):
        seen = []
        call = lambda *a: seen.append(a) or {"ok": 1}
        r = m.handle({"id": 2, "method": "tools/call", "params": {"name": "get_album", "arguments": {"id": A}}}, call)
        self.assertEqual(seen, [("GET", "/albums/{id}", {"id": A})])
        self.assertIn('"ok"', r["result"]["content"][0]["text"])

    def test_notification_gets_no_reply(self):
        self.assertIsNone(m.handle({"method": "notifications/initialized"}, None))

    def test_post_outside_allowlist_refused(self):
        with self.assertRaises(ValueError):
            m.call_immich("POST", "/albums", {"albumName": "x"}, DEAD, "k")

    def test_missing_params_is_not_fatal(self):
        r = m.handle({"id": 4, "method": "tools/call"}, None)
        self.assertIn("error", r)

    def test_null_params_on_initialize(self):
        r = m.handle({"id": 5, "method": "initialize", "params": None}, None)
        self.assertEqual(r["result"]["serverInfo"]["name"], "immich-readonly")
        r = m.handle({"id": 5, "method": "initialize"}, None, True)
        self.assertEqual(r["result"]["serverInfo"]["name"], "immich-write")

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

    # --- mode et liste blanche ---

    def test_write_tools_listed_only_in_write_mode(self):
        r = m.handle({"id": 1, "method": "tools/list"}, None, True)
        names = [t["name"] for t in r["result"]["tools"]]
        self.assertEqual(len(names), 14)
        self.assertTrue(set(WRITE_TOOLS) <= set(names))

    def test_read_mode_refuses_write_tools_before_any_call(self):
        fake = two_albums()
        args = {"id": A, "albumName": "x", "assetIds": [P[0]], "keepId": A, "duplicateId": B}
        for name in WRITE_TOOLS:
            err, text = tool(fake, name, args, write=False)
            self.assertTrue(err)
            self.assertIn("IMMICH_MCP_WRITE", text)
        self.assertEqual(fake.writes, [])

    def test_read_mode_call_layer_refuses_writes(self):
        for method, path in (("POST", "/albums"), ("PATCH", "/albums/{id}"), ("PUT", "/albums/{id}/assets"),
                             ("DELETE", "/albums/{id}/assets"), ("DELETE", "/albums/{id}")):
            with self.assertRaises(ValueError):
                m.call_immich(method, path, {"id": A, "ids": [P[0]]}, DEAD, "k")

    def test_write_mode_allowlist_never_reaches_assets_or_trash(self):
        for method, path in (("DELETE", "/assets"), ("PUT", "/assets"), ("PUT", "/assets/{id}"), ("DELETE", "/assets/{id}"),
                             ("POST", "/trash/empty"), ("POST", "/trash/restore/assets"), ("PUT", "/albums/assets"),
                             ("PUT", "/albums/{id}/users"), ("DELETE", "/albums/{id}/user/{userId}"), ("DELETE", "/people/{id}"),
                             ("POST", "/shared-links"), ("DELETE", "/users/{id}"), ("GET", "/albums/{id}/../assets")):
            with self.assertRaises(ValueError, msg=method + path):
                m.call_immich(method, path, {"id": A, "ids": [P[0]]}, DEAD, "k", write=True)

    def test_write_mode_validates_ids_and_fields(self):
        for args in ({"id": "../assets", "ids": [P[0]]}, {"id": A, "ids": ["x"]}, {"id": A, "ids": [P[0]], "force": True},
                     {"id": A, "ids": []}):
            with self.assertRaises(ValueError):
                m.call_immich("DELETE", "/albums/{id}/assets", args, DEAD, "k", write=True)

    def test_every_write_template_is_album_only(self):
        for key in m.WRITE_BODY:
            self.assertRegex(key, r"^(POST|PATCH|PUT|DELETE) /albums")

    # --- deux temps ---

    def test_preview_writes_nothing_and_confirm_applies(self):
        fake = two_albums()
        _, p = tool(fake, "add_assets", {"id": A, "assetIds": [P[1], P[3]]})
        self.assertFalse(p["applique"])
        self.assertEqual((p["apercu"]["ajoutes"], p["apercu"]["deja_dans_l_album"]), (1, 1))
        self.assertEqual(p["apercu"]["echantillon"], ["f-4.jpg"])
        self.assertEqual(fake.writes, [])
        _, r = tool(fake, "add_assets", {"id": A, "assetIds": [P[1], P[3]], "confirm": p["confirm"]})
        self.assertTrue(r["applique"])
        self.assertEqual(fake.writes, [("PUT", "/albums/{id}/assets", {"id": A, "ids": [P[3]]})])

    def test_stale_or_wrong_token_writes_nothing(self):
        fake = two_albums()
        _, p = tool(fake, "add_assets", {"id": A, "assetIds": [P[3]]})
        fake.albums[A]["assets"][P[3]] = "ajouté entre-temps"  # l'état change
        _, r = tool(fake, "add_assets", {"id": A, "assetIds": [P[3]], "confirm": p["confirm"]})
        self.assertFalse(r["applique"])
        _, r = tool(fake, "add_assets", {"id": A, "assetIds": [P[4]], "confirm": p["confirm"]})  # autres arguments
        self.assertFalse(r["applique"])
        _, r = tool(fake, "add_assets", {"id": A, "assetIds": [P[4]], "confirm": "nimporte"})
        self.assertFalse(r["applique"])
        self.assertEqual(fake.writes, [])

    def test_remove_only_drops_links_present(self):
        fake = two_albums()
        args = {"id": A, "assetIds": [P[0], P[4]]}
        _, p = tool(fake, "remove_assets", args)
        self.assertEqual((p["apercu"]["retires"], p["apercu"]["pas_dans_l_album"]), (1, 1))
        tool(fake, "remove_assets", {**args, "confirm": p["confirm"]})
        self.assertEqual(fake.writes, [("DELETE", "/albums/{id}/assets", {"id": A, "ids": [P[0]]})])

    def test_create_and_update(self):
        fake = two_albums()
        _, p = tool(fake, "create_album", {"albumName": "vacances"})
        self.assertEqual(p["apercu"]["albums_existants_de_meme_nom"], [A, B])
        tool(fake, "create_album", {"albumName": "vacances", "confirm": p["confirm"]})
        self.assertEqual(fake.writes, [("POST", "/albums", {"albumName": "vacances"})])
        _, p = tool(fake, "update_album", {"id": A, "albumName": "Été"})
        self.assertEqual(p["apercu"]["avant"]["albumName"], "Vacances")
        tool(fake, "update_album", {"id": A, "albumName": "Été", "confirm": p["confirm"]})
        self.assertEqual(fake.writes[-1], ("PATCH", "/albums/{id}", {"id": A, "albumName": "Été"}))

    # --- fusion ---

    def test_merge_adds_only_missing_and_keeps_duplicate_by_default(self):
        fake = two_albums()
        args = {"keepId": A, "duplicateId": B}
        _, p = tool(fake, "merge_albums", args)
        a = p["apercu"]
        self.assertEqual((a["assets_communs"], a["propres_au_garde"], a["propres_au_doublon_ajoutes_au_garde"]), (1, 1, 1))
        self.assertEqual(fake.writes, [])
        tool(fake, "merge_albums", {**args, "confirm": p["confirm"]})
        self.assertEqual(fake.writes, [("PUT", "/albums/{id}/assets", {"id": A, "ids": [P[2]]})])
        self.assertIn(B, fake.albums)

    def test_merge_deletes_duplicate_album_only_when_asked(self):
        fake = two_albums()
        args = {"keepId": A, "duplicateId": B, "deleteDuplicate": True}
        _, p = tool(fake, "merge_albums", args)
        self.assertIn("jamais ses photos", p["apercu"]["supprime"])
        tool(fake, "merge_albums", {**args, "confirm": p["confirm"]})
        self.assertEqual(fake.writes[-1], ("DELETE", "/albums/{id}", {"id": B}))
        self.assertNotIn(B, fake.albums)
        # le jeton de la fusion sans suppression ne vaut pas pour la fusion avec suppression
        fake = two_albums()
        _, p = tool(fake, "merge_albums", {"keepId": A, "duplicateId": B})
        _, r = tool(fake, "merge_albums", {**args, "confirm": p["confirm"]})
        self.assertFalse(r["applique"])
        self.assertIn(B, fake.albums)

    def test_merge_refuses_delete_when_a_list_is_incomplete_and_same_album(self):
        fake = two_albums()
        real = fake.__call__
        incomplete = lambda mth, path, a: {**real(mth, path, a), "assetCount": 5} if (mth, path) == ("GET", "/albums/{id}") else real(mth, path, a)
        err, _ = tool(incomplete, "merge_albums", {"keepId": A, "duplicateId": B, "deleteDuplicate": True})
        self.assertTrue(err)
        err, _ = tool(fake, "merge_albums", {"keepId": A, "duplicateId": A})
        self.assertTrue(err)

    def test_merge_keeps_duplicate_if_assets_did_not_land(self):
        fake = two_albums(lossy=True)
        args = {"keepId": A, "duplicateId": B, "deleteDuplicate": True}
        _, p = tool(fake, "merge_albums", args)
        err, _ = tool(fake, "merge_albums", {**args, "confirm": p["confirm"]})
        self.assertTrue(err)
        self.assertIn(B, fake.albums)
        self.assertNotIn(("DELETE", "/albums/{id}", {"id": B}), fake.writes)

    # --- lectures de tri ---

    def test_find_duplicate_albums(self):
        _, out = tool(two_albums(), "find_duplicate_albums", {"minOverlap": 0.5}, write=False)
        self.assertEqual([x["id"] for x in out["meme_nom"][0]], [A, B])
        self.assertEqual((out["recouvrement"][0]["communs"], out["recouvrement"][0]["part_du_plus_petit"]), (1, 0.5))
        _, out = tool(two_albums(), "find_duplicate_albums", {"minOverlap": 0.9}, write=False)
        self.assertEqual(out["recouvrement"], [])

    def test_list_albums_is_compact_sorted_and_filterable(self):
        def call(method, path, args):
            self.assertEqual((method, path), ("GET", "/albums"))
            big = {"owner": {"x": "y" * 500}, "albumUsers": [1, 2, 3]}
            return [dict(id=B, albumName="zèbre", assetCount=3, shared=True, startDate="2024-01-01T00:00:00Z", **big),
                    dict(id=A, albumName="Alpes été", assetCount=0, **big)]

        _, out = tool(call, "list_albums", {}, write=False)
        self.assertEqual([r["id"] for r in out["albums"]], [A, B])
        self.assertEqual(out["albums"][0], {"id": A, "nom": "Alpes été", "assets": 0, "debut": None, "fin": None, "partage": False})
        self.assertEqual((out["albums"][1]["partage"], out["albums"][1]["debut"], out["total"]), (True, "2024-01-01T00:00:00Z", 2))
        self.assertNotIn("owner", out["albums"][0])
        _, out = tool(call, "list_albums", {"contains": " ALPES "}, write=False)
        self.assertEqual([r["id"] for r in out["albums"]], [A])

    def test_long_output_is_marked_truncated(self):
        big = lambda *a: {"x": "y" * 200000}
        r = m.handle({"id": 1, "method": "tools/call", "params": {"name": "get_album", "arguments": {"id": A}}}, big)
        text = r["result"]["content"][0]["text"]
        self.assertTrue(text.endswith(" [... tronqué]"))
        self.assertEqual(len(text), 100000 + len(" [... tronqué]"))

    def test_assets_without_album(self):
        seen = []

        def call(method, path, args):
            seen.append((method, path, args))
            return {"assets": {"items": [{"id": P[0], "originalFileName": "a.jpg", "exifInfo": {"x": 1}}], "nextPage": "2"}}

        _, out = tool(call, "assets_without_album", {}, write=False)
        self.assertEqual(seen[0][2]["isNotInAlbum"], True)
        self.assertEqual(out["assets"][0]["originalFileName"], "a.jpg")
        self.assertNotIn("exifInfo", out["assets"][0])


if __name__ == "__main__":
    unittest.main()
