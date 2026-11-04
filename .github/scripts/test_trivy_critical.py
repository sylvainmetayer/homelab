"""Tests of trivy_critical.py: CRITICAL fixable vulnerabilities and end-of-life distributions, per image, to ntfy
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

    def test_null_field_raises_a_report_error(self):
        with self.assertRaises(trivy_critical.ReportError):
            trivy_critical.critical_fixed(report([vuln("CVE-1"), vuln("CVE-1", pkg=None)]))

    def test_null_installed_version(self):
        self.assertEqual(trivy_critical.critical_fixed(report([vuln("CVE-1", installed=None)])), [("CVE-1", "openssl", "?", "1.0.1")])


def with_os(base, **os_info):
    return {**base, "Metadata": {"OS": os_info}}


class EndOfLifeTest(unittest.TestCase):
    def test_eosl_true(self):
        self.assertEqual(trivy_critical.end_of_life(with_os({}, Family="debian", Name="11.6", EOSL=True)), "debian 11.6")

    def test_field_absent_when_supported(self):
        # Trivy omet EOSL (omitempty) quand la distribution est suivie.
        self.assertIsNone(trivy_critical.end_of_life(with_os({}, Family="alpine", Name="3.22.7")))

    def test_explicit_false(self):
        self.assertIsNone(trivy_critical.end_of_life(with_os({}, Family="alpine", Name="3.22.7", EOSL=False)))

    def test_no_metadata_or_no_os(self):
        # Image sans distribution reconnue (scratch, distroless).
        for found in ({}, {"Metadata": None}, {"Metadata": {}}, {"Metadata": {"OS": None}}):
            self.assertIsNone(trivy_critical.end_of_life(found))

    def test_missing_names(self):
        self.assertEqual(trivy_critical.end_of_life(with_os({}, EOSL=True)), "? ?")

    def test_unexpected_shape_raises(self):
        with self.assertRaises(trivy_critical.ReportError):
            trivy_critical.end_of_life({"Metadata": "debian"})


class CollectTest(unittest.TestCase):
    def test_collects_vulnerabilities_and_end_of_life_apart(self):
        with tempfile.TemporaryDirectory() as directory:
            Path(directory, "monica.json").write_text(json.dumps(with_os(report([]), Family="debian", Name="11.6", EOSL=True)))
            Path(directory, "trek.json").write_text(json.dumps(with_os(report([vuln("CVE-1")]), Family="alpine", Name="3.22.7")))
            images, eol = trivy_critical.collect(directory)
        self.assertEqual(list(images), ["trek"])
        self.assertEqual(eol, {"monica": "debian 11.6"})

    def test_images_without_critical_are_dropped(self):
        with tempfile.TemporaryDirectory() as directory:
            Path(directory, "immich.json").write_text(json.dumps(report([vuln("CVE-1")])))
            Path(directory, "trek.json").write_text(json.dumps(report([vuln("CVE-2", severity="HIGH")])))
            self.assertEqual(list(trivy_critical.collect(directory)[0]), ["immich"])

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
        self.assertEqual(payload["topic"], "github")
        self.assertEqual(payload["title"], "Trivy : 3 CVE critiques corrigeables, 2 images")
        self.assertEqual(payload["message"].splitlines(), [
            "immich", "  CVE-2 zlib 1.2 → 1.3", "  CVE-3 curl 8 → 8.1",
            "trek", "  CVE-1 openssl 1.0.0 → 1.0.1",
        ])
        self.assertEqual(payload["click"], "https://example.test")

    def test_title_counts_distinct_cves(self):
        payload = trivy_critical.message({"trek": [("CVE-1", "libssl3", "1", "2"), ("CVE-1", "openssl", "1", "2")]}, "")
        self.assertEqual(payload["title"], "Trivy : 1 CVE critique corrigeable, 1 image")

    def test_singular(self):
        payload = trivy_critical.message({"trek": [("CVE-1", "openssl", "1", "2")]}, "")
        self.assertEqual(payload["title"], "Trivy : 1 CVE critique corrigeable, 1 image")

    def test_long_message_is_truncated(self):
        vulns = [(f"CVE-2026-{i:05d}", "package-with-a-long-name", "1.0.0", "1.0.1") for i in range(500)]
        payload = trivy_critical.message({"big": vulns}, "")
        self.assertLessEqual(len(payload["message"].encode("utf-8")), trivy_critical.MAX_MESSAGE_BYTES + 100)
        self.assertIn("lignes de plus (onglet Security)", payload["message"].splitlines()[-1])

    def test_end_of_life_alone_is_low_priority(self):
        payload = trivy_critical.message({}, "https://example.test", {"redis-dawarich": "alpine 3.21.9", "monica": "debian 11.6"})
        self.assertEqual(payload["topic"], "github")
        self.assertEqual(payload["title"], "Trivy : 2 images sur une distribution en fin de vie")
        self.assertEqual(payload["message"].splitlines(), [
            "Distribution en fin de vie (information) :", "  monica : debian 11.6", "  redis-dawarich : alpine 3.21.9",
        ])
        self.assertEqual(payload["priority"], 2)
        self.assertNotIn("rotating_light", payload["tags"])
        # L'onglet Security ne dit rien des fins de vie : pas de lien vers lui.
        self.assertNotIn("click", payload)

    def test_end_of_life_follows_the_cves(self):
        payload = trivy_critical.message({"trek": [("CVE-1", "openssl", "1", "2")]}, "https://example.test", {"monica": "debian 11.6"})
        self.assertEqual(payload["title"], "Trivy : 1 CVE critique corrigeable, 1 image ; 1 image en fin de vie")
        self.assertEqual(payload["message"].splitlines(), [
            "trek", "  CVE-1 openssl 1 → 2", "Distribution en fin de vie (information) :", "  monica : debian 11.6",
        ])
        self.assertEqual(payload["priority"], 4)
        self.assertEqual(payload["click"], "https://example.test")

    def test_long_cve_list_does_not_cut_end_of_life(self):
        vulns = [(f"CVE-2026-{i:05d}", "package-with-a-long-name", "1.0.0", "1.0.1") for i in range(500)]
        text = trivy_critical.message({"big": vulns}, "", {"monica": "debian 11.6"})["message"]
        self.assertLessEqual(len(text.encode("utf-8")), trivy_critical.MAX_MESSAGE_BYTES + 100)
        self.assertIn("lignes de plus", text)
        self.assertEqual(text.splitlines()[-1], "  monica : debian 11.6")

    def test_end_of_life_alone_has_the_whole_message(self):
        eol = {f"image-{i:02d}": "debian 11.6" for i in range(70)}
        text = trivy_critical.message({}, "", eol)["message"]
        self.assertGreater(len(text.encode("utf-8")), trivy_critical.MAX_MESSAGE_BYTES // 2)
        self.assertNotIn("de plus", text)

    def test_one_line_left_is_singular(self):
        self.assertEqual(trivy_critical.fit(["a", "b"], 2), "a\n… et 1 ligne de plus\n")

    def test_many_end_of_life_images_stay_under_the_limit(self):
        eol = {f"image-with-a-rather-long-name-{i}": "debian 11.6" for i in range(500)}
        vulns = [(f"CVE-2026-{i:05d}", "package-with-a-long-name", "1.0.0", "1.0.1") for i in range(500)]
        for images in ({}, {"big": vulns}):
            text = trivy_critical.message(images, "", eol)["message"]
            self.assertLessEqual(len(text.encode("utf-8")), trivy_critical.MAX_MESSAGE_BYTES + 100)


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

    def test_end_of_life_alone_is_published_and_succeeds(self):
        Path(self.directory.name, "monica.json").write_text(json.dumps(with_os(report([]), Family="debian", Name="11.6", EOSL=True)))
        with mock.patch.object(trivy_critical, "publish") as publish:
            code, out = self.run_main()
        self.assertEqual(code, 0)
        self.assertEqual(publish.call_args.args[1]["priority"], 2)
        # Dépôt public : le titre seul dans le log, comme pour les CVE.
        self.assertIn("1 image sur une distribution en fin de vie", out)
        self.assertNotIn("debian", out)

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
        self.assertIn("Trivy : 1 CVE critique", out)
        self.assertNotIn("openssl", out)
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
