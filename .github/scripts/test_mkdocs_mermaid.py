"""Tests of mkdocs_mermaid.py, a build step of mkdocs_build.py (Lint
workflow: python -I -m unittest discover -s .github/scripts -p 'test_*.py')."""
import re
import unittest

import mkdocs_mermaid
from mkdocs_mermaid import add_script, check_pin

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


class Pin(unittest.TestCase):
    def test_sha256_is_the_one_of_the_pinned_version(self):
        # Échoue sur une PR Renovate qui monte MERMAID_VERSION : son sha256
        # se recalcule à la main (docstring de mkdocs_mermaid.py) ; le
        # mkdocs_mermaid.MermaidError de check_pin() dit quoi faire.
        check_pin()
        self.assertRegex(mkdocs_mermaid.MERMAID_SHA256, re.compile(r"^[0-9a-f]{64}$"))

    def test_a_version_bumped_alone_stops_the_build(self):
        saved = mkdocs_mermaid.MERMAID_VERSION
        mkdocs_mermaid.MERMAID_VERSION = "99.0.0"
        try:
            with self.assertRaisesRegex(mkdocs_mermaid.MermaidError, "MERMAID_SHA256 est celui de"):
                check_pin()
        finally:
            mkdocs_mermaid.MERMAID_VERSION = saved


if __name__ == "__main__":
    unittest.main()
