#!/usr/bin/env python3
"""Serveur MCP Homebox (stdio, bibliothèque standard) : lecture partout,
création et modification de fiches d'objet, jamais de suppression.

Lancé par Claude Code sur le poste de Sylvain (voir README.md). Variables :
HOMEBOX_URL (sans /api), HOMEBOX_API_KEY (clé d'API du compte, en-tête
Authorization: Bearer) et, hors de chez lui seulement,
HOMEBOX_PANGOLIN_TOKEN_ID / HOMEBOX_PANGOLIN_TOKEN (en-têtes P-Access-Token-*).

Une clé d'API Homebox n'a pas de périmètre : elle a tous les droits du compte.
La garantie « pas de suppression » est donc ICI : seuls les couples
méthode/chemin d'ALLOWED partent vers Homebox, tout le reste est refusé.
"""

import json
import os
import re
import sys
import urllib.error
import urllib.parse
import urllib.request

# Seuls appels autorisés. Aucun DELETE, aucun envoi de pièce jointe.
ALLOWED = [
    ("GET", r"/entities"),
    ("GET", r"/entities/tree"),
    ("GET", r"/entities/[^/]+"),
    ("GET", r"/tags"),
    ("GET", r"/groups/statistics"),
    ("POST", r"/entities"),
    ("PUT", r"/entities/[^/]+"),
]

# Champs de repo.EntityUpdate (swagger 0.27.1) qu'un outil peut changer.
UPDATABLE = {
    "name": "string", "description": "string", "quantity": "number", "locationId": "string",
    "tagIds": "array", "manufacturer": "string", "modelNumber": "string", "serialNumber": "string",
    "purchaseDate": "string", "purchaseFrom": "string", "purchasePrice": "number",
    "warrantyExpires": "string", "lifetimeWarranty": "boolean", "warrantyDetails": "string",
    "notes": "string",
}
# Le reste de EntityUpdate, repris tel quel de la fiche actuelle : un PUT remplace tout.
KEPT = ["archived", "assetId", "fields", "insured", "soldDate", "soldNotes", "soldPrice", "soldTo", "syncChildEntityLocations"]

CREATABLE = ["name", "description", "quantity", "locationId", "tagIds", "manufacturer", "modelNumber"]


def _obj(props=None, required=()):
    return {"type": "object", "properties": props or {}, "required": list(required)}


def _props(keys):
    p = {k: {"type": UPDATABLE[k]} for k in keys}
    if "tagIds" in p:
        p["tagIds"]["items"] = {"type": "string"}
    return p


ID = {"id": {"type": "string"}}
# nom -> (description, schéma, méthode, chemin)
TOOLS = {
    "search_items": ("Recherche d'objets et de lieux (texte libre, #<assetId>, étiquettes)", _obj({
        "q": {"type": "string"}, "page": {"type": "integer"}, "pageSize": {"type": "integer"},
        "tags": {"type": "array", "items": {"type": "string"}, "description": "Identifiants d'étiquettes"},
        "matchAllTags": {"type": "boolean"}, "parentIds": {"type": "array", "items": {"type": "string"}},
        "orderBy": {"type": "string", "enum": ["name", "createdAt", "updatedAt", "assetId"]},
    }), "GET", "/entities"),
    "get_item": ("Fiche complète d'un objet", _obj(ID, ["id"]), "GET", "/entities/{id}"),
    "list_locations": ("Arbre des lieux", _obj(), "GET", "/entities/tree"),
    "list_tags": ("Étiquettes", _obj(), "GET", "/tags"),
    "statistics": ("Nombre d'objets, de lieux, d'étiquettes, valeur totale", _obj(), "GET", "/groups/statistics"),
    "create_item": ("Crée une fiche d'objet", _obj(_props(CREATABLE), ["name"]), "POST", "/entities"),
    "update_item": (
        "Modifie des champs d'une fiche d'objet (les autres sont conservés ; dates en AAAA-MM-JJ)",
        _obj({**ID, **_props(UPDATABLE)}, ["id"]), "PUT", "/entities/{id}"),
}


def check_allowed(method, path):
    if not any(m == method and re.fullmatch(p, path) for m, p in ALLOWED):
        raise ValueError("appel refusé : %s %s" % (method, path))


def merge_update(cur, changes):
    """Corps du PUT : la fiche actuelle (PUT remplace tout) + les changements."""
    unknown = set(changes) - set(UPDATABLE)
    if unknown:
        raise ValueError("champs non modifiables : " + ", ".join(sorted(unknown)))
    if (cur.get("entityType") or {}).get("isLocation"):
        raise ValueError("c'est un lieu, pas un objet : modification refusée")
    body = {k: cur[k] for k in list(UPDATABLE) + KEPT + ["id"] if cur.get(k) is not None}
    body["tagIds"] = [t["id"] for t in cur.get("tags") or []]
    body["entityTypeId"] = cur["entityType"]["id"]
    if cur.get("parent"):
        body["parentId"] = cur["parent"]["id"]
    if not body.get("locationId") and cur.get("location"):
        body["locationId"] = cur["location"]["id"]
    body.update(changes)
    return body


def call_homebox(method, path, args, base, key, extra_headers=None):
    """Un appel à l'API ; renvoie le JSON décodé."""
    args = dict(args)
    if "{id}" in path:
        oid = str(args.pop("id", ""))
        # « . » et « .. » passent le quote() et ALLOWED : un serveur ou un proxy
        # normaliserait /entities/.. hors de la liste blanche.
        if not re.fullmatch(r"[A-Za-z0-9_-]+", oid):
            raise ValueError("identifiant invalide : %r" % oid)
        path = path.replace("{id}", oid)
    check_allowed(method, path)
    if method == "PUT":
        # relit la fiche (GET autorisé) : le PUT d'Homebox efface les champs absents
        args = merge_update(call_homebox("GET", path, {}, base, key, extra_headers), args)
    elif method == "POST":
        extra = set(args) - set(CREATABLE)
        if extra:
            raise ValueError("champs non acceptés : " + ", ".join(sorted(extra)))
    url = base.rstrip("/") + "/api/v1" + path
    data = None
    headers = {"Authorization": "Bearer " + key, "Accept": "application/json", **(extra_headers or {})}
    if method == "GET":
        if args:
            url += "?" + urllib.parse.urlencode(args, doseq=True)
    else:
        data = json.dumps(args).encode()
        headers["Content-Type"] = "application/json"
    req = urllib.request.Request(url, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            return json.load(resp)
    except urllib.error.HTTPError as e:
        raise RuntimeError("HTTP %d : %s" % (e.code, e.read(500).decode(errors="replace"))) from None


def handle(msg, call):
    """Une requête JSON-RPC ; renvoie la réponse, ou None pour une notification."""
    mid, method = msg.get("id"), msg.get("method")
    if mid is None:
        return None
    if method == "initialize":
        result = {
            "protocolVersion": (msg.get("params") or {}).get("protocolVersion", "2025-06-18"),
            "capabilities": {"tools": {}},
            "serverInfo": {"name": "homebox", "version": "1.0.0"},
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
            result = {"isError": True, "content": [{"type": "text", "text": "Erreur Homebox : %s" % e}]}
    else:
        return {"jsonrpc": "2.0", "id": mid, "error": {"code": -32601, "message": "méthode inconnue"}}
    return {"jsonrpc": "2.0", "id": mid, "result": result}


def main():
    base, key = os.environ["HOMEBOX_URL"], os.environ["HOMEBOX_API_KEY"]
    extra = {}
    if os.environ.get("HOMEBOX_PANGOLIN_TOKEN") and os.environ.get("HOMEBOX_PANGOLIN_TOKEN_ID"):
        extra = {
            "P-Access-Token-Id": os.environ["HOMEBOX_PANGOLIN_TOKEN_ID"],
            "P-Access-Token": os.environ["HOMEBOX_PANGOLIN_TOKEN"],
        }

    def call(method, path, args):
        return call_homebox(method, path, args, base, key, extra)

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
