"""Restore test of one borg repository (.github/workflows/restore-test.yaml).

Usage: restore_test.py <app>, from the repository root, with in the
environment:

  BORG_REPO_BASE   ssh://<user>@<host>:23/.  (the read-only sub-account)
  BORG_PASSPHRASE  the repository passphrase
  BORG_RSH         ssh command with the sub-account key
  PUSH_URLS        JSON map app => Uptime Kuma push URL

Steps, on the latest archive:
  1. extract a sample of regular files (borg checks every chunk it decrypts);
  2. replay every PostgreSQL / MySQL dump in a throwaway container of the
     role's database image, and check that a table came back;
  3. run PRAGMA integrity_check on every SQLite copy.
The result is pushed to the app's "Restore test" monitor, success or failure.
"""

import json
import os
import pathlib
import re
import secrets
import subprocess
import sys
import tempfile
import time
import urllib.parse
import urllib.request

MANIFEST = pathlib.Path(".github/restore-test/apps.json")
SAMPLE_FILES = 20
SAMPLE_MAX_BYTES = 5 * 1024 * 1024
DB_READY_TIMEOUT = 180

# Dumps written by borgmatic: <...>/postgresql_databases/<host>/<name>.
DUMP_RE = re.compile(r"(?:^|/)(postgresql|mysql)_databases/[^/]+/([^/]+)$")
SQLITE_STAGING = "var/lib/borgmatic-sqlite/"
# Database names end up in SQL: nothing but identifiers.
SAFE_NAME = re.compile(r"[A-Za-z0-9_-]+")

# Database image of the role, picked from its compose template.
IMAGE_RE = {
    "postgresql": re.compile(r"^\s*image:\s*\"?([^\s\"]*(?:postgres|postgis)[^\s\"]*)\"?\s*$"),
    "mysql": re.compile(r"^\s*image:\s*\"?([^\s\"]*(?:mariadb|mysql)[^\s\"]*)\"?\s*$"),
}


class RestoreError(Exception):
    pass


def run(*args, stdin=None, check=True, cwd=None):
    print("+", " ".join(args), flush=True)
    result = subprocess.run(args, stdin=stdin, capture_output=True, text=True, cwd=cwd)
    if check and result.returncode != 0:
        raise RestoreError(
            f"{args[0]} {args[1] if len(args) > 1 else ''} a échoué ({result.returncode}): "
            f"{result.stderr.strip()[-500:]}"
        )
    return result


def borg(*args, cwd=None):
    # Read-only sub-account: borg 1.x cannot write its lock there.
    return run("borg", args[0], "--bypass-lock", *args[1:], cwd=cwd)


def role_image(role, engine):
    images = set()
    for template in pathlib.Path("ansible/roles", role, "templates").glob("compose.yaml*"):
        for line in template.read_text().splitlines():
            match = IMAGE_RE[engine].match(line)
            if match:
                images.add(match.group(1))
    if len(images) != 1:
        raise RestoreError(f"image {engine} du rôle {role} introuvable ou ambiguë : {sorted(images)}")
    return images.pop()


def wait_until(container, *probe):
    deadline = time.monotonic() + DB_READY_TIMEOUT
    while time.monotonic() < deadline:
        if run("docker", "exec", container, *probe, check=False).returncode == 0:
            return
        time.sleep(3)
    logs = run("docker", "logs", "--tail", "30", container, check=False)
    raise RestoreError(f"{container} pas prêt en {DB_READY_TIMEOUT} s : {logs.stderr[-500:]}")


def restore_postgresql(image, name, dump):
    container = f"restore-pg-{secrets.token_hex(4)}"
    run("docker", "run", "-d", "--name", container, "-e", "POSTGRES_PASSWORD=restore-test", image)
    try:
        wait_until(container, "pg_isready", "-U", "postgres")
        # The entrypoint restarts the server once initialised: wait for a query.
        wait_until(container, "psql", "-U", "postgres", "-c", "select 1")
        run("docker", "cp", str(dump), f"{container}:/tmp/dump")
        run("docker", "exec", container, "createdb", "-U", "postgres", name)
        # borgmatic dumps in pg_dump's custom format by default.
        run("docker", "exec", container, "pg_restore", "-U", "postgres", "--no-owner",
            "--no-privileges", "--exit-on-error", "-d", name, "/tmp/dump")
        tables = run("docker", "exec", container, "psql", "-U", "postgres", "-d", name, "-tAc",
                     "select count(*) from information_schema.tables "
                     "where table_schema not in ('pg_catalog', 'information_schema')").stdout.strip()
    finally:
        run("docker", "rm", "-f", container, check=False)
    return int(tables)


def restore_mysql(image, name, dump):
    container = f"restore-db-{secrets.token_hex(4)}"
    # The official image reads MARIADB_*, linuxserver's MYSQL_*.
    run("docker", "run", "-d", "--name", container, "-e", "MARIADB_ROOT_PASSWORD=restore-test",
        "-e", "MYSQL_ROOT_PASSWORD=restore-test", image)
    try:
        client = ("env", "MYSQL_PWD=restore-test", "mariadb", "-uroot", "--protocol=tcp", "-h127.0.0.1")
        wait_until(container, *client, "-e", "select 1")
        # borgmatic dumps with --databases: the dump creates its database.
        with open(dump) as sql:
            run("docker", "exec", "-i", container, *client, stdin=sql)
        tables = run("docker", "exec", container, *client, "-N", "-e",
                     f"select count(*) from information_schema.tables where table_schema = '{name}'"
                     ).stdout.strip()
    finally:
        run("docker", "rm", "-f", container, check=False)
    return int(tables)


def check_sqlite(path):
    integrity = run("sqlite3", "-readonly", str(path), "PRAGMA integrity_check;").stdout.strip()
    if integrity != "ok":
        raise RestoreError(f"{path.name} : integrity_check = {integrity[:300]}")
    return int(run("sqlite3", "-readonly", str(path),
                   "select count(*) from sqlite_master where type = 'table';").stdout.strip())


def restore(app, entry, workdir):
    repo = f"{os.environ['BORG_REPO_BASE']}/{entry['repo']}"
    archive = borg("list", "--last", "1", "--short", repo).stdout.strip()
    if not archive:
        raise RestoreError("aucune archive")
    location = f"{repo}::{archive}"
    report = [archive]

    listing = borg("list", "--format", "{type} {size} {path}{NL}", location).stdout.splitlines()
    files = []
    for line in listing:
        kind, size, path = line.split(" ", 2)
        if kind == "-":
            files.append((int(size), path))

    dumps = [(m.group(1), m.group(2), path) for _, path in files if (m := DUMP_RE.search(path))]
    sqlite = [path for _, path in files if path.startswith(SQLITE_STAGING + entry["repo"] + "/")]
    sample = [path for size, path in files
              if 0 < size <= SAMPLE_MAX_BYTES and not DUMP_RE.search(path)
              and not path.startswith(SQLITE_STAGING)][:SAMPLE_FILES]
    if not sample and not dumps and not sqlite:
        raise RestoreError(f"{archive} ne contient aucun fichier")

    if sample:
        (workdir / "sample").mkdir()
        borg("extract", location, *sample, cwd=workdir / "sample")
        report.append(f"{len(sample)} fichiers extraits")

    if dumps or sqlite:
        borg("extract", location, *[path for _, _, path in dumps], *sqlite, cwd=workdir)

    for engine, name, path in dumps:
        if not SAFE_NAME.fullmatch(name):
            raise RestoreError(f"nom de base inattendu : {name!r}")
        image = role_image(entry["role"], engine)
        restorer = restore_postgresql if engine == "postgresql" else restore_mysql
        tables = restorer(image, name, workdir / path)
        if tables == 0:
            raise RestoreError(f"{engine} {name} : aucune table après restauration")
        report.append(f"{engine} {name} : {tables} tables")

    for path in sqlite:
        tables = check_sqlite(workdir / path)
        if tables == 0:
            raise RestoreError(f"SQLite {path} : aucune table")
        report.append(f"sqlite {pathlib.PurePath(path).name} : {tables} tables")

    return ", ".join(report)


def push(app, status, message):
    url = json.loads(os.environ["PUSH_URLS"]).get(app)
    if not url:
        print(f"::warning::pas d'URL push pour {app}", flush=True)
        return
    query = urllib.parse.urlencode({"status": status, "msg": message[:250], "ping": ""})
    with urllib.request.urlopen(f"{url}?{query}", timeout=30) as response:
        response.read()



def main():
    app = sys.argv[1]
    entry = json.loads(MANIFEST.read_text())[app]
    with tempfile.TemporaryDirectory(prefix=f"restore-{app}-") as tmp:
        try:
            message = restore(app, entry, pathlib.Path(tmp))
        except Exception as error:  # every failure must reach the monitor
            message = f"{type(error).__name__}: {error}"
            print(f"::error::{app}: {message}", flush=True)
            push(app, "down", message)
            return 1
    print(f"{app}: {message}", flush=True)
    push(app, "up", message)
    return 0


if __name__ == "__main__":
    sys.exit(main())
