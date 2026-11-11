#!/usr/bin/python3
"""S.M.A.R.T. des disques de l'hôte : usure et secteurs, publiés sur ntfy.

Lancé chaque semaine par smart-check.timer (rôle smart_check), en root. Lit
chaque disque par `smartctl -j -i -H -A` et applique les seuils de
docs/runbooks/sante-des-disques.md : verdict FAILED ; disque dur, secteurs
réalloués (5), en attente (197), non corrigeables (198), erreurs CRC (199) ;
SSD SATA, valeur normalisée de l'attribut d'usure sous 20 puis sous 10 ;
NVMe, `Percentage Used` au-delà de 80, `Available Spare` sous 20, erreurs
d'intégrité non nulles. Beszel ne prévient que sur le verdict.

Une alerte ne sonne que sur une HAUSSE : chaque constat garde son plus haut
niveau déjà annoncé (fichier d'état, par numéro de série), si bien qu'un disque
connu défaillant et gardé sans y compter (sdc du NAS) n'est annoncé qu'une
fois, puis à chaque aggravation. Les constats toujours en cours restent dans le
résumé poussé à Uptime Kuma. L'état n'est écrit qu'une fois le message publié :
une publication en échec est refaite au passage suivant.

Chaque passage pousse au moniteur push d'Uptime Kuma : up avec un résumé, down
si un disque est illisible (pont USB sans passage SMART, permission) ou si ntfy
échoue. Un vérificateur mort (timer arrêté, hôte éteint) laisse le moniteur
sans battement : il passe au rouge.

Bibliothèque standard seule. Le jeton ntfy et l'URL push viennent de
l'environnement (EnvironmentFile de l'unité, 0600 root), jamais de la ligne de
commande, jamais affichés.
"""

import argparse
import http.client
import json
import os
import subprocess
import sys
import urllib.parse
import urllib.request

NTFY_TOKEN_VARIABLE = "NTFY_TOKEN"
PUSH_URL_VARIABLE = "UPTIME_PUSH_URL"
RUNBOOK = "docs/runbooks/sante-des-disques.md"
# Attributs d'usure d'un SSD SATA, valeur normalisée (100 neuf, qui descend) ;
# 232 est la réserve de blocs. Le runbook : racheter sous 20, sans attendre sous 10.
SSD_WEAR_IDS = (177, 173, 169, 202, 231, 233, 232)
WEAR_BUY, WEAR_NOW = 20, 10
NVME_USED_BUY, NVME_SPARE_NOW = 80, 20
PRIORITY_BUY, PRIORITY_NOW = 4, 5


class CheckError(Exception):
    """Échec du passage : poussé « down » au moniteur."""


def read_disk(smartctl, spec):
    """Le JSON de smartctl pour « chemin[:type] ». Son code de sortie est un
    masque de bits (un disque mal en point en met), il ne dit rien de la
    lisibilité : seule la présence des données compte."""
    path, _, kind = spec.partition(":")
    # -i : rotation_rate, model_name et serial_number ne sortent que de la section d'identité.
    argv = [smartctl, "-j", "-i", "-H", "-A"] + (["-d", kind] if kind else []) + [path]
    try:
        # Chemins et binaire viennent de l'ExecStart de l'unité (root, écrit par Ansible), pas d'une entrée extérieure.
        result = subprocess.run(argv, capture_output=True, text=True, check=False)  # NOSONAR
    except OSError as error:
        raise CheckError(f"{path} illisible : {type(error).__name__}") from error
    try:
        data = json.loads(result.stdout)
    except ValueError:
        data = {}
    # Des attributs absents ou vides ne sont pas un disque sain : illisible.
    nvme_log = data.get("nvme_smart_health_information_log") or {}
    if not data.get("ata_smart_attributes", {}).get("table") and "percentage_used" not in nvme_log:
        messages = data.get("smartctl", {}).get("messages") or [{}]
        raise CheckError(f"{path} illisible : {messages[0].get('string', 'pas de données S.M.A.R.T.')}")
    return data


def finding(key, text, priority, level):
    return {"key": key, "text": text, "priority": priority, "level": level}


def inspect(data):
    """Les constats d'un disque. Le niveau est la valeur brute d'un compteur,
    ou 1 (racheter) / 2 (sans attendre) pour un seuil : il sert à n'annoncer
    que ce qui monte."""
    found = []
    if data.get("smart_status", {}).get("passed") is False:
        found.append(finding("verdict", "verdict S.M.A.R.T. FAILED", PRIORITY_NOW, 1))

    log = data.get("nvme_smart_health_information_log")
    if log:
        used, spare, errors = log.get("percentage_used", 0), log.get("available_spare", 100), log.get("media_errors", 0)
        if used > NVME_USED_BUY:
            found.append(finding("used", f"Percentage Used {used} % (racheter au-delà de {NVME_USED_BUY})", PRIORITY_BUY, 1))
        if spare < NVME_SPARE_NOW:
            found.append(finding("spare", f"Available Spare {spare} % (sous {NVME_SPARE_NOW})", PRIORITY_NOW, 1))
        if errors > 0:
            found.append(finding("media_errors", f"{errors} erreur(s) d'intégrité", PRIORITY_NOW, errors))
        return found

    attributes = {a["id"]: a for a in data.get("ata_smart_attributes", {}).get("table", [])}
    counters = {
        5: ("réalloués", PRIORITY_BUY),
        197: ("en attente", PRIORITY_NOW),
        198: ("non corrigeables", PRIORITY_NOW),
        199: ("erreurs CRC (câble ou pont)", PRIORITY_BUY),
    }
    for number, (label, priority) in counters.items():
        raw = attributes.get(number, {}).get("raw", {}).get("value", 0)
        if raw > 0:
            found.append(finding(f"attr{number}", f"{number} {label} : {raw}", priority, raw))
    if data.get("rotation_rate") == 0:  # SSD ; un disque dur n'a pas d'attribut d'usure
        for number in SSD_WEAR_IDS:
            attribute = attributes.get(number)
            if attribute is not None and attribute["value"] < WEAR_BUY:
                level = 2 if attribute["value"] < WEAR_NOW else 1
                found.append(finding(
                    f"wear{number}", f"{attribute['name']} ({number}) à {attribute['value']}, 100 neuf",
                    PRIORITY_NOW if level == 2 else PRIORITY_BUY, level,
                ))
    return found


def disk_name(data):
    # Un disque sans modèle ni numéro de série (pont USB sans passthrough) : le chemin seul
    # sert alors de nom et de clé d'état (shortcut: stable tant que sda reste sda).
    return f"{data.get('model_name', 'disque')} {data.get('device', {}).get('name', '?')}"


def load_state(path):
    # path : --state-file de l'ExecStart de l'unité, pas une entrée extérieure.
    try:
        with open(path, encoding="utf-8") as handle:  # NOSONAR
            state = json.load(handle)
        # Une entrée qui n'est pas { constat: niveau } ferait planter chaque passage.
        return {k: v for k, v in state.items() if isinstance(v, dict)} if isinstance(state, dict) else {}
    except (OSError, ValueError):
        return {}


def save_state(path, state):
    tmp = f"{path}.tmp"
    # Même --state-file que load_state.
    with open(tmp, "w", encoding="utf-8") as handle:  # NOSONAR
        json.dump(state, handle)
    os.replace(tmp, path)  # NOSONAR


def check(args):
    """Retourne (notification ou None, nouvel état, résumé, disques illisibles)."""
    state = load_state(args.state_file)
    new_state = {serial: dict(levels) for serial, levels in state.items()}
    lines, priority, ongoing, unreadable = [], 0, [], []
    for spec in args.device:
        try:
            data = read_disk(args.smartctl, spec)
        except CheckError as error:
            unreadable.append(str(error))
            continue
        serial = data.get("serial_number") or disk_name(data)
        risen, kept = [], {}
        for item in inspect(data):
            ongoing.append(f"{disk_name(data)} {item['text']}")
            before = state.get(serial, {}).get(item["key"], 0)
            kept[item["key"]] = max(before, item["level"])
            if item["level"] > before:
                if before:
                    item["text"] += f" (annoncé à {before})"
                risen.append(item)
                priority = max(priority, item["priority"])
        # Un constat disparu est oublié : sa rechute sonne de nouveau, et un
        # disque remplacé, resté sous le même nom, repart de zéro.
        new_state.pop(serial, None)
        if kept:
            new_state[serial] = kept
        if risen:
            lines.append(f"{disk_name(data)} :")
            lines += [f"  {item['text']}" for item in risen]

    read = len(args.device) - len(unreadable)
    summary = f"{read} disque(s) lus, " + (
        f"{len(ongoing)} constat(s) : " + "; ".join(ongoing) if ongoing else "rien à signaler")
    if not lines:
        return None, new_state, summary, unreadable
    lines.append(f"Seuils et remplacement : {RUNBOOK}")
    notification = {
        "title": f"{args.host} : disque à surveiller",
        "message": "\n".join(lines),
        "priority": priority,
        "tags": ["warning"],
    }
    return notification, new_state, summary, unreadable


class _NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


# Aucune redirection suivie : urllib renverrait le jeton (Authorization) à la
# cible, et le 200 de sa page d'arrivée compterait comme une publication réussie.
_OPENER = urllib.request.build_opener(_NoRedirect)


def publish(base_url, topic, token, notification):
    """Publication JSON sur la racine de ntfy (le topic dans le corps)."""
    if not token:
        raise CheckError(f"{NTFY_TOKEN_VARIABLE} vide : rien ne peut être publié")
    body = json.dumps(dict(notification, topic=topic)).encode()
    try:
        request = urllib.request.Request(
            base_url.rstrip("/") + "/",
            data=body,
            method="POST",
            headers={"Authorization": f"Bearer {token}", "Content-Type": "application/json"},
        )
        with _OPENER.open(request, timeout=30) as response:
            response.read()
    except (OSError, ValueError, http.client.HTTPException) as error:
        # Une erreur d'urllib peut citer l'URL ou l'en-tête, donc le jeton : sa classe seule.
        raise CheckError(f"publication ntfy en échec : {type(error).__name__}") from error


def push(url, status, msg):
    if not url:
        print(f"{PUSH_URL_VARIABLE} vide : rien n'est poussé.", file=sys.stderr)
        return True
    query = urllib.parse.urlencode({"status": status, "msg": msg[:250], "ping": ""})
    separator = "&" if "?" in url else "?"
    try:
        with _OPENER.open(url + separator + query, timeout=30) as response:
            response.read()
    except (OSError, ValueError, http.client.HTTPException) as error:
        print(f"push vers Uptime Kuma en échec : {type(error).__name__}", file=sys.stderr)
        return False
    return True


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--host", required=True, help="nom de l'hôte dans les messages")
    parser.add_argument("--ntfy-url", required=True)
    parser.add_argument("--topic", required=True)
    parser.add_argument("--state-file", required=True)
    parser.add_argument("--device", action="append", required=True, help="chemin[:type smartctl]")
    parser.add_argument("--smartctl", default="/usr/sbin/smartctl")
    args = parser.parse_args(argv)

    token = os.environ.get(NTFY_TOKEN_VARIABLE, "")
    push_url = os.environ.get(PUSH_URL_VARIABLE, "")
    try:
        notification, new_state, summary, unreadable = check(args)
        if notification:
            publish(args.ntfy_url, args.topic, token, notification)
            print(f"publié : {notification['title']}", flush=True)
        save_state(args.state_file, new_state)
        if unreadable:
            raise CheckError("; ".join(unreadable))
    except Exception as error:  # noqa: BLE001 un plantage ne doit pas laisser le moniteur muet
        message = str(error) if isinstance(error, (CheckError, OSError)) else f"erreur inattendue : {type(error).__name__}"
        print(f"down: {message}", flush=True)
        push(push_url, "down", message)
        return 1
    print(f"up: {summary}", flush=True)
    return 0 if push(push_url, "up", summary) else 2


if __name__ == "__main__":
    sys.exit(main())
