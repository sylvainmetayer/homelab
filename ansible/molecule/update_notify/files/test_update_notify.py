"""Tests de update_notify.py (rôle update_notify), lancés par verify.yml du
scénario avec le python3 de l'hôte de test. À la main : copier ce fichier à
côté de ansible/roles/update_notify/files/update_notify.py, puis
python3 -I -m unittest discover -s . -p 'test_*.py'.
"""

import io
import json
import os
import tempfile
import types
import unittest
from contextlib import redirect_stderr, redirect_stdout
from unittest import mock

import update_notify as un

# Sortie de `apt-get -s dist-upgrade`, formes vues sur Debian et Proxmox.
SIMULATION = """\
NOTE: This is only a simulation!
Reading package lists...
The following packages will be upgraded:
  curl docker-ce
Inst curl [8.5.0-1] (8.5.0-2 Debian:13.1/stable [amd64])
Inst openssl [3.0.1-1] (3.0.1-2 Debian-Security:13/stable-security [amd64])
Inst libc6 [2.41-1] (2.41-2 Debian:13.1/stable, Debian-Security:13/stable-security [amd64]) [libc-bin:amd64 ]
Inst pve-manager [8.4.1] (8.4.2 Proxmox:8/bookworm [amd64])
Inst libpve-common-perl [8.1] (8.2 local:1 [all])
Inst proxmox-kernel-6.8 [6.8.12-1] (6.8.12-2 local:1 [all])
Inst linux-image-amd64 [6.12.1] (6.12.2 Debian:13.1/stable [amd64])
Inst docker-ce [5:28.0] (5:28.1 Docker:13/trixie [amd64])
Inst containerd.io [1.7.0] (1.7.1 local:1 [amd64])
Inst brand-new (1.0 Debian:13.1/stable [amd64])
Remv old-package [1.0]
Conf curl (8.5.0-2 Debian:13.1/stable [amd64])
"""


class ParseSimulationTest(unittest.TestCase):
    def setUp(self):
        self.security, self.sensitive, self.other, self.removed = un.parse_simulation(SIMULATION)

    def names(self, entries):
        return [entry.split()[0] for entry in entries]

    def test_security_wins_over_any_other_origin(self):
        self.assertEqual(self.names(self.security), ["openssl", "libc6"])

    def test_security_suite_in_lower_case(self):
        security, _, _, _ = un.parse_simulation("Inst x [1] (2 Debian:13/trixie-security [amd64])\n")
        self.assertEqual(security, ["x 1 → 2"])

    def test_sensitive_by_origin_or_by_name(self):
        self.assertEqual(
            self.names(self.sensitive),
            ["pve-manager", "libpve-common-perl", "proxmox-kernel-6.8", "linux-image-amd64", "docker-ce", "containerd.io"],
        )

    def test_other_packages(self):
        self.assertEqual(self.names(self.other), ["curl", "brand-new"])

    def test_entry_shows_both_versions(self):
        self.assertIn("curl 8.5.0-1 → 8.5.0-2", self.other)

    def test_new_package_has_no_installed_version(self):
        self.assertIn("brand-new (nouveau) → 1.0", self.other)

    def test_removed_packages_and_conf_lines(self):
        self.assertEqual(self.removed, ["old-package"])
        # La ligne Conf du même paquet n'en fait pas un second.
        self.assertEqual(self.names(self.other).count("curl"), 1)

    def test_nothing_to_do(self):
        self.assertEqual(un.parse_simulation("0 upgraded, 0 newly installed.\n"), ([], [], [], []))


class RunTest(unittest.TestCase):
    def test_apt_speaks_c_and_never_asks(self):
        # La lecture de la simulation repose sur la sortie anglaise d'apt-get.
        with (
            mock.patch.dict(os.environ, {"LC_ALL": "fr_FR.UTF-8"}),
            mock.patch.object(un.subprocess, "run") as run,
        ):
            un.run(["apt-get", "update"])
        env = run.call_args.kwargs["env"]
        self.assertEqual((env["LC_ALL"], env["DEBIAN_FRONTEND"]), ("C", "noninteractive"))


class VersionKeyTest(unittest.TestCase):
    def test_numeric_not_lexical(self):
        self.assertGreater(un.version_key("6.8.12-10-pve"), un.version_key("6.8.12-9-pve"))
        self.assertGreater(un.version_key("6.14.0-1-pve"), un.version_key("6.8.12-4-pve"))


class PendingKernelTest(unittest.TestCase):
    def boot(self, *kernels):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        for name in kernels:
            with open(os.path.join(directory.name, name), "w", encoding="ascii"):
                pass
        return directory.name

    def test_newer_kernel_of_the_same_family(self):
        boot = self.boot("vmlinuz-6.8.12-9-pve", "vmlinuz-6.8.12-10-pve", "initrd.img-6.14.0-1-pve")
        self.assertEqual(un.pending_kernel(boot, "6.8.12-9-pve"), "6.8.12-10-pve")

    def test_running_the_newest(self):
        boot = self.boot("vmlinuz-6.8.12-9-pve", "vmlinuz-6.8.12-8-pve")
        self.assertIsNone(un.pending_kernel(boot, "6.8.12-9-pve"))

    def test_other_family_is_not_compared(self):
        boot = self.boot("vmlinuz-6.8.12-9-pve", "vmlinuz-7.0.0-1-amd64")
        self.assertIsNone(un.pending_kernel(boot, "6.8.12-9-pve"))

    def test_running_kernel_absent_from_boot_dir(self):
        self.assertIsNone(un.pending_kernel(self.boot(), "6.8.12-9-pve"))

    def test_unreadable_boot_dir(self):
        self.assertIsNone(un.pending_kernel(os.path.join(self.boot(), "absent"), "6.8.12-9-pve"))


class SectionTest(unittest.TestCase):
    def test_empty_section_is_left_out(self):
        self.assertEqual(un.section("Autres", []), [])

    def test_section_counts_all_and_lists_max_listed(self):
        entries = [f"p{i}" for i in range(un.MAX_LISTED + 2)]
        lines = un.section("Autres", entries)
        self.assertEqual(lines[0], f"Autres ({un.MAX_LISTED + 2}) :")
        self.assertEqual(len(lines), un.MAX_LISTED + 2)
        self.assertEqual(lines[-1], "  … et 2 autres")

    def test_section_at_the_cap_has_no_remainder(self):
        lines = un.section("Autres", [f"p{i}" for i in range(un.MAX_LISTED)])
        self.assertEqual(len(lines), un.MAX_LISTED + 1)
        self.assertNotIn("… et", lines[-1])


class FitMessageTest(unittest.TestCase):
    def test_short_message_is_untouched(self):
        self.assertEqual(un.fit_message(["a", "b"], ["fin"]), "a\nb\nfin")

    def test_long_message_stays_under_the_limit_in_bytes_and_keeps_the_tail(self):
        # Caractères de plusieurs octets : la limite de ntfy compte des octets.
        body = ["é" * 100 for _ in range(100)]
        message = un.fit_message(body, ["noyau", "runbook"], limit=2000)
        self.assertLessEqual(len(message.encode()), 2000)
        self.assertEqual(message.splitlines()[-2:], ["noyau", "runbook"])
        self.assertIn("liste tronquée", message)
        self.assertTrue(message.startswith("é" * 100 + "\n"))

    def test_body_exactly_filling_the_budget_is_not_cut(self):
        tail = ["fin"]
        marker = "… liste tronquée : apt list --upgradable sur l'hôte"
        budget = 2000 - len("\n".join([marker] + tail).encode()) - 1
        message = un.fit_message(["x" * (budget - 1)], tail, limit=2000)
        self.assertNotIn("tronquée", message)
        self.assertLessEqual(len(message.encode()), 2000)

    def test_one_byte_over_the_budget_is_cut(self):
        tail = ["fin"]
        marker = "… liste tronquée : apt list --upgradable sur l'hôte"
        budget = 2000 - len("\n".join([marker] + tail).encode()) - 1
        message = un.fit_message(["x" * budget], tail, limit=2000)
        self.assertEqual(message, "\n".join([marker] + tail))


class CheckAptTest(unittest.TestCase):
    """check_apt avec apt-get et le noyau remplacés : le message, sa priorité."""

    def check(self, simulation, kernels=()):
        boot = tempfile.TemporaryDirectory()
        self.addCleanup(boot.cleanup)
        for name in kernels:
            with open(os.path.join(boot.name, name), "w", encoding="ascii"):
                pass
        completed = types.SimpleNamespace(returncode=0, stdout=simulation, stderr="")
        args = types.SimpleNamespace(host="docker", retry_delay=0, boot_dir=boot.name)
        release = types.SimpleNamespace(release="6.12.1-1-amd64")
        with (
            mock.patch.object(un, "run", return_value=completed),
            mock.patch.object(un.shutil, "which", return_value=None),
            mock.patch.object(un.os, "uname", return_value=release),
        ):
            return un.check_apt(args)

    def test_up_to_date_sends_nothing(self):
        self.assertEqual(self.check("0 upgraded\n"), (None, "à jour"))

    def test_security_update_is_high_priority_and_listed_first(self):
        notification, summary = self.check(SIMULATION)
        self.assertEqual(notification["priority"], 4)
        self.assertEqual(notification["tags"], ["warning"])
        self.assertEqual(summary, "10 mises à jour, 2 de sécurité")
        self.assertEqual(notification["title"], "docker : 10 mise(s) à jour, dont 2 de sécurité")
        self.assertTrue(notification["message"].startswith("Sécurité (2) :"))
        self.assertIn("Docker en attente", notification["message"])
        self.assertTrue(notification["message"].endswith(un.RUNBOOK))

    def test_plain_update_is_normal_priority(self):
        notification, _ = self.check("Inst curl [1] (2 Debian:13.1/stable [amd64])\n")
        self.assertEqual(notification["priority"], 3)
        self.assertEqual(notification["tags"], ["package"])
        self.assertNotIn("Docker en attente", notification["message"])

    def test_docker_cli_alone_does_not_announce_a_daemon_restart(self):
        notification, _ = self.check("Inst docker-ce-cli [1] (2 Docker:13/trixie [amd64])\n")
        self.assertNotIn("Docker en attente", notification["message"])

    def test_pending_kernel_alone_notifies(self):
        notification, summary = self.check("0 upgraded\n", ["vmlinuz-6.12.2-1-amd64"])
        self.assertEqual(notification["title"], "docker : redémarrage en attente")
        self.assertIn("Noyau 6.12.2-1-amd64 installé, 6.12.1-1-amd64 en service", notification["message"])
        self.assertIn("noyau 6.12.2-1-amd64 en attente", summary)

    def test_removal_alone_notifies(self):
        # Son titre (« redémarrage en attente ») est trompeur : bug connu, pas figé ici.
        notification, _ = self.check("Remv old-package [1.0]\n")
        self.assertIn("Retirés par dist-upgrade (1) :\n  old-package", notification["message"])

    def test_failed_simulation_raises(self):
        failed = types.SimpleNamespace(returncode=100, stdout="", stderr="E: first\nE: last\n")
        args = types.SimpleNamespace(host="docker", retry_delay=0, boot_dir="/nonexistent")
        with (
            mock.patch.object(un, "apt_update"),
            mock.patch.object(un, "run", return_value=failed),
            self.assertRaisesRegex(un.CheckError, "simulation de dist-upgrade en échec : E: last"),
        ):
            un.check_apt(args)


class AptTailTest(unittest.TestCase):
    def tail(self, result):
        with (
            mock.patch.object(un.shutil, "which", return_value="/usr/bin/pveversion"),
            mock.patch.object(un, "run", return_value=result),
        ):
            return un.apt_tail(None, "6.8.12-9-pve", False)

    def test_first_line_of_pveversion_before_the_runbook(self):
        result = types.SimpleNamespace(returncode=0, stdout="pve-manager/9.2\nautre\n", stderr="")
        self.assertEqual(self.tail(result), ["pve-manager/9.2", f"À appliquer à la main : {un.RUNBOOK}"])

    def test_failed_pveversion_is_left_out(self):
        result = types.SimpleNamespace(returncode=1, stdout="pve-manager/9.2\n", stderr="")
        self.assertEqual(self.tail(result), [f"À appliquer à la main : {un.RUNBOOK}"])


class AptUpdateTest(unittest.TestCase):
    def test_retries_then_succeeds(self):
        results = [types.SimpleNamespace(returncode=rc, stderr="") for rc in (100, 100, 0)]
        with mock.patch.object(un, "run", side_effect=results) as run, mock.patch.object(un.time, "sleep"):
            un.apt_update(1)
        self.assertEqual(run.call_count, 3)

    def test_three_failures_raise_the_last_error(self):
        failed = types.SimpleNamespace(returncode=100, stderr="E: verrou\n")
        with (
            mock.patch.object(un, "run", return_value=failed) as run,
            mock.patch.object(un.time, "sleep") as sleep,
            self.assertRaisesRegex(un.CheckError, "E: verrou"),
        ):
            un.apt_update(7)
        self.assertEqual(run.call_count, 3)
        # Pas d'attente après le dernier essai.
        self.assertEqual(sleep.call_count, 2)


class MainTest(unittest.TestCase):
    ARGV = ["--host", "docker", "--ntfy-url", "http://ntfy.invalid", "--topic", "t"]

    def main(self, check, push_ok=True):
        pushes = []

        def push(url, status, msg):
            pushes.append((status, msg))
            return push_ok

        out = io.StringIO()
        with (
            mock.patch.dict(os.environ, {un.NTFY_TOKEN_VARIABLE: "jeton", un.PUSH_URL_VARIABLE: "http://kuma.invalid"}),
            mock.patch.object(un, "check_apt", **check),
            mock.patch.object(un, "push", side_effect=push),
            mock.patch.object(un, "publish") as publish,
            redirect_stdout(out),
        ):
            code = un.main(self.ARGV)
        return code, pushes, publish

    def test_up_to_date_pushes_up_without_publishing(self):
        code, pushes, publish = self.main({"return_value": (None, "à jour")})
        self.assertEqual((code, pushes), (0, [("up", "à jour")]))
        publish.assert_not_called()

    def test_failed_check_pushes_down(self):
        code, pushes, publish = self.main({"side_effect": un.CheckError("apt cassé")})
        self.assertEqual((code, pushes), (1, [("down", "apt cassé")]))
        publish.assert_not_called()

    def test_failed_push_is_exit_2(self):
        code, _, _ = self.main({"return_value": (None, "à jour")}, push_ok=False)
        self.assertEqual(code, 2)

    def test_publish_refuses_an_empty_token(self):
        with self.assertRaisesRegex(un.CheckError, "vide"):
            un.publish("http://ntfy.invalid", "t", "", {"title": "x"})

    def test_publish_error_does_not_cite_the_request(self):
        error = OSError("http://ntfy.invalid/secret-path")
        with (
            mock.patch.object(un.urllib.request, "urlopen", side_effect=error),
            self.assertRaises(un.CheckError) as raised,
        ):
            un.publish("http://ntfy.invalid", "t", "jeton", {"title": "x"})
        self.assertNotIn("secret-path", str(raised.exception))

    def test_publish_sends_the_topic_in_the_body(self):
        response = mock.MagicMock()
        with mock.patch.object(un.urllib.request, "urlopen", return_value=response) as urlopen:
            un.publish("http://ntfy.invalid/", "t", "jeton", {"title": "x"})
        request = urlopen.call_args.args[0]
        self.assertEqual(request.full_url, "http://ntfy.invalid/")
        self.assertEqual(json.loads(request.data), {"title": "x", "topic": "t"})
        self.assertEqual(request.get_header("Authorization"), "Bearer jeton")

    def test_push_error_does_not_cite_the_url(self):
        err = io.StringIO()
        with (
            mock.patch.object(un.urllib.request, "urlopen", side_effect=OSError("http://kuma.invalid/api/push/jeton")),
            redirect_stderr(err),
        ):
            self.assertFalse(un.push("http://kuma.invalid/api/push/jeton", "up", "ok"))
        self.assertNotIn("jeton", err.getvalue())

    def test_push_truncates_and_appends_to_an_existing_query(self):
        with mock.patch.object(un.urllib.request, "urlopen") as urlopen:
            self.assertTrue(un.push("http://kuma.invalid/p?a=1", "down", "x" * 300))
        url = urlopen.call_args.args[0]
        self.assertTrue(url.startswith("http://kuma.invalid/p?a=1&status=down&msg="))
        self.assertIn("msg=" + "x" * 250 + "&ping=", url)

    def test_empty_push_url_is_not_a_failure(self):
        with redirect_stderr(io.StringIO()):
            self.assertTrue(un.push("", "up", "ok"))


if __name__ == "__main__":
    unittest.main()
