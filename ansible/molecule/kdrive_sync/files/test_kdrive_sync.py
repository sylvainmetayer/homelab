"""Tests de kdrive_sync.py (rôle kdrive_sync), lancés par verify.yml du
scénario avec le python3 de l'hôte de test : sh à la place de rclone, aucun
appel réseau. À la main : copier ce fichier à côté de
ansible/roles/kdrive_sync/files/kdrive_sync.py, puis
python3 -I -m unittest discover -s . -p 'test_*.py'.
"""

import io
import json
import os
import signal
import tempfile
import unittest
from contextlib import redirect_stderr, redirect_stdout
from unittest import mock

import kdrive_sync as ks

STATS = {"transfers": 3, "bytes": 1536, "elapsedTime": 120.0, "checks": 10, "errors": 0}


class HumanSizeTest(unittest.TestCase):
    def test_units(self):
        cases = {
            0: "0 o",
            1023: "1023 o",
            1024: "1.0 Kio",
            1536: "1.5 Kio",
            1024**2: "1.0 Mio",
            1024**3: "1.0 Gio",
            1024**4: "1.0 Tio",
            3 * 1024**5: "3072.0 Tio",
        }
        for size, expected in cases.items():
            with self.subTest(size=size):
                self.assertEqual(ks.human_size(size), expected)


class SummaryTest(unittest.TestCase):
    def test_summary(self):
        self.assertEqual(ks.summary(STATS), "3 fichier(s) copié(s), 1.5 Kio en 2 min ; 10 vérifié(s), 0 erreur(s)")

    def test_missing_stats(self):
        self.assertEqual(ks.summary(None), "statistiques de rclone absentes")

    def test_null_fields(self):
        self.assertEqual(ks.summary({"transfers": None}), "0 fichier(s) copié(s), 0 o en 0 min ; 0 vérifié(s), 0 erreur(s)")


class Script(unittest.TestCase):
    """Un faux rclone : sh qui écrit ces lignes puis sort avec ce code."""

    def setUp(self):
        previous = signal.getsignal(signal.SIGTERM)
        self.addCleanup(signal.signal, signal.SIGTERM, previous)

    def command(self, lines=(), code=0, extra=""):
        script = "".join(f"printf '%s\\n' '{line}'\n" for line in lines) + extra + f"exit {code}\n"
        return ["sh", "-c", script, "rclone"]


class RunTest(Script):
    def run_command(self, command):
        with redirect_stdout(io.StringIO()) as out:
            result = ks.run(command)
        return result, out.getvalue()

    def test_last_stats_win_and_output_is_relayed(self):
        lines = [
            json.dumps({"level": "info", "stats": {"transfers": 1}}),
            "pas du json",
            json.dumps({"level": "info", "stats": STATS}),
        ]
        (code, stats, last_error, interrupted), out = self.run_command(self.command(lines))
        self.assertEqual((code, stats, last_error, interrupted), (0, STATS, "", False))
        self.assertIn("pas du json", out)

    def test_last_error_levels(self):
        lines = [
            json.dumps({"level": "error", "msg": "première"}),
            json.dumps({"level": "critical", "msg": "dernière"}),
            json.dumps({"level": "warning", "msg": "pas une erreur"}),
        ]
        (code, _, last_error, _), _ = self.run_command(self.command(lines, code=1))
        self.assertEqual((code, last_error), (1, "dernière"))

    def test_json_that_is_not_an_object_or_stats_of_another_shape(self):
        lines = ["[1, 2]", "42", json.dumps({"stats": "non"})]
        (code, stats, _, _), _ = self.run_command(self.command(lines))
        self.assertEqual((code, stats), (0, None))

    def test_sigterm_stops_the_command_and_is_reported(self):
        # Le faux rclone envoie SIGTERM au script, comme systemd, puis attend :
        # seul le relais du signal peut le terminer. La pause : le temps que
        # run() pose son gestionnaire, juste après le Popen.
        command = self.command(extra=f"sleep 0.5\nkill -TERM {os.getpid()}\nexec sleep 30\n")
        (code, _, _, interrupted), _ = self.run_command(command)
        self.assertTrue(interrupted)
        self.assertEqual(code, -signal.SIGTERM)


class MainTest(Script):
    def main(self, command, push=None):
        out, err = io.StringIO(), io.StringIO()
        env = {ks.PUSH_URL_VARIABLE: "http://kuma.invalid/api/push/jeton"}
        with (
            mock.patch.dict(os.environ, env),
            mock.patch.object(ks, "push", **(push or {})) as pushed,
            redirect_stdout(out),
            redirect_stderr(err),
        ):
            code = ks.main(["--backup-dir-root", "/sauvegarde/", "--", *command])
        return code, pushed, out.getvalue(), err.getvalue()

    def test_success_pushes_up_with_the_summary(self):
        code, pushed, _, _ = self.main(self.command([json.dumps({"stats": STATS})]))
        self.assertEqual(code, 0)
        self.assertEqual(pushed.call_args.args[1:], ("up", ks.summary(STATS)))

    def test_backup_dir_is_appended_to_the_command(self):
        with tempfile.TemporaryDirectory() as directory:
            # Le faux rclone écrit ses arguments : ceux reçus après `--`, et
            # --backup-dir <racine>/<horodatage>, sans le `--` lui-même.
            trace = os.path.join(directory, "argv")
            command = ["sh", "-c", f'printf "%s\\n" "$@" > {trace}', "rclone", "--rm", "sync"]
            self.main(command)
            with open(trace, encoding="utf-8") as f:
                argv = f.read().splitlines()
        self.assertEqual(argv[:3], ["--rm", "sync", "--backup-dir"])
        self.assertRegex(argv[3], r"^/sauvegarde/\d{4}-\d{2}-\d{2}T\d{6}$")

    def test_failure_pushes_down_with_the_last_error(self):
        lines = [json.dumps({"level": "error", "msg": "quota dépassé"})]
        code, pushed, _, _ = self.main(self.command(lines, code=3))
        self.assertEqual(code, 1)
        status, msg = pushed.call_args.args[1:]
        self.assertEqual(status, "down")
        self.assertTrue(msg.startswith("rclone code 3 : quota dépassé ; statistiques"))

    def test_failure_without_a_message_points_at_the_journal(self):
        _, pushed, _, _ = self.main(self.command(code=3))
        self.assertIn("voir journalctl -u kdrive-sync", pushed.call_args.args[2])

    def test_long_message_is_cut(self):
        lines = [json.dumps({"level": "error", "msg": "x" * 1000})]
        _, pushed, _, _ = self.main(self.command(lines, code=3))
        self.assertEqual(len(pushed.call_args.args[2]), ks.MAX_MESSAGE)

    def test_missing_command_is_red_at_once(self):
        code, pushed, _, _ = self.main(["/nonexistent/rclone"])
        self.assertEqual(code, 1)
        self.assertEqual(pushed.call_args.args[1], "down")
        self.assertIn("rclone code 127 : FileNotFoundError", pushed.call_args.args[2])

    def test_interrupted_with_exit_0_is_still_down(self):
        # rclone qui attrape SIGTERM et sort en 0 : interrompu, jamais up.
        command = self.command(
            extra=f"trap 'exit 0' TERM\nsleep 0.5\nkill -TERM {os.getpid()}\nwhile :; do sleep 0.1; done\n"
        )
        code, pushed, _, _ = self.main(command)
        self.assertEqual(code, 1)
        self.assertEqual(pushed.call_args.args[1], "down")
        self.assertIn("interrompu", pushed.call_args.args[2])

    def test_failed_push_is_exit_2_and_never_cites_the_url(self):
        for error in (OSError("http://kuma.invalid/api/push/jeton"), ValueError("kuma.invalid/api/push/jeton")):
            with self.subTest(error=error):
                code, _, out, err = self.main(self.command(), push={"side_effect": error})
                self.assertEqual(code, 2)
                self.assertNotIn("jeton", out + err)

    def test_empty_url_pushes_nothing(self):
        err = io.StringIO()
        with (
            mock.patch.dict(os.environ, {ks.PUSH_URL_VARIABLE: ""}),
            mock.patch.object(ks, "push") as pushed,
            redirect_stdout(io.StringIO()),
            redirect_stderr(err),
        ):
            code = ks.main(["--backup-dir-root", "/s", "--", *self.command()])
        self.assertEqual(code, 0)
        pushed.assert_not_called()
        self.assertIn("rien n'est poussé", err.getvalue())

    def test_push_appends_to_an_existing_query(self):
        with mock.patch.object(ks.urllib.request, "urlopen") as urlopen:
            ks.push("http://kuma.invalid/p?a=1", "up", "un message")
        self.assertEqual(urlopen.call_args.args[0], "http://kuma.invalid/p?a=1&status=up&msg=un+message&ping=")


if __name__ == "__main__":
    unittest.main()
