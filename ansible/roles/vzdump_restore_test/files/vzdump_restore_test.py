#!/usr/bin/python3
"""Test de restauration des sauvegardes vzdump de l'hôte Proxmox.

Lancé deux fois par mois par vzdump-restore-test.timer (rôle
vzdump_restore_test, pve.yml), en root sur l'hôte même : seuls pct, qm et vma
savent lire une archive vzdump. Pour la dernière sauvegarde de chaque invité
sur le storage du job (nas-backup) :

- LXC (newt) : âge, taille et journal de la sauvegarde, puis restauration
  sur un id jetable (9xx) du storage local, interfaces réseau débranchées
  puis supprimées avant tout démarrage, unités masquées (newt : un second
  Newt avec les mêmes identifiants volerait le tunnel du site), fichiers
  attendus lus hors ligne, démarrage, systemd doit atteindre running ou
  degraded sans aucune interface réseau, puis destruction ;
- VM (docker) : âge, taille et journal, puis l'archive entière décompressée
  et vérifiée (`zstd -d | vma verify`). La restauration complète (qm create
  --archive, sans réseau, démarrage jusqu'au ping de l'agent QEMU, puis
  destruction) est désactivée par défaut : 190 Go de disque et de la mémoire
  que l'hôte n'a pas toujours ; quand elle est demandée, l'espace du storage
  local et la mémoire disponible sont vérifiés d'abord.

Garde-fous : un id cible doit être dans 900-999, libre (aucun invité, aucun
volume) et différent des sources ; rien n'est restauré avec --force ; un
invité n'est détruit que s'il a été créé par ce run et porte la marque
`vzdump-restore-test` dans sa description. Un verrou empêche deux runs, celui
de vzdump (/var/run/vzdump.lock) est tenu pendant tout le test : pas de
sauvegarde ni d'élagage de l'archive lue pendant qu'on la lit. SIGTERM
(délai de l'unité dépassé) interrompt la commande en cours et passe au
nettoyage.

Le résultat part sur ntfy (topic scripts, priorité haute sur échec) et au
moniteur push « Test restauration vzdump » d'Uptime Kuma (tofu/
pangolin_config), qui passe aussi au rouge si plus rien n'arrive. L'URL push
et le jeton ntfy sont lus dans l'environnement (EnvironmentFile 0600 root),
jamais sur la ligne de commande, jamais affichés.

Bibliothèque standard seule : Proxmox n'a ni jq ni pip, mais un python3.
"""

import argparse
import datetime
import fcntl
import json
import os
import re
import signal
import socket
import subprocess
import sys
import time
import traceback
import urllib.parse
import urllib.request

MARKER = "vzdump-restore-test"
TARGET_IDS = range(900, 1000)
LOCK_PATH = "/run/lock/vzdump-restore-test.lock"
VZDUMP_LOCK_PATH = "/var/run/vzdump.lock"
PUSH_URL_VARIABLE = "VZDUMP_RESTORE_TEST_PUSH_URL"
NTFY_TOKEN_VARIABLE = "VZDUMP_RESTORE_TEST_NTFY_TOKEN"
# Délai laissé à une commande interrompue (SIGTERM) pour annuler sa tâche.
STOP_GRACE = 120

NET_KEY = re.compile(r"net\d+")
DRIVE_KEY = re.compile(r"(?:ide|sata|scsi|virtio|efidisk|tpmstate)\d+")
SIZE_UNITS = {"": 1, "K": 1024, "M": 1024**2, "G": 1024**3, "T": 1024**4}
GIB = 1024**3


class TestFailure(Exception):
    """Un contrôle a échoué : le message part tel quel dans le rapport."""


class Terminated(Exception):
    """SIGTERM reçu (délai de l'unité dépassé, arrêt de l'hôte)."""


def on_sigterm(signum, _frame):
    raise Terminated(f"interrompu par le signal {signum}")


def stop(proc):
    """SIGTERM d'abord, SIGKILL après STOP_GRACE secondes.

    pct restore et qm create confient le travail à une tâche détachée
    (fork + setsid) : leur SIGTERM lui est relayé, elle annule la
    restauration et supprime l'invité à moitié créé. Un SIGKILL d'emblée ne
    tuerait que le client : la tâche finirait seule, ou serait tuée à la
    sortie de l'unité en laissant l'invité verrouillé (lock: create), sans
    la marque, que destroy() refuse alors de détruire.
    """
    proc.terminate()
    try:
        proc.communicate(timeout=STOP_GRACE)
    except subprocess.TimeoutExpired:
        proc.kill()
        proc.wait()


def run(argv, timeout=600, check=True, quiet=False):
    """Lance une commande, sortie dans le journal (sauf quiet : le JSON de
    pvesh) ; jamais de secret en argv.

    Délai dépassé ou exception (Terminated comprise) : l'enfant est arrêté
    par stop(), jamais laissé derrière.
    """
    print("+ " + " ".join(argv), flush=True)
    try:
        proc = subprocess.Popen(
            argv,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
    except OSError as error:
        raise TestFailure(f"{argv[0]} : {error.strerror}") from error
    with proc:
        try:
            stdout, stderr = proc.communicate(timeout=timeout)
        except subprocess.TimeoutExpired as error:
            stop(proc)
            raise TestFailure(f"{' '.join(argv[:3])} : plus de {timeout} s") from error
        except BaseException:
            stop(proc)
            raise
    proc = subprocess.CompletedProcess(argv, proc.returncode, stdout, stderr)
    for stream in (proc.stderr,) if quiet else (proc.stdout, proc.stderr):
        if stream.strip():
            print(stream.rstrip(), flush=True)
    if check and proc.returncode != 0:
        lines = (proc.stderr.strip() or proc.stdout.strip()).splitlines()
        last = lines[-1] if lines else ""
        raise TestFailure(f"{' '.join(argv[:3])} : code {proc.returncode} ({last})")
    return proc


def pvesh(path, **params):
    argv = ["pvesh", "get", path, "--output-format", "json"]
    for key, value in params.items():
        argv += [f"--{key}", str(value)]
    return json.loads(run(argv, timeout=180, quiet=True).stdout or "null")


def parse_conf(text):
    """Configuration d'invité Proxmox (clé: valeur), sans les instantanés."""
    conf = {}
    for line in text.splitlines():
        if line.startswith("["):
            break
        if not line or line.startswith("#") or ": " not in line:
            continue
        key, value = line.split(": ", 1)
        conf[key.strip()] = value.strip()
    return conf


def option(value, name):
    """Valeur d'une option `name=` d'une chaîne Proxmox (a=b,c=d)."""
    for part in value.split(","):
        if part.startswith(name + "="):
            return part.split("=", 1)[1]
    return None


def size_bytes(text):
    match = re.fullmatch(r"(\d+(?:\.\d+)?)([KMGT]?)", text)
    if not match:
        raise TestFailure(f"taille de disque illisible : {text}")
    return int(float(match.group(1)) * SIZE_UNITS[match.group(2)])


def disk_bytes(conf):
    """Taille déclarée de tous les disques (lecteurs CD exclus)."""
    total = 0
    for key, value in conf.items():
        if DRIVE_KEY.fullmatch(key) and "media=cdrom" not in value:
            size = option(value, "size")
            if size:
                total += size_bytes(size)
    return total


def gib(value):
    return f"{value / GIB:.1f} Gio"


def mem_available_mib():
    with open("/proc/meminfo", encoding="ascii") as meminfo:
        for line in meminfo:
            if line.startswith("MemAvailable:"):
                return int(line.split()[1]) // 1024
    raise TestFailure("MemAvailable absent de /proc/meminfo")


def rootfs_path(rootfs, relative):
    """Chemin dans le rootfs monté, sans suivre de lien d'un dossier parent.

    Un lien absolu de l'invité pointerait sur l'hôte une fois le rootfs
    monté ici : chaque dossier intermédiaire doit en être un vrai.
    """
    parts = [part for part in relative.split("/") if part]
    if not parts or ".." in parts:
        raise TestFailure(f"chemin refusé : {relative}")
    current = rootfs
    for part in parts[:-1]:
        current = os.path.join(current, part)
        if os.path.islink(current) or not os.path.isdir(current):
            raise TestFailure(f"/{relative} : /{os.path.relpath(current, rootfs)} n'est pas un dossier")
    return os.path.join(current, parts[-1])


class Run:
    def __init__(self, config):
        self.config = config
        self.node = socket.gethostname().split(".")[0]
        self.backup_storage = config["backup_storage"]
        self.restore_storage = config["restore_storage"]
        self.now = time.time()
        self.lines = []
        self.failures = []
        self.created = []
        self.protected = set()
        self.existing = set()

    # --- contexte -----------------------------------------------------------

    def guests(self):
        return {int(guest["vmid"]) for guest in pvesh("/cluster/resources", type="vm")}

    def check_target(self, kind, source, target):
        if target not in TARGET_IDS:
            raise TestFailure(f"{kind} : id cible {target} hors de 900-999")
        if target in self.protected:
            raise TestFailure(f"{kind} : id cible {target} déjà pris (invité existant ou source)")
        volumes = pvesh(f"/nodes/{self.node}/storage/{self.restore_storage}/content", vmid=target)
        if volumes:
            names = ", ".join(volume["volid"] for volume in volumes)
            raise TestFailure(f"{kind} : volumes orphelins de {target} sur {self.restore_storage} ({names})")
        if source == target:
            raise TestFailure(f"{kind} : la source et la cible sont le même id")

    def latest_backup(self, kind, vmid, min_size_mb):
        content = pvesh(
            f"/nodes/{self.node}/storage/{self.backup_storage}/content",
            content="backup",
            vmid=vmid,
        )
        backups = [item for item in content if int(item.get("vmid", -1)) == vmid]
        if not backups:
            raise TestFailure(f"{kind} {vmid} : aucune sauvegarde sur {self.backup_storage}")
        backup = max(backups, key=lambda item: int(item["ctime"]))
        age = (self.now - int(backup["ctime"])) / 3600
        when = datetime.datetime.fromtimestamp(int(backup["ctime"])).strftime("%d/%m %H:%M")
        size = int(backup["size"])
        shown = gib(size) if size >= GIB else f"{size / 1024**2:.0f} Mio"
        backup["summary"] = f"sauvegarde du {when} ({age:.0f} h, {shown})"
        if age > self.config["max_age_hours"]:
            raise TestFailure(
                f"{kind} {vmid} : dernière {backup['summary']}, plus vieille que {self.config['max_age_hours']} h"
            )
        if size < min_size_mb * 1024**2:
            raise TestFailure(f"{kind} {vmid} : {backup['summary']}, sous {min_size_mb} Mio")
        backup["path"] = run(["pvesm", "path", backup["volid"]]).stdout.strip()
        self.check_log(kind, vmid, backup["path"])
        return backup

    def check_log(self, kind, vmid, path):
        log = re.sub(r"\.(?:vma|tar)(?:\.(?:zst|gz|lzo))?$", ".log", path)
        if log == path or not os.path.isfile(log):
            self.lines.append(f"{kind} {vmid} : pas de journal vzdump à côté de l'archive")
            return
        with open(log, encoding="utf-8", errors="replace") as handle:
            text = handle.read()
        if "ERROR:" in text or f"Finished Backup of VM {vmid}" not in text:
            raise TestFailure(f"{kind} {vmid} : le journal de la sauvegarde signale une erreur ({os.path.basename(log)})")

    def archive_conf(self, volid):
        return parse_conf(pvesh(f"/nodes/{self.node}/vzdump/extractconfig", volume=volid) or "")

    def guest_conf(self, kind, vmid):
        return pvesh(f"/nodes/{self.node}/{kind}/{vmid}/config")

    def unplugged(self, conf, lxc):
        """Options --netN qui remplacent celles de l'archive : câble débranché."""
        argv = []
        for key, value in sorted(conf.items()):
            if not NET_KEY.fullmatch(key):
                continue
            bridge = option(value, "bridge")
            if lxc:
                first = f"name={option(value, 'name') or 'eth' + key[3:]}"
            else:
                # Le modèle : « virtio=MAC » ou « model=virtio,macaddr=MAC ».
                name, _, model = value.split(",", 1)[0].partition("=")
                first = model if name == "model" else name
            argv += [f"--{key}", first + (f",bridge={bridge}" if bridge else "") + ",link_down=1"]
        return argv

    def assert_offline(self, kind, vmid):
        conf = self.guest_conf(kind, vmid)
        nets = sorted(key for key in conf if NET_KEY.fullmatch(key))
        if nets:
            raise TestFailure(f"{vmid} : interfaces réseau encore présentes ({', '.join(nets)}), pas de démarrage")
        if str(conf.get("onboot", "0")) != "0":
            raise TestFailure(f"{vmid} : onboot actif, pas de démarrage")
        if MARKER not in (conf.get("description") or ""):
            raise TestFailure(f"{vmid} : marque {MARKER} absente de la description, pas de démarrage")
        return conf

    # --- LXC ----------------------------------------------------------------

    def test_lxc(self, settings):
        source, target = settings["source"], settings["target"]
        self.check_target("LXC", source, target)
        backup = self.latest_backup("LXC", source, settings["min_size_mb"])
        conf = self.archive_conf(backup["volid"])
        hostname = conf.get("hostname", "")
        nets = [key for key in conf if NET_KEY.fullmatch(key)]

        self.created.append(("lxc", target))
        run(
            [
                "pct", "restore", str(target), backup["volid"],
                "--storage", self.restore_storage,
                "--unique", "1",
                "--unprivileged", conf.get("unprivileged", "0"),
                "--onboot", "0",
                "--description", f"{MARKER} : copie jetable de {source}, détruite à la fin du test",
                *self.unplugged(conf, lxc=True),
            ],
            timeout=settings["restore_timeout"],
        )
        if nets:
            run(["pct", "set", str(target), "--delete", ",".join(nets)])
        self.assert_offline("lxc", target)

        self.check_rootfs(target, hostname, settings)

        run(["pct", "start", str(target)], timeout=300)
        interfaces = run(["pct", "exec", str(target), "--", "ls", "-1", "/sys/class/net"]).stdout.split()
        if set(interfaces) - {"lo"}:
            run(["pct", "stop", str(target)], timeout=180, check=False)
            raise TestFailure(f"LXC {target} : interfaces réseau au démarrage ({', '.join(interfaces)}), arrêté")
        timeout = settings["boot_timeout"]
        state = run(
            ["pct", "exec", str(target), "--", "timeout", str(timeout), "systemctl", "is-system-running", "--wait"],
            timeout=timeout + 60,
            check=False,
        ).stdout.strip()
        if state not in ("running", "degraded"):
            raise TestFailure(f"LXC {target} : systemd à l'état « {state or 'inconnu'} » après {timeout} s")
        detail = ""
        if state == "degraded":
            failed = run(
                ["pct", "exec", str(target), "--", "systemctl", "--failed", "--plain", "--no-legend", "--no-pager"],
                check=False,
            ).stdout.split("\n")
            units = [line.split()[0] for line in failed if line.strip()]
            detail = f" ({', '.join(units)} en échec, sans réseau)" if units else ""
        run(["pct", "stop", str(target)], timeout=180)
        self.lines.append(
            f"LXC {source} : {backup['summary']}, restaurée sur {target} sans réseau, "
            f"systemd {state}{detail}, {hostname} et fichiers attendus présents"
        )

    def check_rootfs(self, target, hostname, settings):
        mounted = run(["pct", "mount", str(target)]).stdout
        match = re.search(r"in '([^']+)'", mounted)
        if not match:
            raise TestFailure(f"LXC {target} : point de montage introuvable dans « {mounted.strip()} »")
        rootfs = match.group(1)
        try:
            path = rootfs_path(rootfs, "etc/hostname")
            if os.path.islink(path) or not os.path.isfile(path):
                raise TestFailure(f"LXC {target} : /etc/hostname absent")
            with open(path, encoding="utf-8", errors="replace") as handle:
                found = handle.read().strip()
            if hostname and found != hostname:
                raise TestFailure(f"LXC {target} : /etc/hostname vaut « {found} », pas « {hostname} »")
            for relative in settings["expect_files"] + settings["expect_executables"]:
                path = rootfs_path(rootfs, relative)
                if os.path.islink(path) or not os.path.isfile(path):
                    raise TestFailure(f"LXC {target} : /{relative} absent")
                if relative in settings["expect_executables"] and not os.stat(path).st_mode & 0o111:
                    raise TestFailure(f"LXC {target} : /{relative} n'est pas exécutable")
            # Masquée pour ce démarrage : sans réseau elle ne joindrait rien,
            # mais une interface oubliée ne doit pas suffire à lancer un
            # second Newt sur les identifiants du site.
            for unit in settings["mask_units"]:
                path = rootfs_path(rootfs, f"etc/systemd/system/{unit}")
                temporary = path + f".{MARKER}"
                if os.path.lexists(temporary):
                    os.unlink(temporary)
                os.symlink("/dev/null", temporary)
                os.replace(temporary, path)
        finally:
            run(["pct", "unmount", str(target)], check=False)

    # --- VM -----------------------------------------------------------------

    def test_vm(self, settings):
        source, target = settings["source"], settings["target"]
        self.check_target("VM", source, target)
        backup = self.latest_backup("VM", source, settings["min_size_mb"])
        conf = self.archive_conf(backup["volid"])

        status = pvesh(f"/nodes/{self.node}/storage/{self.restore_storage}/status")
        total, avail = int(status["total"]), int(status["avail"])
        needed = disk_bytes(conf)
        margin = total * self.config["free_margin_percent"] // 100
        space = (
            f"{self.restore_storage} : {gib(avail)} libres sur {gib(total)}, "
            f"disques de la VM {gib(needed)}, marge {gib(margin)}"
        )
        memory = mem_available_mib()
        space += f" ; mémoire disponible {memory} Mio"

        if not settings["full_restore"]:
            self.verify_archive(backup, settings["verify_timeout"])
            self.lines.append(f"VM {source} : {backup['summary']}, archive vérifiée (zstd + vma verify)")
            self.lines.append(f"{space} (restauration complète désactivée)")
            return
        if avail - needed < margin:
            self.verify_archive(backup, settings["verify_timeout"])
            self.lines.append(f"VM {source} : {backup['summary']}, archive vérifiée (zstd + vma verify)")
            self.lines.append(f"{space} : pas assez de place, restauration complète sautée")
            return

        self.created.append(("qemu", target))
        run(
            [
                "qm", "create", str(target),
                "--archive", backup["volid"],
                "--storage", self.restore_storage,
                "--unique", "1",
                "--onboot", "0",
                "--memory", str(settings["boot_memory_mb"]),
                "--balloon", "0",
                "--name", f"restore-test-{source}",
                "--description", f"{MARKER} : copie jetable de {source}, détruite à la fin du test",
                *self.unplugged(conf, lxc=False),
            ],
            timeout=settings["restore_timeout"],
        )
        restored = self.guest_conf("qemu", target)
        nets = sorted(key for key in restored if NET_KEY.fullmatch(key))
        if nets:
            change = ["--delete", ",".join(nets)]
            boot = restored.get("boot", "")
            if boot.startswith("order="):
                order = [device for device in boot[len("order="):].split(";") if device not in nets]
                change += ["--boot", "order=" + ";".join(order)] if order else []
            run(["qm", "set", str(target), *change])
        self.assert_offline("qemu", target)

        # Relue : la restauration a pu durer des heures depuis la mesure.
        memory = mem_available_mib()
        if memory - settings["boot_memory_mb"] < settings["host_memory_reserve_mb"]:
            self.lines.append(f"VM {source} : {backup['summary']}, restaurée sur {target}, démarrage sauté (mémoire)")
            self.lines.append(space)
            return
        run(["qm", "start", str(target)], timeout=300)
        deadline = time.monotonic() + settings["boot_timeout"]
        while run(["qm", "guest", "cmd", str(target), "ping"], timeout=60, check=False).returncode != 0:
            if time.monotonic() > deadline:
                raise TestFailure(f"VM {target} : l'agent QEMU ne répond pas après {settings['boot_timeout']} s")
            time.sleep(10)
        run(["qm", "stop", str(target)], timeout=300)
        self.lines.append(
            f"VM {source} : {backup['summary']}, restaurée sur {target} sans réseau, agent QEMU joint au démarrage"
        )
        self.lines.append(space)

    def verify_archive(self, backup, timeout):
        """Décompresse l'archive entière : somme zstd de chaque trame, puis la
        structure VMA (en-têtes, extents, blocs de chaque disque)."""
        path = backup["path"]
        if path.endswith(".vma.zst"):
            stages = [["zstd", "-q", "-d", "-c", path], ["vma", "verify", "-"]]
        elif path.endswith(".vma"):
            stages = [["vma", "verify", path]]
        else:
            raise TestFailure(f"{os.path.basename(path)} : format d'archive non géré")
        print("+ " + " | ".join(" ".join(stage) for stage in stages), flush=True)
        started = time.monotonic()
        processes = []
        try:
            for index, stage in enumerate(stages):
                last = index == len(stages) - 1
                stdin = processes[-1].stdout if processes else subprocess.DEVNULL
                processes.append(
                    subprocess.Popen(
                        stage,
                        stdin=stdin,
                        stdout=subprocess.DEVNULL if last else subprocess.PIPE,
                        stderr=subprocess.PIPE,
                    )
                )
                # Le tube n'appartient plus qu'aux deux processus : vma
                # sorti en erreur, zstd reçoit SIGPIPE au lieu de bloquer.
                if processes[:-1]:
                    stdin.close()
            for process in reversed(processes):
                remaining = max(1, timeout - (time.monotonic() - started))
                try:
                    _, error = process.communicate(timeout=remaining)
                except subprocess.TimeoutExpired as expired:
                    raise TestFailure(f"vérification de l'archive : plus de {timeout} s") from expired
                if process.returncode != 0:
                    tail = error.decode(errors="replace").strip().splitlines()[-1:]
                    raise TestFailure(
                        f"{process.args[0]} : code {process.returncode} sur l'archive ({' '.join(tail)})"
                    )
        finally:
            for process in processes:
                if process.poll() is None:
                    process.kill()
                    process.wait()
        print(f"archive vérifiée en {(time.monotonic() - started) / 60:.0f} min", flush=True)

    # --- nettoyage ----------------------------------------------------------

    def destroy(self, kind, vmid):
        if vmid not in TARGET_IDS or vmid in self.protected:
            raise TestFailure(f"{vmid} : refus de détruire un id hors de la plage de test ou préexistant")
        if vmid not in self.guests():
            return
        conf = self.guest_conf(kind, vmid)
        if MARKER not in (conf.get("description") or ""):
            raise TestFailure(f"{vmid} existe sans la marque {MARKER} : laissé en place, à voir à la main")
        tool = "pct" if kind == "lxc" else "qm"
        if kind == "lxc":
            run(["pct", "unmount", str(vmid)], check=False)
        if "status: running" in run([tool, "status", str(vmid)]).stdout:
            run([tool, "stop", str(vmid)], timeout=300)
        run([tool, "destroy", str(vmid), "--purge", "0", "--destroy-unreferenced-disks", "0"], timeout=900)
        if vmid in self.guests():
            raise TestFailure(f"{vmid} : toujours là après destroy")

    def cleanup(self):
        while self.created:
            kind, vmid = self.created[-1]
            try:
                self.destroy(kind, vmid)
            except (TestFailure, OSError, ValueError, KeyError) as error:
                self.failures.append(f"nettoyage de {vmid} : {error}")
            # Pas retiré sur SIGTERM (Terminated) : le nettoyage final de
            # main() le reprend.
            self.created.pop()

    # --- déroulé ------------------------------------------------------------

    def execute(self):
        self.existing = self.guests()
        sources = {settings["source"] for settings in (self.config.get("lxc"), self.config.get("vm")) if settings}
        self.protected = self.existing | sources
        for name, test in (("lxc", self.test_lxc), ("vm", self.test_vm)):
            settings = self.config.get(name)
            if not settings:
                continue
            try:
                test(settings)
            except TestFailure as error:
                self.failures.append(str(error))
            except (OSError, ValueError, KeyError) as error:
                # Un rootfs illisible, un JSON inattendu : ce test échoue, le
                # suivant tourne quand même. Terminated, lui, remonte.
                traceback.print_exc()
                self.failures.append(f"{name.upper()} : erreur inattendue : {type(error).__name__}: {error}")
            finally:
                # La copie détruite dès son test fini : le LXC n'attend pas
                # la demi-heure de lecture de l'archive de la VM.
                self.cleanup()


def acquire(path, what):
    # Ouvert en ajout comme vzdump le fait ; tenu jusqu'à la fin du run.
    handle = open(path, "a", encoding="ascii")
    try:
        fcntl.flock(handle, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError as error:
        handle.close()
        raise TestFailure(f"{what} : verrou {path} déjà pris") from error
    return handle


def push(url, status, msg):
    query = urllib.parse.urlencode({"status": status, "msg": msg[:250], "ping": ""})
    separator = "&" if "?" in url else "?"
    with urllib.request.urlopen(url + separator + query, timeout=30) as response:
        response.read()


def ntfy(settings, token, title, message, failed):
    body = json.dumps(
        {
            "topic": settings["topic"],
            "title": title,
            "message": message,
            # 4 (high) : son et bandeau, sans le 5 qui passe le Ne pas déranger.
            "priority": 4 if failed else 2,
            "tags": ["rotating_light"] if failed else ["white_check_mark"],
        }
    ).encode()
    request = urllib.request.Request(
        settings["url"].rstrip("/") + "/",
        data=body,
        method="POST",
        headers={"Authorization": f"Bearer {token}", "Content-Type": "application/json"},
    )
    with urllib.request.urlopen(request, timeout=30) as response:
        response.read()


def notify(config, failures, lines):
    failed = bool(failures)
    title = "Test de restauration vzdump : " + ("ÉCHEC" if failed else "OK")
    message = "\n".join([f"ÉCHEC : {failure}" for failure in failures] + lines)
    print(f"{title}\n{message}", flush=True)
    problems = 0

    token = os.environ.get(NTFY_TOKEN_VARIABLE, "")
    if token and config.get("ntfy"):
        try:
            ntfy(config["ntfy"], token, title, message, failed)
        except (OSError, ValueError) as error:
            # Une erreur d'urllib peut citer l'URL : sa classe seule est affichée.
            print(f"envoi à ntfy en échec : {type(error).__name__}", file=sys.stderr)
            problems += 1
    else:
        print(f"{NTFY_TOKEN_VARIABLE} vide : rien n'est envoyé à ntfy.", file=sys.stderr)

    url = os.environ.get(PUSH_URL_VARIABLE, "")
    if url:
        try:
            push(url, "down" if failed else "up", "; ".join(failures) or " ; ".join(lines))
        # ValueError : http.client.InvalidURL et « unknown url type » citent
        # l'URL, donc le jeton du moniteur, dans un traceback.
        except (OSError, ValueError) as error:
            print(f"push vers Uptime Kuma en échec : {type(error).__name__}", file=sys.stderr)
            problems += 1
    else:
        print(f"{PUSH_URL_VARIABLE} vide : rien n'est poussé.", file=sys.stderr)
    return problems


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--config", required=True, help="fichier JSON posé par le rôle")
    args = parser.parse_args(argv)
    with open(args.config, encoding="utf-8") as handle:
        config = json.load(handle)

    signal.signal(signal.SIGTERM, on_sigterm)
    test = Run(config)
    locks = []
    try:
        locks.append(acquire(LOCK_PATH, "un autre test de restauration tourne"))
        locks.append(acquire(VZDUMP_LOCK_PATH, "vzdump tourne"))
        test.execute()
    except (TestFailure, Terminated) as error:
        test.failures.append(str(error))
    except Exception as error:  # NOSONAR : tout échec doit être rapporté et nettoyé
        traceback.print_exc()
        test.failures.append(f"erreur inattendue : {type(error).__name__}: {error}")
    finally:
        # Un second SIGTERM n'interrompt pas le nettoyage (KillMode=mixed :
        # SIGKILL seulement après TimeoutStopSec).
        signal.signal(signal.SIGTERM, signal.SIG_IGN)
        test.cleanup()
        for handle in locks:
            handle.close()

    problems = notify(config, test.failures, test.lines)
    if test.failures:
        return 1
    return 2 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
