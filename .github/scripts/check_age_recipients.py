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
docs/runbooks/test-cle-secours.md. Les deux fichiers sont lus avec PyYAML
(yaml.safe_load, l'environnement uv du workflow Lint) ; seul le nom d'une
clé, en commentaire sur sa ligne dans .sops.yaml, est lu dans le texte.

Usage (depuis la racine du dépôt, workflow Lint) : check_age_recipients.py
"""

import os
import re
import sys
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parents[2]
SOPS_CONFIG = ".sops.yaml"
# Le seul nom que chiffrent les creation_rules de .sops.yaml.
SOPS_NAME = "secrets.sops.yaml"
SKIP_DIRS = {"collections", "galaxy_roles", "node_modules"}
# Nom (commentaire de .sops.yaml) d'une clé que chaque règle doit compter.
REQUIRED_LABELS = ("secours",)

AGE_KEY_RE = re.compile(r"\bage1[02-9ac-hj-np-z]{58}\b")
LABEL_RE = re.compile(r"#\s*(\S+)")


class ConfigError(Exception):
    """.sops.yaml illisible."""


def key_labels(text):
    """{clé publique: nom} des clés seules sur leur ligne, nom en commentaire.

    safe_load jette les commentaires : le nom se lit dans le texte. Une
    ligne `age: a,b` en compte plusieurs : pas de nom.
    """
    labels = {}
    for line in text.splitlines():
        code, _, comment = line.partition("#")
        keys = AGE_KEY_RE.findall(code)
        label = LABEL_RE.match("#" + comment) if comment else None
        if len(keys) == 1 and label:
            labels[keys[0]] = label.group(1)
    return labels


def rule_keys(rule):
    """Clés age d'une règle : `age:` et l'`age:` de chaque key_groups."""
    values = [rule.get("age")] + [group.get("age") for group in rule.get("key_groups") or [] if isinstance(group, dict)]
    keys = []
    for value in values:
        for item in value if isinstance(value, list) else [value]:
            if isinstance(item, str):
                keys += [key for key in AGE_KEY_RE.findall(item) if key not in keys]
    return keys


def parse_rules(text):
    """[(path_regex, {clé publique: nom})] des creation_rules, dans l'ordre."""
    try:
        data = yaml.safe_load(text)
    except yaml.YAMLError as error:
        raise ConfigError(f"{SOPS_CONFIG} : YAML invalide ({error})") from error
    entries = data.get("creation_rules") if isinstance(data, dict) else None
    if not isinstance(entries, list) or not entries:
        raise ConfigError(f"{SOPS_CONFIG} : aucune creation_rules avec path_regex")
    labels = key_labels(text)
    rules = []
    for number, rule in enumerate(entries, 1):
        pattern = rule.get("path_regex") if isinstance(rule, dict) else None
        if not isinstance(pattern, str):
            # Sans path_regex, sops l'appliquerait à tous les fichiers que
            # les règles précédentes ne désignent pas.
            raise ConfigError(f"{SOPS_CONFIG} : règle n° {number} sans path_regex")
        try:
            compiled = re.compile(pattern)
        except re.error as error:
            raise ConfigError(f"{SOPS_CONFIG} : règle n° {number}, path_regex invalide ({error})") from error
        rules.append((compiled, {key: labels.get(key, key) for key in rule_keys(rule)}))
    return rules


def file_recipients(text):
    """Destinataires age des métadonnées `sops:` d'un fichier chiffré (liste, doublons gardés)."""
    try:
        data = yaml.safe_load(text)
    except yaml.YAMLError:
        return []
    sops = data.get("sops") if isinstance(data, dict) else None
    stanzas = sops.get("age") if isinstance(sops, dict) else None
    return [
        stanza["recipient"]
        for stanza in stanzas or []
        if isinstance(stanza, dict) and isinstance(stanza.get("recipient"), str)
    ]


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
