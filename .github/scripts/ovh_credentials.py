#!/usr/bin/env python3
"""Rotation de la consumer key OVH de Tofu (docs/runbooks/rotation-des-secrets.md, « OVH »).

Trois sous-commandes, sur l'application de OVH_APPLICATION_KEY :
  list          les identifiants (credentials) du compte : id, état,
                application (nom, description), création, dernière
                utilisation, expiration, IP autorisées, règles ; `*` devant
                celui de OVH_CONSUMER_KEY, `t` devant l'identifiant temporaire ;
  renew         demande un identifiant aux règles d'access_rules(), restreint
                aux blocs de --allowed-ip (défaut : home_ip), range la nouvelle
                consumer key dans le fichier SOPS racine par l'entrée standard
                de `sops set`, puis affiche l'URL de validation à ouvrir ;
  revoke <id>   supprime UN identifiant, après confirmation. Refuse, sans option
                pour passer outre, ceux d'une autre application que celle de
                OVH_APPLICATION_KEY ; refuse celui en cours sans
                --force-current, et celui qui a servi après la création de
                l'identifiant en cours sans --ignore-recent-use.

Le jeton de Tofu ne peut ni lister ni révoquer : list et revoke demandent un
identifiant TEMPORAIRE (TEMP_RULES, revoke_rules()), limité à home_ip, à valider dans le navigateur avec la durée
la plus courte, gardé en mémoire le temps de la commande, puis expiré par
POST /auth/logout dans un finally (erreur et Ctrl-C compris).

Les identifiants viennent de l'environnement que mise charge depuis
secrets/secrets.sops.yaml (OVH_APPLICATION_KEY, OVH_APPLICATION_SECRET,
OVH_CONSUMER_KEY, OVH_CLOUD_PROJECT_ID, home_ip). Aucun secret n'est affiché,
écrit sur disque ni passé en argument : une consumer key ne quitte la réponse de
l'API que vers l'entrée standard de sops (renew) ou la mémoire (temporaire), et
tout message passe par redact(). Toute réponse de forme inattendue fait échouer
la commande (fermé).

Usage (depuis la racine du dépôt) :
  mise exec -- python3 -I .github/scripts/ovh_credentials.py list
"""

import argparse
import contextlib
import datetime
import hashlib
import http.client
import ipaddress
import json
import os
import re
import shutil
import subprocess
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
ENDPOINT = "https://eu.api.ovh.com/1.0"
SOPS_FILE = "secrets/secrets.sops.yaml"
SOPS_KEY = '["OVH_CONSUMER_KEY"]'
CURRENT_CREDENTIAL = "/auth/currentCredential"
CREDENTIALS = "/me/api/credential"
AUTH_CREDENTIAL = "POST /auth/credential"
ENV_KEYS = ("OVH_APPLICATION_KEY", "OVH_APPLICATION_SECRET", "OVH_CONSUMER_KEY")
TIMEOUT = 30
MAX_BYTES = 4 * 1024 * 1024
# Un en-tête HTTP ne porte ni espace ni retour à la ligne : une clé qui en
# contient ferait citer sa valeur par http.client.
HEADER_VALUE = re.compile(r"[\x21-\x7e]*")

# Les zones qu'écrivent les modules du fichier racine ; test_ovh_credentials.py
# les relit dans tofu/ et échoue sur toute différence.
ZONES = ("sylvain.cloud", "sylvain.dev", "sylvainmetayer.fr", "metayer.dev")
WRITE = ("GET", "POST", "PUT", "DELETE")
# Version des .terraform.lock.hcl ; le test échoue si elle change, pour relire
# les routes ci-dessous dans le source de la nouvelle version.
PROVIDER_VERSION = "2.24.0"
# Routes du provider hors ressources (ovh/config.go, authenticate()) :
# GET /auth/details au démarrage, refusée = provider en erreur, donc tout plan.
# GET /auth/time (go-ovh, dérive d'horloge) est sans authentification : pas de règle.
PROVIDER_INIT = (("GET", "/auth/details"),)
# Les seules ressources ovh des modules (aucune data source) ; le test échoue
# sur une autre. Leurs routes, lues dans le source de la version ci-dessus :
#   domain_zone_record       /domain/zone/{z}/record, /record/{id}, POST /refresh
#   domain_zone_redirection  /domain/zone/{z}/redirection, /redirection/{id}
#   cloud_project_user (+ _s3_credential, _s3_policy)
#                            /cloud/project/{p}/user, /user/{id}/…, GET /role
#   cloud_project_storage (+ _object_bucket_lifecycle_configuration)
#                            /cloud/project/{p}/region/{r}/storage/…
COVERED_RESOURCES = {
    "ovh_domain_zone_record",
    "ovh_domain_zone_redirection",
    "ovh_cloud_project_user",
    "ovh_cloud_project_user_s3_credential",
    "ovh_cloud_project_user_s3_policy",
    "ovh_cloud_project_storage",
    "ovh_cloud_project_storage_object_bucket_lifecycle_configuration",
}
# Identifiant temporaire de list : lire les identifiants, s'expirer lui-même.
# Celui de revoke est plus étroit (revoke_rules) : le seul identifiant visé.
LOGOUT = ("POST", "/auth/logout")
TEMP_RULES = (("GET", CURRENT_CREDENTIAL), ("GET", CREDENTIALS), ("GET", f"{CREDENTIALS}/*"), LOGOUT)


def _rules(pairs):
    return [{"method": m, "path": p} for m, p in pairs]


def access_rules(project):
    """Les règles du jeton de Tofu : ce que le provider appelle pour ces ressources, rien d'autre."""
    pairs = list(PROVIDER_INIT)
    # Lecture de son propre identifiant : ce script sait ainsi lequel est en cours.
    pairs.append(("GET", CURRENT_CREDENTIAL))
    for zone in ZONES:
        base = f"/domain/zone/{zone}"
        pairs += [("GET", f"{base}/record"), ("POST", f"{base}/record")]
        pairs += [(m, f"{base}/record/*") for m in ("GET", "PUT", "DELETE")]
        pairs += [("POST", f"{base}/refresh")]
        pairs += [("GET", f"{base}/redirection"), ("POST", f"{base}/redirection")]
        pairs += [(m, f"{base}/redirection/*") for m in ("GET", "PUT", "DELETE")]
    # Pas de joker sur tout le projet : ni instances, ni réseau, ni facturation.
    cloud = f"/cloud/project/{project}"
    pairs += [("GET", f"{cloud}/role"), ("GET", f"{cloud}/user"), ("POST", f"{cloud}/user")]
    pairs += [(m, f"{cloud}/user/*") for m in WRITE]
    pairs += [(m, f"{cloud}/region/*") for m in WRITE]
    return _rules(pairs)


class OvhError(Exception):
    """Erreur d'API, de sops ou de réponse ; le message est déjà passé par redact()."""


def redact(text, secrets):
    for secret in secrets:
        if secret:
            text = text.replace(secret, "***")
    return text


def signature(secret, consumer, method, url, body, timestamp):
    """$1$ + SHA-1 de « secret+consumer+méthode+url+corps+horodatage » (protocole de l'API OVH)."""
    payload = "+".join((secret, consumer, method, url, body, str(timestamp)))
    # SHA-1 imposé par le protocole de l'API OVH, pas un choix.
    return "$1$" + hashlib.sha1(payload.encode()).hexdigest()  # NOSONAR


class _NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


# Aucune redirection suivie : urllib renverrait les en-têtes signés à la cible.
_OPENER = urllib.request.build_opener(_NoRedirect)


class Client:
    def __init__(self, application_key, application_secret, consumer_key, endpoint=ENDPOINT, clock=time.time, secrets=None):
        self.endpoint = endpoint.rstrip("/")
        self.application_key = application_key
        self.application_secret = application_secret
        self.consumer_key = consumer_key
        self.clock = clock
        # Liste partagée avec main() et le client temporaire : tout ce qui est masqué.
        self.secrets = secrets if secrets is not None else [application_key, application_secret, consumer_key]

    def with_consumer(self, consumer_key):
        self.secrets.append(consumer_key)
        return Client(self.application_key, self.application_secret, consumer_key, self.endpoint, self.clock, self.secrets)

    def call(self, method, path, body=None, signed=True):
        url = self.endpoint + path
        data = "" if body is None else json.dumps(body, separators=(",", ":"))
        headers = {"X-Ovh-Application": self.application_key, "Accept": "application/json"}
        if data:
            headers["Content-Type"] = "application/json"
        if signed:
            timestamp = int(self.clock())
            headers["X-Ovh-Consumer"] = self.consumer_key
            headers["X-Ovh-Timestamp"] = str(timestamp)
            headers["X-Ovh-Signature"] = signature(self.application_secret, self.consumer_key, method, url, data, timestamp)
        bad = [name for name, value in headers.items() if not HEADER_VALUE.fullmatch(value)]
        if bad:
            raise OvhError(f"{method} {path} : en-tête {', '.join(bad)} invalide (espace ou retour à la ligne), valeur masquée")
        headers["User-Agent"] = "homelab-ovh-credentials"
        if not url.startswith(("https://", "http://127.0.0.1:")):
            raise OvhError("schéma d'URL refusé")
        # Endpoint fixe (ENDPOINT, ou 127.0.0.1 en test), schéma vérifié, aucune redirection suivie.
        request = urllib.request.Request(url, data=data.encode() or None, headers=headers, method=method)  # NOSONAR
        try:
            with _OPENER.open(request, timeout=TIMEOUT) as response:  # NOSONAR
                raw = response.read(MAX_BYTES + 1)
        except urllib.error.HTTPError as error:
            message = _api_message(error)
            if re.search(r"signature|timestamp|time", message, re.IGNORECASE):
                message += " (horloge locale décalée ? l'API refuse une signature dont l'horodatage s'en écarte)"
            raise OvhError(redact(f"{method} {path} : HTTP {error.code} {message}", self.secrets)) from None
        # Sa classe seule : le message d'une URLError, ou le ValueError de
        # http.client sur un en-tête, peut citer la requête ou une clé.
        except (OSError, http.client.HTTPException, ValueError) as error:
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


# --- Formes de réponse : tout écart échoue fermé --------------------------


def _dict(value, what):
    if not isinstance(value, dict):
        raise OvhError(f"{what} : réponse inattendue (objet attendu)")
    return value


def _int(obj, key, what):
    value = obj.get(key)
    if not isinstance(value, int) or isinstance(value, bool):
        raise OvhError(f"{what} : {key} absent ou non entier")
    return value


def _str(obj, key, what):
    value = obj.get(key)
    if not isinstance(value, str) or not value:
        raise OvhError(f"{what} : {key} absent")
    return value


def _date(obj, key, what):
    try:
        value = datetime.datetime.fromisoformat(_str(obj, key, what))
    except ValueError:
        raise OvhError(f"{what} : {key} n'est pas une date") from None
    if value.tzinfo is None:
        raise OvhError(f"{what} : {key} sans fuseau")
    return value


def _ids(value):
    if not isinstance(value, list) or not all(isinstance(i, int) and not isinstance(i, bool) for i in value):
        raise OvhError(f"GET {CREDENTIALS} : réponse inattendue (liste d'entiers attendue)")
    return sorted(value)


def current(client):
    """(credentialId, applicationId, création) de l'identifiant du client."""
    c = _dict(client.call("GET", CURRENT_CREDENTIAL), CURRENT_CREDENTIAL)
    return _int(c, "credentialId", CURRENT_CREDENTIAL), _int(c, "applicationId", CURRENT_CREDENTIAL), _date(c, "creation", CURRENT_CREDENTIAL)


def ip_block(value):
    """Un bloc CIDR ; une adresse seule devient /32 en IPv4, /128 en IPv6."""
    try:
        if "/" in value:
            return str(ipaddress.ip_network(value, strict=True))
        address = ipaddress.ip_address(value)
    except ValueError:
        raise OvhError(f"bloc IP mal formé : {value!r}") from None
    return f"{address}/{address.max_prefixlen}"


@contextlib.contextmanager
def temporary(base, pairs, allowed_ips, out, ask):
    """(client, credentialId, applicationId) d'un identifiant temporaire, expiré à la sortie quoi qu'il arrive."""
    body = {"accessRules": _rules(pairs)}
    if allowed_ips:
        body["allowedIPs"] = allowed_ips
    answer = _dict(base.call("POST", "/auth/credential", body, signed=False), AUTH_CREDENTIAL)
    temp = base.with_consumer(_str(answer, "consumerKey", AUTH_CREDENTIAL))
    url = _str(answer, "validationUrl", AUTH_CREDENTIAL)
    out(f"Identifiant temporaire ({', '.join(f'{m} {p}' for m, p in pairs)}), IP {', '.join(allowed_ips) or 'toutes'}.")
    out(f"Le valider avec la durée la plus courte proposée : {url}")
    temp_id = None
    try:
        ask("Entrée une fois validé (Ctrl-C pour abandonner) : ")
        temp_id, temp_app, _ = current(temp)
        yield temp, temp_id, temp_app
    finally:
        try:
            temp.call("POST", "/auth/logout")
            out("Identifiant temporaire expiré (POST /auth/logout).")
        except OvhError as error:
            if temp_id is None:
                out(
                    f"ATTENTION identifiant temporaire non expiré, id inconnu ({error}). Jamais validé : il expire seul. "
                    "Validé : le repérer dans `list` (créé à l'instant, règles /me/api seulement), "
                    "puis `revoke <id> --ignore-recent-use`."
                )
            else:
                out(
                    f"ATTENTION identifiant temporaire {temp_id} non expiré ({error}). Le révoquer : "
                    f"mise exec -- python3 -I .github/scripts/ovh_credentials.py revoke {temp_id} --ignore-recent-use"
                )


def _scope(c, app_id, what):
    return "rotation" if _int(c, "applicationId", what) == app_id else "AUTRE APPLICATION, hors rotation"


def cmd_list(base, temporary_credential, out):
    temp, temp_id, temp_app = temporary_credential
    try:
        tofu_id = current(base)[0]
    except OvhError as error:
        out(
            f"Identifiant en cours NON MARQUÉ : OVH_CONSUMER_KEY ne peut pas lire son propre identifiant ({error}). "
            "Ancien jeton sans la règle GET /auth/currentCredential (première rotation) ? Le reconnaître à la main "
            "parmi les [rotation] : règles des zones et du projet, IP autorisées, création la plus ancienne, "
            "dernier usage au dernier plan (runbook, « Première rotation »)."
        )
        tofu_id = None
    # Le temporaire est demandé avec OVH_APPLICATION_KEY : son application est celle de la rotation.
    for credential_id in _ids(temp.call("GET", CREDENTIALS)):
        what = f"GET {CREDENTIALS}/{credential_id}"
        c = _dict(temp.call("GET", f"{CREDENTIALS}/{credential_id}"), what)
        app = _dict(temp.call("GET", f"{CREDENTIALS}/{credential_id}/application"), f"{what}/application")
        mark = {tofu_id: "*", temp_id: "t"}.get(credential_id, " ")
        out(
            f"{mark} {credential_id} {c.get('status')} application {c.get('applicationId')} "
            f"« {app.get('name')} » ({app.get('description')}) [{_scope(c, temp_app, what)}]"
        )
        out(
            f"      création {c.get('creation')} dernier usage {c.get('lastUse')} expiration {c.get('expiration')} "
            f"IP {','.join(map(str, c.get('allowedIPs') or [])) or 'toutes'}"
        )
        for rule in c.get("rules") or []:
            out(f"      {rule.get('method')} {rule.get('path')}")
    out("* : OVH_CONSUMER_KEY (en cours) ; t : temporaire de cette commande ; seuls les [rotation] sont révocables")
    return 0


def cmd_renew(client, allowed_ips, project, sops, out, run=subprocess.run):
    body = {"accessRules": access_rules(project), "allowedIPs": allowed_ips}
    out(f"Demande d'un identifiant : {len(body['accessRules'])} règles, IP {', '.join(allowed_ips)}")
    for rule in body["accessRules"]:
        out(f"  {rule['method']} {rule['path']}")
    # POST /auth/credential ne se signe pas : la seule clé d'application suffit.
    answer = _dict(client.call("POST", "/auth/credential", body, signed=False), AUTH_CREDENTIAL)
    consumer_key = _str(answer, "consumerKey", AUTH_CREDENTIAL)
    client.secrets.append(consumer_key)
    url = _str(answer, "validationUrl", AUTH_CREDENTIAL)
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
        detail = redact((result.stderr or "").strip(), client.secrets)
        raise OvhError(f"sops set a échoué ({result.returncode}) : {detail}\nNe rien valider ; relancer renew.")
    out(f"Nouvelle consumer key rangée dans {SOPS_FILE} (OVH_CONSUMER_KEY), sous-module non commité.")
    out("Suite, dans cet ordre (docs/runbooks/rotation-des-secrets.md, « OVH ») :")
    out(f"  1. ouvrir et valider (compte OVH, durée de validité) : {url}")
    out("  2. un plan vide dans chaque module OVH, puis un apply anodin réversible ; sinon retour arrière (runbook) ;")
    out("  3. `list` : le nouvel identifiant doit être `*` et « validated » ;")
    out("  4. `revoke <id de l'ancien>`, commit dans secrets/, date dans secrets-rotation.yaml.")
    return 0


def _refusal(tofu, temporary_credential, credential_id, target, options, what):
    """La raison de refuser la révocation, ou None. Ne lit que l'identifiant visé et l'identifiant en cours."""
    tofu_id, tofu_app, tofu_created = tofu
    _, temp_id, temp_app = temporary_credential
    if tofu_app != temp_app:
        return f"OVH_CONSUMER_KEY ({tofu_app}) et OVH_APPLICATION_KEY ({temp_app}) ne sont pas de la même application : refusé."
    target_app = _int(target, "applicationId", what)
    if target_app != tofu_app:
        return (
            f"{credential_id} appartient à une autre application ({target_app}) : refusé, sans option. "
            "Ses identifiants (DNS-01, ACME de Proxmox, coûts…) se gèrent à la main, voir le runbook."
        )
    if credential_id == temp_id:
        return f"{credential_id} est l'identifiant temporaire de cette commande : il expire à la fin."
    if credential_id == tofu_id:
        return None if options.force_current else f"{credential_id} est l'identifiant en cours (OVH_CONSUMER_KEY) : refusé sans --force-current."
    if target.get("lastUse") is None or options.ignore_recent_use:
        return None
    last_use = _date(target, "lastUse", what)
    if last_use > tofu_created:
        return (
            f"{credential_id} a servi le {last_use.isoformat()}, après la création de l'identifiant en cours "
            f"({tofu_created.isoformat()}) : un autre système s'en sert encore. Refusé sans --ignore-recent-use."
        )
    return None


def cmd_revoke(tofu, temporary_credential, credential_id, options, out, ask):
    """Un seul identifiant, de l'application de OVH_APPLICATION_KEY ; jamais d'un autre système."""
    temp = temporary_credential[0]
    what = f"GET {CREDENTIALS}/{credential_id}"
    target = _dict(temp.call("GET", f"{CREDENTIALS}/{credential_id}"), what)
    refusal = _refusal(tofu, temporary_credential, credential_id, target, options, what)
    if refusal:
        out(refusal)
        return 1
    if not options.yes and ask(f"Révoquer l'identifiant {credential_id} ? Taper son id pour confirmer : ").strip() != str(credential_id):
        out("Abandon : rien n'est révoqué.")
        return 1
    temp.call("DELETE", f"{CREDENTIALS}/{credential_id}")
    out(f"Identifiant {credential_id} révoqué.")
    return 0


def revoke_rules(credential_id):
    """Le temporaire de revoke : son propre identifiant, l'identifiant visé, rien d'autre."""
    target = f"{CREDENTIALS}/{credential_id}"
    return (("GET", CURRENT_CREDENTIAL), ("GET", target), ("DELETE", target), LOGOUT)


def _allowed_ips(args, env):
    ips = [ip_block(value) for value in args.allowed_ip or []]
    if not ips and env.get("home_ip"):
        ips = [ip_block(env["home_ip"])]
    return ips


def main(argv=None, env=None, endpoint=ENDPOINT, out=print, err=None, run=subprocess.run, ask=input):
    env = os.environ if env is None else env
    err = err or (lambda text: print(text, file=sys.stderr))
    common = argparse.ArgumentParser(add_help=False)
    common.add_argument("--allowed-ip", action="append", help="bloc IP autorisé, répétable (défaut : home_ip, /32 ou /128)")
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("list", parents=[common], help="lister les identifiants du compte (identifiant temporaire)")
    renew = sub.add_parser("renew", parents=[common], help="demander un nouvel identifiant et le ranger dans SOPS")
    renew.add_argument("--sops", default=shutil.which("sops"), help="binaire sops (défaut : celui du PATH)")
    revoke = sub.add_parser("revoke", parents=[common], help="révoquer un identifiant (identifiant temporaire)")
    revoke.add_argument("credential_id", type=int)
    revoke.add_argument("--force-current", action="store_true", help="accepter de révoquer l'identifiant en cours")
    revoke.add_argument("--ignore-recent-use", action="store_true", help="accepter un identifiant utilisé après la création de l'actuel")
    revoke.add_argument("--yes", action="store_true", help="sans confirmation")
    args = parser.parse_args(argv)

    missing = [name for name in ENV_KEYS if not env.get(name)]
    malformed = [name for name in ENV_KEYS if env.get(name) and not HEADER_VALUE.fullmatch(env[name])]
    if missing or malformed:
        err(f"Variables absentes ou mal formées : {', '.join(missing + malformed)} (lancer par `mise exec --`, depuis la racine).")
        return 2
    base = Client(*(env[name] for name in ENV_KEYS), endpoint=endpoint)
    try:
        ips = _allowed_ips(args, env)
        if args.command == "list":
            with temporary(base, TEMP_RULES, ips, out, ask) as temp:
                return cmd_list(base, temp, out)
        if args.command == "revoke":
            try:
                tofu = current(base)  # avant la demande temporaire : rien à valider si ceci échoue
            except OvhError as error:
                raise OvhError(
                    f"{error} : identifiant en cours illisible, garde-fous impossibles. "
                    "Révoquer depuis la console OVH (runbook, « Première rotation »)."
                ) from None
            with temporary(base, revoke_rules(args.credential_id), ips, out, ask) as temp:
                return cmd_revoke(tofu, temp, args.credential_id, args, out, ask)
        project = env.get("OVH_CLOUD_PROJECT_ID", "")
        if not project or not ips or not args.sops:
            err("renew : OVH_CLOUD_PROJECT_ID, une IP (--allowed-ip ou home_ip) et sops sont requis.")
            return 2
        return cmd_renew(base, ips, project, args.sops, out, run)
    except OvhError as error:
        err(redact(f"ÉCHEC {error}", base.secrets))
        return 1
    except (KeyboardInterrupt, EOFError):
        err("Interrompu.")
        return 130


if __name__ == "__main__":
    sys.exit(main())
