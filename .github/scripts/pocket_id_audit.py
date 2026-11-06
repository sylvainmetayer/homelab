#!/usr/bin/env python3
"""Audit de sécurité reproductible de Pocket ID (id.sylvain.cloud).

Lancé par `mise run audit-pocket-id` depuis le poste, après une montée de
version : mise met la clé admin (`pocket_id_static_api_key`) dans
l'environnement, jamais affichée. Trois parties :

- passif : découverte OIDC, JWKS, en-têtes, CORS, points d'accès exposés,
  configuration publique, version comparée aux avis de sécurité publiés ;
- sans compte : API admin, userinfo, token, introspection refusés ;
- flux complet : un groupe, deux clients et un utilisateur jetables
  (préfixe `pid-audit-`), connexion par code à usage unique, puis groupes,
  PKCE, redirect_uri piégées, rejeu de code, codes entre clients, refresh
  après retrait du groupe. Tout est supprimé à la fin, et les restes d'un
  passage interrompu au début.

Une rafale bornée (40 requêtes) sur l'API admin vérifie seulement qu'aucune
réponse ne fuit ; la limite de Traefik (50/s, rafale 300) est lue dans le
dépôt. Sortie : un tableau, et `--json` pour le rapport.
"""
import argparse
import base64
import hashlib
import http.client
import json
import os
import re
import secrets
import sys
import time
import urllib.parse
from pathlib import Path

BASE = "https://id.sylvain.cloud"
HOST = urllib.parse.urlsplit(BASE).hostname
PREFIX = "pid-audit-"
CALLBACK = "https://audit.invalid/callback"
REPO = Path(__file__).resolve().parents[2]
EVIL = "https://evil.example"
PRIVATE_JWK_FIELDS = {"d", "p", "q", "dp", "dq", "qi", "k"}

results = []


def redact(text):
    """Masque codes, jetons et secrets qu'une URL ou une réponse ferait passer dans le détail."""
    return re.sub(r"((?:code|token|secret|access_token|refresh_token|id_token)=)[^&\s]+", r"\1…", str(text))


def record(check, status, detail=""):
    detail = redact(detail)
    results.append({"check": check, "status": status, "detail": detail})
    print(f"{status:5} {check}" + (f" : {detail}" if detail else ""), flush=True)


def request(method, path, headers=None, body=None, host=HOST):
    """Une requête HTTPS sans suivre les redirections ; renvoie (statut, en-têtes, corps)."""
    conn = http.client.HTTPSConnection(host, timeout=20)
    hdrs = {"User-Agent": "pocket-id-audit"}
    hdrs.update(headers or {})
    if isinstance(body, (dict, list)):
        body = json.dumps(body)
        hdrs.setdefault("Content-Type", "application/json")
    conn.request(method, path, body=body, headers=hdrs)
    resp = conn.getresponse()
    data = resp.read()
    headers_out = {}
    for k, v in resp.getheaders():
        headers_out.setdefault(k.lower(), []).append(v)
    conn.close()
    return resp.status, headers_out, data


def header(hdrs, name):
    return (hdrs.get(name.lower()) or [""])[0]


def as_json(data):
    try:
        return json.loads(data)
    except ValueError:
        return None


def b64url_decode(part):
    return base64.urlsafe_b64decode(part + "=" * (-len(part) % 4))


def jwt_parts(token):
    """En-tête et charge d'un JWT, sans vérifier la signature."""
    head, payload, _ = token.split(".")
    return json.loads(b64url_decode(head)), json.loads(b64url_decode(payload))


def pkce_pair():
    verifier = secrets.token_urlsafe(48)
    challenge = base64.urlsafe_b64encode(hashlib.sha256(verifier.encode()).digest()).rstrip(b"=").decode()
    return verifier, challenge


def version_tuple(text):
    return tuple(int(x) for x in re.findall(r"\d+", text)[:3])


def in_range(version, spec):
    """`spec` au format des avis GitHub : « >= 1.0.0, < 2.4.0 », « <= 2.3.1 »."""
    for clause in [c.strip() for c in spec.split(",") if c.strip()]:
        op, ver = re.match(r"(>=|<=|>|<|=)?\s*v?([\d.]+)", clause).groups()
        a, b = version, version_tuple(ver)
        ok = {">=": a >= b, "<=": a <= b, ">": a > b, "<": a < b}.get(op or "=", a == b)
        if not ok:
            return False
    return True


# --- Passif -------------------------------------------------------------

def check_discovery():
    status, _, data = request("GET", "/.well-known/openid-configuration")
    doc = as_json(data) or {}
    if status != 200:
        record("découverte OIDC", "FAIL", f"HTTP {status}")
        return doc
    record("découverte : issuer", "PASS" if doc.get("issuer") == BASE else "FAIL", doc.get("issuer", ""))
    methods = doc.get("code_challenge_methods_supported", [])
    record("découverte : PKCE S256 seul", "PASS" if methods == ["S256"] else "WARN", str(methods))
    algs = doc.get("id_token_signing_alg_values_supported", [])
    record("découverte : pas d'alg none", "PASS" if "none" not in algs else "FAIL", str(algs))
    implicit = [t for t in doc.get("response_types_supported", []) if "token" in t.split()]
    record("découverte : pas de flux implicite", "PASS" if not implicit else "WARN", str(implicit or doc.get("response_types_supported")))
    record("découverte : types d'accord", "INFO", str(doc.get("grant_types_supported")))
    record("découverte : auth au token", "INFO", str(doc.get("token_endpoint_auth_methods_supported")))
    return doc


def check_jwks(doc):
    status, _, data = request("GET", urllib.parse.urlsplit(doc.get("jwks_uri", BASE + "/.well-known/jwks.json")).path)
    keys = (as_json(data) or {}).get("keys", [])
    if status != 200 or not keys:
        record("JWKS", "FAIL", f"HTTP {status}, {len(keys)} clé(s)")
        return
    leaked = [k.get("kid") for k in keys if PRIVATE_JWK_FIELDS & set(k)]
    record("JWKS : aucune partie privée", "FAIL" if leaked else "PASS", str(leaked) if leaked else f"{len(keys)} clé(s)")
    for key in keys:
        if key.get("kty") == "RSA":
            bits = len(b64url_decode(key["n"])) * 8
            record(f"JWKS : taille RSA ({key.get('kid')})", "PASS" if bits >= 2048 else "FAIL", f"{bits} bits")
        else:
            record(f"JWKS : clé {key.get('kty')} ({key.get('kid')})", "INFO", key.get("crv", key.get("alg", "")))


def check_headers():
    for path in ("/", "/api/application-configuration"):
        status, hdrs, _ = request("GET", path)
        hsts = header(hdrs, "strict-transport-security")
        age = int((re.search(r"max-age=(\d+)", hsts) or [0, 0])[1])
        record(f"en-têtes {path} : HSTS ≥ 180 j", "PASS" if age >= 15552000 else "FAIL", hsts or "absent")
        record(f"en-têtes {path} : nosniff", "PASS" if header(hdrs, "x-content-type-options") == "nosniff" else "WARN")
        csp = header(hdrs, "content-security-policy")
        framing = header(hdrs, "x-frame-options") or ("frame-ancestors" in csp and "frame-ancestors")
        record(f"en-têtes {path} : anti-iframe", "PASS" if framing else "WARN", framing or "ni X-Frame-Options ni frame-ancestors")
        if path == "/":
            record("en-têtes / : CSP", "PASS" if csp else "WARN", csp[:120] or "absente")
            record("en-têtes / : Referrer-Policy", "PASS" if header(hdrs, "referrer-policy") else "WARN", header(hdrs, "referrer-policy"))
        leak = [h for h in ("server", "x-powered-by") if re.search(r"\d", header(hdrs, h))]
        record(f"en-têtes {path} : pas de version", "PASS" if not leak else "WARN", ", ".join(f"{h}: {header(hdrs, h)}" for h in leak))


def check_cors():
    _, hdrs, _ = request("GET", "/api/users/me", {"Origin": EVIL})
    acao = header(hdrs, "access-control-allow-origin")
    bad = acao in ("*", EVIL) and header(hdrs, "access-control-allow-credentials") == "true"
    record("CORS : origine étrangère refusée", "FAIL" if bad else ("WARN" if acao else "PASS"), acao or "aucun ACAO")


def check_exposed():
    for path in ("/metrics", "/debug/pprof/", "/api/swagger/index.html", "/swagger/index.html", "/.env", "/api/test/reset", "/.git/config"):
        status, hdrs, data = request("GET", path)
        # Le frontal SvelteKit répond 200 (sa page) à tout chemin inconnu : seul compte un contenu qui n'est pas cette page.
        # Un Swagger UI ou un index pprof est aussi du HTML : reconnu à son contenu, jamais pris pour le frontal.
        spa = b"<!doctype html" in data[:200].lower() and not re.search(rb"swagger|openapi|redoc|pprof", data, re.I)
        exposed = status == 200 and not spa
        record(f"exposé : {path}", "FAIL" if exposed else "PASS", f"HTTP {status}" + (" (page du frontal)" if spa else ""))


def check_public_config():
    status, _, data = request("GET", "/api/application-configuration")
    cfg = {item["key"]: item["value"] for item in (as_json(data) or []) if isinstance(item, dict)}
    if status != 200:
        record("configuration publique", "FAIL", f"HTTP {status}")
        return cfg
    signups = cfg.get("allowUserSignups")
    record("config : inscription libre fermée", "PASS" if signups == "disabled" else "FAIL", f"allowUserSignups={signups}")
    unauth = cfg.get("emailOneTimeAccessAsUnauthenticatedEnabled")
    record("config : code par e-mail sans compte connecté", "PASS" if unauth in ("false", None) else "WARN", f"={unauth}")
    secret_like = [k for k in cfg if re.search(r"password|secret|token|key", k, re.I)]
    record("config : aucun secret public", "FAIL" if secret_like else "PASS", ", ".join(secret_like))
    return cfg


def check_version():
    compose = (REPO / "ansible/roles/pocket_id/templates/compose.yaml").read_text()
    tag = re.search(r"pocket-id/pocket-id:v([\d.]+)", compose).group(1)
    version = version_tuple(tag)
    record("version déployée", "INFO", tag)
    status, _, data = request("GET", "/repos/pocket-id/pocket-id/security-advisories?per_page=100&state=published",
                              {"Accept": "application/vnd.github+json"}, host="api.github.com")
    advisories = as_json(data)
    if status != 200 or not isinstance(advisories, list):
        record("avis de sécurité", "SKIP", f"API GitHub HTTP {status}")
        return
    hits = []
    for adv in advisories:
        for vuln in adv.get("vulnerabilities") or []:
            spec = vuln.get("vulnerable_version_range") or ""
            # Une plage ouverte (« >= v2.2.0 ») est bornée par patched_versions.
            patched = [version_tuple(p) for p in (vuln.get("patched_versions") or "").split(",") if re.search(r"\d", p)]
            if spec and in_range(version, spec) and not any(version >= p for p in patched):
                hits.append(f"{adv['ghsa_id']} ({adv.get('severity')}, {spec})")
    record("avis de sécurité publiés", "FAIL" if hits else "PASS", "; ".join(hits) or f"{len(advisories)} avis, aucun ne touche v{tag}")


# --- Sans compte ----------------------------------------------------------

def check_unauthenticated(api_key_len):
    for path in ("/api/users", "/api/oidc/clients", "/api/application-configuration/all", "/api/audit-logs/all"):
        status, _, _ = request("GET", path)
        record(f"sans clé : {path}", "PASS" if status in (401, 403) else "FAIL", f"HTTP {status}")
        status, _, _ = request("GET", path, {"X-API-KEY": "x" * max(api_key_len, 32)})
        record(f"clé fausse : {path}", "PASS" if status in (401, 403) else "FAIL", f"HTTP {status}")
    status, _, _ = request("GET", "/api/oidc/userinfo")
    record("userinfo sans jeton", "PASS" if status == 401 else "FAIL", f"HTTP {status}")
    forged = ".".join(base64.urlsafe_b64encode(json.dumps(p).encode()).rstrip(b"=").decode()
                      for p in ({"alg": "none", "typ": "JWT"}, {"sub": "admin", "iss": BASE, "exp": int(time.time()) + 600})) + "."
    status, _, _ = request("GET", "/api/oidc/userinfo", {"Authorization": f"Bearer {forged}"})
    record("userinfo avec JWT alg=none forgé", "PASS" if status == 401 else "FAIL", f"HTTP {status}")
    status, _, data = request("POST", "/api/oidc/token", {"Content-Type": "application/x-www-form-urlencoded"},
                              urllib.parse.urlencode({"grant_type": "client_credentials", "client_id": "homebox", "client_secret": "wrong-" + secrets.token_hex(8)}))
    record("token : client réel, secret faux", "PASS" if status in (400, 401) else "FAIL", f"HTTP {status} {(as_json(data) or {}).get('error', '')}")
    status, _, _ = request("POST", "/api/oidc/introspect", {"Content-Type": "application/x-www-form-urlencoded"}, "token=abc")
    record("introspection sans client", "PASS" if status in (400, 401) else "FAIL", f"HTTP {status}")
    status, _, data = request("POST", "/api/oidc/device/authorize", {"Content-Type": "application/x-www-form-urlencoded"}, "client_id=homebox")
    record("device flow : client confidentiel sans secret", "PASS" if status in (400, 401) else "FAIL", f"HTTP {status} {(as_json(data) or {}).get('error', '')}")


def check_burst():
    codes = {}
    for _ in range(40):
        status, _, _ = request("GET", "/api/users", {"X-API-KEY": secrets.token_hex(24)})
        codes[status] = codes.get(status, 0) + 1
    ok = set(codes) <= {401, 403, 429}
    record("rafale 40 clés fausses : aucune ne passe", "PASS" if ok else "FAIL", str(codes))
    defaults = (REPO / "ansible/roles/pangolin/defaults/main.yml").read_text()
    avg = re.search(r"pangolin_idp_rate_average:\s*(\d+)", defaults).group(1)
    burst = re.search(r"pangolin_idp_rate_burst:\s*(\d+)", defaults).group(1)
    record("limite Traefik de id.sylvain.cloud", "INFO", f"{avg}/s, rafale {burst} par IP (CrowdSec en plus)")


# --- Flux complet ---------------------------------------------------------

class Admin:
    def __init__(self, key):
        self.key = key

    def call(self, method, path, body=None):
        status, _, data = request(method, path, {"X-API-KEY": self.key}, body)
        if status >= 400:
            raise RuntimeError(f"{method} {path} : HTTP {status} {data[:200]!r}")
        return as_json(data) if data else None

    def cleanup(self, only=None):
        """Supprime les objets pid-audit- ; `only` restreint aux identifiants donnés."""
        for kind, path, field in (("clients", "/api/oidc/clients", "name"), ("users", "/api/users", "username"), ("groups", "/api/user-groups", "name")):
            page = self.call("GET", f"{path}?search={PREFIX}&pagination%5Blimit%5D=100") or {}
            for item in page.get("data", []):
                if str(item.get(field, "")).startswith(PREFIX) and (only is None or item["id"] in only):
                    self.call("DELETE", f"{path}/{item['id']}")


class Session:
    def __init__(self):
        self.cookies = {}

    def call(self, method, path, body=None, extra=None):
        hdrs = {"Origin": BASE, "Sec-Fetch-Site": "same-origin"}
        if self.cookies:
            hdrs["Cookie"] = "; ".join(f"{k}={v}" for k, v in self.cookies.items())
        hdrs.update(extra or {})
        status, out, data = request(method, path, hdrs, body)
        for raw in out.get("set-cookie", []):
            name, _, rest = raw.partition("=")
            self.cookies[name] = rest.split(";", 1)[0]
        return status, out, data


def authorize(sess, client_id, redirect_uri, scope="openid profile email groups", pkce=True, method="S256", extra=None):
    """Va jusqu'au code ou jusqu'au refus. Renvoie (code|None, Location finale, vérificateur, nonce, state)."""
    verifier, challenge = pkce_pair()
    nonce, state = secrets.token_urlsafe(16), secrets.token_urlsafe(16)
    params = {"client_id": client_id, "redirect_uri": redirect_uri, "response_type": "code", "scope": scope, "state": state, "nonce": nonce}
    if pkce:
        params.update(code_challenge=challenge if method == "S256" else verifier, code_challenge_method=method)
    params.update(extra or {})
    path = "/authorize?" + urllib.parse.urlencode(params)
    location = ""
    for _ in range(8):
        status, hdrs, _ = sess.call("GET", path)
        location = header(hdrs, "location")
        if status not in (301, 302, 303) or not location:
            return None, f"HTTP {status}", verifier, nonce, state
        target = urllib.parse.urlsplit(location)
        query = urllib.parse.parse_qs(target.query)
        if target.netloc and target.netloc != HOST:
            return (query.get("code") or [None])[0], location, verifier, nonce, state
        if target.path == "/interaction" and "interaction" in query:
            interaction = query["interaction"][0]
            for _ in range(4):
                st, _, data = sess.call("GET", f"/api/oidc/interactions/{interaction}")
                info = as_json(data) or {}
                step = info.get("currentStep") or (info.get("requiredSteps") or ["consent"])[0]
                st, _, data = sess.call("POST", f"/api/oidc/interactions/{interaction}/complete", {"step": step, "scopes": info.get("scopes", [])})
                done = as_json(data) or {}
                if st >= 400:
                    return None, f"interaction {step} : HTTP {st} {data[:120]!r}", verifier, nonce, state
                if done.get("redirectUrl"):
                    location = done["redirectUrl"]
                    break
            target = urllib.parse.urlsplit(location)
            if target.netloc and target.netloc != HOST:
                query = urllib.parse.parse_qs(target.query)
                return (query.get("code") or [None])[0], location, verifier, nonce, state
            path = target.path + ("?" + target.query if target.query else "")
            continue
        return None, location, verifier, nonce, state
    return None, location, verifier, nonce, state


def token(client_id, secret, **form):
    body = urllib.parse.urlencode({"client_id": client_id, "client_secret": secret, **form})
    status, _, data = request("POST", "/api/oidc/token", {"Content-Type": "application/x-www-form-urlencoded"}, body)
    return status, as_json(data) or {}


def check_refused(label, code, where, cid, secret, **form):
    """Échange refusé attendu ; sans code obtenu le contrôle n'a rien vérifié, il ne passe pas à vide."""
    if not code:
        record(label, "WARN", "aucun code obtenu, non vérifié : " + where[:80])
        return
    status, tok = token(cid, secret, grant_type="authorization_code", code=code, **form)
    record(label, "PASS" if status >= 400 else "FAIL", f"HTTP {status} {tok.get('error', '')}")


def userinfo(access_token):
    status, _, _ = request("GET", "/api/oidc/userinfo", {"Authorization": f"Bearer {access_token}"})
    return status


def check_flow(admin):
    run = PREFIX + time.strftime("%Y%m%d%H%M%S")
    created = set()
    try:
        group = admin.call("POST", "/api/user-groups", {"name": run, "friendlyName": run})
        created.add(group["id"])
        clients = {}
        for suffix in ("a", "b"):
            client = admin.call("POST", "/api/oidc/clients", {
                "id": f"{run}-{suffix}", "name": f"{run}-{suffix}", "callbackURLs": [CALLBACK],
                "isPublic": False, "pkceEnabled": True, "isGroupRestricted": True,
            })
            created.add(client["id"])
            admin.call("PUT", f"/api/oidc/clients/{client['id']}/allowed-user-groups", {"userGroupIds": [group["id"]]})
            secret = admin.call("POST", f"/api/oidc/clients/{client['id']}/secrets", {})
            clients[suffix] = (client["id"], secret.get("secret") or secret.get("value"))
        user = admin.call("POST", "/api/users", {
            "username": run, "email": f"{run}@example.invalid", "emailVerified": True,
            "firstName": "Audit", "lastName": "Pocket ID", "displayName": run, "isAdmin": False, "userGroupIds": [],
        })
        created.add(user["id"])
        login = admin.call("POST", f"/api/users/{user['id']}/one-time-access-token", {})
        sess = Session()
        status, hdrs, _ = sess.call("POST", f"/api/one-time-access-token/{login['token']}")
        record("connexion par code à usage unique", "PASS" if status == 200 and sess.cookies else "FAIL", f"HTTP {status}")
        for raw in hdrs.get("set-cookie", []):
            name = raw.split("=", 1)[0]
            flags = raw.lower()
            missing = [f for f in ("secure", "httponly", "samesite") if f not in flags]
            record(f"cookie {name} : Secure, HttpOnly, SameSite", "WARN" if missing else "PASS", "manque " + ", ".join(missing) if missing else "")

        (cid_a, sec_a), (cid_b, sec_b) = clients["a"], clients["b"]

        code, where, *_ = authorize(sess, cid_a, CALLBACK)
        record("groupe : hors du groupe autorisé, pas de code", "PASS" if not code else "FAIL", where[:120])

        admin.call("PUT", f"/api/users/{user['id']}/user-groups", {"userGroupIds": [group["id"]]})
        code, where, verifier, nonce, state = authorize(sess, cid_a, CALLBACK, scope="openid profile email groups offline_access")
        record("flux : code délivré au membre du groupe", "PASS" if code else "FAIL", where[:120])
        if not code:
            return
        returned_state = urllib.parse.parse_qs(urllib.parse.urlsplit(where).query).get("state", [""])[0]
        record("flux : state renvoyé", "PASS" if returned_state == state else "FAIL")

        check_refused("PKCE : mauvais vérificateur refusé", code, where, cid_a, sec_a, redirect_uri=CALLBACK, code_verifier="faux-" + secrets.token_urlsafe(40))

        code, where, verifier, nonce, state = authorize(sess, cid_a, CALLBACK, scope="openid profile email groups offline_access")
        check_refused("code d'un client échangé par un autre", code, where, cid_b, sec_b, redirect_uri=CALLBACK, code_verifier=verifier)

        code, where, verifier, nonce, state = authorize(sess, cid_a, CALLBACK, scope="openid profile email groups offline_access")
        check_refused("token : redirect_uri différente refusée", code, where, cid_a, sec_a, redirect_uri=CALLBACK + "/autre", code_verifier=verifier)

        code, where, verifier, nonce, state = authorize(sess, cid_a, CALLBACK, scope="openid profile email groups offline_access")
        check_refused("token : secret client faux refusé", code, where, cid_a, "faux-" + secrets.token_hex(16), redirect_uri=CALLBACK, code_verifier=verifier)

        code, where, verifier, nonce, state = authorize(sess, cid_a, CALLBACK, scope="openid profile email groups offline_access")
        if not code:
            record("flux : échange du code", "FAIL", "aucun code obtenu : " + where[:100])
            return
        status, tok = token(cid_a, sec_a, grant_type="authorization_code", code=code, redirect_uri=CALLBACK, code_verifier=verifier, audience=EVIL, resource=EVIL)
        record("flux : échange du code", "PASS" if status == 200 else "FAIL", f"HTTP {status} {tok.get('error', '')}")
        if status != 200:
            return
        head, claims = jwt_parts(tok["id_token"])
        record("id_token : algorithme signé", "PASS" if head.get("alg") not in (None, "none") else "FAIL", head.get("alg", ""))
        aud = claims.get("aud")
        aud = aud if isinstance(aud, list) else [aud]
        record("id_token : iss, aud, nonce", "PASS" if claims.get("iss") == BASE and aud == [cid_a] and claims.get("nonce") == nonce else "FAIL",
               f"iss={claims.get('iss')} aud={aud} nonce={'ok' if claims.get('nonce') == nonce else 'KO'}")
        record("id_token : groupes", "PASS" if group["name"] in (claims.get("groups") or []) else "WARN", str(claims.get("groups")))
        try:
            _, access_claims = jwt_parts(tok["access_token"])
            access_aud = access_claims.get("aud")
            record("access token : audience non détournable", "FAIL" if EVIL in (access_aud if isinstance(access_aud, list) else [access_aud]) else "PASS", str(access_aud))
            record("access token : durée", "INFO", f"{(access_claims.get('exp', 0) - access_claims.get('iat', 0)) // 60} min")
        except ValueError:
            record("access token : opaque", "INFO", f"expires_in={tok.get('expires_in')}")
        record("userinfo avec l'access token", "PASS" if userinfo(tok["access_token"]) == 200 else "FAIL")

        status, again = token(cid_a, sec_a, grant_type="authorization_code", code=code, redirect_uri=CALLBACK, code_verifier=verifier)
        record("rejeu du code refusé", "PASS" if status >= 400 else "FAIL", f"HTTP {status} {again.get('error', '')}")
        revoked = userinfo(tok["access_token"])
        record("rejeu : jetons du premier échange révoqués", "PASS" if revoked == 401 else "WARN", f"userinfo HTTP {revoked}")

        refresh = tok.get("refresh_token")
        if refresh:
            code, where, verifier, nonce, state = authorize(sess, cid_a, CALLBACK, scope="openid profile email groups offline_access")
            status, tok2 = token(cid_a, sec_a, grant_type="authorization_code", code=code, redirect_uri=CALLBACK, code_verifier=verifier) if code else (0, {})
            r1 = tok2.get("refresh_token")
            if r1:
                status, rot = token(cid_a, sec_a, grant_type="refresh_token", refresh_token=r1)
                record("refresh : fonctionne", "PASS" if status == 200 else "WARN", f"HTTP {status}")
                # Pocket ID garde l'ancien jeton une minute après la rotation (refreshTokenGracePeriod,
                # rafraîchissements parallèles) : refusé seulement au-delà.
                time.sleep(65)
                status, reuse = token(cid_a, sec_a, grant_type="refresh_token", refresh_token=r1)
                record("refresh : ancien jeton refusé 65 s après rotation", "PASS" if status >= 400 else "FAIL", f"HTTP {status} {reuse.get('error', '')}")
            else:
                record("refresh : rotation", "WARN", "pas de refresh_token au second échange, non vérifié")
            # Chaîne neuve : la réutilisation de r1 a pu révoquer toute la précédente, le refus ne prouverait alors rien sur le groupe.
            code, where, verifier, nonce, state = authorize(sess, cid_a, CALLBACK, scope="openid profile email groups offline_access")
            status, tok3 = token(cid_a, sec_a, grant_type="authorization_code", code=code, redirect_uri=CALLBACK, code_verifier=verifier) if code else (0, {})
            r3 = tok3.get("refresh_token")
            if r3:
                admin.call("PUT", f"/api/users/{user['id']}/user-groups", {"userGroupIds": []})
                status, after = token(cid_a, sec_a, grant_type="refresh_token", refresh_token=r3)
                record("refresh : refusé après retrait du groupe", "PASS" if status >= 400 else "FAIL", f"HTTP {status} {after.get('error', '')}")
                admin.call("PUT", f"/api/users/{user['id']}/user-groups", {"userGroupIds": [group["id"]]})
            else:
                record("refresh : refusé après retrait du groupe", "WARN", "aucun refresh_token obtenu, non vérifié")
        else:
            record("refresh", "SKIP", "aucun refresh_token délivré (offline_access)")

        code, where, *_ = authorize(sess, cid_a, CALLBACK, pkce=False)
        record("PKCE : demande sans code_challenge refusée", "PASS" if not code else "FAIL", where[:120])
        code, where, *_ = authorize(sess, cid_a, CALLBACK, method="plain")
        # Activée en dur en v2.19.1 (EnablePKCEPlainChallengeMethod) : rien à régler ici, les applis envoient S256.
        record("PKCE : méthode plain refusée", "PASS" if not code else "WARN", "acceptée (en dur dans Pocket ID)" if code else where[:120])
        code, where, *_ = authorize(sess, "pid-audit-inconnu", CALLBACK)
        record("client inconnu : pas de code", "PASS" if not code else "FAIL", where[:120])

        for variant in ("https://evil.example/callback", "https://audit.invalid.evil.example/callback", "https://audit.invalid@evil.example/callback",
                        "https://evil.example\\@audit.invalid/callback", CALLBACK.replace("https://", "http://", 1), "https://AUDIT.invalid/callback",
                        "https://audit.invalid/callback/autre", "https://audit.invalid/callback?x=1", "https://audit.invalid/callback/",
                        "https://audit.invalid/callback/../evil", "https://audit.invalid:8443/callback"):
            code, where, *_ = authorize(sess, cid_a, variant)
            parts = urllib.parse.urlsplit(where)
            target = parts.hostname or ""  # déjà en minuscules : la casse d'un hôte ne compte pas
            same = target == "audit.invalid" and parts.scheme == "https" and parts.port is None and parts.path == "/callback"
            if target not in ("", HOST) and not same:
                status = "FAIL"  # code ou erreur envoyés vers un autre hôte ou chemin
            else:
                status = "INFO" if code else "PASS"  # code vers le même hôte (casse différente) : équivalent
            record(f"redirect_uri piégée : {variant}", status, "code délivré au même hôte" if code else where[:100])
    finally:
        try:
            admin.cleanup(only=created)
            record("nettoyage des objets de test", "PASS")
        except Exception as exc:
            record("nettoyage des objets de test", "FAIL", f"à supprimer à la main (pid-audit-*) : {exc}")


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--json", help="écrit les résultats dans ce fichier")
    parser.add_argument("--no-flow", action="store_true", help="sans le flux complet (pas de clé admin)")
    args = parser.parse_args()
    key = os.environ.get("pocket_id_static_api_key", "")

    def guarded(fn, *a):
        """Une erreur réseau ou une réponse inattendue devient un FAIL : le tableau et le JSON sortent quand même."""
        try:
            return fn(*a)
        except Exception as exc:
            record(fn.__name__, "FAIL", f"{type(exc).__name__}: {exc}")

    doc = guarded(check_discovery) or {}
    guarded(check_jwks, doc)
    for fn in (check_headers, check_cors, check_exposed, check_public_config, check_version):
        guarded(fn)
    guarded(check_unauthenticated, len(key))
    guarded(check_burst)
    if args.no_flow or not key:
        record("flux complet", "SKIP", "pas de clé admin" if not key else "--no-flow")
    else:
        admin = Admin(key)
        guarded(admin.cleanup)
        guarded(check_flow, admin)

    counts = {}
    for r in results:
        counts[r["status"]] = counts.get(r["status"], 0) + 1
    print("\n" + ", ".join(f"{k} {v}" for k, v in sorted(counts.items())))
    if args.json:
        # Chemin donné par la personne qui lance l'audit sur son poste.
        report = json.dumps({"date": time.strftime("%Y-%m-%dT%H:%M:%S%z"), "results": results}, ensure_ascii=False, indent=1)
        Path(args.json).write_text(report)  # NOSONAR
    return 1 if counts.get("FAIL") else 0


if __name__ == "__main__":
    sys.exit(main())
