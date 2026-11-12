#!/usr/bin/env python3
"""Contrôle des applis restaurées sur la copie jetable de la VM docker.

    drill-check [appli ...]        (en root ; sans argument, toutes)

Par appli (dépôt borgmatic, /etc/borgmatic.d/<dépôt>.yaml) :
  - HTTP : la sonde de Pangolin (tofu/pangolin_config/website_*.tf ; Grocy : `/`,
    pas son `/robots.txt` statique), envoyée à
    l'IP du conteneur sur le réseau `newt`, sans suivre de redirection (elle
    pourrait mener à l'adresse de production) ; 200 à 399 passe ;
  - données : ce que contrôle le test de restauration de la CI
    (.github/restore-test/apps.json) : chaque table de `expected_tables` existe
    et a au moins une ligne, `PRAGMA integrity_check` pour SQLite.
Sortie : une ligne OK / FAIL / SKIP par contrôle, code 1 au moindre FAIL.
Lecture seule : aucune écriture dans une base, aucun accès à la production.
"""
import http.client
import json
import sqlite3
import subprocess
import sys
import time
import urllib.error
import urllib.request

import yaml

APPS_JSON = "/usr/local/share/drill/apps.json"
CONFIG_DIR = "/etc/borgmatic.d"

# Rôles non déployés sur la copie (docker.yml) : leurs données ne sont pas rejouées.
EXCLUDED = {
    "beszel": "rôle exclu : le hub alerterait la production",
    # Les jetons Withings de sa base seraient rafraîchis depuis la copie, ce qui invalide ceux de la production.
    "healthlog": "rôle exclu : sa synchronisation Withings tournerait avec les vrais jetons",
}

# dépôt borgmatic : (conteneur, port, chemin de la sonde, en-tête Host ou None).
# Conteneur, port et chemin viennent de tofu/pangolin_config/website_*.tf.
# test_drill_check.py (.github/scripts) garde la table alignée sur apps.json.
HEALTH = "/api/health"
HTTP = {
    "betisier": ("betisier", 80, "/", None),
    "dawarich": ("dawarich-app", 3000, "/api/v1/health", None),
    # Une page PHP (302), pas un fichier statique : Grocy ne crée grocy.db qu'au
    # premier appel, et le second passage --tags app doit la trouver.
    "grocy": ("grocy", 80, "/", None),
    "homebox": ("homebox", 7745, "/api/v1/status", None),
    "jellystat": ("jellystat", 3000, "/auth/isconfigured", None),
    "karakeep": ("karakeep", 3000, HEALTH, None),
    "monica_v4": ("monica_v4", 80, "/", None),
    # Nextcloud répond 400 (« Trusted domain error ») à une IP : « nextcloud »
    # est dans ses trusted_domains (constaté à l'exercice du 09/11/2026).
    "nextcloud": ("nextcloud", 80, "/status.php", "nextcloud"),
    "ntfy": ("ntfy", 8080, "/v1/health", None),
    "openwebui": ("openwebui", 8080, "/health", None),
    "papra": ("papra", 1221, HEALTH, None),
    "rss": ("rss", 80, "/api/", None),
    "speedtest_tracker": ("speedtest-tracker", 80, "/api/healthcheck", None),
    "trek": ("trek", 3000, HEALTH, None),
    "wiki": ("bookstack", 80, "/login", None),
    "wishlist": ("wishlist", 3280, "/favicon.ico", None),
    "yamtrack": ("yamtrack", 8000, "/health/", None),
}
# Applis sans dépôt Borg (rien à restaurer) : seule la sonde HTTP.
STATELESS = {
    "bentopdf": ("bentopdf", 8080, "/", None),
    "enclosed": ("enclosed", 8787, "/api/ping", None),
    "pairdrop": ("pairdrop", 3000, "/", None),
    "docs_site": ("docs-site", 8080, "/", None),
}

failures = 0


def report(status, app, what, detail=""):
    global failures
    if status == "FAIL":
        failures += 1
    print(f"{status:<4} {app:<18} {what}" + (f" : {detail}" if detail else ""), flush=True)


def run(cmd, **kwargs):
    return subprocess.run(cmd, capture_output=True, text=True, check=False, **kwargs)


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *args, **kwargs):
        return None


def container_ip(container):
    out = run(["docker", "inspect", "-f", '{{(index .NetworkSettings.Networks "newt").IPAddress}}', container])
    return out.stdout.strip() if out.returncode == 0 else ""


def probe(opener, ip, port, path, host):
    """(code, None) ou (None, type de l'erreur)."""
    # IP d'un conteneur du réseau Docker local : pas de TLS à vérifier.
    url = f"http://{ip}:{port}{path}"  # NOSONAR
    request = urllib.request.Request(url, headers={"Host": host} if host else {})
    try:
        return opener.open(request, timeout=10).status, None
    except urllib.error.HTTPError as error:
        return error.code, None
    except (OSError, http.client.HTTPException) as error:
        return None, type(error).__name__


def check_http(app, container, port, path, host):
    opener = urllib.request.build_opener(NoRedirect)
    deadline = time.time() + 120
    detail = "conteneur absent du réseau newt"
    while time.time() < deadline:
        ip = container_ip(container)
        code, error = probe(opener, ip, port, path, host) if ip else (None, detail)
        if code is not None and 200 <= code < 400:
            return report("OK", app, f"HTTP {path}", str(code))
        detail = error or f"code {code}"
        time.sleep(5)
    report("FAIL", app, f"HTTP {path}", detail)


def count_sql(cmd):
    out = run(cmd)
    text = out.stdout.strip()
    return int(text) if out.returncode == 0 and text.isdigit() else None


def report_rows(app, base, table, n):
    report("OK" if n else "FAIL", app, f"{base}.{table}", f"lignes : {n}")


def check_postgres(app, d, base, tables):
    for table in tables:
        schema, _, name = table.rpartition(".")
        ref = f'"{schema or "public"}"."{name}"'
        n = count_sql(["docker", "exec", "-e", f"PGPASSWORD={d['password']}", d["container"], "psql",
                       "-U", d["username"], "-d", base, "-tAc", f"select count(*) from {ref}"])
        report_rows(app, base, table, n)


def check_mysql(app, d, base, tables):
    for table in tables:
        n = None
        for client in ("mariadb", "mysql"):
            n = count_sql(["docker", "exec", "-e", f"MYSQL_PWD={d['password']}", d["container"], client,
                           "-u", d["username"], "-N", "-B", base, "-e", f"select count(*) from `{table}`"])
            if n is not None:
                break
        report_rows(app, base, table, n)


def check_sqlite(app, path, base, tables):
    try:
        db = sqlite3.connect(f"file:{path}?mode=ro", uri=True)
        integrity = db.execute("PRAGMA integrity_check").fetchone()[0]
        report("OK" if integrity == "ok" else "FAIL", app, f"{base} integrity_check", integrity)
        for table in tables:
            report_rows(app, base, table, db.execute(f'select count(*) from "{table}"').fetchone()[0])
    except sqlite3.Error as error:
        report("FAIL", app, base, str(error))


def check_tables(app, cfg, entry):
    """Les tables attendues de chaque base de l'appli ont au moins une ligne."""
    excluded = set(cfg.get("exclude_patterns", []))
    sqlite_paths = sorted(e for e in excluded if e.startswith("/") and e + "-wal" in excluded)
    pg = {d["name"]: d for d in cfg.get("postgresql_databases", [])}
    my = {d["name"]: d for d in cfg.get("mysql_databases", [])}
    for base, tables in entry.get("expected_tables", {}).items():
        path = next((p for p in sqlite_paths if p.rsplit("/", 1)[-1] == base), None)
        if base in pg:
            check_postgres(app, pg[base], base, tables)
        elif base in my:
            check_mysql(app, my[base], base, tables)
        elif path:
            check_sqlite(app, path, base, tables)
        else:
            report("FAIL", app, base, "base SQLite introuvable dans la configuration")


def main(only):
    apps = {k: v for k, v in json.load(open(APPS_JSON)).items() if v["host"] == "docker"}
    by_repo = {v["repo"]: v for v in apps.values()}
    names = sorted(set(by_repo) | set(STATELESS))
    for name in names:
        if only and name not in only:
            continue
        if name in EXCLUDED:
            report("SKIP", name, "tout", EXCLUDED[name])
            continue
        if name in STATELESS:
            check_http(name, *STATELESS[name])
            continue
        cfg_path = f"{CONFIG_DIR}/{name}.yaml"
        try:
            cfg = yaml.safe_load(open(cfg_path))
        except OSError:
            report("FAIL", name, "configuration", f"{cfg_path} absente : rôle pas déployé ?")
            continue
        check_http(name, *HTTP[name])
        check_tables(name, cfg, by_repo[name])
    print(f"\n{'ÉCHEC' if failures else 'OK'} : {failures} contrôle(s) en échec")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main(set(sys.argv[1:])))
