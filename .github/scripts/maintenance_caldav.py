#!/usr/bin/env python3
"""Dépose le calendrier de maintenance (maintenance_ics.py) dans un calendrier CalDAV.

Un objet par événement, nommé d'après son UID (`<uid>.ics`, UID stable) : un
nouveau passage remplace l'objet au lieu d'en ajouter un. Les objets du
calendrier dont le nom porte le suffixe de ces UID (`@homelab.sylvain.dev.ics`)
et que le dépôt ne génère plus sont supprimés ; tout autre objet (un événement
ajouté à la main dans ce calendrier) est laissé tel quel. Le calendrier est
créé (MKCALENDAR) s'il n'existe pas.

Cible : le calendrier Nextcloud `maintenance-homelab` de sylvain, joint par
/remote.php/* (ACCEPT de chemin sans SSO, tofu/pangolin_config) avec un mot de
passe d'application (token_auth_enforced). Environnement :
CALDAV_URL (URL de la collection, https), CALDAV_USER, CALDAV_PASSWORD.
Le mot de passe n'est jamais affiché : une erreur cite la méthode, l'objet et
le code HTTP.

Bibliothèque standard seulement, lancé avec `python -I` : maintenance_ics est
chargé par son chemin.

Usage (depuis la racine du dépôt) : maintenance_caldav.py [--dry-run]
"""

import argparse
import base64
import http.client
import importlib.util
import os
import sys
import urllib.error
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET
from pathlib import Path


def load_sibling(name):
    """Un script voisin, chargé par son chemin (sans sys.path)."""
    if name in sys.modules:
        return sys.modules[name]
    spec = importlib.util.spec_from_file_location(name, Path(__file__).with_name(f"{name}.py"))
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


ics = load_sibling("maintenance_ics")

SUFFIX = f"@{ics.UID_DOMAIN}.ics"
DISPLAY_NAME = "Maintenance homelab"
TIMEOUT = 30
DAV = "DAV:"
PROPFIND_BODY = (
    '<?xml version="1.0" encoding="utf-8"?>'
    '<d:propfind xmlns:d="DAV:"><d:prop><d:resourcetype/><d:getetag/></d:prop></d:propfind>'
)
MKCALENDAR_BODY = (
    '<?xml version="1.0" encoding="utf-8"?>'
    '<c:mkcalendar xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav">'
    "<d:set><d:prop>"
    f"<d:displayname>{DISPLAY_NAME}</d:displayname>"
    "<c:supported-calendar-component-set><c:comp name=\"VEVENT\"/></c:supported-calendar-component-set>"
    "</d:prop></d:set></c:mkcalendar>"
)


class CalDAVError(Exception):
    """Une requête CalDAV a échoué (sans le mot de passe dans le message)."""


def object_name(uid):
    """Nom (décodé) de l'objet d'un UID ; request() l'encode, une seule fois."""
    return uid + ".ics"


class Client:
    def __init__(self, url, user, password):
        parsed = urllib.parse.urlsplit(url)
        local = parsed.hostname in ("127.0.0.1", "localhost")
        if parsed.scheme != "https" and not (parsed.scheme == "http" and local):
            raise CalDAVError("CALDAV_URL doit être en https")
        self.url = url if url.endswith("/") else url + "/"
        token = base64.b64encode(f"{user}:{password}".encode()).decode()
        self.auth = f"Basic {token}"
        # Pas de redirection suivie : un 3xx ne doit pas emporter l'en-tête
        # Authorization ailleurs, ni changer la méthode.
        self.opener = urllib.request.build_opener(NoRedirect)

    def request(self, method, name="", body=None, headers=None, ok=(200,)):
        url = urllib.parse.urljoin(self.url, urllib.parse.quote(name, safe="@.-_"))
        data = body.encode("utf-8") if body is not None else None
        request = urllib.request.Request(url, data=data, method=method)
        request.add_header("Authorization", self.auth)
        for key, value in (headers or {}).items():
            request.add_header(key, value)
        try:
            with self.opener.open(request, timeout=TIMEOUT) as response:
                status, payload = response.status, response.read()
        except urllib.error.HTTPError as error:
            with error:
                status, payload = error.code, error.read()
        except (OSError, http.client.HTTPException) as error:
            # La classe de la cause (TLS, DNS, délai), jamais l'URL ni l'en-tête.
            reason = getattr(error, "reason", None)
            cause = f" ({type(reason).__name__})" if isinstance(reason, BaseException) else ""
            raise CalDAVError(f"{method} {name or '<calendrier>'} : {type(error).__name__}{cause}") from None
        if status not in ok:
            raise CalDAVError(f"{method} {name or '<calendrier>'} : HTTP {status}")
        return status, payload

    def create_calendar(self):
        self.request("MKCALENDAR", body=MKCALENDAR_BODY, headers={"Content-Type": "application/xml; charset=utf-8"}, ok=(201,))

    def list_objects(self):
        """Noms (décodés) des objets .ics de la collection, None si elle n'existe pas."""
        status, payload = self.request(
            "PROPFIND", body=PROPFIND_BODY, headers={"Depth": "1", "Content-Type": "application/xml; charset=utf-8"}, ok=(207, 404)
        )
        if status == 404:
            return None
        try:
            # Réponse du serveur CalDAV choisi ; expat ne charge ni DTD ni entité externe.
            tree = ET.fromstring(payload)  # NOSONAR
        except ET.ParseError:
            raise CalDAVError("PROPFIND : réponse multistatus illisible") from None
        collection = urllib.parse.urlsplit(self.url).path
        names = set()
        for href in tree.iter(f"{{{DAV}}}href"):
            path = urllib.parse.urlsplit((href.text or "").strip()).path
            if path.rstrip("/") == collection.rstrip("/") or not path.endswith(".ics"):
                continue
            names.add(urllib.parse.unquote(path.rsplit("/", 1)[-1]))
        return names

    def put(self, name, text):
        self.request("PUT", name, body=text, headers={"Content-Type": "text/calendar; charset=utf-8"}, ok=(200, 201, 204))

    def delete(self, name):
        self.request("DELETE", name, ok=(200, 204, 404))


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *args, **kwargs):
        return None


def plan(objects, existing):
    """(à écrire {nom: texte}, à supprimer [noms]) : seulement les objets à nous."""
    wanted = {object_name(uid): text for uid, text in objects.items()}
    stale = sorted(name for name in existing if name.endswith(SUFFIX) and name not in wanted)
    return wanted, stale


def sync(client, objects):
    existing = client.list_objects()
    created = existing is None
    if created:
        client.create_calendar()
    wanted, stale = plan(objects, existing or set())
    for name, text in sorted(wanted.items()):
        client.put(name, text)
    for name in stale:
        client.delete(name)
    return created, len(wanted), stale


def main(argv=None, root=ics.ROOT, environ=None):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--dry-run", action="store_true", help="lister les objets, sans réseau")
    args = parser.parse_args(argv)
    environ = os.environ if environ is None else environ
    try:
        objects = ics.build_objects(root)
    except (ics.CalendarError, ics.rotation.InventoryError, OSError, ValueError, KeyError) as error:
        print(f"::error::{error}")
        return 1
    errors = [f"{uid} : {e}" for uid, text in objects.items() for e in ics.validate(text)]
    for error in errors:
        print(f"::error::{error}")
    if errors:
        return 1
    if args.dry_run:
        for uid in sorted(objects):
            print(object_name(uid))
        return 0
    missing = [name for name in ("CALDAV_URL", "CALDAV_USER", "CALDAV_PASSWORD") if not environ.get(name)]
    if missing:
        print(f"::error::variables absentes : {', '.join(missing)}")
        return 1
    try:
        client = Client(environ["CALDAV_URL"], environ["CALDAV_USER"], environ["CALDAV_PASSWORD"])
        created, written, stale = sync(client, objects)
    except CalDAVError as error:
        print(f"::error::{error}")
        return 1
    print(f"{'Calendrier créé. ' if created else ''}{written} événements écrits, {len(stale)} supprimés.")
    for name in stale:
        print(f"- supprimé : {name}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
