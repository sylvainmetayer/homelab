"""Tests de ntfy-subscribers-check.sh (rôle ntfy), lancés par verify.yml du
scénario avec le python3 de l'hôte de test : le script tourne pour de bon sous
sh, avec un faux docker (les relevés du test) et un faux uptime-push. Le verify
le joue déjà par l'unité sur un cas up et un cas down ; ici, la lecture des
relevés. À la main : copier ce fichier à côté de
ansible/roles/ntfy/files/ntfy-subscribers-check.sh, puis
python3 -I -m unittest discover -s . -p 'test_*.py'.
"""

import os
import stat
import subprocess
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
SCRIPT = HERE / "ntfy-subscribers-check.sh"
URL = "http://kuma.invalid/api/push/moniteur"


def stats(**fields):
    body = ", ".join(f"{key}={value}" for key, value in sorted(fields.items()))
    return f"2026/11/04 10:00:00 INFO Server stats ({body})"


class CheckTest(unittest.TestCase):
    def setUp(self):
        # À côté du test, pas /tmp : les faux doivent pouvoir s'y exécuter.
        directory = tempfile.TemporaryDirectory(dir=HERE)
        self.addCleanup(directory.cleanup)
        self.dir = Path(directory.name)
        self.push_log = self.dir / "push"
        self.docker = self.dir / "docker"
        self.uptime_push = self.tool(
            "uptime-push",
            f'{{ printf "%s\\n" "$@"; echo ---; cat; }} > "{self.push_log}"\n',
        )

    def tool(self, name, body):
        path = self.dir / name
        path.write_text("#!/bin/sh\n" + body, encoding="utf-8")
        path.chmod(path.stat().st_mode | stat.S_IXUSR)
        return path

    def check(self, logs="", docker_code=0, push_url=""):
        logs_file = self.dir / "logs"
        logs_file.write_text(logs, encoding="utf-8")
        # ntfy journalise sur stderr.
        self.tool("docker", f'echo "$@" > "{self.dir}/docker-args"\ncat "{logs_file}" >&2\nexit {docker_code}\n')
        env = {
            **os.environ,
            "NTFY_SUBSCRIBERS_CHECK_DOCKER": str(self.docker),
            "NTFY_SUBSCRIBERS_CHECK_PUSH_URL": push_url,
            "UPTIME_PUSH": str(self.uptime_push),
        }
        return subprocess.run(
            ["sh", str(SCRIPT), "ntfy", "480"], capture_output=True, text=True, env=env, check=False, timeout=30
        )

    def test_window_is_passed_to_docker(self):
        self.check(stats(subscribers=1))
        self.assertEqual((self.dir / "docker-args").read_text().split(), ["logs", "--since", "480m", "ntfy"])

    def test_one_subscriber_is_up(self):
        result = self.check(stats(subscribers=1))
        self.assertEqual(result.returncode, 0)
        self.assertEqual(result.stdout, "up: jusqu'à 1 abonné(s) sur 480 min\n")

    def test_the_highest_reading_counts_numerically(self):
        logs = "\n".join(stats(subscribers=n) for n in (0, 10, 9)) + "\n"
        result = self.check(logs)
        self.assertEqual(result.returncode, 0)
        self.assertIn("jusqu'à 10 abonné(s)", result.stdout)

    def test_a_field_among_others_is_read(self):
        result = self.check(stats(messages=5, subscribers=2, topics=3))
        self.assertIn("jusqu'à 2 abonné(s)", result.stdout)

    def test_zero_everywhere_is_down(self):
        result = self.check("\n".join(stats(subscribers=0) for _ in range(3)))
        self.assertEqual(result.returncode, 1)
        self.assertIn("down: aucun abonné", result.stdout)

    def test_a_field_merely_ending_in_subscribers_is_not_read(self):
        result = self.check(stats(push_subscribers=9, subscribers=0))
        self.assertEqual(result.returncode, 1)
        self.assertIn("aucun abonné", result.stdout)

    def test_a_field_ending_in_subscribers_alone_is_no_reading(self):
        result = self.check(stats(push_subscribers=9))
        self.assertEqual(result.returncode, 1)
        self.assertIn("aucune ligne Server stats", result.stdout)

    def test_subscribers_in_another_log_line_is_not_read(self):
        result = self.check("INFO Autre chose (subscribers=7)\nsubscribers=7\n")
        self.assertEqual(result.returncode, 1)
        self.assertIn("aucune ligne Server stats de ntfy sur 480 min", result.stdout)

    def test_no_line(self):
        self.assertEqual(self.check("").returncode, 1)

    def test_docker_failure_cites_its_last_line(self):
        result = self.check("première\nNo such container: ntfy", docker_code=1)
        self.assertEqual(result.returncode, 1)
        self.assertEqual(result.stdout, "down: docker logs ntfy en échec : No such container: ntfy\n")

    def test_no_url_pushes_nothing(self):
        self.check(stats(subscribers=1))
        self.assertFalse(self.push_log.exists())

    def test_push_gets_the_url_on_stdin_only(self):
        result = self.check(stats(subscribers=1), push_url=URL)
        self.assertEqual(result.returncode, 0)
        args, _, stdin = self.push_log.read_text(encoding="utf-8").partition("---\n")
        self.assertEqual(args.splitlines(), ["--agent", "ntfy-subscribers-check", "-", "up", "jusqu'à 1 abonné(s) sur 480 min"])
        self.assertEqual(stdin, f'url = "{URL}"\n')

    def test_down_is_pushed_and_still_fails(self):
        result = self.check(stats(subscribers=0), push_url=URL)
        self.assertEqual(result.returncode, 1)
        self.assertEqual(self.push_log.read_text(encoding="utf-8").splitlines()[3], "down")


if __name__ == "__main__":
    unittest.main()
