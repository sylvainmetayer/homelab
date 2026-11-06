"""Étape de mkdocs_build.py : dépose mermaid.min.js dans le site construit.

Sans script Mermaid chargé par la page, Zensical va chercher
https://unpkg.com/mermaid@12 depuis le navigateur ; le site doit se suffire
derrière le SSO (pas de tiers au chargement, comme `font: false`). Ce module
télécharge une version épinglée à la construction, vérifie son sha256 et
l'écrit sous javascripts/ du site ; seules les pages qui ont un diagramme la
chargent (plusieurs Mo à analyser, inutiles ailleurs), et Zensical utilise le
`mermaid` global au lieu du CDN. Testé par test_mkdocs_mermaid.py.

Version : la majeure qu'attend Zensical (bundle : unpkg.com/mermaid@12).
Renovate suit MERMAID_VERSION (customManagers de renovate.json, datasource
npm) mais ne sait pas recalculer le sha256 : sa PR change la version seule,
et test_mkdocs_mermaid.py comme le build échouent tant que MERMAID_SHA256 et
MERMAID_SHA256_OF n'ont pas été mis à jour à la main sur la branche :
  curl -sL <URL> | sha256sum
"""
import hashlib
import http.client
import os
import posixpath
import urllib.request
from pathlib import Path


class MermaidError(Exception):
    """Arrête le build avec un message qui dit quoi faire."""


MERMAID_VERSION = "12.3.0"
MERMAID_SHA256 = "336df803d87a38b70a01e736e666c8f7601d2ce42f5e47c8fafe5d721074b9a3"
# La version dont MERMAID_SHA256 est l'empreinte : Renovate ne touche que
# MERMAID_VERSION, l'écart dit que le sha256 reste à recalculer.
MERMAID_SHA256_OF = "12.3.0"
MERMAID_URL = f"https://cdn.jsdelivr.net/npm/mermaid@{MERMAID_VERSION}/dist/mermaid.min.js"
# Chemin dans le site.
SITE_PATH = "javascripts/mermaid.min.js"
# Ce que pymdownx.superfences (custom_fences de mkdocs.yml) fait d'un bloc
# ```mermaid.
MERMAID_BLOCK = '<pre class="mermaid">'


def _cache_file():
    # Version et sha256 dans le nom : une version montée sans son sha256 ne
    # retombe pas sur le fichier de l'ancienne, qui passerait la vérification.
    base = os.environ.get("XDG_CACHE_HOME") or Path.home() / ".cache"
    return Path(base) / "homelab-mkdocs" / f"mermaid-{MERMAID_VERSION}-{MERMAID_SHA256}.min.js"


def check_pin():
    """Arrête le build quand la version a changé sans son sha256 (PR
    Renovate) : un message qui dit quoi faire, pas un « sha256 inattendu »."""
    if MERMAID_SHA256_OF != MERMAID_VERSION:
        raise MermaidError(
            f"mermaid {MERMAID_VERSION} : MERMAID_SHA256 est celui de {MERMAID_SHA256_OF} ; "
            f"mettre MERMAID_SHA256 (curl -sL {MERMAID_URL} | sha256sum) "
            f"et MERMAID_SHA256_OF = \"{MERMAID_VERSION}\" dans .github/scripts/mkdocs_mermaid.py"
        )


def _sha256_ok(data):
    return hashlib.sha256(data).hexdigest() == MERMAID_SHA256


def load_mermaid():
    """Le script épinglé, du cache ou téléchargé ; un contenu au mauvais sha256 arrête le
    build."""
    check_pin()
    cache = _cache_file()
    if cache.is_file():
        data = cache.read_bytes()
        if _sha256_ok(data):
            return data
    try:
        with urllib.request.urlopen(MERMAID_URL, timeout=60) as response:
            data = response.read()
    except (OSError, http.client.HTTPException) as error:
        raise MermaidError(f"mermaid {MERMAID_VERSION} : téléchargement impossible ({error})") from error
    if not _sha256_ok(data):
        raise MermaidError(f"mermaid {MERMAID_VERSION} : sha256 inattendu pour {MERMAID_URL}")
    try:
        cache.parent.mkdir(parents=True, exist_ok=True)
        cache.write_bytes(data)
    except OSError:
        pass  # Cache facultatif : le prochain build retélécharge.
    return data


def add_script(html, page_url):
    """La balise du script, avant </body>, après le bundle de Zensical
    (comme `extra_javascript`) ; une page sans diagramme reste telle quelle."""
    if MERMAID_BLOCK not in html:
        return html
    head, sep, tail = html.rpartition("</body>")
    if not sep:
        return html
    src = posixpath.relpath(SITE_PATH, page_url or ".")
    return f'{head}<script src="{src}"></script>{sep}{tail}'
