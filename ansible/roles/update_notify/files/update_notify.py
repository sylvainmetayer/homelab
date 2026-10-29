#!/usr/bin/python3
"""Mises à jour apt en attente sur l'hôte, publiées sur ntfy.

Lancé chaque semaine par update-notify.timer (rôle update_notify), en root,
sur l'hôte Proxmox, la VM docker, le Pi, flip et Pangolin. N'installe jamais
rien : il liste, puis prévient. apt-get update, puis une simulation de
dist-upgrade (apt-get -s, rien n'est installé). Les paquets de
Debian-Security sont listés d'abord, puis Docker (docker-ce, containerd…),
Proxmox et les noyaux, puis le reste ; un noyau installé plus récent que
celui qui tourne est signalé (redémarrage en attente). Message ntfy de
priorité haute dès qu'une mise à jour de sécurité attend, normale sinon,
aucun quand tout est à jour.

Chaque passage pousse aussi au moniteur push d'Uptime Kuma de l'hôte : up avec
un résumé, down si apt-get ou ntfy échouent. Un vérificateur mort (timer
arrêté, hôte éteint) laisse le moniteur sans battement : il passe au rouge au
bout de son intervalle.

Bibliothèque standard seule (le Python de Debian). Le jeton ntfy et l'URL
push viennent de l'environnement (EnvironmentFile de l'unité, 0600 root),
jamais de la ligne de commande, jamais affichés.
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
RUNBOOK = "docs/runbooks/mises-a-jour-hotes.md"
# ntfy refuse un message de plus de 4096 octets (message-size-limit, sans
# pièces jointes) : chaque section est coupée à MAX_LISTED paquets, puis le
# message entier à MESSAGE_LIMIT octets (quatre sections pleines le passeraient).
MAX_LISTED = 25
MESSAGE_LIMIT = 3900

# Inst <paquet> [<installée>] (<candidate> <origine>[, <origine>…] [<arch>])
INST_RE = re.compile(r"^Inst (\S+) (?:\[([^\]]+)\] )?\((\S+) ([^\[]+) \[[^\]]+\]\)")
REMV_RE = re.compile(r"^Remv (\S+)")
PROXMOX_NAME_RE = re.compile(r"^(pve-|proxmox-|libpve|qemu-server|lxc-pve|corosync|libknet)")
KERNEL_NAME_RE = re.compile(r"(^|-)kernel|^linux-image")
# Le moteur Docker et ce qui l'accompagne (dépôt download.docker.com) : sa
# mise à jour redémarre dockerd, donc tous les conteneurs de l'hôte.
DOCKER_NAME_RE = re.compile(r"^(docker-|containerd)")


class CheckError(Exception):
    """Échec du passage : poussé « down » au moniteur."""


def run(argv):
    env = dict(os.environ, LC_ALL="C", DEBIAN_FRONTEND="noninteractive")
    return subprocess.run(argv, capture_output=True, text=True, env=env, check=False)


def version_key(version):
    return tuple(int(n) for n in re.findall(r"\d+", version))


def parse_simulation(output):
    """Paquets d'une simulation de dist-upgrade, rangés par catégorie :
    sécurité, Docker/Proxmox/noyaux (sensibles : un redémarrage du démon,
    des VM ou de l'hôte), le reste, les retirés."""
    security, sensitive, other, removed = [], [], [], []
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
        elif (
            "Proxmox" in origins or "Docker" in origins or PROXMOX_NAME_RE.search(name)
            or KERNEL_NAME_RE.search(name) or DOCKER_NAME_RE.search(name)
        ):
            sensitive.append(entry)
        else:
            other.append(entry)
    return security, sensitive, other, removed


def pending_kernel(boot_dir, running):
    """Le noyau installé le plus récent de la même famille que celui qui
    tourne (suffixe -pve), s'il est plus récent que lui. Un noyau Debian
    resté installé (-amd64) n'est pas comparé : il ne démarrerait pas par
    défaut."""
    flavour = "-" + running.rsplit("-", 1)[-1] if "-" in running else ""
    try:
        kernels = [
            f[len("vmlinuz-"):] for f in os.listdir(boot_dir)
            if f.startswith("vmlinuz-") and f.endswith(flavour)
        ]
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


def fit_message(body, tail, limit=MESSAGE_LIMIT):
    """Les lignes de body, coupées pour que le message tienne en limit
    octets, puis celles de tail (noyau, version, runbook), gardées entières."""
    marker = "… liste tronquée : apt list --upgradable sur l'hôte"
    budget = limit - len("\n".join([marker] + tail).encode()) - 1
    kept, size = [], 0
    for line in body:
        size += len(line.encode()) + 1
        if size > budget:
            return "\n".join(kept + [marker] + tail)
        kept.append(line)
    return "\n".join(kept + tail)


def last_error(result):
    return (result.stderr.strip().splitlines() or ["?"])[-1]


def apt_update(retry_delay):
    """apt-get update, deux nouvelles tentatives : les listes verrouillées
    par pve-daily-update, un miroir indisponible."""
    for attempt in range(3):
        update = run(["apt-get", "update", "-q"])
        if update.returncode == 0:
            return
        if attempt < 2:
            time.sleep(retry_delay)
    raise CheckError(f"apt-get update en échec : {last_error(update)}")


def apt_tail(newest, running, docker):
    """Les dernières lignes du message, jamais coupées."""
    tail = []
    if docker:
        tail.append("Docker en attente : sa mise à jour redémarre tous les conteneurs de l'hôte.")
    if newest:
        tail.append(f"Noyau {newest} installé, {running} en service : redémarrage à prévoir.")
    pveversion = run(["pveversion"]) if shutil.which("pveversion") else None
    if pveversion is not None and pveversion.returncode == 0 and pveversion.stdout.strip():
        tail.append(pveversion.stdout.strip().splitlines()[0])
    tail.append(f"À appliquer à la main : {RUNBOOK}")
    return tail


def check_apt(args):
    """Retourne (notification ou None, résumé pour Uptime Kuma)."""
    apt_update(args.retry_delay)

    simulation = run(["apt-get", "-s", "-o", "Debug::NoLocking=1", "dist-upgrade"])
    if simulation.returncode != 0:
        raise CheckError(f"simulation de dist-upgrade en échec : {last_error(simulation)}")
    security, sensitive, other, removed = parse_simulation(simulation.stdout)
    total = len(security) + len(sensitive) + len(other)
    docker = any(DOCKER_NAME_RE.search(e) for e in security + sensitive)

    running = os.uname().release
    newest = pending_kernel(args.boot_dir, running)
    summary = f"{total} mises à jour, {len(security)} de sécurité"
    if newest:
        summary += f", noyau {newest} en attente de redémarrage"
    if not total and not removed and not newest:
        return None, "à jour"

    lines = section("Sécurité", security)
    lines += section("Docker, Proxmox et noyaux", sensitive)
    lines += section("Autres", other)
    lines += section("Retirés par dist-upgrade", removed)
    tail = apt_tail(newest, running, docker)

    if total:
        title = f"{args.host} : {total} mise(s) à jour, dont {len(security)} de sécurité"
    else:
        title = f"{args.host} : redémarrage en attente"
    notification = {
        "title": title,
        "message": fit_message(lines, tail),
        "priority": 4 if security else 3,
        "tags": ["warning"] if security else ["package"],
    }
    return notification, summary


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


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--host", required=True, help="nom de l'hôte dans les messages")
    parser.add_argument("--ntfy-url", required=True)
    parser.add_argument("--topic", required=True)
    parser.add_argument("--boot-dir", default="/boot")
    parser.add_argument("--retry-delay", type=int, default=60)
    args = parser.parse_args(argv)

    token = os.environ.get(NTFY_TOKEN_VARIABLE, "")
    push_url = os.environ.get(PUSH_URL_VARIABLE, "")
    try:
        notification, summary = check_apt(args)
        if notification:
            publish(args.ntfy_url, args.topic, token, notification)
            print(f"publié : {notification['title']}", flush=True)
    except CheckError as error:
        print(f"down: {error}", flush=True)
        push(push_url, "down", str(error))
        return 1
    print(f"up: {summary}", flush=True)
    return 0 if push(push_url, "up", summary) else 2


if __name__ == "__main__":
    sys.exit(main())
