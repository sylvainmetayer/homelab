#!/usr/bin/env python3
"""Serveur MCP Papra (stdio, bibliothèque standard) : lecture partout, tags en
écriture (créer un tag, poser ou retirer un tag sur un document), jamais de
suppression de document ni de tag.

Lancé par Claude Code sur le poste de Sylvain (voir README.md). Variables :
PAPRA_URL (sans /api), PAPRA_API_KEY (clé d'API Papra, en-tête
Authorization: Bearer) et, hors de chez lui seulement,
PAPRA_PANGOLIN_TOKEN_ID / PAPRA_PANGOLIN_TOKEN (en-têtes P-Access-Token-*).

Les permissions de la clé (organizations:read, documents:read,
documents:update, tags:read, tags:create) sont une première barrière, mais
documents:update ouvre aussi PATCH et retraitement : la liste blanche est donc
ICI. Seuls les couples méthode/chemin d'ALLOWED partent vers Papra. Le seul
DELETE est le retrait d'un tag d'un document ; les DELETE de document, de
corbeille et de tag sont refusés.
"""

import json
import os
import re
import sys
import urllib.error
import urllib.parse
import urllib.request

ORG = r"/organizations/[A-Za-z0-9_-]+"
# Seuls appels autorisés. Un seul DELETE : /documents/<id>/tags/<tag>.
ALLOWED = [
    ("GET", r"/organizations"),
    ("GET", ORG + r"/documents"),
    ("GET", ORG + r"/documents/statistics"),
    ("GET", ORG + r"/documents/[A-Za-z0-9_-]+"),
    ("GET", ORG + r"/tags"),
    ("POST", ORG + r"/tags"),
    ("POST", ORG + r"/documents/[A-Za-z0-9_-]+/tags"),
    ("DELETE", ORG + r"/documents/[A-Za-z0-9_-]+/tags/[A-Za-z0-9_-]+"),
]

ID_RE = re.compile(r"[A-Za-z0-9_-]+")
# Champs de chaque écriture : nom -> (type JSON, motif facultatif).
BODY = {
    "POST /organizations/{org}/tags": {
        "name": (str, None), "color": (str, r"#[0-9a-fA-F]{6}"), "description": (str, None)},
    "POST /organizations/{org}/documents/{id}/tags": {"tagId": (str, ID_RE.pattern)},
}

ORG_ID = {"organizationId": {"type": "string", "description": "Identifiant d'organisation (list_organizations)"}}
DOC_ID = {**ORG_ID, "id": {"type": "string", "description": "Identifiant du document"}}
SEARCH = {
    **ORG_ID, "searchQuery": {"type": "string"}, "pageIndex": {"type": "integer"},
    "pageSize": {"type": "integer", "description": "100 au plus"},
    "sortField": {"type": "string", "enum": ["createdAt", "name"]}, "sortOrder": {"type": "string", "enum": ["asc", "desc"]},
}
TAG_ARGS = {**DOC_ID, "tagId": {"type": "string"}}


def _obj(props=None, required=()):
    return {"type": "object", "properties": props or {}, "required": list(required)}


# nom -> (description, schéma, méthode, chemin)
TOOLS = {
    "list_organizations": ("Organisations de l'utilisateur", _obj(), "GET", "/organizations"),
    "search_documents": (
        "Recherche de documents (texte libre, sans le texte OCR ; get_document_text le donne)",
        _obj(SEARCH, ["organizationId"]), "GET", "/organizations/{org}/documents"),
    "get_document": ("Fiche d'un document : nom, date, tags, propriétés, sans le texte", _obj(DOC_ID, ["organizationId", "id"]),
                     "GET", "/organizations/{org}/documents/{id}"),
    "get_document_text": ("Texte (OCR) d'un document", _obj(DOC_ID, ["organizationId", "id"]),
                          "GET", "/organizations/{org}/documents/{id}"),
    "list_tags": ("Tags de l'organisation", _obj(ORG_ID, ["organizationId"]), "GET", "/organizations/{org}/tags"),
    "statistics": ("Nombre et taille des documents, corbeille comprise", _obj(ORG_ID, ["organizationId"]),
                   "GET", "/organizations/{org}/documents/statistics"),
    "create_tag": (
        "Crée un tag (couleur #rrggbb)",
        _obj({**ORG_ID, "name": {"type": "string"}, "color": {"type": "string"}, "description": {"type": "string"}},
             ["organizationId", "name", "color"]),
        "POST", "/organizations/{org}/tags"),
    "add_tag": ("Pose un tag sur un document", _obj(TAG_ARGS, ["organizationId", "id", "tagId"]),
                "POST", "/organizations/{org}/documents/{id}/tags"),
    "remove_tag": ("Retire un tag d'un document (le tag et le document restent)", _obj(TAG_ARGS, ["organizationId", "id", "tagId"]),
                   "DELETE", "/organizations/{org}/documents/{id}/tags/{tag}"),
}


def _without_content(data):
    """Le texte OCR pèse : il n'est rendu que par get_document_text."""
    for doc in data.get("documents", []) + [data.get("document") or {}]:
        doc.pop("content", None)
    return data


# Mise en forme de la réponse, par outil.
SHAPE = {
    "search_documents": _without_content,
    "get_document": _without_content,
    "get_document_text": lambda data: {"content": (data.get("document") or {}).get("content")},
}


def check_allowed(method, path):
    if not any(m == method and re.fullmatch(p, path) for m, p in ALLOWED):
        raise ValueError("appel refusé : %s %s" % (method, path))


def call_papra(method, path, args, base, key, extra_headers=None):
    """Un appel à l'API ; renvoie le JSON décodé ({"ok": true} si la réponse est vide)."""
    args = dict(args)
    template = path
    for ph, arg in (("{org}", "organizationId"), ("{id}", "id"), ("{tag}", "tagId")):
        if ph in path:
            val = args.pop(arg, "")
            # « . » et « .. » passeraient quote() : seuls des identifiants Papra (lettres, chiffres, _ et -).
            if not isinstance(val, str) or not ID_RE.fullmatch(val):
                raise ValueError("identifiant invalide : %r" % (val,))
            path = path.replace(ph, val)
    check_allowed(method, path)
    url = base.rstrip("/") + "/api" + path
    data = None
    headers = {"Authorization": "Bearer " + key, "Accept": "application/json", **(extra_headers or {})}
    if method == "GET":
        if args:
            url += "?" + urllib.parse.urlencode(args, doseq=True)
    elif method == "POST":
        spec = BODY[method + " " + template]
        if set(args) - set(spec):
            raise ValueError("champs non acceptés : " + ", ".join(sorted(set(args) - set(spec))))
        for k, v in args.items():
            if not isinstance(v, str) or (spec[k][1] and not re.fullmatch(spec[k][1], v)):
                raise ValueError("champ %s invalide" % k)
        data = json.dumps(args).encode()
        headers["Content-Type"] = "application/json"
    elif args:
        raise ValueError("champs non acceptés : " + ", ".join(sorted(args)))
    req = urllib.request.Request(url, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            body = resp.read()
    except urllib.error.HTTPError as e:
        raise RuntimeError("HTTP %d : %s" % (e.code, e.read(500).decode(errors="replace"))) from None
    return json.loads(body) if body else {"ok": True}


def handle(msg, call):
    """Une requête JSON-RPC ; renvoie la réponse, ou None pour une notification."""
    mid, method = msg.get("id"), msg.get("method")
    if mid is None:
        return None
    if method == "initialize":
        result = {
            "protocolVersion": (msg.get("params") or {}).get("protocolVersion", "2025-06-18"),
            "capabilities": {"tools": {}},
            "serverInfo": {"name": "papra", "version": "1.0.0"},
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
            data = call(TOOLS[name][2], TOOLS[name][3], args)
            text = json.dumps(SHAPE.get(name, lambda d: d)(data), ensure_ascii=False)
            result = {"content": [{"type": "text", "text": text[:100000]}]}
        except Exception as e:  # erreur d'outil : renvoyée au modèle, pas fatale
            result = {"isError": True, "content": [{"type": "text", "text": "Erreur Papra : %s" % e}]}
    else:
        return {"jsonrpc": "2.0", "id": mid, "error": {"code": -32601, "message": "méthode inconnue"}}
    return {"jsonrpc": "2.0", "id": mid, "result": result}


def main():
    base, key = os.environ["PAPRA_URL"], os.environ["PAPRA_API_KEY"]
    extra = {}
    if os.environ.get("PAPRA_PANGOLIN_TOKEN") and os.environ.get("PAPRA_PANGOLIN_TOKEN_ID"):
        extra = {
            "P-Access-Token-Id": os.environ["PAPRA_PANGOLIN_TOKEN_ID"],
            "P-Access-Token": os.environ["PAPRA_PANGOLIN_TOKEN"],
        }

    def call(method, path, args):
        return call_papra(method, path, args, base, key, extra)

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
