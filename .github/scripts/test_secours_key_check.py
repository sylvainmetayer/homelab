"""Tests of secours_key_check.py, sops and age-keygen mocked (Lint workflow:
python -I -m unittest discover -s .github/scripts -p 'test_*.py')."""

import datetime
import subprocess
import tempfile
import unittest
from pathlib import Path

import check_secret_rotation as rotation
import secours_key_check as secours

SECOURS = "age1uskgue38aysxxcp6p6l47xxxsjfnpm93wsgt3m7wj6qrr73zh3esy8d2qa"
PERSO = "age1pvr43f8dnpsq7swgc0r3cy799yvyk2y4wj8z3n57sckq3z6dx5yq4rntuu"
TODAY = datetime.date(2026, 10, 29)

CONFIG = f"""\
creation_rules:
  - path_regex: (^|/)ansible/secrets\\.sops\\.yaml$
    key_groups:
      - age:
          - {PERSO} # perso
          - {SECOURS} # secours
  - path_regex: (^|/)secrets\\.sops\\.yaml$
    key_groups:
      - age:
          - {PERSO} # perso
          - {SECOURS} # secours
"""

RUNBOOK = """\
---
# Date du dernier test réussi.
dernier_test: 2026-07-01
---

# Tester la clé age `secours`

dernier_test: 1999-01-01 hors du front matter, inchangé
"""


class FakeRun:
    """subprocess.run of age-keygen and sops: records each call, decides from the key file."""

    def __init__(self, public=SECOURS, decrypt_with=("key",), keygen_rc=0, refusal=secours.NO_DATA_KEY):
        self.public, self.decrypt_with, self.keygen_rc = public, decrypt_with, keygen_rc
        self.refusal = refusal
        self.calls = []

    def __call__(self, cmd, **kwargs):
        self.calls.append((cmd, kwargs))
        if cmd[1] == "-y":
            return subprocess.CompletedProcess(cmd, self.keygen_rc, stdout=self.public + "\n")
        keyfile = kwargs["env"]["SOPS_AGE_KEY_FILE"]
        name = "devnull" if keyfile == "/dev/null" else "key"
        if name in self.decrypt_with:
            return subprocess.CompletedProcess(cmd, 0, stderr=None)
        stderr = self.refusal if kwargs["stderr"] == subprocess.PIPE else None
        return subprocess.CompletedProcess(cmd, 128, stderr=stderr)


class Repo:
    def __enter__(self):
        self.tmp = tempfile.TemporaryDirectory()
        root = Path(self.tmp.name)
        (root / "docs/runbooks").mkdir(parents=True)
        (root / "ansible").mkdir()
        (root / ".sops.yaml").write_text(CONFIG, encoding="utf-8")
        (root / secours.RUNBOOK).write_text(RUNBOOK, encoding="utf-8")
        self.key = root / "secours.key"
        self.key.write_text("not read by the script\n", encoding="utf-8")
        return root

    def __exit__(self, *exc):
        self.tmp.cleanup()


def run_main(root, fake, key, *extra):
    lines = []
    rc = secours.main(
        [str(key), "--sops", "/opt/sops/sops", "--age-keygen", "/opt/age/age-keygen", "--today", TODAY.isoformat(), *extra],
        root=root,
        run=fake,
        out=lines.append,
    )
    return rc, lines


class SecoursKeysTest(unittest.TestCase):
    def test_reads_the_secours_lines_only(self):
        self.assertEqual(secours.secours_keys(CONFIG), {SECOURS})

    def test_real_sops_config_has_one_secours_key(self):
        text = (secours.ROOT / ".sops.yaml").read_text(encoding="utf-8")
        self.assertEqual(len(secours.secours_keys(text)), 1)


class SetLastTestTest(unittest.TestCase):
    def test_updates_the_front_matter_only(self):
        text = secours.set_last_test(RUNBOOK, TODAY)
        self.assertIn("dernier_test: 2026-10-29\n", text)
        self.assertIn("dernier_test: 1999-01-01 hors du front matter", text)
        self.assertEqual(text.count("\n"), RUNBOOK.count("\n"))
        date, errors = rotation.secours_test(text, TODAY)
        self.assertEqual((date, errors), (TODAY, []))

    def test_keeps_a_trailing_comment(self):
        text = RUNBOOK.replace("2026-07-01", "2026-07-01 # note")
        self.assertIn("dernier_test: 2026-10-29 # note", secours.set_last_test(text, TODAY))

    def test_keeps_a_comment_without_space_and_fills_an_empty_value(self):
        text = RUNBOOK.replace("2026-07-01", "2026-07-01# note")
        self.assertIn("dernier_test: 2026-10-29# note", secours.set_last_test(text, TODAY))
        text = RUNBOOK.replace(" 2026-07-01", "")
        self.assertEqual(rotation.secours_test(secours.set_last_test(text, TODAY), TODAY), (TODAY, []))

    def test_same_pattern_as_check_secret_rotation(self):
        self.assertEqual(secours.LAST_TEST_RE.pattern, rotation.LAST_TEST_RE.pattern)

    def test_real_runbook_parses(self):
        text = (secours.ROOT / secours.RUNBOOK).read_text(encoding="utf-8")
        self.assertEqual(rotation.secours_test(secours.set_last_test(text, TODAY), TODAY), (TODAY, []))

    def test_missing_line_raises(self):
        with self.assertRaises(ValueError):
            secours.set_last_test("---\nfoo: bar\n---\n", TODAY)
        with self.assertRaises(ValueError):
            secours.set_last_test("# pas de front matter\n", TODAY)


class MainTest(unittest.TestCase):
    def test_success_updates_the_date(self):
        with Repo() as root:
            fake = FakeRun()
            rc, lines = run_main(root, fake, root / "secours.key")
            self.assertEqual(rc, 0, lines)
            self.assertTrue(all(line.startswith(("ok ", "ÉCHEC ")) for line in lines))
            self.assertFalse(any(line.startswith("ÉCHEC") for line in lines))
            self.assertIn("dernier_test: 2026-10-29", (root / secours.RUNBOOK).read_text(encoding="utf-8"))

    def test_sops_runs_isolated(self):
        with Repo() as root:
            fake = FakeRun()
            run_main(root, fake, root / "secours.key")
            sops_calls = [kw for cmd, kw in fake.calls if cmd[0] == "/opt/sops/sops"]
            self.assertEqual(len(sops_calls), 4)  # deux fichiers, puis la contre-épreuve
            for kw in sops_calls:
                env = kw["env"]
                self.assertEqual(set(env), {"PATH", "HOME", "SOPS_AGE_KEY_FILE"})
                self.assertEqual(env["PATH"], secours.ISOLATED_PATH)
                self.assertFalse(Path(env["HOME"]).exists(), "HOME temporaire non supprimé")
                self.assertEqual(kw["stdout"], subprocess.DEVNULL)
            self.assertEqual(
                [kw["env"]["SOPS_AGE_KEY_FILE"] for kw in sops_calls],
                [str((root / "secours.key").resolve())] * 2 + ["/dev/null"] * 2,
            )
            # Le déchiffrement avec la clé ne garde rien, même pas stderr ;
            # seule la contre-épreuve lit stderr, pour la raison du refus.
            self.assertEqual([kw["stderr"] for kw in sops_calls], [subprocess.DEVNULL] * 2 + [subprocess.PIPE] * 2)
            keygen = [kw for cmd, kw in fake.calls if cmd[1] == "-y"]
            self.assertEqual([kw["env"] for kw in keygen], [{"PATH": secours.ISOLATED_PATH}])

    def _fails_unchanged(self, fake, expected):
        with Repo() as root:
            rc, lines = run_main(root, fake, root / "secours.key")
            self.assertEqual(rc, 1)
            self.assertTrue(any(line.startswith("ÉCHEC") and expected in line for line in lines), lines)
            self.assertEqual((root / secours.RUNBOOK).read_text(encoding="utf-8"), RUNBOOK)
            return fake

    def test_wrong_key(self):
        fake = self._fails_unchanged(FakeRun(public=PERSO), "clé publique")
        self.assertEqual(len(fake.calls), 1, "pas de déchiffrement avec une autre clé")

    def test_unreadable_key(self):
        self._fails_unchanged(FakeRun(keygen_rc=1), "age-keygen")

    def test_decrypt_fails(self):
        self._fails_unchanged(FakeRun(decrypt_with=()), "déchiffrement")

    def test_isolation_broken(self):
        self._fails_unchanged(FakeRun(decrypt_with=("key", "devnull")), "contre-épreuve")

    def test_counter_test_refused_for_another_reason(self):
        self._fails_unchanged(FakeRun(refusal="Error: cannot read config"), "isolement n'est pas prouvé")

    def test_key_file_with_several_identities(self):
        fake = self._fails_unchanged(FakeRun(public=f"{SECOURS}\n{PERSO}"), "identités")
        self.assertEqual(len(fake.calls), 1, "pas de déchiffrement : perso ouvrirait à la place de secours")

    def test_missing_binary(self):
        def missing(cmd, **kwargs):
            raise FileNotFoundError(2, "No such file or directory", cmd[0])

        with Repo() as root:
            rc, lines = run_main(root, missing, root / "secours.key")
            self.assertEqual(rc, 1)
            self.assertTrue(all(line.startswith("ÉCHEC ") for line in lines), lines)
            self.assertEqual((root / secours.RUNBOOK).read_text(encoding="utf-8"), RUNBOOK)

    def test_runbook_without_the_line(self):
        with Repo() as root:
            (root / secours.RUNBOOK).write_text("---\nfoo: bar\n---\n", encoding="utf-8")
            rc, lines = run_main(root, FakeRun(), root / "secours.key")
            self.assertEqual(rc, 1)
            self.assertIn("à la main", lines[-1])

    def test_missing_keyfile(self):
        with Repo() as root:
            fake = FakeRun()
            rc, _ = run_main(root, fake, root / "absent.key")
            self.assertEqual((rc, fake.calls), (1, []))

    def test_refuses_a_mise_shim(self):
        with Repo() as root:
            fake = FakeRun()
            lines = []
            rc = secours.main(
                [str(root / "secours.key"), "--sops", "/home/x/.local/share/mise/shims/sops", "--age-keygen", "/a"],
                root=root,
                run=fake,
                out=lines.append,
            )
            self.assertEqual((rc, fake.calls), (1, []))
            self.assertIn("shim", lines[-1])


if __name__ == "__main__":
    unittest.main()
