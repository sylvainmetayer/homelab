"""Tests of check_age_recipients.py: the age recipients of each SOPS file
against .sops.yaml (Lint workflow: python -I -m unittest discover -s
.github/scripts -p 'test_*.py')."""

import io
import tempfile
import unittest
from contextlib import redirect_stdout
from pathlib import Path

import check_age_recipients as recipients

# Post-quantum recipients (age-keygen -pq): same length as real ones.
PERSO = "age1pq1" + "p" * 1952
PRO = "age1pq1" + "r" * 1952
CI = "age1pq1" + "c" * 1952
SECOURS = "age1pq1" + "s" * 1952
PQ = "age1pq1" + "q" * 1952
# An X25519 recipient (plain age-keygen), refused in a rule.
OLD = "age1" + "q" * 58

CONFIG = f"""\
# Une règle par fichier, la plus précise en premier.
creation_rules:
  - path_regex: (^|/)ansible/secrets\\.sops\\.yaml$
    key_groups:
      - age:
          - {PERSO} # perso
          - {PRO} # pro
          - {CI} # github-actions
          - {SECOURS} # secours
  - path_regex: (^|/)secrets\\.sops\\.yaml$
    key_groups:
      - age:
          - {PERSO} # perso
          - {PRO} # pro
          - {SECOURS} # secours
"""


def encrypted(*keys):
    """A SOPS file as sops writes it, with one age stanza per recipient."""
    stanzas = "".join(
        "        - enc: |\n"
        "            -----BEGIN AGE ENCRYPTED FILE-----\n"
        "            YWdlLWVuY3J5cHRpb24ub3JnL3YxCg==\n"
        "            -----END AGE ENCRYPTED FILE-----\n"
        f"          recipient: {key}\n"
        for key in keys
    )
    return (
        "HCLOUD_TOKEN: ENC[AES256_GCM,data:xx,iv:xx,tag:xx,type:str]\n"
        "sops:\n"
        f"    age:\n{stanzas}"
        '    lastmodified: "2026-10-28T00:00:00Z"\n'
        "    version: 3.13.3\n"
    )


ROOT_OK = encrypted(PERSO, PRO, SECOURS)
ANSIBLE_OK = encrypted(PERSO, PRO, CI, SECOURS)


class ParseRulesTest(unittest.TestCase):
    def test_reads_each_rule_in_order_with_its_labels(self):
        rules = recipients.parse_rules(CONFIG)
        self.assertEqual([p.pattern for p, _ in rules], [r"(^|/)ansible/secrets\.sops\.yaml$", r"(^|/)secrets\.sops\.yaml$"])
        self.assertEqual(rules[0][1], {PERSO: "perso", PRO: "pro", CI: "github-actions", SECOURS: "secours"})
        self.assertEqual(rules[1][1], {PERSO: "perso", PRO: "pro", SECOURS: "secours"})

    def test_quoted_regex_and_unlabelled_key(self):
        # Single quotes: in double quotes, YAML (and sops) reject `\.`.
        rules = recipients.parse_rules(f"creation_rules:\n  - path_regex: 'x\\.yaml$'\n    age: {PERSO}\n")
        self.assertEqual(rules[0][0].pattern, r"x\.yaml$")
        self.assertEqual(rules[0][1], {PERSO: PERSO})

    def test_commented_out_key_is_not_a_recipient(self):
        rules = recipients.parse_rules(CONFIG.replace(f"- {PRO} # pro", f"# - {PRO} # pro", 1))
        self.assertNotIn(PRO, rules[0][1])

    def test_post_quantum_key_is_read(self):
        rules = recipients.parse_rules(CONFIG.replace(f"{SECOURS} # secours", f"{PQ} # secours"))
        self.assertEqual(rules[0][1][PQ], "secours")
        self.assertEqual(recipients.check(rules, {"secrets.sops.yaml": encrypted(PERSO, PRO, PQ)}), [])

    def test_x25519_key_is_still_read(self):
        rules = recipients.parse_rules(CONFIG.replace(f"{PRO} # pro", f"{OLD} # pro"))
        self.assertEqual(rules[0][1][OLD], "pro")

    def test_several_keys_on_one_line(self):
        rules = recipients.parse_rules(f"creation_rules:\n  - path_regex: x$\n    age: {PERSO},{PRO} # perso\n")
        self.assertEqual(rules[0][1], {PERSO: PERSO, PRO: PRO})

    def test_rule_without_path_regex_is_an_error(self):
        # sops would apply a catch-all rule to every file left over.
        with self.assertRaises(recipients.ConfigError):
            recipients.parse_rules(CONFIG + f"  - age: {OLD}\n")

    def test_other_top_level_lists_are_ignored(self):
        rules = recipients.parse_rules(CONFIG + f"destination_rules:\n  - s3_bucket: b\n    age: {OLD}\n")
        self.assertNotIn(OLD, rules[-1][1])

    def test_no_rule_is_an_error(self):
        with self.assertRaises(recipients.ConfigError):
            recipients.parse_rules("creation_rules: []\n")

    def test_key_before_any_rule_is_an_error(self):
        with self.assertRaises(recipients.ConfigError):
            recipients.parse_rules(f"keys:\n  - {PERSO}\n")

    def test_invalid_yaml_or_regex_is_an_error(self):
        for text in ("creation_rules: [\n", "creation_rules:\n  - path_regex: '('\n"):
            with self.subTest(text=text), self.assertRaises(recipients.ConfigError):
                recipients.parse_rules(text)


class FileRecipientsTest(unittest.TestCase):
    def test_reads_the_sops_metadata_only(self):
        text = f"note: {OLD}\n" + ROOT_OK
        self.assertEqual(recipients.file_recipients(text), [PERSO, PRO, SECOURS])

    def test_unencrypted_file_has_none(self):
        self.assertEqual(recipients.file_recipients("a: b\n"), [])

    def test_reads_every_key_group(self):
        # With several key groups (shamir), sops writes sops.key_groups.
        text = (
            "sops:\n  key_groups:\n"
            f"    - age:\n        - recipient: {PERSO}\n          enc: x\n"
            f"    - age:\n        - recipient: {SECOURS}\n          enc: y\n"
        )
        self.assertEqual(recipients.file_recipients(text), [PERSO, SECOURS])

    def test_invalid_yaml_is_reported_as_such(self):
        errors = recipients.check(recipients.parse_rules(CONFIG), {"secrets.sops.yaml": "<<<<<<< HEAD\na: [\n"})
        self.assertEqual(len(errors), 1)
        self.assertIn("YAML invalide", errors[0])


class CheckTest(unittest.TestCase):
    def setUp(self):
        self.rules = recipients.parse_rules(CONFIG)

    def test_matching_files_pass(self):
        files = {"secrets.sops.yaml": ROOT_OK, "ansible/secrets.sops.yaml": ANSIBLE_OK}
        self.assertEqual(recipients.check(self.rules, files), [])

    def test_order_of_stanzas_does_not_matter(self):
        self.assertEqual(recipients.check(self.rules, {"secrets.sops.yaml": encrypted(SECOURS, PERSO, PRO)}), [])

    def test_file_reencrypted_without_secours_is_caught(self):
        errors = recipients.check(self.rules, {"ansible/secrets.sops.yaml": encrypted(PERSO, PRO, CI)})
        self.assertEqual(len(errors), 1)
        self.assertIn("n'est pas chiffré pour secours", errors[0])
        self.assertIn("sops updatekeys ansible/secrets.sops.yaml", errors[0])

    def test_first_matching_rule_wins(self):
        # The root rule also matches ansible/secrets.sops.yaml: without the CI
        # key, the ansible file must still fail on the first (ansible) rule.
        errors = recipients.check(self.rules, {"ansible/secrets.sops.yaml": ROOT_OK})
        self.assertEqual(len(errors), 1)
        self.assertIn("github-actions", errors[0])

    def test_extra_recipient_is_caught(self):
        errors = recipients.check(self.rules, {"secrets.sops.yaml": encrypted(PERSO, PRO, SECOURS, CI)})
        self.assertEqual(len(errors), 1)
        self.assertIn(f"chiffré pour {CI}", errors[0])
        self.assertIn("sops rotate -i secrets.sops.yaml", errors[0])

    def test_duplicate_recipient_is_caught(self):
        errors = recipients.check(self.rules, {"secrets.sops.yaml": encrypted(PERSO, PRO, SECOURS, SECOURS)})
        self.assertEqual(errors, [f"secrets.sops.yaml : destinataire(s) en double : {SECOURS}"])

    def test_unencrypted_file_is_caught(self):
        errors = recipients.check(self.rules, {"secrets.sops.yaml": "a: b\n"})
        self.assertIn("aucun destinataire age", errors[0])

    def test_file_no_rule_designates(self):
        rules = recipients.parse_rules(CONFIG.replace(r"(^|/)secrets\.sops\.yaml$", r"^secrets\.sops\.yaml$"))
        errors = recipients.check(rules, {"compose/secrets.sops.yaml": ROOT_OK})
        self.assertEqual(errors, [f"compose/secrets.sops.yaml : aucune règle de {recipients.SOPS_CONFIG} ne le désigne"])

    def test_rule_without_secours_is_caught_even_if_files_follow_it(self):
        # secours removed from .sops.yaml, then sops updatekeys: the files
        # match their rule, the rule itself fails.
        rules = recipients.parse_rules(CONFIG.replace(f"          - {SECOURS} # secours\n", "", 1))
        errors = recipients.check(rules, {"ansible/secrets.sops.yaml": encrypted(PERSO, PRO, CI)})
        self.assertEqual(len(errors), 1)
        self.assertIn("ne compte pas la clé secours", errors[0])


    def test_x25519_recipient_in_a_rule_is_caught(self):
        # One X25519 recipient is enough to expose the data key.
        rules = recipients.parse_rules(CONFIG.replace(f"{PRO} # pro", f"{OLD} # pro", 1))
        errors = recipients.check(rules, {"ansible/secrets.sops.yaml": encrypted(PERSO, OLD, CI, SECOURS)})
        self.assertEqual(len(errors), 1)
        self.assertIn("compte pro, clé X25519", errors[0])


class MainTest(unittest.TestCase):
    def run_main(self, files, config=CONFIG):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / recipients.SOPS_CONFIG).write_text(config, encoding="utf-8")
            for path, text in files.items():
                (root / path).parent.mkdir(parents=True, exist_ok=True)
                (root / path).write_text(text, encoding="utf-8")
            out = io.StringIO()
            with redirect_stdout(out):
                code = recipients.main(root)
            return code, out.getvalue()

    def test_repository_layout_passes(self):
        code, out = self.run_main({"secrets.sops.yaml": ROOT_OK, "ansible/secrets.sops.yaml": ANSIBLE_OK})
        self.assertEqual(code, 0, out)
        self.assertIn("2 fichier(s)", out)

    def test_failure_is_annotated(self):
        code, out = self.run_main({"secrets.sops.yaml": encrypted(PERSO, PRO)})
        self.assertEqual(code, 1)
        self.assertIn("::error::secrets.sops.yaml : n'est pas chiffré pour secours", out)

    def test_dot_dirs_are_skipped(self):
        # .claude/worktrees/… holds other checkouts: never theirs to check.
        code, out = self.run_main({"secrets.sops.yaml": ROOT_OK, ".claude/worktrees/x/secrets.sops.yaml": "a: b\n"})
        self.assertEqual(code, 0, out)

    def test_no_sops_file_fails(self):
        code, out = self.run_main({})
        self.assertEqual(code, 1)
        self.assertIn("aucun secrets.sops.yaml", out)

    def test_missing_config_fails(self):
        with tempfile.TemporaryDirectory() as directory, redirect_stdout(io.StringIO()):
            self.assertEqual(recipients.main(Path(directory)), 1)

    def test_this_repository_passes(self):
        out = io.StringIO()
        with redirect_stdout(out):
            self.assertEqual(recipients.main(), 0, out.getvalue())


if __name__ == "__main__":
    unittest.main()
