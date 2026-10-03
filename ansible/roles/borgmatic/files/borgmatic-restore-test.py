#!/usr/bin/env python3
"""Restore test of every borgmatic configuration on this host (issue #444).

A backup job that succeeds proves that borgmatic could write, not that the
archive can be read back: a wrong passphrase, a corrupt chunk or a database
dump cut short all go unnoticed until the day a restore is needed. For each
configuration this script:

  1. checks that the latest archive is recent (a backup that silently stopped
     running looks exactly like a healthy one from the push monitor's side
     once its last heartbeat is old enough to have been forgotten);
  2. extracts, into a throwaway directory, every database dump of that
     archive plus a random sample of its files - borg verifies each chunk's
     MAC on extraction, so this is a real read of the repository, not a
     listing;
  3. checks what came out: sampled files have the size the archive lists,
     PostgreSQL custom-format dumps open with `pg_restore --list` (run inside
     the dump's own container when there is one, so the client matches the
     server version), plain SQL dumps end with their completion trailer.

Nothing is restored into a live database. The result is pushed to an Uptime
Kuma push monitor: `up` when every configuration passed, `down` with the
failures otherwise, and nothing at all if the script never runs - which the
monitor reports by itself.
"""

import argparse
import datetime
import glob
import json
import os
import random
import subprocess
import sys
import tempfile
import time
import urllib.parse
import urllib.request


class RestoreTestError(Exception):
    pass


# borgmatic ends its output with a summary whose first specific line is the
# actual error ("Passphrase ... is incorrect", "Data integrity error: ..."),
# wrapped in generic lines and followed by borg's traceback.
GENERIC_ERROR_LINES = (
    "An error occurred",
    "Error running actions for repository",
    "Error running configuration",
    "Need some help?",
)


def first_error(output):
    lines = [line.strip() for line in output.splitlines() if line.strip()]
    if "summary:" in lines:
        lines = lines[lines.index("summary:") + 1 :]
    for line in lines:
        if not any(generic in line for generic in GENERIC_ERROR_LINES):
            return line
    return "no output"


def run(command, what, **kwargs):
    result = subprocess.run(command, capture_output=True, text=True, **kwargs)
    if result.returncode != 0:
        raise RestoreTestError(
            f"{what} exited {result.returncode}: {first_error(result.stderr or result.stdout)}"
        )
    return result.stdout


def wait_for_backup(timeout):
    """Borg locks the repository: do not race the nightly backup."""
    deadline = time.monotonic() + timeout
    while True:
        state = subprocess.run(
            ["systemctl", "is-active", "borgmatic.service"],
            capture_output=True,
            text=True,
        ).stdout.strip()
        if state not in ("active", "activating"):
            return
        if time.monotonic() > deadline:
            raise RestoreTestError(
                "borgmatic.service still running, restore test skipped"
            )
        time.sleep(60)


def tail(path, size=4096):
    with open(path, "rb") as handle:
        handle.seek(0, os.SEEK_END)
        handle.seek(max(0, handle.tell() - size))
        return handle.read().decode("utf-8", errors="replace")


def dump_path(root, hook, dump):
    """Mirror of borgmatic's make_data_source_dump_filename()."""
    identifier = dump.get("label") or (
        (dump.get("container") or dump.get("hostname") or "localhost")
        + ("" if dump.get("port") is None else f":{dump['port']}")
    )
    return os.path.join(root, "borgmatic", hook, identifier, dump["data_source_name"])


def check_dump(hook, dump, path):
    label = f"{hook}/{dump['data_source_name']}"
    if not os.path.exists(path):
        raise RestoreTestError(
            f"{label}: listed in dumps.json but missing from the archive"
        )

    if os.path.isdir(path):  # pg_dump --format=directory
        if not os.path.exists(os.path.join(path, "toc.dat")):
            raise RestoreTestError(f"{label}: directory dump without toc.dat")
        return

    if os.path.getsize(path) == 0:
        raise RestoreTestError(f"{label}: empty dump")

    with open(path, "rb") as handle:
        magic = handle.read(5)

    if hook == "postgresql_databases" and magic == b"PGDMP":
        container = dump.get("container")
        if container:
            with open(path, "rb") as handle:
                run(
                    ["docker", "exec", "-i", container, "pg_restore", "--list"],
                    f"{label}: pg_restore",
                    stdin=handle,
                )
        else:
            run(["pg_restore", "--list", path], f"{label}: pg_restore")
    elif hook == "postgresql_databases":
        if "PostgreSQL database dump complete" not in tail(path):
            raise RestoreTestError(
                f"{label}: plain SQL dump without its completion trailer"
            )
    elif hook in ("mysql_databases", "mariadb_databases"):
        if "Dump completed" not in tail(path):
            raise RestoreTestError(
                f"{label}: dump without its completion trailer (truncated?)"
            )
    elif hook == "sqlite_databases":
        if "COMMIT;" not in tail(path):
            raise RestoreTestError(
                f"{label}: dump without its final COMMIT (truncated?)"
            )


def test_configuration(args, config):
    borgmatic = [args.borgmatic, "--config", config]
    results = json.loads(
        run(borgmatic + ["repo-list", "--json", "--last", "1"], "repo-list")
    )
    checked = []

    for result in results:
        repository = (
            result["repository"].get("label") or result["repository"]["location"]
        )
        if not result["archives"]:
            raise RestoreTestError(f"{repository}: no archive")
        archive = result["archives"][0]

        # Borg 1 reports archive times in the host's local time, without offset.
        created = datetime.datetime.fromisoformat(archive["time"])
        age = datetime.datetime.now() - created
        if age > datetime.timedelta(hours=args.max_age_hours):
            raise RestoreTestError(
                f"{repository}: latest archive {archive['name']} is {age.days}d "
                f"{age.seconds // 3600}h old (limit {args.max_age_hours}h)"
            )

        selector = ["--repository", repository, "--archive", archive["name"]]
        listing = run(
            borgmatic + ["list"] + selector + ["--json"], f"{repository}: list"
        )
        files = [
            entry
            for entry in (
                json.loads(line)
                for line in listing.splitlines()
                if line.startswith("{")
            )
            if entry.get("type") == "-"
            and not entry["path"].startswith("borgmatic/")
            and entry.get("size", 0) <= args.sample_max_bytes
        ]
        sample = random.sample(files, min(args.sample_files, len(files)))

        with tempfile.TemporaryDirectory(
            dir=args.work_dir, prefix=f"restore-test-{os.path.basename(config)}-"
        ) as root:
            command = borgmatic + ["extract"] + selector + ["--destination", root]
            # `borgmatic/` holds the database dumps and the bootstrap manifest,
            # so it is in every archive borgmatic 2 writes.
            for path in ["borgmatic"] + [entry["path"] for entry in sample]:
                command += ["--path", path]
            run(command, f"{repository}: extract")

            for entry in sample:
                restored = os.path.join(root, entry["path"])
                if (
                    not os.path.isfile(restored)
                    or os.path.getsize(restored) != entry["size"]
                ):
                    raise RestoreTestError(
                        f"{repository}: {entry['path']} not restored intact"
                    )

            dumps = 0
            for metadata in glob.glob(
                os.path.join(root, "borgmatic", "*_databases", "dumps.json")
            ):
                hook = os.path.basename(os.path.dirname(metadata))
                with open(metadata) as handle:
                    for dump in json.load(handle)["dumps"]:
                        check_dump(hook, dump, dump_path(root, hook, dump))
                        dumps += 1

        checked.append(f"{repository} ({len(sample)} files, {dumps} dumps)")

    return checked


def push(url, status, message):
    if not url:
        return
    query = urllib.parse.urlencode({"status": status, "msg": message[:250], "ping": ""})
    try:
        urllib.request.urlopen(f"{url}?{query}", timeout=30).read()
    except OSError as error:  # the test result is still in the journal
        print(f"Could not push to Uptime Kuma: {error}", file=sys.stderr)


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--config-dir", default="/etc/borgmatic.d")
    parser.add_argument("--borgmatic", default="/root/.local/bin/borgmatic")
    parser.add_argument("--work-dir", default="/var/tmp")
    parser.add_argument("--max-age-hours", type=int, default=48)
    parser.add_argument("--sample-files", type=int, default=10)
    parser.add_argument("--sample-max-bytes", type=int, default=50 * 1024 * 1024)
    parser.add_argument(
        "--wait-for-backup",
        type=int,
        default=4 * 3600,
        help="seconds to wait for a running borgmatic.service",
    )
    parser.add_argument(
        "--push-url", default=os.environ.get("RESTORE_TEST_PUSH_URL", "")
    )
    args = parser.parse_args()

    failures = []
    try:
        wait_for_backup(args.wait_for_backup)
    except RestoreTestError as error:
        failures.append(str(error))

    configs = sorted(glob.glob(os.path.join(args.config_dir, "*.yaml")))
    if not configs:
        failures.append(f"no configuration in {args.config_dir}")

    for config in configs if not failures else []:
        name = os.path.splitext(os.path.basename(config))[0]
        try:
            for line in test_configuration(args, config):
                print(f"{name}: OK {line}")
        # Anything else too (a missing `docker` or `pg_restore` binary, an
        # unexpected JSON shape): a crash would push nothing, and the monitor
        # would only notice once its 8-day interval runs out, with no reason.
        except Exception as error:
            print(f"{name}: FAILED {error}", file=sys.stderr)
            failures.append(f"{name}: {error}")

    if failures:
        print("Restore test failed: " + "; ".join(failures), file=sys.stderr)
        push(args.push_url, "down", "; ".join(failures))
        return 1
    push(args.push_url, "up", f"{len(configs)} configurations restored")
    return 0


if __name__ == "__main__":
    sys.exit(main())
