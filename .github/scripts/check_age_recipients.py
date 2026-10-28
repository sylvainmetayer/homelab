#!/usr/bin/env python3
"""Destinataires age des fichiers SOPS, comparés à .sops.yaml.

Chaque `secrets.sops.yaml` du dépôt doit être chiffré pour exactement les
destinataires de la première `creation_rules` de `.sops.yaml` qui le
désigne (sops prend la première qui correspond), et chaque règle doit
compter la clé `secours` : un fichier rechiffré sans elle (un `sops
updatekeys` lancé avec un `.sops.yaml` d'une autre branche, un `sops
--age …` à la main) ne s'ouvrirait plus avec la clé hors ligne, et rien
ne le dirait avant le jour où elle sert. Un destinataire en trop (une
ancienne clé que `sops updatekeys` n'a pas retirée) échoue aussi.

Les destinataires sont en clair dans les métadonnées `sops:` du fichier
chiffré : rien n'est déchiffré, aucune clé age n'est lue. Le test de
déchiffrement avec la clé secours, lui, est manuel :
docs/runbooks/test-cle-secours.md. Bibliothèque standard seulement ; les
deux fichiers suivent le format que sops et ce dépôt écrivent (une règle
par `- path_regex:`, une clé publique par ligne, son nom en commentaire).

Usage (depuis la racine du dépôt, workflow Lint) : check_age_recipients.py
"""

import os
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SOPS_CONFIG = ".sops.yaml"
# Le seul nom que chiffrent les creation_rules de .sops.yaml.
SOPS_NAME = "secrets.sops.yaml"
SKIP_DIRS = {"collections", "galaxy_roles", "node_modules"}
# Nom (commentaire de .sops.yaml) d'une clé que chaque règle doit compter.
REQUIRED_LABELS = ("secours",)

RULE_RE = re.compile(r"^\s*-\s+path_regex:\s*(.+?)\s*$")
AGE_KEY_RE = re.compile(r"\bage1[02-9ac-hj-np-z]{58}\b")
LABEL_RE = re.compile(r"#\s*(\S+)")
RECIPIENT_RE = re.compile(r"^\s+recipient:\s*(\S+)\s*$")


class ConfigError(Exception):
    """.sops.yaml illisible."""


def parse_rules(text):
    """[(path_regex, {clé publique: nom})] des creation_rules, dans l'ordre."""
    rules = []
    for number, line in enumerate(text.splitlines(), 1):
        rule = RULE_RE.match(line)
        if rule:
            pattern = rule.group(1)
            if len(pattern) >= 2 and pattern[0] == pattern[-1] and pattern[0] in "\"'":
                pattern = pattern[1:-1]
            try:
                rules.append((re.compile(pattern), {}))
            except re.error as error:
                raise ConfigError(f"{SOPS_CONFIG}:{number} : path_regex invalide ({error})") from error
            continue
        key = AGE_KEY_RE.search(line.split("#", 1)[0])
        if key:
            if not rules:
                raise ConfigError(f"{SOPS_CONFIG}:{number} : clé age hors d'une règle path_regex")
            label = LABEL_RE.search(line[key.end():])
            rules[-1][1][key.group(0)] = label.group(1) if label else key.group(0)
    if not rules:
        raise ConfigError(f"{SOPS_CONFIG} : aucune creation_rules avec path_regex")
    return rules


def file_recipients(text):
    """Destinataires age des métadonnées `sops:` d'un fichier chiffré (liste, doublons gardés)."""
    recipients, inside = [], False
    for line in text.splitlines():
        if line.startswith("sops:"):
            inside = True
            continue
        if inside and line and not line[0].isspace():
            inside = False
        if inside:
            match = RECIPIENT_RE.match(line)
            if match:
                recipients.append(match.group(1))
    return recipients


def sops_files(root=ROOT):
    """Chemins relatifs (posix) de chaque secrets.sops.yaml du dépôt."""
    found = []
    for directory, subdirs, files in os.walk(root):
        subdirs[:] = sorted(d for d in subdirs if not d.startswith(".") and d not in SKIP_DIRS)
        if SOPS_NAME in files:
            found.append(Path(directory, SOPS_NAME).relative_to(root).as_posix())
    return sorted(found)


def check(rules, files):
    """Erreurs (chaînes). `files` : {chemin relatif: texte chiffré}."""
    errors = []
    for pattern, keys in rules:
        for label in REQUIRED_LABELS:
            if label not in keys.values():
                errors.append(f"{SOPS_CONFIG} : la règle {pattern.pattern} ne compte pas la clé {label}")
    for path, text in sorted(files.items()):
        rule = next(((p, k) for p, k in rules if p.search(path)), None)
        if rule is None:
            errors.append(f"{path} : aucune règle de {SOPS_CONFIG} ne le désigne")
            continue
        pattern, expected = rule
        actual = file_recipients(text)
        if not actual:
            errors.append(f"{path} : aucun destinataire age dans ses métadonnées sops (pas chiffré par sops ?)")
            continue
        duplicates = sorted({key for key in actual if actual.count(key) > 1})
        if duplicates:
            errors.append(f"{path} : destinataire(s) en double : {', '.join(duplicates)}")
        for key in sorted(set(expected) - set(actual), key=expected.get):
            errors.append(
                f"{path} : n'est pas chiffré pour {expected[key]} ({key}), attendu par la règle {pattern.pattern} :"
                f" sops updatekeys {path}"
            )
        for key in sorted(set(actual) - set(expected)):
            errors.append(
                f"{path} : chiffré pour {key}, absent de la règle {pattern.pattern} (ancienne clé ?) :"
                f" sops updatekeys {path}, puis sops rotate -i {path}"
            )
    return errors


def main(root=ROOT):
    try:
        rules = parse_rules((root / SOPS_CONFIG).read_text(encoding="utf-8"))
        files = {path: (root / path).read_text(encoding="utf-8") for path in sops_files(root)}
        errors = check(rules, files)
    except (ConfigError, OSError) as error:
        files, errors = {}, [str(error)]
    if not files and not errors:
        errors = [f"aucun {SOPS_NAME} trouvé sous {root}"]
    for error in errors:
        print(f"::error::{error}")
    if errors:
        return 1
    print(f"{len(files)} fichier(s) SOPS chiffré(s) pour les destinataires de {SOPS_CONFIG} : {', '.join(files)}.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
