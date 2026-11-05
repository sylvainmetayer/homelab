"""Tests de cert_check.py (rôle nas_proxy), lancés par verify.yml du scénario
avec le python3 de l'hôte de test : le push seul, le verify jouant déjà de
vrais certificats de bout en bout. À la main : copier ce fichier à côté de
ansible/roles/nas_proxy/files/cert_check.py, puis
python3 -I -m unittest discover -s . -p 'test_*.py'.
"""

import http.client
import io
import os
import unittest
from contextlib import redirect_stderr, redirect_stdout
from unittest import mock

import cert_check as cc


class MainPushTest(unittest.TestCase):
    """main() avec un certificat à 60 jours : seul le push peut échouer."""

    def main(self, url, **opener):
        out, err = io.StringIO(), io.StringIO()
        real_open = cc._OPENER.open
        with (
            mock.patch.dict(os.environ, {cc.PUSH_URL_VARIABLE: url}),
            mock.patch.object(cc, "days_left", return_value=60),
            mock.patch.object(cc._OPENER, "open", **(opener or {"side_effect": real_open})) as opened,
            redirect_stdout(out),
            redirect_stderr(err),
        ):
            code = cc.main(["--host", "127.0.0.1", "--port", "8443", "--min-days", "21", "a.test"])
        return code, opened, out.getvalue(), err.getvalue()

    def test_malformed_url_is_exit_2_and_never_cited(self):
        # Vrai urllib, rien ne part : l'URL est refusée avant toute connexion.
        for url in ("kuma.invalid/api/push/jeton-du-moniteur", "http://kuma.invalid/api/push/jeton du moniteur"):
            with self.subTest(url=url):
                code, _, out, err = self.main(url)
                self.assertEqual(code, 2)
                self.assertIn("push vers Uptime Kuma en échec", err)
                self.assertNotIn("jeton", out + err)

    def test_errors_of_the_exchange_are_exit_2_and_show_their_class_only(self):
        for error in (
            OSError("http://kuma.invalid/api/push/jeton"),
            ValueError("http://kuma.invalid/api/push/jeton"),
            http.client.InvalidURL("http://kuma.invalid/api/push/jeton"),
            http.client.IncompleteRead(b"jeton"),
        ):
            with self.subTest(error=type(error).__name__):
                code, _, out, err = self.main("http://kuma.invalid/p", side_effect=error)
                self.assertEqual(code, 2)
                self.assertIn(type(error).__name__, err)
                self.assertNotIn("jeton", out + err)

    def test_up_pushes_and_succeeds(self):
        code, opened, _, _ = self.main("http://kuma.invalid/p?a=1", return_value=mock.MagicMock())
        self.assertEqual(code, 0)
        self.assertTrue(opened.call_args.args[0].startswith("http://kuma.invalid/p?a=1&status=up&msg="))

    def test_redirect_is_exit_2_and_nothing_reaches_the_target(self):
        seen = []

        def http_open(_handler, request):
            seen.append(request.full_url)
            headers = http.client.parse_headers(io.BytesIO(b"Location: /arrivee\r\n\r\n"))
            return mock.MagicMock(code=302, msg="x", info=lambda: headers)

        with mock.patch.object(cc.urllib.request.HTTPHandler, "http_open", http_open):
            code, _, out, err = self.main("http://kuma.invalid/jeton")
        self.assertEqual(code, 2)
        self.assertIn("HTTPError", err)
        self.assertNotIn("jeton", out + err)
        self.assertEqual(len(seen), 1)


if __name__ == "__main__":
    unittest.main()
