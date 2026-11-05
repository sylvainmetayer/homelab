"""Tests of mkdocs_build.py, the docs site build (Lint workflow:
python -I -m unittest discover -s .github/scripts -p 'test_*.py')."""
import tempfile
import unittest
from pathlib import Path

import mkdocs_build
from mkdocs_build import blob_url, check_sources

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


class Mermaid(unittest.TestCase):
    def test_a_site_without_diagram_stops_the_build(self):
        with tempfile.TemporaryDirectory() as tmp:
            Path(tmp, "index.html").write_text("<body></body>", encoding="utf-8")
            with self.assertRaises(mkdocs_build.BuildError):
                mkdocs_build.add_mermaid(Path(tmp))


class BlobUrl(unittest.TestCase):
    def test_trailing_slash_is_dropped(self):
        self.assertEqual(blob_url(CONFIG), "https://example.org/blob/main")


if __name__ == "__main__":
    unittest.main()
