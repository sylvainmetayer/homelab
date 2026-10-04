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
  3. checks what came out: there is at least one dump per database the
     configuration declares, sampled files have the size the archive lists,
     PostgreSQL custom-format dumps are read through by `pg_restore` (run
     inside the dump's own container when there is one, so the client matches
     the server version), plain SQL dumps end with their completion trailer.

Nothing is restored into a live database. The result is pushed to an Uptime
Kuma push monitor: `up` when every configuration passed, `down` with the
failures otherwise, and nothing at all if the script never runs - which the
monitor reports by itself.

It takes no argument and reads nothing from its environment: the only input is
SETTINGS_FILE, written by the borgmatic Ansible role and readable by root only.
Everything this script hands to borg, open() or urlopen() therefore comes from
root-owned files or from borgmatic's own output.
"""

import datetime
import glob
import json
import os
import random
import re
import shutil
import subprocess
import sys
import tempfile
import urllib.parse
import urllib.request


SETTINGS_FILE = "/etc/borgmatic-restore-test.json"
BORGMATIC = "/root/.local/bin/borgmatic"
# The unit's StateDirectory=: root-only (0700), unlike /tmp or /var/tmp, and on
# disk rather than in RAM, since database dumps can be large.
WORK_DIR = "/var/lib/borgmatic-restore-test"
WORK_PREFIX = "restore-test-"

DEFAULT_SETTINGS = {
    "config_dir": "/etc/borgmatic.d",
    "max_age_hours": 48,
    "sample_files": 10,
    "sample_max_bytes": 50 * 1024 * 1024,
    "push_url": "",
}


# Hooks whose dumps this script knows how to check; the others are skipped.
# The extraction itself still reads them: borg checks every chunk it returns.
DATA_SOURCE_HOOKS = (
    "mariadb_databases",
    "mysql_databases",
    "postgresql_databases",
    "sqlite_databases",
)

# A top-level hook key of a borgmatic configuration, e.g. `postgresql_databases:`
# followed by its list on the next lines (an inline `[]` declares nothing).
HOOK_KEY = re.compile(r"(%s):\s*" % "|".join(DATA_SOURCE_HOOKS))

# One line of `borgmatic list --format "{type} {size} {path}{NL}"`.
LISTING_LINE = re.compile(r"([-dlbcps]) (\d+) (.+)")

# Names read from the archive under test are data, not trusted paths: a name
# may not contain a separator nor be "." / "..", and a container name follows
# Docker's own rule.
SAFE_NAME = re.compile(r"[A-Za-z0-9_][A-Za-z0-9_.:@-]*")
CONTAINER_NAME = re.compile(r"[A-Za-z0-9][A-Za-z0-9_.-]*")


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


def tail(path, size=4096):
    with open(path, "rb") as handle:
        handle.seek(0, os.SEEK_END)
        handle.seek(max(0, handle.tell() - size))
        return handle.read().decode("utf-8", errors="replace")


def declared_databases(config):
    """Count the entries of each *_databases hook in a configuration file.

    The configurations are templated by Ansible with the hooks as top-level
    keys and their entries as `- ` items one level down, which is all this
    reads. Nothing is imported to parse YAML: this runs on the host's python3.
    """
    counts = {}
    hook = indent = None
    with open(config) as handle:
        for line in handle:
            stripped = line.strip()
            if not stripped or stripped.startswith("#"):
                continue
            if not line[0].isspace():
                match = HOOK_KEY.fullmatch(line.rstrip())
                hook = match.group(1) if match else None
                indent = None
                if hook:
                    counts.setdefault(hook, 0)
                continue
            if hook and stripped.startswith("- "):
                depth = len(line) - len(line.lstrip())
                indent = depth if indent is None else indent
                if depth == indent:
                    counts[hook] += 1
    return counts


def under(base, *parts):
    """Join validated archive names under base, refusing anything that escapes."""
    for part in parts:
        if not SAFE_NAME.fullmatch(part):
            raise RestoreTestError(f"unexpected name {part!r} in the archive")
    base = os.path.realpath(base)
    path = os.path.realpath(os.path.join(base, *parts))
    if not path.startswith(base + os.sep):
        raise RestoreTestError(f"{'/'.join(parts)} resolves outside the archive")
    return path


def dump_metadata(hook_dir):
    """Map "identifier/name" to the dumps.json entry borgmatic wrote, if any.

    Mirrors borgmatic's make_data_source_dump_filename(). The file is only
    used to find a dump's container: the dumps themselves are found on disk,
    so an archive without it (older borgmatic) is still checked.
    """
    path = os.path.join(hook_dir, "dumps.json")
    if not os.path.exists(path):
        return {}
    with open(path) as handle:
        dumps = json.load(handle).get("dumps", [])
    metadata = {}
    for dump in dumps:
        identifier = dump.get("label") or (
            (dump.get("container") or dump.get("hostname") or "localhost")
            + ("" if dump.get("port") is None else f":{dump['port']}")
        )
        metadata[f"{identifier}/{dump.get('data_source_name')}"] = dump
    return metadata


def container_of(identifier, dump):
    """The container to run pg_restore in, or None to run it on the host."""
    container = dump.get("container")
    if container is None and not dump:
        # No dumps.json: the identifier of a container dump is its name, plus
        # the port when one is set.
        candidate = identifier.split(":", 1)[0]
        inspect = subprocess.run(
            ["docker", "container", "inspect", candidate],
            capture_output=True,
        )
        container = candidate if inspect.returncode == 0 else None
    if container is not None and not CONTAINER_NAME.fullmatch(str(container)):
        raise RestoreTestError(f"unexpected container name {container!r}")
    return container


def check_dump(hook, label, path, container):
    if os.path.isdir(path):  # pg_dump --format=directory
        if not os.path.exists(os.path.join(path, "toc.dat")):
            raise RestoreTestError(f"{label}: directory dump without toc.dat")
        return

    if os.path.getsize(path) == 0:
        raise RestoreTestError(f"{label}: empty dump")

    with open(path, "rb") as handle:
        magic = handle.read(5)

    if hook == "postgresql_databases" and magic == b"PGDMP":
        # A full read, not `--list`: the table of contents sits at the start
        # of a custom-format dump, so a dump cut short in its data still lists.
        command = ["pg_restore", "-f", "/dev/null"]
        if container:
            command = ["docker", "exec", "-i", container] + command
        with open(path, "rb") as handle:
            run(command, f"{label}: pg_restore", stdin=handle)
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


def check_dumps(root, declared):
    """Check every dump of the extracted archive; return how many there were."""
    total = 0
    for hook in DATA_SOURCE_HOOKS:
        hook_dir = os.path.join(root, "borgmatic", hook)
        found = 0
        if os.path.isdir(hook_dir):
            metadata = dump_metadata(hook_dir)
            for identifier in sorted(os.listdir(hook_dir)):
                identifier_dir = under(hook_dir, identifier)
                if not os.path.isdir(identifier_dir):
                    continue  # dumps.json
                for name in sorted(os.listdir(identifier_dir)):
                    key = f"{identifier}/{name}"
                    dump = metadata.pop(key, {})
                    check_dump(
                        hook,
                        f"{hook}/{key}",
                        under(hook_dir, identifier, name),
                        container_of(identifier, dump),
                    )
                    found += 1
            if metadata:
                raise RestoreTestError(
                    f"{hook}: listed in dumps.json but missing from the archive: "
                    + ", ".join(sorted(metadata))
                )
        # `name: all` dumps every database separately, hence at least.
        if found < declared.get(hook, 0):
            raise RestoreTestError(
                f"{hook}: the configuration declares {declared[hook]} "
                f"database(s), the archive holds {found} dump(s)"
            )
        total += found
    return total


def sample_files(command, what, size, max_bytes):
    """Reservoir-sample regular files from a streamed archive listing.

    The listing of a photo library runs to hundreds of thousands of lines:
    it is read line by line and only `size` entries are ever kept.
    """
    rng = random.SystemRandom()
    sample = []
    seen = 0
    with tempfile.TemporaryFile(dir=WORK_DIR) as errors:
        process = subprocess.Popen(
            command, stdout=subprocess.PIPE, stderr=errors, text=True
        )
        for line in process.stdout:
            match = LISTING_LINE.fullmatch(line.rstrip("\n"))
            if not match or match.group(1) != "-":
                continue
            path, length = match.group(3), int(match.group(2))
            if path.startswith("borgmatic/") or length > max_bytes:
                continue
            seen += 1
            if len(sample) < size:
                sample.append((path, length))
            else:
                slot = rng.randrange(seen)
                if slot < size:
                    sample[slot] = (path, length)
        if process.wait() != 0:
            errors.seek(0)
            raise RestoreTestError(
                f"{what} exited {process.returncode}: "
                + first_error(errors.read().decode("utf-8", errors="replace"))
            )
    return sample


def test_configuration(settings, config):
    borgmatic = [BORGMATIC, "--config", config]
    declared = declared_databases(config)
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
        if age > datetime.timedelta(hours=settings["max_age_hours"]):
            raise RestoreTestError(
                f"{repository}: latest archive {archive['name']} is {age.days}d "
                f"{age.seconds // 3600}h old (limit {settings['max_age_hours']}h)"
            )

        selector = ["--repository", repository, "--archive", archive["name"]]
        sample = sample_files(
            borgmatic + ["list"] + selector + ["--format", "{type} {size} {path}{NL}"],
            f"{repository}: list",
            settings["sample_files"],
            settings["sample_max_bytes"],
        )

        with tempfile.TemporaryDirectory(
            dir=WORK_DIR, prefix=f"{WORK_PREFIX}{os.path.basename(config)}-"
        ) as root:
            command = borgmatic + ["extract"] + selector + ["--destination", root]
            # `borgmatic/` holds the database dumps and the bootstrap manifest,
            # so it is in every archive borgmatic 2 writes.
            for path in ["borgmatic"] + [path for path, _ in sample]:
                command += ["--path", path]
            run(command, f"{repository}: extract")

            for path, length in sample:
                restored = os.path.join(root, path)
                if not os.path.isfile(restored) or os.path.getsize(restored) != length:
                    raise RestoreTestError(f"{repository}: {path} not restored intact")

            dumps = check_dumps(root, declared)

        checked.append(f"{repository} ({len(sample)} files, {dumps} dumps)")

    return checked


def push(url, status, message):
    if not url:
        return
    query = urllib.parse.urlencode({"status": status, "msg": message[:250], "ping": ""})
    try:
        urllib.request.urlopen(f"{url}?{query}", timeout=30).read()
    # A malformed URL raises ValueError, not OSError; either way the result is
    # already in the journal and must not turn into a traceback.
    except Exception as error:
        print(f"Could not push to Uptime Kuma: {error}", file=sys.stderr)


def load_settings():
    settings = dict(DEFAULT_SETTINGS)
    with open(SETTINGS_FILE) as handle:
        settings.update(json.load(handle))
    for key in ("max_age_hours", "sample_files", "sample_max_bytes"):
        settings[key] = int(settings[key])
    return settings


def main():
    failures = []
    try:
        settings = load_settings()
    except (OSError, ValueError) as error:
        # Without settings there is no push URL either: the journal is all
        # there is, and the monitor goes DOWN when its interval runs out.
        print(f"Cannot read {SETTINGS_FILE}: {error}", file=sys.stderr)
        return 1

    # A run killed mid-extraction (OOM, reboot, TimeoutStartSec) never reaches
    # TemporaryDirectory's cleanup, and the dumps it left can be gigabytes.
    for leftover in os.listdir(WORK_DIR):
        if leftover.startswith(WORK_PREFIX):
            shutil.rmtree(os.path.join(WORK_DIR, leftover), ignore_errors=True)

    configs = sorted(glob.glob(os.path.join(settings["config_dir"], "*.yaml")))
    if not configs:
        failures.append(f"no configuration in {settings['config_dir']}")

    for config in configs if not failures else []:
        name = os.path.splitext(os.path.basename(config))[0]
        try:
            for line in test_configuration(settings, config):
                print(f"{name}: OK {line}")
        # Anything else too (a missing `docker` or `pg_restore` binary, an
        # unexpected JSON shape): a crash would push nothing, and the monitor
        # would only notice once its 8-day interval runs out, with no reason.
        except Exception as error:
            print(f"{name}: FAILED {error}", file=sys.stderr)
            failures.append(f"{name}: {error}")

    if failures:
        print("Restore test failed: " + "; ".join(failures), file=sys.stderr)
        push(settings["push_url"], "down", "; ".join(failures))
        return 1
    push(settings["push_url"], "up", f"{len(configs)} configurations restored")
    return 0


if __name__ == "__main__":
    sys.exit(main())
