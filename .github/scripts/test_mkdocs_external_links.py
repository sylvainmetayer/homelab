"""Tests of mkdocs_external_links.py, the MkDocs hook of mkdocs.yml (Lint
workflow: python -I -m unittest discover -s .github/scripts -p 'test_*.py')."""
import unittest

from mkdocs_external_links import rewrite

BLOB = "https://github.com/sylvainmetayer/homelab/blob/main"


def run(markdown, page="runbooks/crowdsec.md"):
    return rewrite(markdown, page, "docs", BLOB)


class Rewrite(unittest.TestCase):
    def test_link_out_of_docs_becomes_its_github_url(self):
        self.assertEqual(
            run("voir [le rôle](../../ansible/roles/borgmatic/README.md)."),
            f"voir [le rôle]({BLOB}/ansible/roles/borgmatic/README.md).",
        )

    def test_top_level_page(self):
        self.assertEqual(run("[AGENTS.md](../AGENTS.md)", page="architecture.md"),
                         f"[AGENTS.md]({BLOB}/AGENTS.md)")

    def test_anchor_and_title_are_kept(self):
        self.assertEqual(
            run('[x](../../tofu/pangolin_config/README.md#rules "Règles")'),
            f'[x]({BLOB}/tofu/pangolin_config/README.md#rules "Règles")',
        )

    def test_links_inside_docs_are_left_to_mkdocs(self):
        for link in ("[a](../architecture.md)", "[b](appli-en-panne.md#diagnostic)",
                     "[c](../adr/README.md)", "[d](./dns-blocky.md)"):
            self.assertEqual(run(link), link)

    def test_absolute_urls_anchors_and_mail_are_left_alone(self):
        for link in ("[a](https://example.org/../x)", "[b](#symptome)",
                     "[c](mailto:x@example.org)", "[d](/runbooks/)"):
            self.assertEqual(run(link), link)

    def test_link_out_of_the_repository_is_left_alone(self):
        link = "[x](../../../ailleurs.md)"
        self.assertEqual(run(link), link)

    def test_reference_definition_out_of_docs(self):
        self.assertEqual(
            run('Voir [le rôle][r].\n\n[r]: ../../AGENTS.md#rules "Règles"\n[s]: ../architecture.md\n'),
            f'Voir [le rôle][r].\n\n[r]: {BLOB}/AGENTS.md#rules "Règles"\n[s]: ../architecture.md\n',
        )

    def test_several_links_on_one_line(self):
        self.assertEqual(
            run("[a](../../AGENTS.md) et [b](../architecture.md)"),
            f"[a]({BLOB}/AGENTS.md) et [b](../architecture.md)",
        )


if __name__ == "__main__":
    unittest.main()
