"""Scripts sending a token (trivy_critical, renovate_digest, storage_box_quota):
no redirect followed. The real urllib on a fake answer, without network: a mock
of the opener would not see the following. In one file, for Sonar's duplication
gate (python -I -m unittest discover -s .github/scripts -p 'test_*.py')."""

import http.client
import io
import os
import unittest
import urllib.error
import urllib.request
from contextlib import redirect_stdout
from unittest import mock

import renovate_digest
import storage_box_quota
import trivy_critical


def answering_302(seen):
    """Everything answers 302 to /arrivee, which answers 200."""

    def https_open(_handler, request):
        seen.append((request.full_url, request.get_header("Authorization")))
        headers = http.client.parse_headers(io.BytesIO(b"Location: /arrivee\r\n\r\n"))
        code = 200 if request.full_url.endswith("/arrivee") else 302
        return mock.MagicMock(code=code, msg="x", info=lambda: headers)

    return mock.patch.object(urllib.request.HTTPSHandler, "https_open", https_open)


class TrivyCriticalTest(unittest.TestCase):
    def test_ntfy_redirect_is_an_error_and_nothing_reaches_the_target(self):
        seen = []
        with answering_302(seen), self.assertRaises(urllib.error.HTTPError) as raised:
            trivy_critical.publish("jeton", {"title": "x"})
        self.assertEqual(raised.exception.code, 302)
        self.assertEqual(seen, [(trivy_critical.NTFY_URL, "Bearer jeton")])


class RenovateDigestTest(unittest.TestCase):
    def test_github_redirect_is_an_error_and_nothing_reaches_the_target(self):
        for body in (None, {"query": "x"}):
            seen = []
            with self.subTest(body=body), answering_302(seen), self.assertRaises(urllib.error.HTTPError) as raised:
                renovate_digest.github("jeton", "/graphql", body)
            self.assertEqual(raised.exception.code, 302)
            self.assertEqual(seen, [(renovate_digest.API + "/graphql", "Bearer jeton")])

    def test_ntfy_redirect_is_an_error_and_nothing_reaches_the_target(self):
        seen = []
        with answering_302(seen), self.assertRaises(urllib.error.HTTPError) as raised:
            renovate_digest.publish(renovate_digest.NTFY_URL, "t", "jeton", {"title": "x"})
        self.assertEqual(raised.exception.code, 302)
        self.assertEqual(seen, [(renovate_digest.NTFY_URL + "/", "Bearer jeton")])

    def test_both_redirects_fail_the_run_without_the_token(self):
        out, seen = io.StringIO(), []
        env = {"GITHUB_TOKEN": "jeton", "NTFY_TOKEN": "jeton"}
        with answering_302(seen), mock.patch.dict(os.environ, env, clear=True), redirect_stdout(out):
            code = renovate_digest.main(["--repo", "o/r"])
        self.assertEqual(code, 1)
        self.assertIn("::error::API GitHub : HTTP 302", out.getvalue())
        self.assertIn("::error::publication sur ntfy en échec : HTTPError", out.getvalue())
        self.assertNotIn("jeton", out.getvalue())
        self.assertEqual(len(seen), 2)
        self.assertFalse([url for url, _ in seen if url.endswith("/arrivee")])


class StorageBoxQuotaTest(unittest.TestCase):
    def test_hetzner_redirect_is_an_error_and_nothing_reaches_the_target(self):
        seen = []
        with answering_302(seen), self.assertRaises(urllib.error.HTTPError) as raised:
            storage_box_quota.fetch("jeton", "backups")
        self.assertEqual(raised.exception.code, 302)
        self.assertEqual(seen, [(storage_box_quota.API + "?name=backups", "Bearer jeton")])

    def test_both_redirects_fail_the_run_without_the_token_nor_the_push_url(self):
        out, seen = io.StringIO(), []
        env = {"HCLOUD_READONLY_TOKEN": "jeton", "PUSH_URL": "https://kuma.invalid/api/push/monitor"}
        with answering_302(seen), mock.patch.dict(os.environ, env, clear=True), redirect_stdout(out):
            code = storage_box_quota.main([])
        self.assertEqual(code, 1)
        self.assertIn("API Hetzner : HTTP 302", out.getvalue())
        self.assertIn("::error::push vers Uptime Kuma en échec : HTTPError", out.getvalue())
        self.assertNotIn("jeton", out.getvalue())
        self.assertNotIn("kuma.invalid", out.getvalue())
        self.assertEqual(len(seen), 2)
        self.assertFalse([url for url, _ in seen if url.endswith("/arrivee")])


if __name__ == "__main__":
    unittest.main()
