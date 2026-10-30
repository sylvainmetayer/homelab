"""Tests of the --verify-data mode of restore_test.py (Lint workflow:
python -I -m unittest discover -s .github/scripts -p 'test_*.py')."""
import json
import os
import subprocess
import unittest
from unittest import mock

import restore_test as rt

ENTRY = {"host": "docker", "repo": "wiki", "role": "wiki"}
SUMMARY = ("Finished cryptographic data integrity verification, "
           "verified {chunks} chunks with {errors} integrity errors.")


def listing(stamp, name="wiki-1"):
    stdout = json.dumps({"archives": [{"name": name}], "repository": {"last_modified": stamp}})
    return subprocess.CompletedProcess([], 0, stdout, "")


def check(returncode, stderr):
    return subprocess.CompletedProcess([], returncode, "", stderr)


class VerifyData(unittest.TestCase):
    def verify(self, *results):
        calls = []

        def fake_run(*args, **kwargs):
            calls.append((args, kwargs))
            result = results[len(calls) - 1]
            if isinstance(result, Exception):
                raise result
            return result

        with mock.patch.dict(os.environ, {"BORG_REPO_BASE": "ssh://u@h:23/."}), \
                mock.patch.object(rt, "run", side_effect=fake_run):
            try:
                return rt.verify_data(ENTRY), calls
            finally:
                self.assertEqual(len(calls), len(results))

    def test_clean_check(self):
        message, calls = self.verify(
            listing("t1"),
            check(0, "Analyzing archive wiki-1 (1/1)\n" + SUMMARY.format(chunks=1234, errors=0)))
        self.assertIn("1234 blocs vérifiés", message)
        borg_check = calls[1]
        self.assertEqual(borg_check[0][:3], ("borg", "check", "--bypass-lock"))
        self.assertIn("--verify-data", borg_check[0])
        self.assertIn("--archives-only", borg_check[0])
        self.assertNotIn("--repair", borg_check[0])
        self.assertTrue(borg_check[1]["quiet"])
        self.assertEqual(borg_check[0][-1], "ssh://u@h:23/./docker/wiki")

    def test_errors_hide_borg_output(self):
        stderr = "archive wiki-1: /secret/path: New missing file chunk detected\n" \
                 + SUMMARY.format(chunks=10, errors=2)
        with self.assertRaises(rt.RestoreError) as raised:
            self.verify(listing("t1"), check(1, stderr), listing("t1"))
        self.assertIn("2 blocs corrompus sur 10", str(raised.exception))
        self.assertNotIn("/secret/path", str(raised.exception))

    def test_crash_without_summary(self):
        with self.assertRaises(rt.RestoreError) as raised:
            self.verify(listing("t1"), check(2, "Traceback /secret/path"), listing("t1"))
        self.assertIn("pas de résumé", str(raised.exception))
        self.assertNotIn("/secret/path", str(raised.exception))

    def test_backup_during_check_is_inconclusive(self):
        with self.assertRaises(rt.RestoreError) as raised:
            self.verify(listing("t1"), check(1, "orphaned objects found"), listing("t2", name="wiki-2"))
        self.assertIn("non concluant", str(raised.exception))

    def test_prune_during_check_is_inconclusive(self):
        # Same latest archive, older one pruned: only the manifest's timestamp moved.
        with self.assertRaises(rt.RestoreError) as raised:
            self.verify(listing("t1"), check(1, "missing chunk"), listing("t2"))
        self.assertIn("non concluant", str(raised.exception))

    def test_archive_error_without_integrity_error(self):
        with self.assertRaises(rt.RestoreError) as raised:
            self.verify(listing("t1"), check(1, SUMMARY.format(chunks=10, errors=0)), listing("t1"))
        self.assertNotIn("0 blocs corrompus", str(raised.exception))
        self.assertIn("erreur hors des blocs", str(raised.exception))

    def test_failed_listing_keeps_the_check_failure(self):
        with self.assertRaises(rt.RestoreError) as raised:
            self.verify(listing("t1"), check(1, SUMMARY.format(chunks=10, errors=2)),
                        rt.RestoreError("borg list a échoué (2): Connection closed"))
        self.assertIn("2 blocs corrompus sur 10", str(raised.exception))

    def test_success_needs_the_summary(self):
        with self.assertRaises(rt.RestoreError):
            self.verify(listing("t1"), check(0, ""))

    def test_failure_prints_the_filtered_output(self):
        stderr = ("archive wiki-1: /secret/path: New missing file chunk detected\n"
                  + SUMMARY.format(chunks=10, errors=0) + "\n"
                  + "OSError: [Errno 30] Read-only file system: '/home/sub/docker/wiki/nonce-x1y2.tmp'\n")
        with mock.patch("builtins.print") as printed, self.assertRaises(rt.RestoreError):
            self.verify(listing("t1"), check(2, stderr), listing("t1"))
        out = "\n".join(str(call.args[0]) for call in printed.call_args_list)
        self.assertIn("Read-only file system: '…/nonce-x1y2.tmp'", out)
        self.assertIn("verified 10 chunks", out)
        self.assertNotIn("/secret/path", out)
        self.assertNotIn("/home/sub", out)

    def test_clean_check_prints_nothing(self):
        with mock.patch("builtins.print") as printed:
            self.verify(listing("t1"), check(0, SUMMARY.format(chunks=1, errors=0)))
        printed.assert_not_called()


# A borg 1.4.5 client (PyInstaller binary) failing on an exception of borg
# serve after the data verification, sysinfo included, interleaved with
# lines that name archived files.
REMOTE_FAILURE = """\
Starting archive consistency check...
Starting cryptographic data integrity verification...
Finished cryptographic data integrity verification, verified 4242 chunks with 0 integrity errors.
Analyzing archive homebox-2026-10-29T01:00:02 (1/14)
homebox-2026-10-29T01:00:02: data/Documents/impots 2025.pdf: New missing file chunk detected \
(Byte 0-1024, Chunk %s). Replacing with all-zero chunk.
homebox-2026-10-29T01:00:02: /srv/homebox/data/secret.db: size inconsistency detected: size 10, chunks size 0
Borg server: Traceback (most recent call last):
Borg server:   File "/usr/lib/python3/dist-packages/borg/remote.py", line 248, in serve
Borg server:     res = f(**args)
Borg server:           ^^^^^^^^^
Borg server:   File "/usr/lib/python3/dist-packages/borg/repository.py", line 397, in commit_nonce_reservation
Borg server:     with SaveFile(nonce_path, binary=False) as fd:
Borg server:   File "/usr/lib/python3.11/tempfile.py", line 256, in _mkstemp_inner
Borg server: OSError: [Errno 30] Read-only file system: '/home/docker/homebox/nonce-abc_12.tmp'
Borg server: Platform: Linux storagebox 6.1.0 #1 SMP x86_64
Borg server: Linux: Unknown Linux
Borg server: Borg: 1.4.0  Python: CPython 3.11.2 msgpack: 1.0.5 fuse: None [pyfuse3,llfuse]
Borg server: PID: 4242  CWD: /home
Borg server: sys.argv: ['borg', 'serve', '--info']
Borg server: SSH_ORIGINAL_COMMAND: 'borg serve --info'
Platform: Linux runner 6.8.0 #1 SMP x86_64
Borg: 1.4.5  Python: CPython 3.13.5 msgpack: 1.1.0 fuse: llfuse 1.5.1 [pyfuse3,llfuse]
PID: 99  CWD: /home/runner/work/homelab/homelab
sys.argv: ['borg', 'check', '--bypass-lock', '--info', 'ssh://u123-sub4@u123.your-storagebox.de:23/./docker/homebox']
SSH_ORIGINAL_COMMAND: None
OSError: [Errno 30] Read-only file system: '/home/docker/homebox/nonce-abc_12.tmp'
""" % ("ab" * 32)


class VerifyDiagnostic(unittest.TestCase):
    def test_remote_exception_keeps_the_cause_only(self):
        lines = rt.verify_diagnostic(REMOTE_FAILURE)
        self.assertEqual(lines, [
            "Starting archive consistency check...",
            "Starting cryptographic data integrity verification...",
            SUMMARY.format(chunks=4242, errors=0),
            "Analyzing archive homebox-2026-10-29T01:00:02 (1/14)",
            "serveur : Traceback (most recent call last):",
            'serveur : File "remote.py", line 248, in serve',
            'serveur : File "repository.py", line 397, in commit_nonce_reservation',
            'serveur : File "tempfile.py", line 256, in _mkstemp_inner',
            "serveur : OSError: [Errno 30] Read-only file system: '…/nonce-abc_12.tmp'",
            "serveur : Borg: 1.4.0  Python: CPython 3.11.2 msgpack: 1.0.5 fuse: None [pyfuse3,llfuse]",
            "Borg: 1.4.5  Python: CPython 3.13.5 msgpack: 1.1.0 fuse: llfuse 1.5.1 [pyfuse3,llfuse]",
            "OSError: [Errno 30] Read-only file system: '…/nonce-abc_12.tmp'",
        ])
        out = "\n".join(lines)
        for secret in ("impots", "secret.db", "/srv", "/home", "u123", "storagebox", "sys.argv", "CWD"):
            self.assertNotIn(secret, out)

    def test_paths_outside_the_repository_files_are_cut(self):
        lines = rt.verify_diagnostic(
            "PermissionError: [Errno 13] Permission denied: '/data/Documents/secret.txt'\n"
            "FileNotFoundError: [Errno 2] No such file or directory: /var/x/config\n"
            "Repository manifest is corrupted: bad index.12 at ssh://user@host:23/./docker/wiki\n")
        self.assertEqual(lines, [
            "PermissionError: [Errno 13] Permission denied: '…'",
            "FileNotFoundError: [Errno 2] No such file or directory: …/config",
            "Repository manifest is corrupted: bad index.12 at …",
        ])

    def test_read_only_warning_is_kept(self):
        lines = rt.verify_diagnostic(
            "Permission denied: Failed writing to '/home/docker/wiki/nonce'. This is expected when "
            "working on read-only repositories.\n")
        self.assertEqual(lines, ["Permission denied: Failed writing to '…/nonce'. This is expected when "
                                 "working on read-only repositories."])

    def test_item_level_errors_never_pass(self):
        stderr = "\n".join([
            "wiki-1: etc/passwd: New missing file chunk detected (Byte 0-10, Chunk %s). x" % ("cd" * 32),
            "wiki-1: home/me/.ssh/id_ed25519: Missing all-zero replacement chunk detected",
            "wiki-1: notes.txt: size inconsistency detected: size 1, chunks size 2",
            "Did not get expected metadata dict when unpacking item metadata (notes.txt)",
            "    with open(path) as fd:",
            "                ^^^^",
        ])
        self.assertEqual(rt.verify_diagnostic(stderr), [])

    def test_chunk_errors_are_folded_and_capped(self):
        missing = "chunk {0}: Object with key {0} not found in repository ssh://u@h:23/./docker/wiki."
        same = [missing.format("ab" * 32)] * 3
        lines = rt.verify_diagnostic("\n".join(same + [missing.format("%064x" % n) for n in range(100)]))
        self.assertEqual(len(lines), rt.VERIFY_DIAG_LINES)
        self.assertFalse([line for line in lines if "ssh:" in line or "u@h" in line])
        folded = rt.verify_diagnostic("\n".join(same))
        self.assertEqual(len(folded), 1)
        self.assertTrue(folded[0].endswith("(×3)"))

    def test_long_lines_are_cut(self):
        lines = rt.verify_diagnostic("ValueError: " + "x" * 1000)
        self.assertEqual(len(lines[0]), rt.VERIFY_DIAG_WIDTH)


class Main(unittest.TestCase):
    def test_usage(self):
        with mock.patch("sys.stderr"):
            self.assertEqual(rt.main([]), 2)
            self.assertEqual(rt.main(["--verify-data"]), 2)
            self.assertEqual(rt.main(["a", "b"]), 2)


if __name__ == "__main__":
    unittest.main()
