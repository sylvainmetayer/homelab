"""Tests of mkdocs_build.py, the docs site build (Lint workflow:
python -I -m unittest discover -s .github/scripts -p 'test_*.py')."""
import tempfile
import unittest
from pathlib import Path

import mkdocs_build
from mkdocs_build import blob_url, check_sources, check_targets

CONFIG = """extra:
  repo_blob_url: https://example.org/blob/main/
nav:
  - Accueil: index.md
  - Runbooks:
      - runbooks/a.md
"""


class Sources(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.docs = Path(tmp.name)
        (self.docs / "runbooks").mkdir()
        (self.docs / "index.md").write_text("[a](runbooks/a.md)\n", encoding="utf-8")
        (self.docs / "runbooks/a.md").write_text("texte\n", encoding="utf-8")

    def test_clean_sources(self):
        self.assertEqual(check_sources(CONFIG, self.docs), [])

    def test_page_missing_from_nav(self):
        (self.docs / "b.md").write_text("x\n", encoding="utf-8")
        self.assertEqual(check_sources(CONFIG, self.docs), ["b.md : absente de nav:"])

    def test_nav_entry_without_file(self):
        (self.docs / "runbooks/a.md").unlink()
        self.assertEqual(check_sources(CONFIG, self.docs), ["runbooks/a.md : dans nav:, fichier absent"])

    def test_absolute_link(self):
        (self.docs / "index.md").write_text("[x](/runbooks/a/)\n", encoding="utf-8")
        self.assertEqual(check_sources(CONFIG, self.docs), ["index.md : lien absolu /runbooks/a/"])

    def test_absolute_link_in_a_code_block_is_ignored(self):
        (self.docs / "index.md").write_text("```\n[x](/y)\n```\n", encoding="utf-8")
        self.assertEqual(check_sources(CONFIG, self.docs), [])

    def test_absolute_link_in_inline_code_or_long_fence_is_ignored(self):
        (self.docs / "index.md").write_text("`[x](/y)`\n````md\n```\n[x](/z)\n````\n", encoding="utf-8")
        self.assertEqual(check_sources(CONFIG, self.docs), [])

    def test_absolute_reference_link(self):
        (self.docs / "index.md").write_text("[r]\n\n[r]: /runbooks/a/\n", encoding="utf-8")
        self.assertEqual(check_sources(CONFIG, self.docs), ["index.md : lien absolu /runbooks/a/"])


class Targets(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.docs = Path(tmp.name)
        (self.docs / "img").mkdir()
        (self.docs / "img/a.png").write_bytes(b"")

    def page(self, text):
        (self.docs / "index.md").write_text(text, encoding="utf-8")
        return check_targets(self.docs)

    def test_existing_file_url_and_anchor_are_fine(self):
        self.assertEqual(self.page("![a](img/a.png) [b](https://x.org/y) [c](#c) [d](other.md#d)\n"), [])

    def test_missing_file(self):
        self.assertEqual(len(self.page("![a](img/b.png)\n")), 1)

    def test_folder_link(self):
        self.assertEqual(len(self.page("[a](img/)\n")), 1)


def write_bundle(site, major):
    bundles = Path(site, "assets/javascripts")
    bundles.mkdir(parents=True)
    (bundles / "bundle.min.js").write_text(f"unpkg.com/mermaid@{major}/dist", encoding="utf-8")


class Mermaid(unittest.TestCase):
    def test_a_bundle_on_another_major_stops_the_build(self):
        with tempfile.TemporaryDirectory() as tmp:
            write_bundle(tmp, "999")
            with self.assertRaisesRegex(mkdocs_build.BuildError, "n'attend plus Mermaid"):
                mkdocs_build.add_mermaid(Path(tmp))

    def test_a_site_without_diagram_stops_the_build(self):
        with tempfile.TemporaryDirectory() as tmp:
            write_bundle(tmp, mkdocs_build.MERMAID_VERSION.split(".")[0])
            Path(tmp, "index.html").write_text("<body></body>", encoding="utf-8")
            with self.assertRaises(mkdocs_build.BuildError):
                mkdocs_build.add_mermaid(Path(tmp))


class BlobUrl(unittest.TestCase):
    def test_trailing_slash_is_dropped(self):
        self.assertEqual(blob_url(CONFIG), "https://example.org/blob/main")


if __name__ == "__main__":
    unittest.main()
