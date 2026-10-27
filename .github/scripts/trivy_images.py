"""Images that the Trivy workflow scans (.github/workflows/trivy.yaml).

Reads every image reference written in clear in the repository: the `image:`
lines of the roles' compose templates (and of compose/), and the
`<role>_image*:` variables of the role defaults that those templates
reference through Jinja (beszel_agent, flip_planning, pangolin's
geoipupdate). A Jinja expression is skipped, its value is read where it is
defined. Prints a JSON list of {"ref", "name"} for the workflow matrix, one
entry per distinct image (two references of one digest are scanned once).
`name` is the code scanning category: the repository with its registry
dropped and `/` turned into `-`, so that a Renovate bump of the tag or the
digest keeps it (a new category would leave the old one's alerts open). Only
a repository pinned more than once gets its tag, then its digest, appended.

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
# `<role>_image<suffix>: "<ref>"` in role defaults.
DEFAULTS_LINE = re.compile(r"""^[a-z0-9_]*_image[a-z0-9_]*:\s*(["']?)(?P<ref>""" + REF + r""")\1\s*(?:#.*)?$""")


def compose_files(root):
    yield from sorted(root.glob("ansible/roles/*/templates/compose.yaml*"))
    yield from sorted(root.glob("compose/*/compose.yaml"))


def defaults_files(root):
    yield from sorted(root.glob("ansible/roles/*/defaults/main.yml"))


def refs_in(text, pattern):
    for line in text.splitlines():
        match = pattern.match(line)
        # A bare word (no `/`, `:` nor `@`) is a variable name or a Jinja
        # leftover, never an image of ours (they all carry a tag).
        if match and re.search(r"[/:@]", match["ref"]):
            yield match["ref"]


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
    found = set()
    for path in compose_files(root):
        found.update(refs_in(path.read_text(), COMPOSE_LINE))
    for path in defaults_files(root):
        found.update(refs_in(path.read_text(), DEFAULTS_LINE))

    by_image = {}
    for ref in sorted(found):
        name, tag, digest = split_ref(ref)
        by_image.setdefault(digest or ref, (ref, name, tag, digest))

    entries = list(by_image.values())
    names = Counter(name for _, name, _, _ in entries)
    entries = [(ref, f"{name}-{tag or 'latest'}" if names[name] > 1 else name, digest)
               for ref, name, tag, digest in entries]
    names = Counter(name for _, name, _ in entries)
    result = []
    for ref, name, digest in entries:
        if names[name] > 1:
            name += "-" + (digest.removeprefix("sha256:")[:12] or "nodigest")
        result.append({"ref": ref, "name": re.sub(r"[^A-Za-z0-9._-]", "-", name)})
    return sorted(result, key=lambda entry: entry["name"])


def main():
    entries = images()
    if not entries:
        print("no image found", file=sys.stderr)
        return 1
    print(json.dumps(entries))
    return 0


if __name__ == "__main__":
    sys.exit(main())
