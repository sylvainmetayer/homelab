#!/usr/bin/env python3
"""Serveur MCP Grocy (stdio, bibliothèque standard) : lecture partout, liste de
courses (ajouter, modifier une ligne, marquer fait) et corvées (marquer une
corvée faite) en écriture, jamais de suppression.

Lancé par Claude Code sur le poste de Sylvain (voir README.md). Variables :
GROCY_URL (sans /api), GROCY_API_KEY (en-tête GROCY-API-KEY) et, hors de chez
lui seulement, GROCY_PANGOLIN_TOKEN_ID / GROCY_PANGOLIN_TOKEN (en-têtes
P-Access-Token-*).

Une clé d'API Grocy n'a pas de périmètre : elle a tous les droits du compte.
La garantie « pas de suppression » est donc ICI : seuls les couples
méthode/chemin d'ALLOWED partent vers Grocy, tout le reste est refusé.
"""

import json
import os
import re
import sys
import urllib.error
import urllib.parse
import urllib.request

# Seuls appels autorisés. Aucun DELETE ; /objects/ n'est ouvert que pour les
# produits (lecture) et la liste de courses (lecture, POST, PUT).
ALLOWED = [
    ("GET", r"/stock"),
    ("GET", r"/stock/volatile"),
    ("GET", r"/stock/products/[0-9]+"),
    ("GET", r"/objects/products"),
    ("GET", r"/objects/shopping_list"),
    ("GET", r"/chores"),
    ("GET", r"/chores/[0-9]+"),
    ("GET", r"/recipes/fulfillment"),
    ("POST", r"/objects/shopping_list"),
    ("PUT", r"/objects/shopping_list/[0-9]+"),
    ("POST", r"/chores/[0-9]+/execute"),
]

# Champs que chaque écriture accepte (type JSON). `skipped` d'une corvée n'y est pas.
NEW_LINE = {"product_id": "integer", "note": "string", "amount": "number", "shopping_list_id": "integer"}
LINE = {**NEW_LINE, "done": "boolean"}
EXECUTE = {"tracked_time": "string", "done_by": "integer"}
BODY = {"POST /objects/shopping_list": NEW_LINE, "PUT /objects/shopping_list/{id}": LINE, "POST /chores/{id}/execute": EXECUTE}
PY_TYPE = {"integer": int, "number": (int, float), "string": str, "boolean": bool}


def _obj(props=None, required=()):
    return {"type": "object", "properties": props or {}, "required": list(required)}


def _props(spec):
    return {k: {"type": t} for k, t in spec.items()}


ID = {"id": {"type": "integer"}}
PAGE = {"limit": {"type": "integer"}, "offset": {"type": "integer"}}
# nom -> (description, schéma, méthode, chemin)
TOOLS = {
    "stock": ("Stock actuel, un produit par ligne (quantité, prochaine péremption)", _obj(), "GET", "/stock"),
    "expiring": (
        "Produits bientôt périmés, périmés, expirés et manquants",
        _obj({"due_soon_days": {"type": "integer"}}), "GET", "/stock/volatile"),
    "list_products": ("Produits (identifiants, noms, unités)", _obj(PAGE), "GET", "/objects/products"),
    "get_product": ("Détail d'un produit : stock, emplacements, dernier achat", _obj(ID, ["id"]), "GET", "/stock/products/{id}"),
    "shopping_list": ("Lignes de la liste de courses (done = 1 : déjà prise)", _obj(PAGE), "GET", "/objects/shopping_list"),
    "list_chores": ("Corvées et leur prochaine échéance", _obj(PAGE), "GET", "/chores"),
    "get_chore": ("Détail d'une corvée et de sa dernière exécution", _obj(ID, ["id"]), "GET", "/chores/{id}"),
    "list_recipes": ("Recettes et ce qui manque en stock pour chacune", _obj(PAGE), "GET", "/recipes/fulfillment"),
    "add_shopping_item": (
        "Ajoute une ligne à la liste de courses (un produit, ou une simple note)",
        _obj(_props(NEW_LINE)), "POST", "/objects/shopping_list"),
    "update_shopping_item": (
        "Modifie une ligne de la liste de courses ; done: true la marque faite (les autres champs sont conservés)",
        _obj({**ID, **_props(LINE)}, ["id"]), "PUT", "/objects/shopping_list/{id}"),
    "complete_chore": (
        "Marque une corvée faite (maintenant, ou à tracked_time AAAA-MM-JJ hh:mm:ss ; done_by : identifiant d'utilisateur)",
        _obj({**ID, **_props(EXECUTE)}, ["id"]), "POST", "/chores/{id}/execute"),
}


def check_allowed(method, path):
    if not any(m == method and re.fullmatch(p, path) for m, p in ALLOWED):
        raise ValueError("appel refusé : %s %s" % (method, path))


def check_body(spec, args):
    """Refuse un champ hors liste ou d'un autre type ; un booléen part en 0/1 (Grocy)."""
    extra = set(args) - set(spec)
    if extra:
        raise ValueError("champs non acceptés : " + ", ".join(sorted(extra)))
    for k, v in args.items():
        # bool est un int en Python : refusé là où un nombre est attendu
        if not isinstance(v, PY_TYPE[spec[k]]) or (spec[k] != "boolean" and isinstance(v, bool)):
            raise ValueError("champ %s : %s attendu" % (k, spec[k]))
    return {k: int(v) if isinstance(v, bool) else v for k, v in args.items()}


def call_grocy(method, path, args, base, key, extra_headers=None):
    """Un appel à l'API ; renvoie le JSON décodé ({"ok": true} si la réponse est vide)."""
    args = dict(args)
    template = path
    if "{id}" in path:
        oid = args.pop("id", "")
        # Des chiffres seulement : « .. » passerait quote() et ne sortirait pas de la liste blanche.
        if isinstance(oid, bool) or not re.fullmatch(r"[0-9]+", str(oid)):
            raise ValueError("identifiant invalide : %r" % oid)
        path = path.replace("{id}", str(oid))
    check_allowed(method, path)
    if method != "GET":
        args = check_body(BODY["%s %s" % (method, template)], args)
        if not args and "shopping_list" in path:  # une corvée se marque faite sans champ
            raise ValueError("rien à écrire")
    url = base.rstrip("/") + "/api" + path
    data = None
    headers = {"GROCY-API-KEY": key, "Accept": "application/json", **(extra_headers or {})}
    if method == "GET":
        if args:
            url += "?" + urllib.parse.urlencode(args, doseq=True)
    else:
        data = json.dumps(args).encode()
        headers["Content-Type"] = "application/json"
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
            "serverInfo": {"name": "grocy", "version": "1.0.0"},
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
            result = {"isError": True, "content": [{"type": "text", "text": "Erreur Grocy : %s" % e}]}
    else:
        return {"jsonrpc": "2.0", "id": mid, "error": {"code": -32601, "message": "méthode inconnue"}}
    return {"jsonrpc": "2.0", "id": mid, "result": result}


def main():
    base, key = os.environ["GROCY_URL"], os.environ["GROCY_API_KEY"]
    extra = {}
    if os.environ.get("GROCY_PANGOLIN_TOKEN") and os.environ.get("GROCY_PANGOLIN_TOKEN_ID"):
        extra = {
            "P-Access-Token-Id": os.environ["GROCY_PANGOLIN_TOKEN_ID"],
            "P-Access-Token": os.environ["GROCY_PANGOLIN_TOKEN"],
        }

    def call(method, path, args):
        return call_grocy(method, path, args, base, key, extra)

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
