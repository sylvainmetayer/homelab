#!/usr/bin/env python3
"""Rotation de la consumer key OVH de Tofu (docs/runbooks/rotation-des-secrets.md, « OVH »).

Trois sous-commandes, sur l'application de OVH_APPLICATION_KEY :
  list          les identifiants (credentials) de l'application : id, état,
                création, dernière utilisation, expiration, IP autorisées,
                règles ; `*` devant celui de OVH_CONSUMER_KEY ;
  renew         demande un identifiant aux règles de ACCESS_RULES, restreint
                aux IP de --allowed-ip (défaut : home_ip), range la nouvelle
                consumer key dans le fichier SOPS racine par l'entrée standard
                de `sops set`, puis affiche l'URL de validation à ouvrir ;
  revoke <id>   supprime un identifiant, après confirmation ; refuse celui en
                cours sans --force-current.

Les identifiants viennent de l'environnement que mise charge depuis
secrets/secrets.sops.yaml (OVH_APPLICATION_KEY, OVH_APPLICATION_SECRET,
OVH_CONSUMER_KEY, OVH_CLOUD_PROJECT_ID, home_ip). Aucun secret n'est affiché,
écrit sur disque ni passé en argument : la nouvelle consumer key ne quitte la
réponse de l'API que vers l'entrée standard de sops, et tout message (erreur
d'API, de sops) passe par redact() avant d'être affiché.

Usage (depuis la racine du dépôt) :
  mise exec -- python3 -I .github/scripts/ovh_credentials.py list
"""

import argparse
import hashlib
import http.client
import json
import os
import shutil
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
ENDPOINT = "https://eu.api.ovh.com/1.0"
SOPS_FILE = "secrets/secrets.sops.yaml"
SOPS_KEY = '["OVH_CONSUMER_KEY"]'
ENV_KEYS = ("OVH_APPLICATION_KEY", "OVH_APPLICATION_SECRET", "OVH_CONSUMER_KEY")
TIMEOUT = 30
MAX_BYTES = 4 * 1024 * 1024

# Les zones qu'écrivent les modules du fichier racine (tofu/dns, et
# var.domain_zone de ref, site, 1y, planning) ; test_ovh_credentials.py
# échoue si un module en touche une autre.
ZONES = ("sylvain.cloud", "sylvain.dev", "sylvainmetayer.fr", "metayer.dev")
WRITE = ("GET", "POST", "PUT", "DELETE")


def access_rules(project):
    """Les règles du jeton de Tofu : rien d'autre que ce que ses modules appellent."""
    rules = []
    for zone in ZONES:  # ovh_domain_zone_record, ovh_domain_zone_redirection (+ refresh)
        rules += [{"method": "GET", "path": f"/domain/zone/{zone}"}]
        rules += [{"method": m, "path": f"/domain/zone/{zone}/*"} for m in WRITE]
    # tofu/s3_state, tofu/keepass_backup : buckets, utilisateurs S3, leurs clés et politiques.
    rules += [{"method": "GET", "path": f"/cloud/project/{project}"}]
    rules += [{"method": m, "path": f"/cloud/project/{project}/*"} for m in WRITE]
    # Ce script, à la rotation suivante : lister et révoquer (pas de PUT, pas de POST).
    rules += [
        {"method": "GET", "path": "/auth/currentCredential"},
        {"method": "GET", "path": "/me/api/credential"},
        {"method": "GET", "path": "/me/api/credential/*"},
        {"method": "DELETE", "path": "/me/api/credential/*"},
    ]
    return rules


class OvhError(Exception):
    """Erreur d'API ou de sops ; le message est déjà passé par redact()."""


def redact(text, secrets):
    for secret in secrets:
        if secret:
            text = text.replace(secret, "***")
    return text


def signature(secret, consumer, method, url, body, timestamp):
    """$1$ + SHA-1 de « secret+consumer+méthode+url+corps+horodatage » (protocole de l'API OVH)."""
    payload = "+".join((secret, consumer, method, url, body, str(timestamp)))
    return "$1$" + hashlib.sha1(payload.encode()).hexdigest()  # NOSONAR SHA-1 imposé par le protocole OVH


class _NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


# Aucune redirection suivie : urllib renverrait les en-têtes signés à la cible.
_OPENER = urllib.request.build_opener(_NoRedirect)


class Client:
    def __init__(self, application_key, application_secret, consumer_key, endpoint=ENDPOINT, clock=time.time):
        self.endpoint = endpoint.rstrip("/")
        self.application_key = application_key
        self.application_secret = application_secret
        self.consumer_key = consumer_key
        self.clock = clock
        self.secrets = [application_secret, consumer_key]

    def call(self, method, path, body=None, signed=True):
        url = self.endpoint + path
        data = "" if body is None else json.dumps(body, separators=(",", ":"))
        headers = {"X-Ovh-Application": self.application_key, "Accept": "application/json", "User-Agent": "homelab-ovh-credentials"}
        if data:
            headers["Content-Type"] = "application/json"
        if signed:
            timestamp = int(self.clock())
            headers["X-Ovh-Consumer"] = self.consumer_key
            headers["X-Ovh-Timestamp"] = str(timestamp)
            headers["X-Ovh-Signature"] = signature(self.application_secret, self.consumer_key, method, url, data, timestamp)
        if not url.startswith(("https://", "http://127.0.0.1:")):
            raise OvhError("schéma d'URL refusé")
        request = urllib.request.Request(url, data=data.encode() or None, headers=headers, method=method)  # NOSONAR schéma vérifié juste au-dessus
        try:
            with _OPENER.open(request, timeout=TIMEOUT) as response:  # NOSONAR schéma vérifié, aucune redirection suivie
                raw = response.read(MAX_BYTES + 1)
        except urllib.error.HTTPError as error:
            raise OvhError(redact(f"{method} {path} : HTTP {error.code} {_api_message(error)}", self.secrets)) from None
        # Sa classe seule : le message d'une URLError peut citer la requête.
        except (OSError, http.client.HTTPException) as error:
            raise OvhError(f"{method} {path} : {type(error).__name__}") from None
        if len(raw) > MAX_BYTES:
            raise OvhError(f"{method} {path} : réponse trop grosse")
        try:
            return json.loads(raw) if raw.strip() else None
        except ValueError:
            raise OvhError(f"{method} {path} : réponse illisible") from None


def _api_message(error):
    """errorCode et message du corps d'erreur OVH, rien d'autre."""
    try:
        body = json.loads(error.read(65536))
        return f"{body.get('errorCode', '')} {body.get('message', '')}".strip()
    except (ValueError, AttributeError, OSError):
        return ""


def current_id(client):
    return client.call("GET", "/auth/currentCredential").get("credentialId")


def cmd_list(client, out):
    current = client.call("GET", "/auth/currentCredential")
    ids = client.call("GET", f"/me/api/credential?applicationId={int(current['applicationId'])}")
    for credential_id in sorted(ids):
        c = client.call("GET", f"/me/api/credential/{int(credential_id)}")
        mark = "*" if credential_id == current["credentialId"] else " "
        out(
            f"{mark} {credential_id} {c.get('status')} création {c.get('creation')} "
            f"dernier usage {c.get('lastUse')} expiration {c.get('expiration')} "
            f"IP {','.join(c.get('allowedIPs') or []) or 'toutes'}"
        )
        for rule in c.get("rules") or []:
            out(f"      {rule.get('method')} {rule.get('path')}")
    out("* : l'identifiant de OVH_CONSUMER_KEY (en cours)")
    return 0


def cmd_renew(client, allowed_ips, project, sops, out, run=subprocess.run):
    body = {"accessRules": access_rules(project), "allowedIPs": allowed_ips}
    out(f"Demande d'un identifiant : {len(body['accessRules'])} règles, IP {', '.join(allowed_ips)}")
    for rule in body["accessRules"]:
        out(f"  {rule['method']} {rule['path']}")
    # POST /auth/credential ne se signe pas : la seule clé d'application suffit.
    answer = client.call("POST", "/auth/credential", body, signed=False)
    consumer_key = answer.get("consumerKey") or ""
    url = answer.get("validationUrl") or ""
    secrets = client.secrets + [consumer_key]
    if not consumer_key or not url:
        raise OvhError("réponse sans consumerKey ni validationUrl")
    result = run(
        [sops, "set", "--value-stdin", SOPS_FILE, SOPS_KEY],
        input=json.dumps(consumer_key),
        cwd=ROOT,
        capture_output=True,
        text=True,
        check=False,
    )
    if result.returncode != 0:
        # L'URL n'est pas montrée : non validé, l'identifiant expire seul.
        detail = redact((result.stderr or "").strip(), secrets)
        raise OvhError(f"sops set a échoué ({result.returncode}) : {detail}\nNe rien valider ; relancer renew.")
    out(f"Nouvelle consumer key rangée dans {SOPS_FILE} (OVH_CONSUMER_KEY).")
    out("Suite, dans cet ordre (docs/runbooks/rotation-des-secrets.md, « OVH ») :")
    out(f"  1. ouvrir et valider (compte OVH, durée de validité) : {url}")
    out("  2. `list` : le nouvel identifiant doit être `*` et « validated » ;")
    out("  3. un plan vide dans chaque module OVH ;")
    out("  4. `revoke <id de l'ancien>`, commit dans secrets/, date dans secrets-rotation.yaml.")
    return 0


def cmd_revoke(client, credential_id, force_current, assume_yes, out, ask=input):
    if credential_id == current_id(client) and not force_current:
        out(f"{credential_id} est l'identifiant en cours (OVH_CONSUMER_KEY) : refusé sans --force-current.")
        return 1
    if not assume_yes and ask(f"Révoquer l'identifiant {credential_id} ? Taper son id pour confirmer : ").strip() != str(credential_id):
        out("Abandon : rien n'est révoqué.")
        return 1
    client.call("DELETE", f"/me/api/credential/{credential_id}")
    out(f"Identifiant {credential_id} révoqué.")
    return 0


def main(argv=None, env=None, endpoint=ENDPOINT, out=print, err=None, run=subprocess.run, ask=input):
    env = os.environ if env is None else env
    err = err or (lambda text: print(text, file=sys.stderr))
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("list", help="lister les identifiants de l'application")
    renew = sub.add_parser("renew", help="demander un nouvel identifiant et le ranger dans SOPS")
    renew.add_argument("--allowed-ip", action="append", help="bloc IP autorisé, répétable (défaut : $home_ip/32)")
    renew.add_argument("--sops", default=shutil.which("sops"), help="binaire sops (défaut : celui du PATH)")
    revoke = sub.add_parser("revoke", help="révoquer un identifiant")
    revoke.add_argument("credential_id", type=int)
    revoke.add_argument("--force-current", action="store_true", help="accepter de révoquer l'identifiant en cours")
    revoke.add_argument("--yes", action="store_true", help="sans confirmation")
    args = parser.parse_args(argv)

    missing = [name for name in ENV_KEYS if not env.get(name)]
    if missing:
        err(f"Variables absentes : {', '.join(missing)} (lancer par `mise exec --`, depuis la racine).")
        return 2
    client = Client(*(env[name] for name in ENV_KEYS), endpoint=endpoint)
    try:
        if args.command == "list":
            return cmd_list(client, out)
        if args.command == "revoke":
            return cmd_revoke(client, args.credential_id, args.force_current, args.yes, out, ask)
        project = env.get("OVH_CLOUD_PROJECT_ID", "")
        home = env.get("home_ip", "")
        ips = args.allowed_ip or ([home if "/" in home else f"{home}/32"] if home else [])
        if not project or not ips or not args.sops:
            err("renew : OVH_CLOUD_PROJECT_ID, une IP (--allowed-ip ou home_ip) et sops sont requis.")
            return 2
        return cmd_renew(client, ips, project, args.sops, out, run)
    except OvhError as error:
        err(f"ÉCHEC {error}")
        return 1


if __name__ == "__main__":
    sys.exit(main())
