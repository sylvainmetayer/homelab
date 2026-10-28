"""Fixtures du scénario mem_report, dans le dossier donné :
  - cgroup/ : un faux /sys/fs/cgroup, un dossier par conteneur (memory.max,
    memory.peak, memory.current, memory.events) ;
  - inspect.tsv : ce que le faux docker (fake_docker.sh) répond à `ps` et à
    `inspect`, au format INSPECT_FORMAT de mem_report.py.
"""

import datetime
import os
import sys

MIB = 1024 * 1024
ROOT = sys.argv[1]
NOW = datetime.datetime.now(datetime.timezone.utc)

# (caractère de l'id, nom, dossier du cgroup ou None, memory.max, memory.peak
# ou None, memory.current, événements max, oom_kill, redémarrages, âge en jours)
CONTAINERS = [
    # 255 Mio sur 256 Mio, un OOM-kill : à agrandir, au plafond.
    ("a", "molecule-big", "system.slice/docker-{}.scope", 256 * MIB, 255 * MIB, 190 * MIB, 12, 1, 0, 30),
    # 100 Mio sur 1 Gio, sous le cgroup_parent des conteneurs du NAS, démarré
    # il y a 2 jours : à réduire, pic sur peu de jours.
    ("b", "molecule-idle", "nas-storage.slice/docker-{}.scope", 1024 * MIB, 100 * MIB, 48 * MIB, 0, 0, 0, 2),
    # Pas de limite.
    ("c", "molecule-nolimit", "system.slice/docker-{}.scope", "max", 50 * MIB, 38 * MIB, 0, 0, 0, 30),
    # 4 Mio sur 64 Mio : sous 25 %, mais 16m ne libère que 48 Mio.
    ("d", "molecule-small", "system.slice/docker-{}.scope", 64 * MIB, 4 * MIB, 3 * MIB, 0, 0, 0, 30),
    # Noyau sans memory.peak : memory.current, 900 Mio sur 1 Gio.
    ("e", "molecule-oldkernel", "system.slice/docker-{}.scope", 1024 * MIB, None, 900 * MIB, 0, 0, 3, 30),
    # Pilote cgroupfs (docker/<id>), 300 Mio sur 512 Mio : rien à dire.
    ("f", "molecule-cgroupfs", "docker/{}", 512 * MIB, 300 * MIB, 290 * MIB, 0, 0, 0, 30),
    # Listé par docker, cgroup introuvable.
    ("9", "molecule-gone", None, None, None, None, 0, 0, 0, 30),
]


def write(directory, name, value):
    with open(os.path.join(directory, name), "w") as handle:
        handle.write(f"{value}\n")


with open(os.path.join(ROOT, "inspect.tsv"), "w") as tsv:
    for char, name, path, limit, peak, current, max_events, oom_kill, restarts, days in CONTAINERS:
        container_id = char * 64
        if path:
            directory = os.path.join(ROOT, "cgroup", path.format(container_id))
            os.makedirs(directory, mode=0o700)
            write(directory, "memory.max", limit)
            if peak is not None:
                write(directory, "memory.peak", peak)
            write(directory, "memory.current", current)
            write(
                directory,
                "memory.events",
                f"low 0\nhigh 0\nmax {max_events}\noom {oom_kill}\noom_kill {oom_kill}\noom_group_kill 0",
            )
        started = (NOW - datetime.timedelta(days=days)).strftime("%Y-%m-%dT%H:%M:%S.123456789Z")
        tsv.write(f"{container_id}\t/{name}\t{restarts}\tfalse\t{started}\n")

# Le cgroup d'un conteneur que docker ne liste pas (ceux du runner de la CI,
# vus à travers cgroupns host) : ignoré.
foreign = os.path.join(ROOT, "cgroup", "system.slice", "docker-" + "1" * 64 + ".scope")
os.makedirs(foreign, mode=0o700)
write(foreign, "memory.max", MIB)
write(foreign, "memory.peak", MIB)
