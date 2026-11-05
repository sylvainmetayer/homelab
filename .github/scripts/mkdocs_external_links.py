"""Étape de mkdocs_build.py : un lien relatif qui sort de docs/
(README d'un rôle, AGENTS.md, un module tofu...) devient son URL GitHub.

Les fichiers Markdown gardent leurs liens relatifs, justes sur GitHub et dans
un éditeur ; seul le site les réécrit, faute de quoi `zensical build --strict`
échoue (cible absente des fichiers de la documentation) et le lien serait
mort sur docs.sylvain.cloud. Testé par test_mkdocs_external_links.py.
"""
import posixpath
import re

# [texte](cible) ou [texte](cible "titre") ; la cible s'arrête au premier
# blanc ou à la parenthèse fermante.
LINK_RE = re.compile(r"(\]\()([^)\s]+)")
# Définition d'un lien par référence, [id]: cible "titre" : Zensical la valide
# comme un lien en ligne.
REF_RE = re.compile(r"^( {0,3}\[[^\]]+\]:[ \t]*)(\S+)", re.MULTILINE)
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

    return REF_RE.sub(replace, LINK_RE.sub(replace, markdown))
