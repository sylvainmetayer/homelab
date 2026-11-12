#!/usr/bin/env python3
"""Serveur MCP Immich en lecture seule (stdio, bibliothèque standard).

Lancé par Claude Code sur le poste de Sylvain (voir README.md). Variables :
IMMICH_URL (sans /api), IMMICH_API_KEY (clé aux permissions de lecture seules),
et, hors de chez lui seulement, IMMICH_PANGOLIN_TOKEN_ID / IMMICH_PANGOLIN_TOKEN
(en-têtes P-Access-Token-* de Pangolin).

Lecture seule par construction : seuls GET et deux POST de recherche (list
blanche ci-dessous) partent vers Immich ; la clé, elle, n'a de toute façon
aucun droit d'écriture.
"""

import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request

# POST autorisés : des recherches, qui ne modifient rien.
POST_OK = {"/search/metadata", "/search/smart"}

SEARCH_PROPS = {
    "query": {"type": "string", "description": "Texte libre (recherche sémantique) ou nom de fichier"},
    "takenAfter": {"type": "string", "description": "Date ISO 8601, ex. 2024-07-01T00:00:00.000Z"},
    "takenBefore": {"type": "string", "description": "Date ISO 8601"},
    "city": {"type": "string"},
    "country": {"type": "string"},
    "personIds": {"type": "array", "items": {"type": "string"}},
    "type": {"type": "string", "enum": ["IMAGE", "VIDEO"]},
    "size": {"type": "integer", "description": "Résultats par page (défaut 20)"},
    "page": {"type": "integer"},
}

# /search/metadata n'a pas de champ `query` (ignoré par Immich : tout reviendrait) ;
# le nom de fichier s'y passe par originalFileName.
META_PROPS = {k: v for k, v in SEARCH_PROPS.items() if k != "query"}
META_PROPS["originalFileName"] = {"type": "string", "description": "Nom de fichier d'origine (correspondance partielle)"}


class _NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


# urllib rejoue les en-têtes (clé d'API, jeton Pangolin) vers la cible d'une
# redirection : une 3xx est une erreur, jamais suivie.
_OPENER = urllib.request.build_opener(_NoRedirect)


def _obj(props=None, required=()):
    return {"type": "object", "properties": props or {}, "required": list(required)}


# nom -> (description, schéma, méthode, chemin, clé du corps/paramètres)
TOOLS = {
    "search_smart": ("Recherche sémantique (CLIP) de photos et vidéos", _obj(SEARCH_PROPS, ["query"]), "POST", "/search/smart"),
    "search_metadata": ("Recherche par métadonnées (dates, lieu, personnes, nom de fichier)", _obj(META_PROPS), "POST", "/search/metadata"),
    "list_albums": ("Liste des albums", _obj(), "GET", "/albums"),
    "get_album": ("Un album et ses assets", _obj({"id": {"type": "string"}}, ["id"]), "GET", "/albums/{id}"),
    "list_people": ("Personnes reconnues", _obj({"size": {"type": "integer"}, "page": {"type": "integer"}}), "GET", "/people"),
    "get_asset": ("Détail d'un asset (EXIF, lieu, personnes)", _obj({"id": {"type": "string"}}, ["id"]), "GET", "/assets/{id}"),
    "asset_statistics": ("Nombre de photos et de vidéos (hors corbeille)", _obj(), "GET", "/assets/statistics"),
}


def call_immich(method, path, args, base, key, extra_headers=None):
    """Un appel à l'API ; renvoie le JSON décodé."""
    args = dict(args)
    if "{id}" in path:
        path = path.replace("{id}", urllib.parse.quote(str(args.pop("id")), safe=""))
    if method == "POST" and path not in POST_OK:
        raise ValueError("POST refusé : " + path)
    url = base.rstrip("/") + "/api" + path
    data = None
    headers = {"x-api-key": key, "Accept": "application/json", **(extra_headers or {})}
    if method == "GET":
        if args:
            url += "?" + urllib.parse.urlencode(args)
    else:
        data = json.dumps(args).encode()
        headers["Content-Type"] = "application/json"
    req = urllib.request.Request(url, data=data, headers=headers, method=method)
    try:
        with _OPENER.open(req, timeout=30) as resp:
            return json.load(resp)
    except urllib.error.HTTPError as e:
        # le corps d'Immich nomme la permission manquante d'un 403
        # une 3xx n'a pas de corps : sa cible dit où l'on voulait aller (login Pangolin, http -> https)
        detail = e.read(500).decode(errors="replace") or e.headers.get("Location", "")
        raise RuntimeError("HTTP %d : %s" % (e.code, detail)) from None


def handle(msg, call):
    """Une requête JSON-RPC ; renvoie la réponse, ou None pour une notification."""
    mid, method = msg.get("id"), msg.get("method")
    if mid is None:
        return None
    if method == "initialize":
        result = {
            "protocolVersion": (msg.get("params") or {}).get("protocolVersion", "2025-06-18"),
            "capabilities": {"tools": {}},
            "serverInfo": {"name": "immich-readonly", "version": "1.0.0"},
        }
    elif method == "ping":
        result = {}
    elif method == "tools/list":
        result = {"tools": [{"name": n, "description": d, "inputSchema": s} for n, (d, s, _, _) in TOOLS.items()]}
    elif method == "tools/call":
        params = msg.get("params") or {}
        name, args = params.get("name"), params.get("arguments") or {}
        if name not in TOOLS:
            return {"jsonrpc": "2.0", "id": mid, "error": {"code": -32602, "message": "outil inconnu : %s" % name}}
        try:
            text = json.dumps(call(TOOLS[name][2], TOOLS[name][3], args), ensure_ascii=False)
            result = {"content": [{"type": "text", "text": text[:100000]}]}
        except Exception as e:  # erreur d'outil : renvoyée au modèle, pas fatale
            result = {"isError": True, "content": [{"type": "text", "text": "Erreur Immich : %s" % e}]}
    else:
        return {"jsonrpc": "2.0", "id": mid, "error": {"code": -32601, "message": "méthode inconnue"}}
    return {"jsonrpc": "2.0", "id": mid, "result": result}


def main():
    base, key = os.environ["IMMICH_URL"], os.environ["IMMICH_API_KEY"]
    extra = {}
    if os.environ.get("IMMICH_PANGOLIN_TOKEN") and os.environ.get("IMMICH_PANGOLIN_TOKEN_ID"):
        extra = {
            "P-Access-Token-Id": os.environ["IMMICH_PANGOLIN_TOKEN_ID"],
            "P-Access-Token": os.environ["IMMICH_PANGOLIN_TOKEN"],
        }

    def call(method, path, args):
        return call_immich(method, path, args, base, key, extra)

    for line in sys.stdin:
        if line.strip():
            try:
                msg = json.loads(line)
            except ValueError:  # ligne illisible : ignorée, le serveur reste vivant
                continue
            reply = handle(msg, call) if isinstance(msg, dict) else None
            if reply:
                print(json.dumps(reply, ensure_ascii=False), flush=True)


if __name__ == "__main__":
    main()
