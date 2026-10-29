#!/usr/bin/env python3
"""Versions d'immich-server et d'immich-machine-learning, alignées.

Immich publie ses deux images à chaque release, et le serveur refuse un
machine learning d'une autre version (ou s'en sert mal). Renovate les monte
ensemble (groupe immich-role-dependencies de renovate.json), mais un groupe
n'est pas atomique : quand la recherche des tags d'une image échoue (ghcr.io
pagine ceux d'immich-machine-learning en plus de 200 pages de 1000, une seule
page en erreur et Renovate n'a « no-result »), la PR du groupe part avec le
serveur seul. C'est arrivé le 16/10/2026 (#753, v3.3.1 → v3.3.3) : six jours
de versions décalées.

Ce contrôle (workflow Lint, requis par le ruleset de main) échoue donc si
les tags de ces deux images diffèrent dans les fichiers qui les citent
(le rôle immich du Pi, le compose du worker distant compose/immich/). Le
digest n'est pas comparé, il diffère par image ; un suffixe d'accélération
matérielle (`v3.3.5-cuda`, `-openvino`…) est ignoré.

Une PR Renovate qui échoue ici : cocher « rebase/retry » dans la PR (ou
attendre le run suivant), qui relance la recherche ; ne pas merger le
serveur seul. Une montée à la main monte les deux images partout.

Usage (depuis la racine du dépôt, workflow Lint) : check_immich_versions.py
"""

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
# Répertoires où vivent les composes d'Immich (rôle Ansible, worker distant).
SEARCH_DIRS = ("ansible/roles", "compose")
SUFFIXES = {".yaml", ".yml", ".j2"}
IMAGES = ("immich-server", "immich-machine-learning")
IMAGE_RE = re.compile(
    r"^\s*image:\s*['\"]?ghcr\.io/immich-app/"
    r"(?P<image>immich-server|immich-machine-learning):(?P<tag>[^@\s'\"]+)",
    re.MULTILINE,
)


def version(tag):
    """La version d'un tag, sans suffixe d'accélération (v3.3.5-cuda → v3.3.5)."""
    return tag.split("-", 1)[0]


def find_images(root, search_dirs=SEARCH_DIRS):
    """[(chemin relatif, image, tag)] de chaque image Immich citée."""
    found = []
    for directory in search_dirs:
        base = root / directory
        if not base.is_dir():
            continue
        for path in sorted(base.rglob("*")):
            if not path.is_file() or path.suffix not in SUFFIXES:
                continue
            text = path.read_text(encoding="utf-8")
            for match in IMAGE_RE.finditer(text):
                found.append(
                    (path.relative_to(root).as_posix(), match["image"], match["tag"])
                )
    return found


def check(found):
    """Liste des erreurs ; vide si chaque image est citée et toutes alignées."""
    errors = []
    for image in IMAGES:
        if not any(entry[1] == image for entry in found):
            errors.append(
                f"ghcr.io/immich-app/{image} n'est cité nulle part : le contrôle "
                "ne vérifie plus rien (image renommée ? mettre à jour IMAGE_RE)."
            )
    versions = {version(tag) for _, _, tag in found}
    if len(versions) > 1:
        errors.append(
            "immich-server et immich-machine-learning ne sont pas à la même "
            "version (" + ", ".join(sorted(versions)) + ") :"
        )
        errors.extend(f"  {path}: {image}:{tag}" for path, image, tag in found)
        errors.append(
            "Renovate n'a sans doute pas trouvé l'une des deux (recherche des "
            "tags ghcr.io en échec) : cocher « rebase/retry » dans sa PR, ne "
            "pas merger une image seule."
        )
    return errors


def main():
    errors = check(find_images(ROOT))
    for error in errors:
        print(error)
    if not errors:
        print("immich-server et immich-machine-learning alignés.")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
