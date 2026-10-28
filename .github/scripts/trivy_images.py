"""Images that the Trivy workflow scans (.github/workflows/trivy.yaml).

Reads every image reference written in clear in the repository: the `image:`
lines of the roles' compose templates (and of compose/), and the
`<role>_image*:` variables of the role defaults and of the playbooks' role
entries that those templates reference through Jinja (beszel_agent,
flip_planning and its Keycloak demo, pangolin's geoipupdate and crowdsec). A Jinja
expression is skipped, its value is read where it is defined. Prints a JSON
list of {"ref", "name"} for the workflow matrix, one entry per distinct image
(two references of one digest are scanned once).
`name` is the code scanning category: the repository with its registry
dropped and `/` turned into `-`, so that a Renovate bump of the tag or the
digest keeps it (a new category would leave the old one's alerts open). A
repository pinned more than once gets, for the same reason, where it is
pinned rather than its tag or digest: the role (or compose/ directory), then
the compose service or the variable when the role pins it twice.

    python -I .github/scripts/trivy_images.py
"""
import json
import re
import sys
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

# An image reference: [registry/]repository[:tag][@sha256:<digest>].
REF = r"[a-z0-9][a-z0-9._\-/]*(?::[A-Za-z0-9_][A-Za-z0-9._\-]*)?(?:@sha256:[0-9a-f]{64})?"
# `image: <ref>` in a compose file, quoted or not, optional trailing comment.
COMPOSE_LINE = re.compile(r"""^\s*image:\s*(["']?)(?P<ref>""" + REF + r""")\1\s*(?:#.*)?$""")
# A compose service key (two-space indent), the location of the next `image:`.
SERVICE_LINE = re.compile(r"^  (?P<key>[A-Za-z0-9._-]+):\s*(?:#.*)?$")
# `<role>_image<suffix>: "<ref>"` in role defaults or a playbook's role entry.
VARS_LINE = re.compile(
    r"""^\s*(?P<key>[a-z0-9_]*_image[a-z0-9_]*):\s*(["']?)(?P<ref>""" + REF + r""")\2\s*(?:#.*)?$""")


def compose_files(root):
    yield from sorted(root.glob("ansible/roles/*/templates/compose.yaml*"))
    yield from sorted(root.glob("compose/*/compose.yaml"))


def vars_files(root):
    yield from sorted(root.glob("ansible/roles/*/defaults/main.yml"))
    yield from sorted(p for p in root.glob("ansible/*.y*ml") if p.name != "secrets.sops.yaml")


def owner(root, path):
    """Role, compose/ directory or playbook a file belongs to."""
    parts = path.relative_to(root).parts
    if parts[:2] == ("ansible", "roles"):
        return parts[2]
    return parts[1] if parts[0] == "compose" else path.stem


def refs_in(text, pattern):
    """(ref, key) of each reference: key is the compose service or the variable."""
    service = ""
    for line in text.splitlines():
        if pattern is COMPOSE_LINE and (key := SERVICE_LINE.match(line)):
            service = key["key"]
        match = pattern.match(line)
        # A bare word (no `/`, `:` nor `@`) is a variable name or a Jinja
        # leftover, never an image of ours (they all carry a tag).
        if match and re.search(r"[/:@]", match["ref"]):
            yield match["ref"], match.groupdict().get("key") or service


def split_ref(ref):
    """(repository name, tag, digest) of a reference, registry dropped."""
    repository, _, digest = ref.partition("@")
    tag = ""
    last = repository.rsplit("/", 1)[-1]
    if ":" in last:
        tag = last.split(":", 1)[1]
        repository = repository[: repository.rindex(":")]
    parts = repository.split("/")
    # A first component holding a dot or a port is a registry.
    if len(parts) > 1 and ("." in parts[0] or ":" in parts[0] or parts[0] == "localhost"):
        parts = parts[1:]
    if parts[0] == "library" and len(parts) > 1:
        parts = parts[1:]
    return "-".join(parts), tag, digest


def images(root=ROOT):
    # ref -> (role, key) of every place that pins it.
    found = {}
    for files, pattern in ((compose_files, COMPOSE_LINE), (vars_files, VARS_LINE)):
        for path in files(root):
            role = owner(root, path)
            for ref, key in refs_in(path.read_text(), pattern):
                found.setdefault(ref, set()).add((role, key.removeprefix(role + "_")))

    # One scan per digest; its first location (sorted) names it.
    by_image = {}
    for ref in sorted(found):
        name, _, digest = split_ref(ref)
        entry = by_image.setdefault(digest or ref, [ref, name, set()])
        entry[2].update(found[ref])
    entries = [(ref, name, min(places)) for ref, name, places in by_image.values()]

    names = Counter(name for _, name, _ in entries)
    roles = Counter((name, role) for _, name, (role, _) in entries)
    result = []
    for ref, name, (role, key) in entries:
        if names[name] > 1:
            name += f"-{role}" if roles[(name, role)] == 1 else f"-{role}-{key}"
        result.append({"ref": ref, "name": re.sub(r"[^A-Za-z0-9._-]", "-", name)})
    return sorted(result, key=lambda entry: entry["name"])


def main():
    entries = images()
    if not entries:
        print("no image found", file=sys.stderr)
        return 1
    names = Counter(entry["name"] for entry in entries)
    if dup := sorted(name for name, count in names.items() if count > 1):
        print(f"two images share a category: {dup}", file=sys.stderr)
        return 1
    print(json.dumps(entries))
    return 0


if __name__ == "__main__":
    sys.exit(main())
