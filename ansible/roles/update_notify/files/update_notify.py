#!/usr/bin/python3
"""Mises à jour en attente sur l'hôte Proxmox ou le NAS, publiées sur ntfy.

Lancé chaque semaine par update-notify.timer (rôle update_notify), en root.
N'installe jamais rien : il liste, puis prévient.

- apt (hôte Proxmox VE) : apt-get update, puis une simulation de
  dist-upgrade (apt-get -s, rien n'est installé). Les paquets de
  Debian-Security sont listés d'abord, puis ceux de Proxmox et les noyaux,
  puis le reste ; un noyau installé plus récent que celui qui tourne est
  signalé (redémarrage en attente). Message ntfy de priorité haute dès qu'une
  mise à jour de sécurité attend, normale sinon, aucun quand tout est à jour.
- ugos (NAS Ugreen) : UGOS n'a pas d'apt et ne publie aucune source lisible
  sans session de son interface. Le script lit la version installée
  (/etc/os-release, OS_VERSION) et envoie un rappel par mois, plus un message
  de priorité haute quand la version a changé depuis le passage précédent
  (rejouer nas.yml après une mise à jour d'UGOS).

Chaque passage pousse aussi au moniteur push d'Uptime Kuma de l'hôte : up avec
un résumé, down si apt-get, la lecture de la version ou ntfy échouent. Un
vérificateur mort (timer arrêté, hôte éteint) laisse le moniteur sans
battement : il passe au rouge au bout de son intervalle.

Bibliothèque standard seule (le Python de Proxmox, celui d'UGOS). Le jeton
ntfy et l'URL push viennent de l'environnement (EnvironmentFile de l'unité,
0600 root), jamais de la ligne de commande, jamais affichés.
"""

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import time
import urllib.parse
import urllib.request

NTFY_TOKEN_VARIABLE = "NTFY_TOKEN"
PUSH_URL_VARIABLE = "UPTIME_PUSH_URL"
RUNBOOK = "docs/runbooks/mises-a-jour-proxmox-ugos.md"
# ntfy refuse un message de plus de 4096 octets (message-size-limit) : la
# liste est coupée bien avant.
MAX_LISTED = 25

# Inst <paquet> [<installée>] (<candidate> <origine>[, <origine>…] [<arch>])
INST_RE = re.compile(r"^Inst (\S+) (?:\[([^\]]+)\] )?\((\S+) (.+?) \[[^\]]+\]\)")
REMV_RE = re.compile(r"^Remv (\S+)")
PROXMOX_NAME_RE = re.compile(r"^(pve-|proxmox-|libpve|qemu-server|lxc-pve|corosync|libknet)")
KERNEL_NAME_RE = re.compile(r"(^|-)kernel|^linux-image")


class CheckError(Exception):
    """Échec du passage : poussé « down » au moniteur."""


def run(argv):
    env = dict(os.environ, LC_ALL="C", DEBIAN_FRONTEND="noninteractive")
    return subprocess.run(argv, capture_output=True, text=True, env=env, check=False)


def version_key(version):
    return tuple(int(n) for n in re.findall(r"\d+", version))


def parse_simulation(output):
    """Paquets d'une simulation de dist-upgrade, rangés par catégorie."""
    security, proxmox, other, removed = [], [], [], []
    for line in output.splitlines():
        removal = REMV_RE.match(line)
        if removal:
            removed.append(removal.group(1))
            continue
        match = INST_RE.match(line)
        if not match:
            continue
        name, installed, candidate, origins = match.groups()
        entry = f"{name} {installed or '(nouveau)'} → {candidate}"
        if "-Security:" in origins or "-security" in origins:
            security.append(entry)
        elif "Proxmox" in origins or PROXMOX_NAME_RE.search(name) or KERNEL_NAME_RE.search(name):
            proxmox.append(entry)
        else:
            other.append(entry)
    return security, proxmox, other, removed


def pending_kernel(boot_dir, running):
    """Le noyau installé le plus récent, s'il n'est pas celui qui tourne."""
    try:
        kernels = [f[len("vmlinuz-"):] for f in os.listdir(boot_dir) if f.startswith("vmlinuz-")]
    except OSError:
        return None
    if not kernels:
        return None
    newest = max(kernels, key=version_key)
    return newest if version_key(newest) > version_key(running) else None


def section(title, entries):
    if not entries:
        return []
    shown = entries[:MAX_LISTED]
    lines = [f"{title} ({len(entries)}) :"] + [f"  {e}" for e in shown]
    if len(entries) > len(shown):
        lines.append(f"  … et {len(entries) - len(shown)} autres")
    return lines


def check_apt(args):
    """Retourne (notification ou None, résumé pour Uptime Kuma)."""
    for attempt in range(3):
        update = run(["apt-get", "update", "-q"])
        if update.returncode == 0:
            break
        # Les listes d'apt verrouillées par pve-daily-update, un miroir
        # indisponible : deux nouvelles tentatives.
        if attempt < 2:
            time.sleep(args.retry_delay)
    else:
        last = (update.stderr.strip().splitlines() or ["?"])[-1]
        raise CheckError(f"apt-get update en échec : {last}")

    simulation = run(["apt-get", "-s", "-o", "Debug::NoLocking=1", "dist-upgrade"])
    if simulation.returncode != 0:
        last = (simulation.stderr.strip().splitlines() or ["?"])[-1]
        raise CheckError(f"simulation de dist-upgrade en échec : {last}")
    security, proxmox, other, removed = parse_simulation(simulation.stdout)
    total = len(security) + len(proxmox) + len(other)

    running = os.uname().release
    newest = pending_kernel(args.boot_dir, running)
    summary = f"{total} mises à jour, {len(security)} de sécurité"
    if newest:
        summary += f", noyau {newest} en attente de redémarrage"
    if not total and not removed and not newest:
        return None, "à jour"

    lines = section("Sécurité", security)
    lines += section("Proxmox et noyaux", proxmox)
    lines += section("Autres", other)
    lines += section("Retirés par dist-upgrade", removed)
    if newest:
        lines.append(f"Noyau {newest} installé, {running} en service : redémarrage à prévoir.")
    pveversion = run(["pveversion"]) if shutil.which("pveversion") else None
    if pveversion is not None and pveversion.returncode == 0 and pveversion.stdout.strip():
        lines.append(pveversion.stdout.strip().splitlines()[0])
    lines.append(f"Rien n'est installé seul : {RUNBOOK}")

    if total:
        title = f"{args.host} : {total} mise(s) à jour, dont {len(security)} de sécurité"
    else:
        title = f"{args.host} : redémarrage en attente"
    notification = {
        "title": title,
        "message": "\n".join(lines),
        "priority": 4 if security else 3,
        "tags": ["warning"] if security else ["package"],
    }
    return notification, summary


def read_os_release(path):
    values = {}
    with open(path, encoding="utf-8") as handle:
        for line in handle:
            key, sep, value = line.strip().partition("=")
            if sep:
                values[key] = value.strip().strip('"')
    return values


def check_ugos(args):
    """Retourne (notification ou None, résumé, nouvel état)."""
    try:
        release = read_os_release(args.os_release)
    except OSError as error:
        raise CheckError(f"{args.os_release} illisible : {error}") from error
    version = release.get("OS_VERSION", "")
    if not version:
        raise CheckError(f"OS_VERSION absent de {args.os_release}")

    try:
        with open(args.state, encoding="utf-8") as handle:
            state = json.load(handle)
    except (OSError, ValueError):
        state = {}
    month = time.strftime("%Y-%m")
    previous = state.get("version")
    beta = " (bêta)" if release.get("OS_IS_BETA", "").lower() == "true" else ""

    notification = None
    if previous and previous != version:
        notification = {
            "title": f"{args.host} : UGOS mis à jour, {previous} → {version}",
            "message": (
                f"UGOS {version}{beta} installé. Rejouer nas.yml : une mise à jour "
                "d'UGOS peut recocher sa redirection HTTPS (443 de l'hôte), "
                f"ou effacer ce qui est posé dans /etc. Procédure : {RUNBOOK}"
            ),
            "priority": 4,
            "tags": ["arrows_counterclockwise"],
        }
    elif state.get("reminded") != month:
        notification = {
            "title": f"{args.host} : rappel mensuel des mises à jour d'UGOS",
            "message": (
                f"UGOS {version}{beta} installé. UGOS ne publie aucune source "
                "lisible sans session de son interface : ce rappel ne sait pas "
                "si une mise à jour attend. Panneau de configuration > Mise à "
                f"jour et restauration. Procédure : {RUNBOOK}"
            ),
            "priority": 3,
            "tags": ["calendar"],
        }
    return notification, f"UGOS {version}{beta}", {"version": version, "reminded": month}


def publish(base_url, topic, token, notification):
    """Publication JSON sur la racine de ntfy (le topic dans le corps)."""
    if not token:
        raise CheckError(f"{NTFY_TOKEN_VARIABLE} vide : rien ne peut être publié")
    body = json.dumps(dict(notification, topic=topic)).encode()
    request = urllib.request.Request(
        base_url.rstrip("/") + "/",
        data=body,
        method="POST",
        headers={"Authorization": f"Bearer {token}", "Content-Type": "application/json"},
    )
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            response.read()
    except OSError as error:
        # Une erreur d'urllib peut citer l'URL ou la requête : sa classe seule.
        raise CheckError(f"publication ntfy en échec : {type(error).__name__}") from error


def push(url, status, msg):
    if not url:
        print(f"{PUSH_URL_VARIABLE} vide : rien n'est poussé.", file=sys.stderr)
        return True
    query = urllib.parse.urlencode({"status": status, "msg": msg[:250], "ping": ""})
    separator = "&" if "?" in url else "?"
    try:
        with urllib.request.urlopen(url + separator + query, timeout=30) as response:
            response.read()
    except OSError as error:
        print(f"push vers Uptime Kuma en échec : {type(error).__name__}", file=sys.stderr)
        return False
    return True


def save_state(path, state):
    temporary = f"{path}.tmp"
    with open(temporary, "w", encoding="utf-8") as handle:
        json.dump(state, handle)
    os.replace(temporary, path)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("mode", choices=["apt", "ugos"])
    parser.add_argument("--host", required=True, help="nom de l'hôte dans les messages")
    parser.add_argument("--ntfy-url", required=True)
    parser.add_argument("--topic", required=True)
    parser.add_argument("--state", default="/var/lib/update-notify/state.json")
    parser.add_argument("--os-release", default="/etc/os-release")
    parser.add_argument("--boot-dir", default="/boot")
    parser.add_argument("--retry-delay", type=int, default=60)
    args = parser.parse_args(argv)

    token = os.environ.get(NTFY_TOKEN_VARIABLE, "")
    push_url = os.environ.get(PUSH_URL_VARIABLE, "")
    try:
        if args.mode == "apt":
            notification, summary = check_apt(args)
            state = None
        else:
            notification, summary, state = check_ugos(args)
        if notification:
            publish(args.ntfy_url, args.topic, token, notification)
            print(f"publié : {notification['title']}", flush=True)
        if state is not None:
            # Après la publication seulement : un rappel perdu est renvoyé au
            # passage suivant.
            save_state(args.state, state)
    except CheckError as error:
        print(f"down: {error}", flush=True)
        push(push_url, "down", str(error))
        return 1
    print(f"up: {summary}", flush=True)
    return 0 if push(push_url, "up", summary) else 2


if __name__ == "__main__":
    sys.exit(main())
