"""Tests of check_immich_versions.py: immich-server and
immich-machine-learning at the same version (Lint workflow: python -I -m
unittest discover -s .github/scripts -p 'test_*.py')."""

import tempfile
import unittest
from pathlib import Path

import check_immich_versions as immich

SERVER = "ghcr.io/immich-app/immich-server"
ML = "ghcr.io/immich-app/immich-machine-learning"
DIGEST = "@sha256:" + "0" * 64


def compose(server_tag, ml_tag, ml_quote=""):
    return (
        "services:\n"
        "  immich-server:\n"
        f"    image: {SERVER}:{server_tag}{DIGEST}\n"
        "  immich-machine-learning:\n"
        "    # Example tag: ${IMMICH_VERSION:-release}-cuda\n"
        f"    image: {ml_quote}{ML}:{ml_tag}{DIGEST}{ml_quote}\n"
        "  database:\n"
        "    image: ghcr.io/immich-app/postgres:14-vectorchord0.4.3" + DIGEST + "\n"
    )


class CheckImmichVersionsTest(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.root = Path(self._tmp.name)

    def tearDown(self):
        self._tmp.cleanup()

    def write(self, relative, text):
        path = self.root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")

    def errors(self):
        return immich.check(immich.find_images(self.root))

    def test_aligned_versions_pass(self):
        self.write("ansible/roles/immich/templates/compose.yaml", compose("v3.3.5", "v3.3.5"))
        self.write("compose/immich/compose.yaml", compose("v3.3.5", "v3.3.5", ml_quote='"'))
        self.assertEqual(self.errors(), [])
        self.assertEqual(len(immich.find_images(self.root)), 4)

    def test_server_bumped_alone_fails(self):
        # Le cas de #753 : le serveur monté, le machine learning resté derrière.
        self.write("ansible/roles/immich/templates/compose.yaml", compose("v3.3.3", "v3.3.1"))
        errors = self.errors()
        self.assertTrue(errors)
        self.assertIn("v3.3.1, v3.3.3", errors[0])
        self.assertTrue(any("immich-machine-learning:v3.3.1" in e for e in errors))

    def test_files_disagree_fails(self):
        self.write("ansible/roles/immich/templates/compose.yaml", compose("v3.3.5", "v3.3.5"))
        self.write("compose/immich/compose.yaml", compose("v3.3.4", "v3.3.4"))
        self.assertTrue(self.errors())

    def test_hardware_suffix_is_ignored(self):
        self.write("compose/immich/compose.yaml", compose("v3.3.5", "v3.3.5-openvino"))
        self.assertEqual(self.errors(), [])

    def test_prerelease_suffix_is_compared(self):
        self.write("compose/immich/compose.yaml", compose("v3.4.0-rc.1", "v3.4.0"))
        self.assertTrue(self.errors())

    def test_untagged_reference_fails(self):
        self.write("ansible/roles/immich/templates/compose.yaml", compose("v3.3.5", "v3.3.5"))
        self.write(
            "compose/immich/compose.yaml",
            f"services:\n  ml:\n    image: {ML}{DIGEST}\n",
        )
        errors = self.errors()
        self.assertEqual(len(errors), 1)
        self.assertIn("compose/immich/compose.yaml", errors[0])

    def test_missing_image_fails(self):
        self.write(
            "ansible/roles/immich/templates/compose.yaml",
            f"services:\n  s:\n    image: {SERVER}:v3.3.5{DIGEST}\n",
        )
        errors = self.errors()
        self.assertEqual(len(errors), 1)
        self.assertIn("immich-machine-learning", errors[0])

    def test_comments_and_other_files_are_ignored(self):
        self.write(
            "ansible/roles/immich/templates/compose.yaml",
            compose("v3.3.5", "v3.3.5") + f"#    image: {ML}:v1.0.0\n",
        )
        self.write("compose/immich/README.md", f"image: {ML}:v1.0.0\n")
        self.write("docs/old.yaml", f"image: {ML}:v1.0.0\n")
        self.assertEqual(self.errors(), [])


if __name__ == "__main__":
    unittest.main()
