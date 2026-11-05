#!/usr/bin/env python3
"""Construit docs.sylvain.cloud avec Zensical (rôle docs_site, workflow Lint).

Zensical ne prend pas les hooks de MkDocs : les liens hors de docs/ sont donc
réécrits sur une copie de docs/ avant le build (les sources restent justes sur
GitHub), et Mermaid est déposé dans le site après.
"""
import argparse
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

from mkdocs_external_links import rewrite
from mkdocs_mermaid import SITE_PATH, MermaidError, add_script, load_mermaid


class BuildError(Exception):
    """Arrête le build avec la liste de ce qui est à corriger."""


FENCE_RE = re.compile(r"^ *```.*?^ *```", re.MULTILINE | re.DOTALL)
ABSOLUTE_LINK_RE = re.compile(r"\]\((/[^)\s]*)")


def blob_url(config_text):
    return re.search(r"^\s*repo_blob_url:\s*(\S+)", config_text, re.MULTILINE).group(1).rstrip("/")


def check_sources(config_text, docs):
    """Ce que MkDocs refusait en strict et que Zensical 0.0.x laisse passer :
    page absente de nav:, entrée de nav: sans fichier, lien absolu."""
    nav = set(re.findall(r"^\s*-\s*(?:[^\n]*?:\s+)?(\S+\.md)\s*$", config_text.partition("\nnav:")[2], re.MULTILINE))
    pages = {page.relative_to(docs).as_posix() for page in docs.rglob("*.md")}
    problems = [f"{page} : absente de nav:" for page in sorted(pages - nav)]
    problems += [f"{page} : dans nav:, fichier absent" for page in sorted(nav - pages)]
    for page in sorted(pages):
        text = FENCE_RE.sub("", (docs / page).read_text(encoding="utf-8"))
        problems += [f"{page} : lien absolu {target}" for target in ABSOLUTE_LINK_RE.findall(text)]
    return problems


def prepare(config, work):
    """Copie mkdocs.yml et docs/ dans `work`, liens hors de docs/ réécrits."""
    text = config.read_text(encoding="utf-8")
    (work / "mkdocs.yml").write_text(text, encoding="utf-8")
    docs = work / "docs"
    shutil.copytree(config.parent / "docs", docs)
    problems = check_sources(text, docs)
    if problems:
        raise BuildError("\n".join(problems))
    url = blob_url(text)
    for page in docs.rglob("*.md"):
        uri = page.relative_to(docs).as_posix()
        page.write_text(rewrite(page.read_text(encoding="utf-8"), uri, "docs", url), encoding="utf-8")


def add_mermaid(site):
    """Ajoute le script aux seules pages à diagramme, et le dépose s'il sert."""
    used = False
    for page in site.rglob("*.html"):
        html = page.read_text(encoding="utf-8")
        url = page.parent.relative_to(site).as_posix()
        out = add_script(html, "" if url == "." else f"{url}/")
        if out != html:
            page.write_text(out, encoding="utf-8")
            used = True
    if not used:
        raise BuildError(f"aucune page à diagramme dans {site} : le rendu de Zensical a changé ?")
    dest = site / SITE_PATH
    dest.parent.mkdir(parents=True, exist_ok=True)
    dest.write_bytes(load_mermaid())


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config-file", type=Path, default=Path("mkdocs.yml"))
    parser.add_argument("--site-dir", type=Path, required=True)
    args = parser.parse_args()
    target = args.site_dir.resolve()
    with tempfile.TemporaryDirectory(suffix=".docs_build") as tmp:
        work = Path(tmp)
        prepare(args.config_file.resolve(), work)
        subprocess.run(
            [sys.executable, "-m", "zensical", "build", "--strict", "--clean", "--config-file", str(work / "mkdocs.yml")],
            cwd=work, check=True,
        )
        add_mermaid(work / "site")
        if target.exists():
            shutil.rmtree(target)
        shutil.move(str(work / "site"), target)


if __name__ == "__main__":
    try:
        main()
    except (BuildError, MermaidError, subprocess.CalledProcessError) as error:
        sys.exit(f"mkdocs_build : {error}")
