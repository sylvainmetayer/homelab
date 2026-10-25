"""Restore test of one borg repository (.github/workflows/restore-test.yaml).

Usage: restore_test.py <app>, from the repository root, with in the
environment:

  BORG_REPO_BASE   ssh://<user>@<host>:23/.  (the read-only sub-account,
                   whose home is backup/: repositories are <host>/<repo>)
  BORG_PASSPHRASE  the repository passphrase
  BORG_RSH         ssh command with the sub-account key

Steps, on the latest archive:
  0. fail if it is older than MAX_ARCHIVE_AGE: a backup that stopped (a dump
     failing every night) leaves an old archive that restores fine;
  1. extract a sample of regular files (borg checks every chunk it decrypts);
  2. replay every PostgreSQL / MySQL dump in a throwaway container of the
     role's database image, and check that a table came back;
  3. run PRAGMA integrity_check on every SQLite copy.
Exits non-zero on any failure; the workflow's last job pushes the overall
result to the "Restore test" monitor.
"""

import datetime
import json
import os
import pathlib
import re
import secrets
import subprocess
import sys
import tempfile
import time

MANIFEST = pathlib.Path(".github/restore-test/apps.json")
SAMPLE_FILES = 20
SAMPLE_MAX_BYTES = 5 * 1024 * 1024
DB_READY_TIMEOUT = 180
# Backups run every night at 01:00 (borgmatic_timer_schedule), the test at
# 10:00 UTC: one missed night is enough to fail.
MAX_ARCHIVE_AGE = datetime.timedelta(hours=36)

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


def run(*args, stdin=None, check=True, cwd=None, quiet=False):
    # The logs of a public repository are public: a quiet command (archive
    # paths in its arguments, rows of a dump in its errors) shows neither
    # its arguments nor its stderr. Reproduce it from a workstation.
    shown = args[:2] if quiet else args
    print("+", " ".join(shown), "…" if quiet else "", flush=True)
    result = subprocess.run(args, stdin=stdin, capture_output=True, text=True, cwd=cwd)
    if check and result.returncode != 0:
        detail = "(sortie masquée)" if quiet else result.stderr.strip()[-500:]
        raise RestoreError(f"{' '.join(args[:2])} a échoué ({result.returncode}): {detail}")
    return result


def borg(*args, cwd=None, quiet=False):
    # Read-only sub-account: borg 1.x cannot write its lock there.
    return run("borg", args[0], "--bypass-lock", *args[1:], cwd=cwd, quiet=quiet)


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


def wait_until(container, *probe, ready=lambda stdout: True):
    deadline = time.monotonic() + DB_READY_TIMEOUT
    while time.monotonic() < deadline:
        result = run("docker", "exec", container, *probe, check=False)
        if result.returncode == 0 and ready(result.stdout):
            return
        time.sleep(3)
    logs = run("docker", "logs", "--tail", "30", container, check=False)
    raise RestoreError(f"{container} pas prêt en {DB_READY_TIMEOUT} s : {logs.stderr[-500:]}")


def restore_postgresql(image, name, dump):
    container = f"restore-pg-{secrets.token_hex(4)}"
    run("docker", "run", "-d", "--name", container, "-e", "POSTGRES_PASSWORD=restore-test", image)
    try:
        # The entrypoint first runs a temporary server (initdb, init scripts:
        # postgis takes seconds) listening on the Unix socket only, then stops
        # it and starts the real one. A socket probe answers during that first
        # phase and createdb/pg_restore die with the restart: probe over TCP,
        # which only the real server listens on.
        wait_until(container, "pg_isready", "-h", "127.0.0.1", "-U", "postgres")
        run("docker", "cp", str(dump), f"{container}:/tmp/dump")
        run("docker", "exec", container, "createdb", "-U", "postgres", name)
        # borgmatic dumps in pg_dump's custom format by default.
        run("docker", "exec", container, "pg_restore", "-U", "postgres", "--no-owner",
            "--no-privileges", "--exit-on-error", "-d", name, "/tmp/dump", quiet=True)
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
        # linuxserver's init runs a temporary server WITH networking (its
        # --init-file sets the root password, so this probe answers), then
        # shuts it down as soon as it answers and s6 starts the real one: wait
        # for an uptime that temporary server never reaches.
        wait_until(container, *client, "-N", "-e",
                   "select variable_value from information_schema.global_status "
                   "where variable_name = 'UPTIME'",
                   ready=lambda stdout: stdout.strip().isdigit() and int(stdout.strip()) >= 10)
        # borgmatic dumps with --databases: the dump creates its database.
        with open(dump) as sql:
            run("docker", "exec", "-i", container, *client, stdin=sql, quiet=True)
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


def archive_age(timestamp):
    started = datetime.datetime.fromisoformat(timestamp)
    if started.tzinfo is None:
        # borg renders it in the local time of the machine running borg,
        # the runner, whose time zone is UTC.
        started = started.replace(tzinfo=datetime.timezone.utc)
    return datetime.datetime.now(datetime.timezone.utc) - started


def restore(entry, workdir):
    repo = f"{os.environ['BORG_REPO_BASE']}/{entry['host']}/{entry['repo']}"
    # borg >= 1.2 leaves *.checkpoint archives (interrupted runs) out of a
    # listing unless --consider-checkpoints: this is the last complete one.
    archives = json.loads(borg("list", "--last", "1", "--json", repo).stdout)["archives"]
    if not archives:
        raise RestoreError("aucune archive")
    archive = archives[0]["name"]
    age = archive_age(archives[0]["time"])
    if age > MAX_ARCHIVE_AGE:
        raise RestoreError(f"dernière archive {archive} vieille de {age} : la sauvegarde ne tourne plus")
    location = f"{repo}::{archive}"
    report = [archive]

    listing = borg("list", "--format", "{type} {size} {path}{NL}", location, quiet=True).stdout.splitlines()
    files = []
    for line in listing:
        kind, size, path = line.split(" ", 2)
        if kind == "-":
            files.append((int(size), path))

    dumps = [(m.group(1), m.group(2), path) for _, path in files if (m := DUMP_RE.search(path))]
    sqlite = [path for _, path in files if path.startswith(SQLITE_STAGING + entry["repo"] + "/")]
    candidates = [path for size, path in files
                  if 0 < size <= SAMPLE_MAX_BYTES and not DUMP_RE.search(path)
                  and not path.startswith(SQLITE_STAGING)]
    # Random, not the head of the listing: every run reads other chunks.
    sample = secrets.SystemRandom().sample(candidates, min(SAMPLE_FILES, len(candidates)))
    if not sample and not dumps and not sqlite:
        raise RestoreError(f"{archive} ne contient aucun fichier")

    if sample:
        (workdir / "sample").mkdir()
        borg("extract", location, *sample, cwd=workdir / "sample", quiet=True)
        report.append(f"{len(sample)} fichiers extraits")

    if dumps or sqlite:
        borg("extract", location, *[path for _, _, path in dumps], *sqlite, cwd=workdir, quiet=True)

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


def main():
    app = sys.argv[1]
    entry = json.loads(MANIFEST.read_text())[app]
    with tempfile.TemporaryDirectory(prefix=f"restore-{app}-") as tmp:
        try:
            message = restore(entry, pathlib.Path(tmp))
        except RestoreError as error:
            print(f"::error::{app}: {error}", flush=True)
            return 1
    print(f"{app}: {message}", flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
