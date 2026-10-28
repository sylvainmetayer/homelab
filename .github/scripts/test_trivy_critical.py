"""Tests of trivy_critical.py: CRITICAL fixable vulnerabilities, per image, to ntfy
(Lint workflow: python -I -m unittest discover -s .github/scripts -p 'test_*.py')."""

import io
import json
import os
import tempfile
import unittest
import urllib.error
from contextlib import redirect_stdout
from pathlib import Path
from unittest import mock

import trivy_critical


def vuln(vid, severity="CRITICAL", fixed="1.0.1", pkg="openssl", installed="1.0.0"):
    return {"VulnerabilityID": vid, "Severity": severity, "PkgName": pkg, "InstalledVersion": installed, "FixedVersion": fixed}


def report(*results):
    return {"ArtifactName": "example/image:1", "Results": [{"Target": f"t{i}", "Vulnerabilities": v} for i, v in enumerate(results)]}


class CriticalFixedTest(unittest.TestCase):
    def test_keeps_only_critical_with_a_fix(self):
        found = trivy_critical.critical_fixed(report([
            vuln("CVE-1"),
            vuln("CVE-2", severity="HIGH"),
            vuln("CVE-3", fixed=""),
        ]))
        self.assertEqual(found, [("CVE-1", "openssl", "1.0.0", "1.0.1")])

    def test_deduplicates_across_targets(self):
        found = trivy_critical.critical_fixed(report([vuln("CVE-1")], [vuln("CVE-1")], [vuln("CVE-1", pkg="libssl")]))
        self.assertEqual(len(found), 2)

    def test_no_results_or_null_vulnerabilities(self):
        self.assertEqual(trivy_critical.critical_fixed({}), [])
        self.assertEqual(trivy_critical.critical_fixed({"Results": [{"Target": "x", "Vulnerabilities": None}]}), [])

    def test_unexpected_shape_raises(self):
        with self.assertRaises(trivy_critical.ReportError):
            trivy_critical.critical_fixed({"Results": [{"Vulnerabilities": [{"Severity": "CRITICAL", "FixedVersion": "1"}]}]})


class CollectTest(unittest.TestCase):
    def test_images_without_critical_are_dropped(self):
        with tempfile.TemporaryDirectory() as directory:
            Path(directory, "immich.json").write_text(json.dumps(report([vuln("CVE-1")])))
            Path(directory, "trek.json").write_text(json.dumps(report([vuln("CVE-2", severity="HIGH")])))
            self.assertEqual(list(trivy_critical.collect(directory)), ["immich"])

    def test_empty_directory_is_an_error(self):
        with tempfile.TemporaryDirectory() as directory, self.assertRaises(trivy_critical.ReportError):
            trivy_critical.collect(directory)

    def test_invalid_json_is_an_error(self):
        with tempfile.TemporaryDirectory() as directory:
            Path(directory, "x.json").write_text("{")
            with self.assertRaises(trivy_critical.ReportError):
                trivy_critical.collect(directory)


class MessageTest(unittest.TestCase):
    def test_nothing_to_say(self):
        self.assertIsNone(trivy_critical.message({}, "https://example.test"))

    def test_lists_each_image_with_the_fixed_version(self):
        payload = trivy_critical.message(
            {"trek": [("CVE-1", "openssl", "1.0.0", "1.0.1")], "immich": [("CVE-2", "zlib", "1.2", "1.3"), ("CVE-3", "curl", "8", "8.1")]},
            "https://example.test",
        )
        self.assertEqual(payload["topic"], "scripts")
        self.assertEqual(payload["title"], "Trivy : 3 CVE critiques corrigeables, 2 images")
        self.assertEqual(payload["message"].splitlines(), [
            "immich", "  CVE-2 zlib 1.2 → 1.3", "  CVE-3 curl 8 → 8.1",
            "trek", "  CVE-1 openssl 1.0.0 → 1.0.1",
        ])
        self.assertEqual(payload["click"], "https://example.test")

    def test_singular(self):
        payload = trivy_critical.message({"trek": [("CVE-1", "openssl", "1", "2")]}, "")
        self.assertEqual(payload["title"], "Trivy : 1 CVE critique corrigeable, 1 image")

    def test_long_message_is_truncated(self):
        vulns = [(f"CVE-2026-{i:05d}", "package-with-a-long-name", "1.0.0", "1.0.1") for i in range(500)]
        payload = trivy_critical.message({"big": vulns}, "")
        self.assertLessEqual(len(payload["message"].encode("utf-8")), trivy_critical.MAX_MESSAGE_BYTES + 100)
        self.assertIn("lignes de plus", payload["message"].splitlines()[-1])


class MainTest(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)

    def write(self, *vulns):
        Path(self.directory.name, "trek.json").write_text(json.dumps(report(list(vulns))))

    def run_main(self, *args, token="tk_fake"):
        out = io.StringIO()
        with mock.patch.dict(os.environ, {"NTFY_TOKEN": token}), redirect_stdout(out):
            code = trivy_critical.main([self.directory.name, *args])
        return code, out.getvalue()

    def test_nothing_published_without_critical(self):
        self.write(vuln("CVE-1", severity="HIGH"))
        with mock.patch.object(trivy_critical, "publish") as publish:
            code, _ = self.run_main()
        self.assertEqual(code, 0)
        publish.assert_not_called()

    def test_publishes_with_the_token(self):
        self.write(vuln("CVE-1"))
        with mock.patch.object(trivy_critical, "publish") as publish:
            code, _ = self.run_main()
        self.assertEqual(code, 0)
        token, payload = publish.call_args.args
        self.assertEqual(token, "tk_fake")
        self.assertIn("CVE-1", payload["message"])

    def test_dry_run_does_not_publish(self):
        self.write(vuln("CVE-1"))
        with mock.patch.object(trivy_critical, "publish") as publish:
            code, out = self.run_main("--dry-run", token="")
        self.assertEqual(code, 0)
        self.assertIn("CVE-1", out)
        publish.assert_not_called()

    def test_missing_token_fails(self):
        self.write(vuln("CVE-1"))
        code, out = self.run_main(token="")
        self.assertEqual(code, 1)
        self.assertIn("NTFY_TOKEN", out)

    def test_http_error_fails_without_leaking(self):
        self.write(vuln("CVE-1"))
        error = urllib.error.HTTPError(trivy_critical.NTFY_URL, 403, "Forbidden", {}, None)
        with mock.patch.object(trivy_critical, "publish", side_effect=error):
            code, out = self.run_main(token="tk_secret_value")
        self.assertEqual(code, 1)
        self.assertIn("HTTP 403", out)
        self.assertNotIn("tk_secret_value", out)


if __name__ == "__main__":
    unittest.main()
