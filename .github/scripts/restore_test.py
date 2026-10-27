"""Restore test of one borg repository (.github/workflows/restore-test.yaml).

Usage: restore_test.py <app>, or restore_test.py --verify-data <app> for the
quarterly full data check (.github/workflows/borg-check.yaml), from the
repository root, with in the environment:

  BORG_REPO_BASE   ssh://<user>@<host>:23/.  (the read-only sub-account,
                   whose home is backup/: repositories are <host>/<repo>)
  BORG_PASSPHRASE  the repository passphrase
  BORG_RSH         ssh command with the sub-account key

Steps, on the latest archive:
  0. fail if it is older than MAX_ARCHIVE_AGE: a backup that stopped (a dump
     failing every night) leaves an old archive that restores fine;
  1. extract a sample of regular files (borg checks every chunk it decrypts);
  2. replay every PostgreSQL / MySQL dump in a throwaway container of the
     role's database image, and check that a table came back (unless the
     database is listed in the entry's allow_empty_databases);
  3. run PRAGMA integrity_check on every SQLite copy.
Exits non-zero on any failure; the workflow's last job pushes the overall
result to the "Restore test" monitor.

--verify-data runs `borg check --archives-only --verify-data` instead, what
`borgmatic check --only data` runs: every object of the repository is
downloaded, its MAC checked and decrypted. Without --repair, borg 1.4 writes
nothing to the repository on that path (ArchiveChecker only puts, deletes
and commits under `if self.repair`), and --archives-only skips
Repository.check, the one part that rewrites the repository config.
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
# Backups start every night at 01:00 Europe/Paris (borgmatic_timer_schedule,
# 23:00 or 00:00 UTC), the test at 10:00 UTC: the last archive is ~10 h old,
# the one before ~34 h. 28 h makes one missed night enough to fail, while
# leaving a manual rerun the same day, or a backup started late, in time.
MAX_ARCHIVE_AGE = datetime.timedelta(hours=28)

# Dumps written by borgmatic: <...>/postgresql_databases/<host>/<name>.
DUMP_RE = re.compile(r"(?:^|/)(postgresql|mysql)_databases/[^/]+/([^/]+)$")
SQLITE_STAGING = "var/lib/borgmatic-sqlite/"
# The one line of `borg check --info` shown in the log: its other lines name
# files of the archives (missing chunks are reported with the item path).
VERIFY_SUMMARY_RE = re.compile(
    r"Finished cryptographic data integrity verification, verified (\d+) chunks with (\d+) integrity errors")

# Database names end up in SQL: nothing but identifiers.
SAFE_NAME = re.compile(r"[A-Za-z0-9_-]+")

# Database image of the role, picked from its compose template.
IMAGE_RE = {
    "postgresql": re.compile(r"^\s*image:\s*\"?([^\s\"]*(?:postgres|postgis)[^\s\"]*)\"?\s*$"),
    "mysql": re.compile(r"^\s*image:\s*\"?([^\s\"]*(?:mariadb|mysql)[^\s\"]*)\"?\s*$"),
}


class RestoreError(Exception):
    pass


def run(*args, stdin=None, check=True, cwd=None, quiet=False, show_error=False):
    # The logs of a public repository are public: a quiet command (archive
    # paths in its arguments) does not show its arguments, and no command
    # shows its stderr (rows of a dump, names of files), except the last line
    # of one that asks for it (show_error: borg's own message when the
    # repository cannot be opened). Reproduce a failure from a workstation.
    shown = args[:2] if quiet else args
    print("+", " ".join(shown), "…" if quiet else "", flush=True)
    # surrogateescape: an archive path that is not UTF-8 round-trips to borg
    # extract unchanged instead of raising UnicodeDecodeError.
    result = subprocess.run(args, stdin=stdin, capture_output=True, text=True,
                            errors="surrogateescape", cwd=cwd)
    if check and result.returncode != 0:
        lines = result.stderr.strip().splitlines()
        detail = lines[-1][:200] if show_error and lines else "(sortie masquée)"
        raise RestoreError(f"{' '.join(args[:2])} a échoué ({result.returncode}): {detail}")
    return result


def borg(*args, check=True, cwd=None, quiet=False, show_error=False):
    # Read-only sub-account: borg 1.x cannot write its lock there.
    return run("borg", args[0], "--bypass-lock", *args[1:], check=check, cwd=cwd, quiet=quiet,
               show_error=show_error)


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
    # Not its logs: they are not shown in a public log.
    raise RestoreError(f"{container} pas prêt en {DB_READY_TIMEOUT} s")


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
        run("docker", "cp", str(dump), f"{container}:/tmp/dump", quiet=True)
        run("docker", "exec", container, "createdb", "-U", "postgres", name)
        # borgmatic dumps in pg_dump's custom format by default.
        run("docker", "exec", container, "pg_restore", "-U", "postgres", "--no-owner",
            "--no-privileges", "--exit-on-error", "-d", name, "/tmp/dump", quiet=True)
        # Tables of the dump only: those an extension creates (postgis's
        # spatial_ref_sys, topology, tiger) would make an empty dump pass.
        tables = run("docker", "exec", container, "psql", "-U", "postgres", "-d", name, "-tAc",
                     "select count(*) from pg_class c join pg_namespace n on n.oid = c.relnamespace "
                     "where c.relkind in ('r', 'p') "
                     "and n.nspname not in ('pg_catalog', 'information_schema') "
                     "and not exists (select 1 from pg_depend d where d.classid = 'pg_class'::regclass "
                     "and d.objid = c.oid and d.deptype = 'e')").stdout.strip()
    finally:
        run("docker", "rm", "-f", container, check=False)
    return int(tables)


def restore_mysql(image, name, dump):
    container = f"restore-db-{secrets.token_hex(4)}"
    # No root password: linuxserver's image only sets it on root@'%' and
    # leaves root@localhost without one, so a password is refused from inside
    # the container. Without MYSQL_ROOT_PASSWORD it gives root@'%' none
    # either, and the official image needs MARIADB_ALLOW_EMPTY_ROOT_PASSWORD.
    # The container publishes no port and lives as long as the test.
    run("docker", "run", "-d", "--name", container, "-e", "MARIADB_ALLOW_EMPTY_ROOT_PASSWORD=1", image)
    try:
        client = ("mariadb", "-uroot", "--protocol=tcp", "-h127.0.0.1")
        # linuxserver's init runs a temporary server first, then shuts it
        # down and s6 starts the real one: wait for an uptime that temporary
        # server never reaches.
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


def check_sqlite(path, label):
    # Not the path: a staging file name carries its source path (FreshRSS's
    # data/users/<user>/db.sqlite), hence quiet and a label.
    integrity = run("sqlite3", "-readonly", str(path), "PRAGMA integrity_check;", quiet=True).stdout.strip()
    if integrity != "ok":
        # Its messages name tables, indexes and rows: only their count.
        raise RestoreError(f"{label} : integrity_check en échec ({len(integrity.splitlines())} lignes)")
    return int(run("sqlite3", "-readonly", str(path),
                   "select count(*) from sqlite_master where type = 'table';", quiet=True).stdout.strip())


def archive_age(timestamp):
    started = datetime.datetime.fromisoformat(timestamp)
    if started.tzinfo is None:
        # borg renders it in the local time of the machine running borg,
        # the runner, whose time zone is UTC.
        started = started.replace(tzinfo=datetime.timezone.utc)
    return datetime.datetime.now(datetime.timezone.utc) - started


def repository(entry):
    return f"{os.environ['BORG_REPO_BASE']}/{entry['host']}/{entry['repo']}"


def last_listing(repo):
    # borg >= 1.2 leaves *.checkpoint archives (interrupted runs) out of a
    # listing unless --consider-checkpoints: this is the last complete one.
    listing = json.loads(borg("list", "--last", "1", "--json", repo, show_error=True).stdout)
    if not listing["archives"]:
        raise RestoreError("aucune archive")
    return listing


def latest_archive(repo):
    return last_listing(repo)["archives"][0]


def last_modified(repo):
    # The manifest's timestamp: create (checkpoints included) and prune
    # rewrite it, the latest archive's name only changes with a new archive.
    return last_listing(repo)["repository"]["last_modified"]


def verify_data(entry):
    repo = repository(entry)
    before = last_modified(repo)
    started = time.monotonic()
    # Neither its arguments (nothing secret, but kept uniform) nor its
    # stderr: only the summary line, parsed below.
    result = borg("check", "--info", "--archives-only", "--verify-data", repo, check=False, quiet=True)
    elapsed = datetime.timedelta(seconds=round(time.monotonic() - started))
    summary = VERIFY_SUMMARY_RE.search(result.stderr)
    if result.returncode != 0:
        # Lock-free: a backup (create, prune) running meanwhile makes chunks
        # vanish or appear unreferenced. Say so instead of crying wolf. A
        # listing that fails now must not hide the failure of the check.
        try:
            changed = last_modified(repo) != before
        except RestoreError:
            changed = False
        if changed:
            raise RestoreError(f"une sauvegarde a écrit dans le dépôt pendant la vérification ({elapsed}) : "
                               "résultat non concluant, relancer hors de la fenêtre nocturne")
        if not summary:
            found = "sortie masquée"
        elif int(summary.group(2)):
            found = f"{summary.group(2)} blocs corrompus sur {summary.group(1)}"
        else:
            found = f"aucun des {summary.group(1)} blocs corrompu, erreur dans les archives, sortie masquée"
        raise RestoreError(f"borg check a échoué ({result.returncode}, {found}) en {elapsed}")
    if not summary:
        raise RestoreError("borg check n'a pas donné le résumé de --verify-data")
    # Defensive: borg already exits 1 on an integrity error.
    if int(summary.group(2)):
        raise RestoreError(f"{summary.group(2)} blocs corrompus sur {summary.group(1)}")
    return f"{summary.group(1)} blocs vérifiés en {elapsed}, aucune erreur"


def restore(entry, workdir):
    repo = repository(entry)
    latest = latest_archive(repo)
    archive = latest["name"]
    age = archive_age(latest["time"])
    if age > MAX_ARCHIVE_AGE:
        raise RestoreError(f"dernière archive {archive} vieille de {age} : la sauvegarde ne tourne plus")
    location = f"{repo}::{archive}"
    report = [archive]

    # NUL-separated: a file name may hold a newline.
    listing = borg("list", "--format", "{type} {size} {path}{NUL}", location, quiet=True).stdout.split("\0")
    files = []
    for line in filter(None, listing):
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
        # By name, not for the whole app: a second database added later, or
        # a non-list value ("false" is truthy), must not slip through.
        if tables == 0 and name not in entry.get("allow_empty_databases", []):
            raise RestoreError(f"{engine} {name} : aucune table après restauration")
        report.append(f"{engine} {name} : {tables} tables")

    for index, path in enumerate(sqlite, 1):
        label = f"sqlite n°{index}"
        tables = check_sqlite(workdir / path, label)
        if tables == 0:
            raise RestoreError(f"{label} : aucune table")
        report.append(f"{label} : {tables} tables")

    return ", ".join(report)


def main(argv):
    verify = argv[:1] == ["--verify-data"]
    if len(argv) != 1 + verify:
        print("usage: restore_test.py [--verify-data] <app>", file=sys.stderr)
        return 2
    app = argv[-1]
    entry = json.loads(MANIFEST.read_text())[app]
    with tempfile.TemporaryDirectory(prefix=f"restore-{app}-") as tmp:
        try:
            message = verify_data(entry) if verify else restore(entry, pathlib.Path(tmp))
        except RestoreError as error:
            print(f"::error::{app}: {error}", flush=True)
            return 1
        except Exception as error:  # noqa: BLE001
            # No traceback nor message in a public log (a path, a line of
            # output): the type is enough to reproduce it from a workstation.
            print(f"::error::{app}: erreur inattendue ({type(error).__name__})", flush=True)
            return 1
    print(f"{app}: {message}", flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
