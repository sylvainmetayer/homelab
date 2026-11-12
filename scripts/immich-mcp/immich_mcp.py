#!/usr/bin/env python3
"""Serveur MCP Immich (stdio, bibliothèque standard) : lecture seule par défaut,
tri des albums en écriture si IMMICH_MCP_WRITE=1.

Lancé par Claude Code sur le poste de Sylvain (voir README.md). Variables :
IMMICH_URL (sans /api), IMMICH_API_KEY (clé de lecture, ou clé d'écriture en
mode écriture), IMMICH_MCP_WRITE=1 (active les outils d'écriture) et, hors de
chez lui seulement, IMMICH_PANGOLIN_TOKEN_ID / IMMICH_PANGOLIN_TOKEN
(en-têtes P-Access-Token-* de Pangolin).

La liste blanche méthode/chemin est ICI (READ, WRITE_BODY), pas dans les
permissions de la clé. En lecture, seuls des GET et deux POST de recherche
partent. En écriture s'ajoutent cinq appels, tous sur des albums : créer,
renommer, ajouter des assets, retirer des assets (le lien, jamais la photo),
supprimer l'album. Aucun chemin /assets en écriture, ni corbeille, ni
personnes, partages, utilisateurs : ils sont refusés avant l'envoi.
Chaque outil d'écriture est en deux temps (aperçu + jeton, puis exécution).
"""

import hashlib
import hmac
import json
import os
import re
import sys
import urllib.error
import urllib.parse
import urllib.request

UUID = r"[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}"
# Appels de lecture (les deux POST sont des recherches, qui ne modifient rien).
READ = {
    "GET /albums", "GET /albums/{id}", "GET /people", "GET /assets/{id}", "GET /assets/statistics",
    "POST /search/metadata", "POST /search/smart",
}
# Appels d'écriture, mode écriture seulement : gabarit -> champs du corps (str ou liste d'UUID).
WRITE_BODY = {
    "POST /albums": {"albumName": "str", "description": "str", "assetIds": "uuids"},
    "PATCH /albums/{id}": {"albumName": "str", "description": "str"},
    "PUT /albums/{id}/assets": {"ids": "uuids"},
    "DELETE /albums/{id}/assets": {"ids": "uuids"},
    "DELETE /albums/{id}": {},
}

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
META_PROPS["albumIds"] = {"type": "array", "items": {"type": "string"}, "description": "UUID d'albums : les assets de ces albums"}


class _NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


# urllib rejoue les en-têtes (clé d'API, jeton Pangolin) vers la cible d'une
# redirection : une 3xx est une erreur, jamais suivie.
_OPENER = urllib.request.build_opener(_NoRedirect)


def _obj(props=None, required=()):
    return {"type": "object", "properties": props or {}, "required": list(required)}


# nom -> (description, schéma, méthode, chemin)
TOOLS = {
    "search_smart": ("Recherche sémantique (CLIP) de photos et vidéos", _obj(SEARCH_PROPS, ["query"]), "POST", "/search/smart"),
    "search_metadata": ("Recherche par métadonnées (dates, lieu, personnes, nom de fichier)", _obj(META_PROPS), "POST", "/search/metadata"),
    "get_album": ("Un album (nom, description, nombre d'assets) ; ses assets : search_metadata avec albumIds",
                  _obj({"id": {"type": "string"}}, ["id"]), "GET", "/albums/{id}"),
    "list_people": ("Personnes reconnues", _obj({"size": {"type": "integer"}, "page": {"type": "integer"}}), "GET", "/people"),
    "get_asset": ("Détail d'un asset (EXIF, lieu, personnes)", _obj({"id": {"type": "string"}}, ["id"]), "GET", "/assets/{id}"),
    "asset_statistics": ("Nombre de photos et de vidéos (hors corbeille)", _obj(), "GET", "/assets/statistics"),
}


def _uuid(v):
    if not isinstance(v, str) or not re.fullmatch(UUID, v):
        raise ValueError("identifiant invalide : %r" % (v,))
    return v


def _uuids(v):
    if not isinstance(v, list) or not v or len(v) > 5000:
        raise ValueError("liste d'identifiants attendue (1 à 5000)")
    return list(dict.fromkeys(_uuid(i) for i in v))


def call_immich(method, path, args, base, key, extra_headers=None, write=False):
    """Un appel à l'API ; renvoie le JSON décodé ({"ok": true} si la réponse est vide)."""
    args = dict(args)
    template = method + " " + path
    if template not in READ and not (write and template in WRITE_BODY):
        raise ValueError("appel refusé : " + template)
    if "{id}" in path:
        path = path.replace("{id}", _uuid(args.pop("id", None)))
    if template in WRITE_BODY:
        spec = WRITE_BODY[template]
        if set(args) - set(spec):
            raise ValueError("champs non acceptés : " + ", ".join(sorted(set(args) - set(spec))))
        for k, v in args.items():
            if spec[k] == "uuids":
                args[k] = _uuids(v)
            elif not isinstance(v, str):
                raise ValueError("champ %s invalide" % k)
    url = base.rstrip("/") + "/api" + path
    data = None
    headers = {"x-api-key": key, "Accept": "application/json", **(extra_headers or {})}
    if method == "GET":
        if args:
            url += "?" + urllib.parse.urlencode(args)
    elif args:
        data = json.dumps(args).encode()
        headers["Content-Type"] = "application/json"
    req = urllib.request.Request(url, data=data, headers=headers, method=method)
    try:
        with _OPENER.open(req, timeout=30) as resp:
            body = resp.read()
    except urllib.error.HTTPError as e:
        # le corps d'Immich nomme la permission manquante d'un 403
        # une 3xx n'a pas de corps : sa cible dit où l'on voulait aller (login Pangolin, http -> https)
        detail = e.read(500).decode(errors="replace") or e.headers.get("Location", "")
        raise RuntimeError("HTTP %d : %s" % (e.code, detail)) from None
    return json.loads(body) if body else {"ok": True}


# --- Outils composés : lectures sur plusieurs appels, écritures en deux temps ---

CONFIRM = {"type": "string", "description": "Jeton rendu par l'aperçu. Absent : aperçu seul, rien n'est écrit."}
TWO_STEP = (" EN DEUX TEMPS : sans `confirm`, ne fait qu'un aperçu (rien n'est écrit) et rend un jeton `confirm`. "
            "Montre l'aperçu à Sylvain ; seulement s'il valide, rappelle le même outil avec les mêmes arguments "
            "et `confirm`. Si l'état d'Immich a changé entre-temps, le jeton ne correspond plus et rien n'est écrit.")
ALBUM_ID = {"type": "string", "description": "UUID de l'album (list_albums)"}
ASSET_IDS = {"type": "array", "items": {"type": "string"}, "description": "UUID d'assets"}


def _norm(name):
    return " ".join((name or "").split()).casefold()


def _album_assets(call, aid, album=None):
    """({id: nom de fichier}, liste complète ?) : l'album seul ne rend pas ses assets, la recherche si.
    `album` : l'album déjà lu (id, assetCount), pour ne pas le relire."""
    items, page = {}, 1
    while page:
        r = call("POST", "/search/metadata", {"albumIds": [_uuid(aid)], "size": 1000, "page": page})["assets"]
        items.update({i["id"]: i.get("originalFileName", "") for i in r["items"]})
        page = page + 1 if r.get("nextPage") and page < 50 else 0
    album = album or call("GET", "/albums/{id}", {"id": aid})
    return items, len(items) == album.get("assetCount")


def _sample(ids, names, n=10):
    return [names.get(i, i) for i in ids[:n]]


def _guarded(name, args, preview, fp, apply):
    """Deux temps : le jeton est l'empreinte de (outil, arguments, état lu), il ne vit nulle part."""
    body = {k: v for k, v in args.items() if k != "confirm"}
    token = hashlib.sha256(json.dumps([name, body, fp], sort_keys=True).encode()).hexdigest()[:16]
    given = args.get("confirm")
    if given is None:
        return {"applique": False, "apercu": preview, "confirm": token}
    if not isinstance(given, str) or not hmac.compare_digest(given, token):
        return {"applique": False, "erreur": "jeton périmé ou inexact (l'état a changé ?) : rien n'a été écrit",
                "apercu": preview, "confirm": token}
    return {"applique": True, "resultat": apply()}


def _bulk(call, method, aid, ids):
    """Ajoute ou retire des assets par paquets ; Immich répond un résultat par asset."""
    ok, errors = 0, []
    for i in range(0, len(ids), 500):
        for r in call(method, "/albums/{id}/assets", {"id": aid, "ids": ids[i:i + 500]}):
            if r.get("success"):
                ok += 1
            else:
                errors.append("%s : %s" % (r.get("id"), r.get("error")))
    return {"ok": ok, "erreurs": errors[:20]}


def list_albums(call, args):
    """Liste compacte, triée par nom ; `contains` filtre sur le nom (casse ignorée)."""
    q = _norm(args.get("contains"))
    rows = [{"id": a["id"], "nom": a["albumName"], "assets": a["assetCount"], "debut": a.get("startDate"),
             "fin": a.get("endDate"), "partage": bool(a.get("shared"))}
            for a in call("GET", "/albums", {}) if q in _norm(a["albumName"])]
    return {"albums": sorted(rows, key=lambda r: _norm(r["nom"])), "total": len(rows)}


def find_duplicate_albums(call, args):
    albums = call("GET", "/albums", {})
    groups = {}
    for a in albums:
        groups.setdefault(_norm(a["albumName"]), []).append(a)
    out = {"meme_nom": [[{"id": a["id"], "nom": a["albumName"], "assets": a["assetCount"]} for a in g]
                        for g in groups.values() if len(g) > 1]}
    if "minOverlap" in args:
        t = float(args["minOverlap"])
        full = [a for a in albums if a["assetCount"]]
        if len(full) > 100:
            raise ValueError("plus de 100 albums non vides : le recouvrement est trop long, noms seulement")
        sets = {a["id"]: set(_album_assets(call, a["id"], a)[0]) for a in full}
        out["recouvrement"] = []
        for i, a in enumerate(full):
            for b in full[i + 1:]:
                sa, sb = sets[a["id"]], sets[b["id"]]
                common = len(sa & sb)
                ratio = common / max(min(len(sa), len(sb)), 1)
                if common and ratio >= t:
                    out["recouvrement"].append({"a": {"id": a["id"], "nom": a["albumName"]}, "b": {"id": b["id"], "nom": b["albumName"]},
                                                "communs": common, "part_du_plus_petit": round(ratio, 2)})
    return out


def assets_without_album(call, args):
    r = call("POST", "/search/metadata", {"isNotInAlbum": True, "size": int(args.get("size", 100)), "page": int(args.get("page", 1))})["assets"]
    return {"assets": [{k: i.get(k) for k in ("id", "originalFileName", "fileCreatedAt", "type")} for i in r["items"]],
            "pageSuivante": r.get("nextPage")}


def create_album(call, args):
    name = args.get("albumName")
    if not isinstance(name, str) or not name.strip():
        raise ValueError("albumName requis")
    body = {"albumName": name}
    if "description" in args:
        body["description"] = args["description"]
    if args.get("assetIds"):
        body["assetIds"] = _uuids(args["assetIds"])
    same = [a["id"] for a in call("GET", "/albums", {}) if _norm(a["albumName"]) == _norm(name)]
    preview = {"action": "créer un album", "albumName": name, "description": body.get("description"),
               "assets_ajoutes": len(body.get("assetIds", [])), "albums_existants_de_meme_nom": same}
    return _guarded("create_album", args, preview, same, lambda: call("POST", "/albums", body))


def update_album(call, args):
    aid = _uuid(args.get("id"))
    body = {k: args[k] for k in ("albumName", "description") if k in args}
    if not body or not all(isinstance(v, str) for v in body.values()) or not body.get("albumName", "x").strip():
        raise ValueError("albumName (non vide) ou description (texte) requis")
    a = call("GET", "/albums/{id}", {"id": aid})
    now = {"albumName": a["albumName"], "description": a.get("description")}
    preview = {"action": "modifier l'album", "id": aid, "avant": now, "apres": {**now, **body}}
    return _guarded("update_album", args, preview, now, lambda: call("PATCH", "/albums/{id}", {"id": aid, **body}))


def add_assets(call, args):
    aid, ids = _uuid(args.get("id")), _uuids(args.get("assetIds"))
    a = call("GET", "/albums/{id}", {"id": aid})
    have, complete = _album_assets(call, aid, a)
    todo = [i for i in ids if i not in have]
    names = {i: call("GET", "/assets/{id}", {"id": i}).get("originalFileName", "") for i in todo[:10]}
    preview = {"action": "ajouter des assets", "album": a["albumName"], "ajoutes": len(todo), "deja_dans_l_album": len(ids) - len(todo),
               "echantillon": _sample(todo, names), "liste_de_l_album_complete": complete}
    return _guarded("add_assets", args, preview, [aid, sorted(todo)], lambda: _bulk(call, "PUT", aid, todo) if todo else {"ok": 0})


def remove_assets(call, args):
    aid, ids = _uuid(args.get("id")), _uuids(args.get("assetIds"))
    a = call("GET", "/albums/{id}", {"id": aid})
    have, complete = _album_assets(call, aid, a)
    todo = [i for i in ids if i in have]
    preview = {"action": "retirer des assets de l'album (le lien seulement, les photos restent)", "album": a["albumName"],
               "retires": len(todo), "pas_dans_l_album": len(ids) - len(todo), "echantillon": _sample(todo, have),
               "liste_de_l_album_complete": complete}
    return _guarded("remove_assets", args, preview, [aid, sorted(todo)], lambda: _bulk(call, "DELETE", aid, todo) if todo else {"ok": 0})


def merge_albums(call, args):
    keep, dup, delete = _uuid(args.get("keepId")), _uuid(args.get("duplicateId")), args.get("deleteDuplicate") is True
    if keep == dup:
        raise ValueError("keepId et duplicateId sont le même album")
    ka, dn = call("GET", "/albums/{id}", {"id": keep}), call("GET", "/albums/{id}", {"id": dup})
    kept, kc = _album_assets(call, keep, ka)
    dups, dc = _album_assets(call, dup, dn)
    if delete and not (kc and dc):
        raise ValueError("liste d'assets incomplète (archivés ?) : suppression de l'album doublon refusée, fusion sans suppression possible")
    missing = [i for i in dups if i not in kept]
    preview = {"action": "fusionner", "garde": ka["albumName"], "doublon": dn["albumName"],
               "assets_communs": len(dups) - len(missing), "propres_au_garde": len(kept) - (len(dups) - len(missing)),
               "propres_au_doublon_ajoutes_au_garde": len(missing), "echantillon_ajoutes": _sample(missing, dups),
               "supprime": "l'objet album doublon « %s » (jamais ses photos)" % dn["albumName"] if delete else "rien (deleteDuplicate absent)",
               "listes_completes": kc and dc}

    def apply():
        res = _bulk(call, "PUT", keep, missing) if missing else {"ok": 0, "erreurs": []}
        out = {"ajoutes": res}
        if delete:
            now, _ = _album_assets(call, keep)
            if any(i not in now for i in dups):  # filet : l'album doublon ne part que si tout est dans le gardé
                raise RuntimeError("des assets du doublon manquent dans l'album gardé : album doublon conservé. " + str(res))
            call("DELETE", "/albums/{id}", {"id": dup})
            out["doublon_supprime"] = True
        return out

    return _guarded("merge_albums", args, preview, [keep, dup, sorted(kept), sorted(dups), delete], apply)


def _w(desc, props, req, fn):
    return (desc + TWO_STEP, _obj({**props, "confirm": CONFIRM}, req), fn, True)


# nom -> (description, schéma, fonction(call, args), écriture ?)
LOCAL = {
    "list_albums": ("Liste compacte des albums, triée par nom : id, nom, assets (nombre), debut, fin, partage. "
                    "`contains` : ne garde que les noms contenant ce texte (casse ignorée). Détail d'un album : get_album.",
                    _obj({"contains": {"type": "string"}}), list_albums, False),
    "find_duplicate_albums": ("Albums en doublon probables : même nom (casse et espaces ignorés) et, si `minOverlap` (0 à 1) est donné, "
                              "recouvrement d'assets (part du plus petit album). Lecture seule ; prépare merge_albums.",
                              _obj({"minOverlap": {"type": "number"}}), find_duplicate_albums, False),
    "assets_without_album": ("Photos et vidéos d'aucun album (page par page)", _obj({"size": {"type": "integer"}, "page": {"type": "integer"}}),
                             assets_without_album, False),
    "create_album": _w("Crée un album (nom, description, assets de départ facultatifs).",
                       {"albumName": {"type": "string"}, "description": {"type": "string"}, "assetIds": ASSET_IDS}, ["albumName"], create_album),
    "update_album": _w("Renomme un album ou change sa description.",
                       {"id": ALBUM_ID, "albumName": {"type": "string"}, "description": {"type": "string"}}, ["id"], update_album),
    "add_assets": _w("Ajoute des assets à un album (ceux qui y sont déjà sont ignorés).", {"id": ALBUM_ID, "assetIds": ASSET_IDS},
                     ["id", "assetIds"], add_assets),
    "remove_assets": _w("Retire des assets d'un album : seul le lien disparaît, les photos ne sont jamais supprimées.",
                        {"id": ALBUM_ID, "assetIds": ASSET_IDS}, ["id", "assetIds"], remove_assets),
    "merge_albums": _w("Fusionne un album doublon dans l'album gardé : ajoute au gardé les assets du doublon qui n'y sont pas. "
                       "`deleteDuplicate: true` supprime ensuite l'album doublon (l'objet album, jamais ses photos) ; à ne mettre "
                       "que si Sylvain l'a demandé explicitement.",
                       {"keepId": ALBUM_ID, "duplicateId": ALBUM_ID, "deleteDuplicate": {"type": "boolean"}}, ["keepId", "duplicateId"], merge_albums),
}


def handle(msg, call, write=False):
    """Une requête JSON-RPC ; renvoie la réponse, ou None pour une notification."""
    mid, method = msg.get("id"), msg.get("method")
    if mid is None:
        return None
    if method == "initialize":
        result = {
            "protocolVersion": (msg.get("params") or {}).get("protocolVersion", "2025-06-18"),
            "capabilities": {"tools": {}},
            "serverInfo": {"name": "immich-write" if write else "immich-readonly", "version": "2.0.0"},
        }
    elif method == "ping":
        result = {}
    elif method == "tools/list":
        tools = [(n, d, s) for n, (d, s, _, _) in TOOLS.items()]
        tools += [(n, d, s) for n, (d, s, _, w) in LOCAL.items() if write or not w]
        result = {"tools": [{"name": n, "description": d, "inputSchema": s} for n, d, s in tools]}
    elif method == "tools/call":
        params = msg.get("params") or {}
        name, args = params.get("name"), params.get("arguments") or {}
        if name in LOCAL:
            if LOCAL[name][3] and not write:  # refusé avant tout envoi
                text = "Écriture désactivée : serveur lancé sans IMMICH_MCP_WRITE=1 (entrée immich-ecriture du .mcp.json)."
                return {"jsonrpc": "2.0", "id": mid, "result": {"isError": True, "content": [{"type": "text", "text": text}]}}
        elif name not in TOOLS:
            return {"jsonrpc": "2.0", "id": mid, "error": {"code": -32602, "message": "outil inconnu : %s" % name}}
        try:
            out = LOCAL[name][2](call, args) if name in LOCAL else call(TOOLS[name][2], TOOLS[name][3], args)
            text = json.dumps(out, ensure_ascii=False)
            if len(text) > 100000:  # signalé, comme papra-mcp et grocy-mcp : jamais coupé en silence
                text = text[:100000] + " [... tronqué]"
            result = {"content": [{"type": "text", "text": text}]}
        except Exception as e:  # erreur d'outil : renvoyée au modèle, pas fatale
            result = {"isError": True, "content": [{"type": "text", "text": "Erreur Immich : %s" % e}]}
    else:
        return {"jsonrpc": "2.0", "id": mid, "error": {"code": -32601, "message": "méthode inconnue"}}
    return {"jsonrpc": "2.0", "id": mid, "result": result}


def main():
    base, key = os.environ["IMMICH_URL"], os.environ["IMMICH_API_KEY"]
    write = os.environ.get("IMMICH_MCP_WRITE") == "1"
    extra = {}
    if os.environ.get("IMMICH_PANGOLIN_TOKEN") and os.environ.get("IMMICH_PANGOLIN_TOKEN_ID"):
        extra = {
            "P-Access-Token-Id": os.environ["IMMICH_PANGOLIN_TOKEN_ID"],
            "P-Access-Token": os.environ["IMMICH_PANGOLIN_TOKEN"],
        }

    def call(method, path, args):
        return call_immich(method, path, args, base, key, extra, write)

    for line in sys.stdin:
        if line.strip():
            try:
                msg = json.loads(line)
            except ValueError:  # ligne illisible : ignorée, le serveur reste vivant
                continue
            try:
                reply = handle(msg, call, write) if isinstance(msg, dict) else None
            except Exception:  # params d'un autre type qu'un objet, etc. : ne pas tuer le serveur
                reply = {"jsonrpc": "2.0", "id": msg.get("id"), "error": {"code": -32600, "message": "requête invalide"}} if msg.get("id") is not None else None
            if reply:
                print(json.dumps(reply, ensure_ascii=False), flush=True)


if __name__ == "__main__":
    main()
