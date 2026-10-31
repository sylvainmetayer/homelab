"""Hook MkDocs (mkdocs.yml, `hooks:`) : un lien relatif qui sort de docs/
(README d'un rôle, AGENTS.md, un module tofu...) devient son URL GitHub.

Les fichiers Markdown gardent leurs liens relatifs, justes sur GitHub et dans
un éditeur ; seul le site les réécrit, faute de quoi `mkdocs build --strict`
échoue (cible absente des fichiers de la documentation) et le lien serait
mort sur docs.sylvain.cloud. Testé par test_mkdocs_external_links.py.
"""
import posixpath
import re
from pathlib import Path

# [texte](cible) ou [texte](cible "titre") ; la cible s'arrête au premier
# blanc ou à la parenthèse fermante.
LINK_RE = re.compile(r"(\]\()([^)\s]+)")
SCHEME_RE = re.compile(r"^[a-zA-Z][a-zA-Z0-9+.-]*:")


def rewrite(markdown, src_uri, docs_prefix, repo_blob_url):
    """Réécrit les liens de `markdown` (page `src_uri`, relative à docs/) qui
    sortent de docs/. `docs_prefix` : docs/ vu de la racine du dépôt
    ("docs") ; `repo_blob_url` : https://github.com/<dépôt>/blob/main."""
    page_dir = posixpath.dirname(src_uri)

    def replace(match):
        target = match.group(2)
        if target.startswith(("#", "/")) or SCHEME_RE.match(target):
            return match.group(0)
        path, sep, anchor = target.partition("#")
        resolved = posixpath.normpath(posixpath.join(page_dir, path))
        if resolved != ".." and not resolved.startswith("../"):
            return match.group(0)
        in_repo = posixpath.normpath(posixpath.join(docs_prefix, resolved))
        if in_repo == ".." or in_repo.startswith("../"):
            return match.group(0)
        return f"{match.group(1)}{repo_blob_url}/{in_repo}{sep}{anchor}"

    return LINK_RE.sub(replace, markdown)


def on_page_markdown(markdown, page, config, files, **kwargs):
    root = Path(config.config_file_path).resolve().parent
    docs_prefix = Path(config.docs_dir).resolve().relative_to(root).as_posix()
    blob_url = f"{config.repo_url.rstrip('/')}/blob/main"
    return rewrite(markdown, page.file.src_uri, docs_prefix, blob_url)
