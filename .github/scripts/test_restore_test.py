"""Tests of restore_test.py: command line, redaction of printed lines (Lint workflow:
python -I -m unittest discover -s .github/scripts -p 'test_*.py')."""
import subprocess
import unittest
from unittest import mock

import restore_test as rt


class Main(unittest.TestCase):
    def test_usage(self):
        with mock.patch("sys.stderr"):
            self.assertEqual(rt.main([]), 2)
            self.assertEqual(rt.main(["a", "b"]), 2)


class Redact(unittest.TestCase):
    # Fictitious sub-account, shaped like a Storage Box one.
    ACCOUNT = "u123-sub4"
    HOST = "u123.your-storagebox.de"

    def assertClean(self, text):
        for leak in (self.ACCOUNT, self.HOST, "u123", "docker/wiki", "srv/", "/home"):
            self.assertNotIn(leak, text)

    def test_repository_url(self):
        line = f"Repository ssh://{self.ACCOUNT}@{self.HOST}:23/./docker/wiki does not exist."
        self.assertEqual(rt.redact(line), "Repository ssh://… does not exist.")

    def test_remote_permission_denied(self):
        line = f"Remote: {self.ACCOUNT}@{self.HOST}: Permission denied (publickey)."
        self.assertEqual(rt.redact(line), "Remote: <compte>@<hôte>: Permission denied (publickey).")

    def test_host_alone(self):
        line = f"Remote: ssh: Could not resolve hostname {self.HOST}: Name or service not known"
        redacted = rt.redact(line)
        self.assertClean(redacted)
        self.assertIn("Could not resolve hostname <hôte>: Name or service not known", redacted)

    def test_quoted_path_with_spaces(self):
        line = "FileNotFoundError: [Errno 2] No such file or directory: 'srv/my docs/rapport final.pdf'"
        self.assertEqual(rt.redact(line),
                         "FileNotFoundError: [Errno 2] No such file or directory: '…'")

    def test_absolute_path(self):
        line = "Failed to create/acquire the lock /home/runner/.cache/borg/lock.exclusive (timeout)."
        self.assertEqual(rt.redact(line), "Failed to create/acquire the lock <chemin> (timeout).")

    def test_unquoted_archived_path(self):
        line = "srv/nextcloud/data/admin/notes.md: [Errno 13] Permission denied"
        self.assertEqual(rt.redact(line), "<chemin>: [Errno 13] Permission denied")

    def test_keeps_diagnosis(self):
        for line in ("Connection closed by remote host. Is borg working on the server?",
                     "borg.locking.LockTimeout: Failed to create/acquire the lock",
                     "Error: PassphraseWrong"):
            self.assertEqual(rt.redact(line), line)

    def test_run_error_and_command_line(self):
        repo = f"ssh://{self.ACCOUNT}@{self.HOST}:23/./docker/wiki"
        stderr = ("noise\n" f"Remote: {self.ACCOUNT}@{self.HOST}: Permission denied "
                  "(publickey).\n" + f"Repository {repo} does not exist." + " x" * 150)
        failed = subprocess.CompletedProcess([], 2, stdout="", stderr=stderr)
        with mock.patch("subprocess.run", return_value=failed), \
                mock.patch("builtins.print") as printed:
            with self.assertRaises(rt.RestoreError) as caught:
                rt.borg("list", "--json", repo, show_error=True)
        shown = " ".join(str(arg) for call in printed.call_args_list for arg in call.args)
        self.assertClean(shown)
        self.assertClean(str(caught.exception))
        self.assertIn("Repository ssh://… does not exist.", str(caught.exception))


if __name__ == "__main__":
    unittest.main()
