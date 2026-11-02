"""Hook MkDocs (mkdocs.yml, `hooks:`) : dépose mermaid.min.js dans le site.

Sans script Mermaid chargé par la page, Material va chercher
https://unpkg.com/mermaid@11 depuis le navigateur ; le site doit se suffire
derrière le SSO (pas de tiers au chargement, comme `font: false`). Ce hook
télécharge une version épinglée à la construction, vérifie son sha256 et
l'écrit sous javascripts/ du site ; seules les pages qui ont un diagramme la
chargent (3,5 Mo à analyser, inutiles ailleurs), et Material utilise le `mermaid`
global au lieu du CDN. Testé par test_mkdocs_mermaid.py.

Version : la majeure qu'attend Material (bundle : unpkg.com/mermaid@11).
Renovate suit MERMAID_VERSION (customManagers de renovate.json, datasource
npm) mais ne sait pas recalculer le sha256 : sa PR change la version seule,
et test_mkdocs_mermaid.py comme le build échouent tant que MERMAID_SHA256 et
MERMAID_SHA256_OF n'ont pas été mis à jour à la main sur la branche :
  curl -sL <URL> | sha256sum
"""
import hashlib
import http.client
import os
import urllib.request
from pathlib import Path

from mkdocs.exceptions import PluginError
from mkdocs.utils import get_relative_url

MERMAID_VERSION = "11.17.2"
MERMAID_SHA256 = "581ed7d74bd9048d0e3a91363927d72ef22942d7722546b27f7cc29e35390eb8"
# La version dont MERMAID_SHA256 est l'empreinte : Renovate ne touche que
# MERMAID_VERSION, l'écart dit que le sha256 reste à recalculer.
MERMAID_SHA256_OF = "11.17.2"
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
        raise PluginError(
            f"mermaid {MERMAID_VERSION} : MERMAID_SHA256 est celui de {MERMAID_SHA256_OF} ; "
            f"mettre MERMAID_SHA256 (curl -sL {MERMAID_URL} | sha256sum) "
            f"et MERMAID_SHA256_OF = \"{MERMAID_VERSION}\" dans .github/scripts/mkdocs_mermaid.py"
        )


def _sha256_ok(data):
    return hashlib.sha256(data).hexdigest() == MERMAID_SHA256


def load_mermaid():
    """Le script épinglé, du cache (`mkdocs serve` reconstruit à chaque
    modification) ou téléchargé ; un contenu au mauvais sha256 arrête le
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
        raise PluginError(f"mermaid {MERMAID_VERSION} : téléchargement impossible ({error})") from error
    if not _sha256_ok(data):
        raise PluginError(f"mermaid {MERMAID_VERSION} : sha256 inattendu pour {MERMAID_URL}")
    try:
        cache.parent.mkdir(parents=True, exist_ok=True)
        cache.write_bytes(data)
    except OSError:
        pass  # Cache facultatif : le prochain build retélécharge.
    return data


def add_script(html, page_url):
    """La balise du script, avant </body>, après le bundle de Material
    (comme `extra_javascript`) ; une page sans diagramme reste telle quelle."""
    if MERMAID_BLOCK not in html:
        return html
    head, sep, tail = html.rpartition("</body>")
    if not sep:
        return html
    src = get_relative_url(SITE_PATH, page_url)
    return f'{head}<script src="{src}"></script>{sep}{tail}'


def on_post_page(output, page, config, **kwargs):
    return add_script(output, page.url)


def on_post_build(config, **kwargs):
    dest = Path(config.site_dir) / SITE_PATH
    dest.parent.mkdir(parents=True, exist_ok=True)
    dest.write_bytes(load_mermaid())
