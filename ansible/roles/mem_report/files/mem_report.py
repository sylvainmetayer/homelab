#!/usr/bin/python3
"""Rapport hebdomadaire de la mémoire des conteneurs, publié sur ntfy (rôle mem_report).

Lancé chaque semaine par mem-report.timer. Pour chaque conteneur en cours
(`docker ps`), lit dans son cgroup v2 memory.max (la limite, mem_limit),
memory.peak (le pic depuis la création du cgroup), memory.current et
memory.events (max, oom, oom_kill), puis publie sur ntfy :
  - les conteneurs à au moins --high % de leur limite, ou tués par l'OOM
    killer : à agrandir ;
  - ceux dont le pic reste sous --low % de la limite, quand la limite
    suggérée libère au moins --min-saving-mb : à réduire ;
  - ceux qui n'ont pas de limite (la doctrine en veut une partout) ;
  - ceux dont la limite réelle (memory.max) n'est pas le mem_limit de leur
    compose : un conteneur créé sans contrôleur mémoire garde « max » une fois
    le contrôleur revenu, et `docker compose up` ne le recrée pas, sa
    configuration n'ayant pas changé (leçon du Pi, #846).
La limite suggérée est 2x le pic, arrondie au-dessus (doctrine des limites,
AGENTS.md). memory.peak et memory.events repartent de zéro avec le cgroup,
c'est-à-dire à chaque redémarrage du conteneur ou du serveur : le message le
rappelle, et signale un pic mesuré sur moins de 7 jours.

Bibliothèque standard seule. Le jeton ntfy (écriture seule sur son topic)
est lu dans l'environnement (EnvironmentFile de l'unité, 0600 root), jamais
sur la ligne de commande, jamais affiché.
"""

import argparse
import datetime
import http.client
import json
import os
import re
import subprocess
import sys
import time
import urllib.request
from pathlib import Path

TOKEN_VARIABLE = "MEM_REPORT_NTFY_TOKEN"
MIB = 1024 * 1024
GIB = 1024 * MIB
# ntfy refuse un message de plus de 4096 octets quand les pièces jointes sont
# désactivées (rôle ntfy) : marge pour le JSON et le pied de message.
MAX_MESSAGE = 3800
# Pic mesuré sur moins de jours que ça : signalé comme sous-estimé.
SHORT_WINDOW_DAYS = 7
# Pic à ce pourcentage de la limite ou plus : le conteneur est au plafond, le
# vrai besoin peut être plus haut que 2x le pic.
AT_CAP_PERCENT = 98
# Pilote systemd (docker-<id>.scope, sous system.slice ou le cgroup_parent du
# compose) ou cgroupfs (docker/<id>).
SCOPE_RE = re.compile(r"^(?:docker-)?([0-9a-f]{64})(?:\.scope)?$")
# Pas de State.OOMKilled : Docker le remet à false à chaque démarrage, il est
# toujours faux sur un conteneur en cours.
INSPECT_FORMAT = (
    "{{.Id}}\t{{.Name}}\t{{.RestartCount}}\t{{.State.StartedAt}}"
    '\t{{index .Config.Labels "com.docker.compose.project.config_files"}}'
    '\t{{index .Config.Labels "com.docker.compose.service"}}'
)
# Le compose tel qu'écrit : ni ${VAR} ni env_file résolus, le script n'a pas à
# voir les secrets. mem_limit y reste donc en texte (« 512m »).
COMPOSE_CONFIG = ("config", "--format", "json", "--no-interpolate", "--no-env-resolution")
COMPOSE_TIMEOUT_SECONDS = 60
# Pour tous les composes d'un hôte : le rapport doit partir avant que l'unité
# ne soit tuée (TimeoutStartSec=5min), les composes restants sont cités.
COMPOSE_BUDGET_SECONDS = 180
# Unités de Docker : base 1024.
COMPOSE_SIZE_RE = re.compile(r"^(\d+(?:\.\d+)?)([kmgt]?)i?b?$", re.IGNORECASE)
# Le noyau arrondit memory.max à la page (16 Kio au plus sur nos hôtes).
DRIFT_TOLERANCE = 64 * 1024
# Les écarts et « À agrandir » : ne partent du message que si le reste est vide.
PROTECTED_SECTIONS = 2


def human(size):
    if size >= GIB:
        return f"{size / GIB:.1f} Gio"
    return f"{size / MIB:.0f} Mio"


def suggested_limit(peak):
    """2x le pic, arrondi au-dessus à un pas lisible (16 Mio, 64 Mio, 256 Mio)."""
    size = 2 * peak
    if size <= 256 * MIB:
        step = 16 * MIB
    elif size <= GIB:
        step = 64 * MIB
    else:
        step = 256 * MIB
    return max(step, -(-size // step) * step)


def compose_size(size):
    """Une taille comme l'écrit un compose (mem_limit) : 512m, 2g."""
    return f"{size // GIB}g" if size % GIB == 0 else f"{size // MIB}m"


def parse_compose_size(value):
    """Un mem_limit de compose en octets ; ValueError s'il n'est pas lisible."""
    match = COMPOSE_SIZE_RE.match(str(value).strip())
    if not match:
        raise ValueError("mem_limit illisible")
    number, unit = match.groups()
    return int(float(number) * 1024 ** " kmgt".index(unit.lower() or " "))


def read_text(path):
    try:
        return path.read_text().strip()
    except (FileNotFoundError, PermissionError):
        return None


def read_bytes(path):
    """Un entier d'un fichier cgroup ; "max" (pas de limite) et absent : None."""
    text = read_text(path)
    return int(text) if text and text.isdigit() else None


def read_events(path):
    events = {}
    for line in (read_text(path) or "").splitlines():
        key, _, value = line.partition(" ")
        if value.strip().isdigit():
            events[key] = int(value)
    return events


def find_scopes(root):
    """{id du conteneur: dossier de son cgroup}, sous toute la hiérarchie."""
    scopes = {}
    for dirpath, dirnames, _ in os.walk(root):
        kept = []
        for name in dirnames:
            match = SCOPE_RE.match(name)
            if match and (name.startswith("docker-") or os.path.basename(dirpath) == "docker"):
                scopes[match.group(1)] = Path(dirpath) / name
            else:
                kept.append(name)
        dirnames[:] = kept
    return scopes


def list_containers(docker):
    """Les conteneurs en cours : (id, nom, redémarrages, démarrage, fichiers
    compose, service)."""
    # Binaire posé par l'ExecStart de l'unité (root, Ansible), sans shell :
    # aucune entrée extérieure.
    ids = subprocess.run(  # NOSONAR
        [docker, "ps", "--quiet", "--no-trunc"], check=True, capture_output=True, text=True
    ).stdout.split()
    if not ids:
        return []
    # Un conteneur arrêté entre les deux appels fait échouer inspect pour lui
    # seul : les lignes des autres sont gardées.
    result = subprocess.run(  # NOSONAR
        [docker, "inspect", "--format", INSPECT_FORMAT, *ids], check=False, capture_output=True, text=True
    )
    if result.returncode != 0 and not result.stdout.strip():
        raise subprocess.CalledProcessError(result.returncode, "docker inspect", stderr=result.stderr)
    containers = []
    for line in result.stdout.splitlines():
        fields = line.split("\t")
        if len(fields) != 6:
            continue
        container_id, name, restarts, started, config_files, service = fields
        containers.append((container_id, name.lstrip("/"), int(restarts or 0), started, config_files, service))
    return containers


def compose_limits(docker, config_files, timeout):
    """{service: mem_limit en octets, ou None} d'un projet compose."""
    files = [arg for path in config_files.split(",") for arg in ("-f", path)]
    # Sortie gardée en mémoire et stderr jamais affiché : le compose peut
    # porter des secrets en clair.
    output = subprocess.run(  # NOSONAR
        [docker, "compose", *files, *COMPOSE_CONFIG],
        check=True,
        capture_output=True,
        text=True,
        timeout=timeout,
    ).stdout
    limits = {}
    for service, config in json.loads(output)["services"].items():
        limit = config.get("mem_limit")
        limits[service] = parse_compose_size(limit) if limit else None
    return limits


def read_declared(docker, containers):
    """({id du conteneur: mem_limit déclaré ou None}, ce qui n'a pas pu être
    comparé). Un conteneur hors compose n'y figure pas : rien à comparer."""
    projects, unread, declared = {}, set(), {}
    deadline = time.monotonic() + COMPOSE_BUDGET_SECONDS
    for container_id, _, _, _, config_files, service in containers:
        if not config_files or not service:
            continue
        if config_files not in projects:
            try:
                timeout = min(COMPOSE_TIMEOUT_SECONDS, deadline - time.monotonic())
                projects[config_files] = compose_limits(docker, config_files, timeout)
            except (OSError, ValueError, KeyError, AttributeError, TypeError, subprocess.SubprocessError) as error:
                # Sa classe seule : l'erreur peut citer le compose.
                print(f"{config_files} non lu : {type(error).__name__}", file=sys.stderr)
                projects[config_files] = None
                unread.add(config_files)
        limits = projects[config_files]
        if limits is None:
            continue
        if service in limits:
            declared[container_id] = limits[service]
        else:
            # Service retiré, conteneur resté : `up --force-recreate` le refuserait.
            unread.add(f"{config_files} : service {service} absent")
    return declared, sorted(unread)


def age_days(started, now):
    try:
        start = datetime.datetime.strptime(started[:19], "%Y-%m-%dT%H:%M:%S").replace(tzinfo=datetime.timezone.utc)
    except ValueError:
        return None
    return (now - start).total_seconds() / 86400


def measure(containers, scopes, now, declared):
    measures, drifts, missing, compared = [], [], 0, 0
    for container_id, name, restarts, started, _, service in containers:
        scope = scopes.get(container_id)
        if scope is None:
            missing += 1
            continue
        drift = {"name": name, "service": service, "declared": declared.get(container_id)}
        current = read_bytes(scope / "memory.current")
        if current is None:
            # Cgroup disparu depuis le parcours (conteneur arrêté), ou
            # contrôleur memory absent (Pi sans cgroup_enable=memory) : rien à
            # lire, surtout pas « sans limite, pic 0 ». Mais sans contrôleur,
            # un mem_limit déclaré n'est pas appliqué : c'est un écart.
            missing += 1
            if scope.is_dir() and declared.get(container_id):
                compared += 1
                drifts.append({**drift, "real": None, "no_controller": True})
            continue
        peak = read_bytes(scope / "memory.peak")
        events = read_events(scope / "memory.events")
        limit = read_bytes(scope / "memory.max")
        drifted = container_id in declared and abs((declared[container_id] or 0) - (limit or 0)) > DRIFT_TOLERANCE
        compared += container_id in declared
        if drifted:
            drifts.append({**drift, "real": limit, "no_controller": False})
        measures.append(
            {
                "name": name,
                "limit": limit,
                "drifted": drifted,
                # memory.peak date du noyau 5.19 : sans lui, l'instantané.
                "peak": peak if peak is not None else current,
                "peak_is_current": peak is None,
                "oom_kill": events.get("oom_kill", 0),
                "max_events": events.get("max", 0),
                "restarts": restarts,
                "days": age_days(started, now),
            }
        )
    return measures, drifts, missing, compared


def window_note(measure_):
    notes = []
    if measure_["peak_is_current"]:
        notes.append("memory.current, pas de memory.peak")
    days = measure_["days"]
    if days is not None and days < SHORT_WINDOW_DAYS:
        notes.append(f"pic sur {days:.0f} j seulement" if days >= 1 else "pic sur moins d'un jour")
    return f" ({', '.join(notes)})" if notes else ""


def recently_restarted(m):
    """Relancé par Docker, pic mesuré sur peu de jours : un OOM-kill du
    processus principal relance le conteneur dans un cgroup neuf, et son pic
    bas ne dit pas qu'il faut réduire."""
    return m["restarts"] > 0 and m["days"] is not None and m["days"] < SHORT_WINDOW_DAYS


def restarts_note(m):
    return f", redémarré x{m['restarts']}" if m["restarts"] else ""


def classify(measures, high, low, min_saving):
    grow, shrink, unlimited = [], [], []
    for m in measures:
        if m["limit"] is None:
            # Une limite déclarée mais pas appliquée est dans la section des
            # écarts : lui en suggérer une serait un faux conseil.
            if not m["drifted"]:
                unlimited.append(m)
            continue
        percent = 100 * m["peak"] / m["limit"]
        m["percent"] = percent
        m["suggested"] = suggested_limit(m["peak"])
        if percent >= high or m["oom_kill"]:
            # Tué sous un pic loin de la limite (memory.current faute de
            # memory.peak) : 2x le pic serait une réduction.
            if m["suggested"] <= m["limit"]:
                m["suggested"] = suggested_limit(m["limit"])
            grow.append(m)
        elif (
            percent < low
            and m["limit"] - m["suggested"] >= min_saving
            and not recently_restarted(m)
            # Limite périmée : le gain se juge une fois recréé, contre le compose.
            and not m["drifted"]
        ):
            shrink.append(m)
    grow.sort(key=lambda m: (-m["oom_kill"], -m["percent"]))
    shrink.sort(key=lambda m: m["suggested"] - m["limit"])
    unlimited.sort(key=lambda m: -m["peak"])
    return grow, shrink, unlimited


def grow_line(m):
    details = [f"pic {human(m['peak'])} / {human(m['limit'])} ({m['percent']:.0f} %)"]
    if m["oom_kill"]:
        details.append(f"OOM-kill x{m['oom_kill']}")
    if m["max_events"]:
        details.append(f"plafond atteint x{m['max_events']}")
    if m["restarts"]:
        details.append(f"redémarré x{m['restarts']}")
    advice = f"mem_limit {compose_size(m['suggested'])}"
    if m["percent"] >= AT_CAP_PERCENT:
        advice += " au moins (au plafond : le besoin réel peut être plus haut)"
    return f"- {m['name']} : {', '.join(details)}{window_note(m)} -> {advice}"


def shrink_line(m):
    return (
        f"- {m['name']} : pic {human(m['peak'])} / {human(m['limit'])} ({m['percent']:.0f} %)"
        f"{restarts_note(m)}{window_note(m)} -> mem_limit {compose_size(m['suggested'])}"
    )


def unlimited_line(m):
    return (
        f"- {m['name']} : pic {human(m['peak'])}{restarts_note(m)}{window_note(m)}"
        f" -> mem_limit {compose_size(suggested_limit(m['peak']))}"
    )


def drift_line(d):
    declared = human(d["declared"]) if d["declared"] else "rien"
    if d["no_controller"]:
        return f"- {d['name']} : déclaré {declared}, contrôleur mémoire absent de l'hôte -> l'activer, puis recréer"
    real = human(d["real"]) if d["real"] else "aucune limite"
    return f"- {d['name']} : déclaré {declared}, réel {real} -> docker compose up -d --force-recreate {d['service']}"


def fit(sections, footer):
    """(message sous MAX_MESSAGE octets, texte complet pour le journal). Les
    dernières lignes (sections triées) de la plus longue section partent les
    premières ; les PROTECTED_SECTIONS premières, seulement quand les autres
    sont vides."""
    sections = [(title, list(lines)) for title, lines in sections]
    dropped = 0

    def render():
        parts = [title + "\n" + "\n".join(lines) for title, lines in sections if lines]
        if dropped:
            parts.append(f"... et {dropped} ligne(s) de plus : journalctl -u mem-report")
        return "\n\n".join(parts + [footer])

    full = message = render()
    while len(message.encode()) > MAX_MESSAGE and any(lines for _, lines in sections):
        others = [lines for _, lines in sections[PROTECTED_SECTIONS:] if lines]
        longest = max(others or [lines for _, lines in sections if lines], key=len)
        longest.pop()
        dropped += 1
        message = render()
    return message, full


def build_report(host, measures, missing, args, drifts, unread, compared):
    grow, shrink, unlimited = classify(measures, args.high, args.low, args.min_saving_mb * MIB)
    sections = [
        (
            "Limite réelle différente du compose (Compose ne le voit pas, un redémarrage ne suffit pas) :",
            [drift_line(d) for d in sorted(drifts, key=lambda d: d["name"])],
        ),
        (f"À agrandir (pic >= {args.high} % de la limite, ou OOM-kill) :", [grow_line(m) for m in grow]),
        (
            f"À réduire (pic < {args.low} % de la limite, {args.min_saving_mb} Mio libérés au moins) :",
            [shrink_line(m) for m in shrink],
        ),
        ("Sans limite (la doctrine en veut une) :", [unlimited_line(m) for m in unlimited]),
        ("Limite non comparée (compose illisible ou service absent) :", [f"- {entry}" for entry in unread]),
    ]
    counted = f"{len(measures)} conteneur(s) lu(s)"
    if missing:
        counted += f", {missing} sans cgroup trouvé"
    counted += f", {compared} comparé(s) à leur compose"
    footer = (
        f"{counted}. Limite suggérée : 2x le pic, arrondie. memory.peak et "
        "memory.events repartent de zéro à chaque redémarrage du conteneur "
        "(et du serveur) : un pic mesuré sur peu de jours sous-estime le besoin."
    )
    if grow or drifts:
        priority, tags = 4, ["warning"]
    elif shrink or unlimited or unread:
        priority, tags = 3, ["chart_with_downwards_trend"]
    else:
        priority, tags = 2, ["white_check_mark"]
        sections = [
            (
                "Rien à signaler :",
                [
                    f"aucun conteneur à {args.high} % de sa limite ni tué, aucun sous {args.low} % "
                    f"dont la réduction libère {args.min_saving_mb} Mio ou plus, {compared} limite(s) "
                    "réelle(s) conforme(s) au compose."
                ],
            )
        ]
    title = f"Mémoire des conteneurs : {host}"
    if not measures and not missing:
        message = "Aucun conteneur en cours : rien à mesurer."
        return {"title": title, "message": message, "priority": 2, "tags": tags}, message
    message, full = fit(sections, footer)
    return {"title": title, "message": message, "priority": priority, "tags": tags}, full


def publish(url, topic, token, report):
    payload = dict(report, topic=topic)
    request = urllib.request.Request(  # NOSONAR
        url.rstrip("/") + "/",
        data=json.dumps(payload).encode(),
        headers={"Authorization": f"Bearer {token}", "Content-Type": "application/json"},
        method="POST",
    )
    # URL posée par l'ExecStart de l'unité (Ansible), pas une entrée
    # extérieure : la règle SSRF de Sonar ne s'applique pas.
    with urllib.request.urlopen(request, timeout=30) as response:  # NOSONAR
        response.read()


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--host", required=True, help="nom de l'hôte dans le titre")
    parser.add_argument("--url", required=True, help="URL du serveur ntfy")
    parser.add_argument("--topic", required=True)
    parser.add_argument("--high", type=int, default=80)
    parser.add_argument("--low", type=int, default=25)
    parser.add_argument("--min-saving-mb", type=int, default=64)
    parser.add_argument("--cgroup-root", default="/sys/fs/cgroup")
    parser.add_argument("--docker", default="/usr/bin/docker")
    args = parser.parse_args(argv)

    now = datetime.datetime.now(datetime.timezone.utc)
    try:
        containers = list_containers(args.docker)
        declared, unread = read_declared(args.docker, containers)
        measures, drifts, missing, compared = measure(containers, find_scopes(args.cgroup_root), now, declared)
        # Le journal garde le texte complet, lignes coupées du message comprises.
        report, journal = build_report(args.host, measures, missing, args, drifts, unread, compared)
        failed = False
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        # Publié quand même : un rapport qui ne vient plus ne se remarque pas.
        report = {
            "title": f"Mémoire des conteneurs : {args.host}",
            "message": f"Lecture impossible ({type(error).__name__}) : journalctl -u mem-report",
            "priority": 4,
            "tags": ["warning"],
        }
        print(f"lecture en échec : {error}", file=sys.stderr)
        journal = report["message"]
        failed = True
    print(f"{report['title']}\n\n{journal}", flush=True)

    token = os.environ.get(TOKEN_VARIABLE, "")
    if not token:
        print(f"{TOKEN_VARIABLE} vide : rien n'est publié.", file=sys.stderr)
        return 1 if failed else 0
    try:
        publish(args.url, args.topic, token, report)
    except (OSError, ValueError, http.client.HTTPException) as error:
        # Sa classe seule : une erreur d'urllib peut citer la requête.
        print(f"publication sur ntfy en échec : {type(error).__name__}", file=sys.stderr)
        return 2
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
