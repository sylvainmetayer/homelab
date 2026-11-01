"""Tests of mkdocs_mermaid.py, the MkDocs hook of mkdocs.yml (Lint
workflow: python -I -m unittest discover -s .github/scripts -p 'test_*.py')."""
import unittest

from mkdocs_mermaid import add_script

PAGE = '<pre class="mermaid"><code>flowchart LR</code></pre><script src="b.js"></script></body></html>'


class AddScript(unittest.TestCase):
    def test_page_with_a_diagram_loads_the_script_after_the_bundle(self):
        self.assertEqual(
            add_script(PAGE, "architecture/"),
            '<pre class="mermaid"><code>flowchart LR</code></pre><script src="b.js"></script>'
            '<script src="../javascripts/mermaid.min.js"></script></body></html>',
        )

    def test_home_page_path(self):
        self.assertIn('<script src="javascripts/mermaid.min.js">', add_script(PAGE, ""))

    def test_page_without_a_diagram_is_left_alone(self):
        html = "<pre><code>flowchart LR</code></pre></body></html>"
        self.assertEqual(add_script(html, "runbooks/crowdsec/"), html)


if __name__ == "__main__":
    unittest.main()
