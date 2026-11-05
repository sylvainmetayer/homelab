import os
import tempfile
import unittest
from pathlib import Path

import check_sops_shadowing as c


class ShadowingTest(unittest.TestCase):
    def run_in(self, files):
        """Run main() in a temp tree; the SOPS file is a fake with one key."""
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            for name, text in files.items():
                (root / name).parent.mkdir(parents=True, exist_ok=True)
                (root / name).write_text(text)
            (root / "s.yml").write_text("secret_key: x\nsops: {}\n")
            old_sops, cwd = c.SOPS_FILES, os.getcwd()
            c.SOPS_FILES = ["s.yml"]
            os.chdir(root)
            try:
                return c.main()
            finally:
                os.chdir(cwd)
                c.SOPS_FILES = old_sops

    def test_host_vars_collision(self):
        self.assertEqual(1, self.run_in({"ansible/host_vars/docker/variables.yaml": "secret_key: 1\n"}))

    def test_group_vars_collision(self):
        self.assertEqual(1, self.run_in({"ansible/group_vars/all/v.yml": "secret_key: 1\n"}))

    def test_reference_is_not_a_definition(self):
        text = "other: \"{{ secret_key | default('') }}\"\nlist: [\"{{ secret_key }}\"]\n"
        self.assertEqual(0, self.run_in({"ansible/host_vars/docker/variables.yaml": text}))

    def test_empty_vars_file(self):
        self.assertEqual(0, self.run_in({"ansible/group_vars/all/v.yml": ""}))


if __name__ == "__main__":
    unittest.main()
