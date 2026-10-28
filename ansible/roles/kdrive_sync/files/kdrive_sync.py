#!/usr/bin/python3
"""Copie à sens unique de kDrive vers le NAS (rôle kdrive_sync).

Lancé chaque nuit par kdrive-sync.timer, en root, sur le NAS. Exécute la
commande reçue après `--` (le `docker compose run --rm` de l'image rclone),
en lui ajoutant `--backup-dir <racine>/<horodatage>` : un fichier que la copie
remplace y est déplacé au lieu d'être écrasé, dans un dossier par passage
(deux passages le même jour ne s'écrasent pas). Relaie la sortie de rclone
au journal, lit ses statistiques finales (--use-json-log, champ `stats`),
puis pousse le résultat au moniteur push « kDrive vers NAS »
(tofu/pangolin_config) : status=up avec le volume copié, ou status=down avec
le code de sortie et la dernière erreur. Sans aucun push (NAS éteint, timer
mort), le moniteur passe aussi au rouge au bout de son intervalle.

Bibliothèque standard seule : UGOS n'installe rien, mais Ansible s'appuie
déjà sur son /usr/bin/python3. L'URL push porte le jeton du moniteur : lue
dans l'environnement (EnvironmentFile de l'unité, 0600 root), jamais sur la
ligne de commande, jamais affichée.
"""

import argparse
import http.client
import json
import os
import signal
import subprocess
import sys
import time
import urllib.parse
import urllib.request

PUSH_URL_VARIABLE = "KDRIVE_SYNC_PUSH_URL"
# Uptime Kuma garde le message du battement ; une erreur de rclone peut être
# longue (pile d'erreurs HTTP).
MAX_MESSAGE = 300


def human_size(size):
    for unit in ("o", "Kio", "Mio", "Gio"):
        if size < 1024:
            return f"{size:.0f} {unit}" if unit == "o" else f"{size:.1f} {unit}"
        size /= 1024
    return f"{size:.1f} Tio"


def summary(stats):
    """Ce que la copie a fait, d'après les statistiques finales de rclone."""
    if stats is None:
        return "statistiques de rclone absentes"
    elapsed = float(stats.get("elapsedTime") or 0)
    return (
        f"{int(stats.get('transfers') or 0)} fichier(s) copié(s), "
        f"{human_size(float(stats.get('bytes') or 0))} en {elapsed / 60:.0f} min ; "
        f"{int(stats.get('checks') or 0)} vérifié(s), {int(stats.get('errors') or 0)} erreur(s)"
    )


def run(command):
    """Relaie la sortie de la commande.

    Renvoie (code, stats, dernière erreur, interrompu). Un SIGTERM (arrêt de
    l'unité, dépassement de TimeoutStartSec) n'arrête pas le script : il
    arrête la commande, puis le script pousse quand même le rouge.
    """
    stats, last_error, interrupted = None, "", False
    # La commande vient de l'ExecStart de l'unité (root, posée par Ansible),
    # sans shell : aucune entrée extérieure, la règle d'injection de Sonar ne
    # s'applique pas.
    with subprocess.Popen(  # NOSONAR
        command,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        errors="replace",
    ) as process:

        def stop(_signum, _frame):
            nonlocal interrupted
            interrupted = True
            process.terminate()

        signal.signal(signal.SIGTERM, stop)
        for line in process.stdout:
            print(line, end="", flush=True)
            try:
                entry = json.loads(line)
            except ValueError:
                continue
            if not isinstance(entry, dict):
                continue
            if isinstance(entry.get("stats"), dict):
                stats = entry["stats"]
            if entry.get("level") in ("error", "critical", "fatal"):
                last_error = str(entry.get("msg", ""))
    return process.returncode, stats, last_error, interrupted


def push(url, status, msg):
    query = urllib.parse.urlencode({"status": status, "msg": msg, "ping": ""})
    separator = "&" if "?" in url else "?"
    # URL lue dans l'environnement de l'unité (root), pas une entrée
    # extérieure : la règle SSRF de Sonar ne s'applique pas.
    with urllib.request.urlopen(url + separator + query, timeout=30) as response:  # NOSONAR
        response.read()


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--backup-dir-root", required=True)
    parser.add_argument("command", nargs="+")
    args = parser.parse_args(argv)

    backup_dir = f"{args.backup_dir_root.rstrip('/')}/{time.strftime('%Y-%m-%dT%H%M%S')}"
    try:
        returncode, stats, last_error, interrupted = run(args.command + ["--backup-dir", backup_dir])
    except OSError as error:
        # Commande introuvable ou non exécutable : rouge tout de suite, pas
        # au bout des 49 h du moniteur.
        returncode, stats, last_error, interrupted = 127, None, type(error).__name__, False

    if interrupted:
        status = "down"
        msg = f"interrompu (arrêt de l'unité ou TimeoutStartSec) ; {summary(stats)}"
    elif returncode == 0:
        status, msg = "up", summary(stats)
    else:
        status = "down"
        msg = f"rclone code {returncode} : {last_error or 'voir journalctl -u kdrive-sync'} ; {summary(stats)}"
    msg = msg[:MAX_MESSAGE]
    print(f"{status}: {msg}", flush=True)

    url = os.environ.get(PUSH_URL_VARIABLE, "")
    if url:
        try:
            push(url, status, msg)
        except (OSError, ValueError, http.client.HTTPException) as error:
            # Une erreur d'urllib peut citer l'URL (ValueError d'une URL
            # malformée comprise) : sa classe seule est affichée.
            print(f"push vers Uptime Kuma en échec : {type(error).__name__}", file=sys.stderr)
            return 2
    else:
        print(f"{PUSH_URL_VARIABLE} vide : rien n'est poussé.", file=sys.stderr)
    return 1 if returncode or interrupted else 0


if __name__ == "__main__":
    sys.exit(main())
