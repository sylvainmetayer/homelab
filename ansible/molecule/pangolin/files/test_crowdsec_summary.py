"""Tests de crowdsec-summary.py (rôle pangolin), lancés par verify.yml du
scénario avec le python3 de l'hôte de test : le script y est copié sous le nom
crowdsec_summary.py (un tiret ne s'importe pas), cscli remplacé. À la main :
copier ce fichier et ansible/roles/pangolin/files/crowdsec-summary.py sous ce
nom dans un même dossier, puis
python3 -I -m unittest discover -s . -p 'test_*.py'.
"""

import io
import json
import os
import subprocess
import unittest
from contextlib import redirect_stdout
from unittest import mock

import crowdsec_summary as cs


def alert(scenario="crowdsecurity/ssh-bf", cn="FR", decisions=0):
    return {"scenario": scenario, "source": {"cn": cn}, "decisions": [{}] * decisions}


def completed(stdout="[]", returncode=0, stderr=""):
    return subprocess.CompletedProcess([], returncode, stdout, stderr)


class CscliTest(unittest.TestCase):
    def cscli(self, result):
        with mock.patch.object(cs.subprocess, "run", return_value=result) as run:
            return cs.cscli("alerts", "list"), run

    def test_default_command(self):
        with mock.patch.dict(os.environ):
            os.environ.pop("CROWDSEC_SUMMARY_CSCLI", None)
            _, run = self.cscli(completed())
        self.assertEqual(
            run.call_args.args[0],
            ["docker", "exec", "crowdsec", "cscli", "alerts", "list", "-o", "json"],
        )

    def test_command_from_the_environment(self):
        with mock.patch.dict(os.environ, {"CROWDSEC_SUMMARY_CSCLI": "/opt/faux 'cs cli'"}):
            _, run = self.cscli(completed())
        self.assertEqual(run.call_args.args[0][:2], ["/opt/faux", "cs cli"])

    def test_null_and_empty_output_are_no_alert(self):
        for stdout in ("null", "", "[]"):
            with self.subTest(stdout=stdout):
                self.assertEqual(self.cscli(completed(stdout))[0], [])

    def test_failure_cites_the_last_line_of_stderr(self):
        result = completed(returncode=1, stderr="première\ndernière\n")
        with self.assertRaisesRegex(RuntimeError, "^dernière$"):
            self.cscli(result)

    def test_failure_without_stderr(self):
        result = completed(returncode=1)
        with self.assertRaisesRegex(RuntimeError, r"^\?$"):
            self.cscli(result)

    def test_other_shapes_are_refused(self):
        for stdout in ('{"a": 1}', "[1]", "pas du json", '"texte"'):
            result = completed(stdout)
            with self.subTest(stdout=stdout), self.assertRaises(ValueError):
                self.cscli(result)


class SummaryTest(unittest.TestCase):
    def summary(self, alerts=(), decisions=()):
        with mock.patch.object(cs, "cscli", side_effect=[list(alerts), list(decisions)]):
            return cs.summary()

    def test_nothing(self):
        title, text, priority = self.summary()
        self.assertEqual(title, "CrowdSec 7 j : 0 alerte, 0 décision active, AppSec 0")
        self.assertEqual(text, "Décisions actives : 0")
        self.assertEqual(priority, 2)

    def test_counts_and_plurals(self):
        title, text, priority = self.summary(
            [alert(), alert(), alert("crowdsecurity/http-probing", cn="DE")],
            [alert(decisions=2), alert(decisions=1)],
        )
        self.assertEqual(title, "CrowdSec 7 j : 3 alertes, 3 décisions actives, AppSec 0")
        self.assertEqual(priority, 2)
        self.assertEqual(
            text.splitlines(),
            [
                "Scénarios :",
                "  crowdsecurity/ssh-bf 2",
                "  crowdsecurity/http-probing 1",
                "Pays : FR 2, DE 1",
                "Décisions actives : 3",
            ],
        )

    def test_appsec_is_high_and_kept_out_of_the_alert_counts(self):
        title, text, priority = self.summary([alert("homelab/appsec-alert-only"), alert(cs.APPSEC[1], cn="CN"), alert()])
        self.assertEqual(priority, 4)
        self.assertEqual(title, "CrowdSec 7 j : 1 alerte, 0 décision active, AppSec 2")
        self.assertIn("AppSec (détection seule) : 2", text)
        self.assertNotIn("appsec-alert-only", text)
        self.assertNotIn("CN", text)

    def test_only_appsec_has_no_scenario_section(self):
        _, text, _ = self.summary([alert(cs.APPSEC[0])])
        self.assertNotIn("Scénarios", text)
        self.assertNotIn("Pays", text)

    def test_top_cap(self):
        alerts = [alert(f"s{i}", cn=f"C{i}") for i in range(cs.TOP + 2)]
        lines = self.summary(alerts)[1].splitlines()
        self.assertIn("  … et 2 autres", lines)
        self.assertEqual(len([line for line in lines if line.startswith("  s")]), cs.TOP)
        self.assertEqual(lines[-2].count(","), cs.TOP - 1)

    def test_at_the_cap_has_no_remainder(self):
        alerts = [alert(f"s{i}") for i in range(cs.TOP)]
        self.assertNotIn("… et", self.summary(alerts)[1])

    def test_one_over_the_cap_is_singular(self):
        alerts = [alert(f"s{i}") for i in range(cs.TOP + 1)]
        self.assertIn("  … et 1 autre", self.summary(alerts)[1].splitlines())

    def test_fields_missing_or_null(self):
        _, text, _ = self.summary([{"scenario": None, "source": None}, {}], [{"decisions": None}])
        self.assertIn("  ? 2", text)
        self.assertIn("Pays : ?? 2", text)
        self.assertIn("Décisions actives : 0", text)


class MainTest(unittest.TestCase):
    ENV = {"NTFY_URL": "http://ntfy.invalid/t", "NTFY_TOPIC": "t", "NTFY_TOKEN": "jeton"}

    def main(self, argv=(), env=None, **cscli):
        out = io.StringIO()
        with (
            mock.patch.object(cs.sys, "argv", ["crowdsec-summary", *argv]),
            mock.patch.dict(os.environ, env if env is not None else self.ENV),
            mock.patch.object(cs, "cscli", **(cscli or {"return_value": []})),
            mock.patch.object(cs.urllib.request, "urlopen") as urlopen,
            redirect_stdout(out),
        ):
            code = cs.main()
        return code, urlopen, out.getvalue()

    def test_dry_run_prints_without_publishing(self):
        code, urlopen, out = self.main(["--dry-run"], env={})
        self.assertEqual(code, 0)
        urlopen.assert_not_called()
        self.assertEqual(json.loads(out)["priority"], 2)

    def test_dry_run_of_a_failure_fails(self):
        code, urlopen, out = self.main(["--dry-run"], env={}, side_effect=RuntimeError("cscli absent"))
        self.assertEqual(code, 1)
        urlopen.assert_not_called()
        self.assertEqual(json.loads(out)["priority"], 4)

    def test_publishes_with_the_token(self):
        code, urlopen, _ = self.main()
        self.assertEqual(code, 0)
        request = urlopen.call_args.args[0]
        self.assertEqual(request.get_header("Authorization"), "Bearer jeton")
        self.assertEqual(json.loads(request.data)["topic"], "t")

    def test_cscli_failure_is_published_high_and_the_service_fails(self):
        for error in (
            RuntimeError("cscli absent"),
            OSError("docker absent"),
            ValueError("une liste"),
            subprocess.TimeoutExpired("cscli", 120),
        ):
            with self.subTest(error=error):
                code, urlopen, _ = self.main(side_effect=error)
                self.assertEqual(code, 1)
                body = json.loads(urlopen.call_args.args[0].data)
                self.assertEqual((body["priority"], body["title"]), (4, "CrowdSec : résumé impossible"))
                self.assertIn(str(error), body["message"])

    def test_bad_arguments(self):
        with self.assertRaises(SystemExit) as raised:
            self.main(["--autre"])
        self.assertIn("usage", str(raised.exception.code))

    def test_missing_settings_publish_nothing(self):
        for missing in self.ENV:
            with self.subTest(missing=missing), mock.patch.dict(os.environ), self.assertRaises(SystemExit) as raised:
                self.main(env={**self.ENV, missing: ""})
            self.assertIn("rien n'est publié", str(raised.exception.code))

    def test_publication_refused_cites_its_http_code(self):
        refused = cs.urllib.error.HTTPError("http://ntfy.invalid/jeton", 403, "refus", {}, None)
        self.addCleanup(refused.close)
        with (
            mock.patch.object(cs.sys, "argv", ["crowdsec-summary"]),
            mock.patch.dict(os.environ, self.ENV),
            mock.patch.object(cs, "cscli", return_value=[]),
            mock.patch.object(cs.urllib.request, "urlopen", side_effect=refused),
            self.assertRaises(SystemExit) as raised,
        ):
            cs.main()
        self.assertEqual(raised.exception.code, "publication ntfy en échec : HTTP 403")

    def test_publication_error_cites_its_class_only(self):
        with (
            mock.patch.object(cs.sys, "argv", ["crowdsec-summary"]),
            mock.patch.dict(os.environ, self.ENV),
            mock.patch.object(cs, "cscli", return_value=[]),
            mock.patch.object(cs.urllib.request, "urlopen", side_effect=OSError("http://ntfy.invalid/jeton")),
            self.assertRaises(SystemExit) as raised,
        ):
            cs.main()
        self.assertEqual(raised.exception.code, "publication ntfy en échec : OSError")


if __name__ == "__main__":
    unittest.main()
