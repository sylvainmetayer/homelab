#!/usr/bin/env python3
"""Inventaire de rotation des secrets SOPS (secrets-rotation.yaml).

Deux usages :

- sans option (workflow Lint) : échoue quand une clé d'un fichier SOPS
  manque à l'inventaire, quand une entrée de l'inventaire ne correspond plus
  à aucune clé, ou quand une entrée est invalide (nature inconnue, date
  absente ou dans le futur, lien vers un fichier ou une ancre qui n'existe
  pas) ;
- `--due` (workflow Secrets rotation, chaque lundi) : en plus, liste les
  secrets dont l'échéance tombe dans les `--window` jours (30 par défaut) ou
  est dépassée, et pousse « down » avec leurs noms au moniteur Uptime Kuma
  « Rotation des secrets » (PUSH_URL), « up » sinon.

Les noms de clés d'un fichier SOPS sont en clair : le fichier chiffré est lu
tel quel, sans clé age, et aucune valeur n'est jamais déchiffrée ni affichée.
Bibliothèque standard seulement : l'inventaire suit un sous-ensemble fixe de
YAML (une liste `secrets:` de mappings plats), que ce script lit lui-même.

Usage (depuis la racine du dépôt) : check_secret_rotation.py [--due]
"""

import argparse
import datetime
import http.client
import os
import re
import sys
import urllib.parse
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
INVENTORY = "secrets-rotation.yaml"
SOPS_FILES = ("secrets.sops.yaml", "ansible/secrets.sops.yaml")

# Nature -> période de rotation en mois ; None : pas d'échéance (rotation sur
# incident seulement, ou pas un secret).
KINDS = {
    "provider": 12,  # jetons d'API cloud/fournisseur
    "application": 24,  # clés, jetons et mots de passe d'application
    "database": None,  # mots de passe de base : sur incident
    "encryption": None,  # clés de chiffrement de données : sur incident
    "identifier": None,  # identifiant, adresse, IP : pas un secret
}
FIELDS = {"key", "file", "kind", "last_rotated", "estimated", "how"}
# Tout sauf `identifier` porte une date et un lien vers sa procédure.
DATED_FIELDS = ("last_rotated", "estimated", "how")

TOP_KEY_RE = re.compile(r"^([A-Za-z0-9_]+):")
ENTRY_RE = re.compile(r"^  - ([a-z_]+):(?: (.*))?$")
FIELD_RE = re.compile(r"^    ([a-z_]+):(?: (.*))?$")


class InventoryError(Exception):
    """Inventaire illisible."""


def sops_keys(text):
    """Clés de premier niveau d'un fichier SOPS chiffré, sans `sops`."""
    keys = set()
    for line in text.splitlines():
        match = TOP_KEY_RE.match(line)
        if match and match.group(1) != "sops":
            keys.add(match.group(1))
    return keys


def _scalar(value):
    value = (value or "").strip()
    if len(value) >= 2 and value[0] == value[-1] and value[0] in "\"'":
        return value[1:-1]
    if value in ("true", "false"):
        return value == "true"
    return value


def parse_inventory(text):
    """Liste des entrées (dict, avec `line`) de la liste `secrets:`."""
    entries, current, seen_root = [], None, False
    for number, line in enumerate(text.splitlines(), 1):
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue
        if line == "secrets:":
            if seen_root:
                raise InventoryError(f"ligne {number} : `secrets:` en double")
            seen_root = True
            continue
        if not seen_root:
            raise InventoryError(f"ligne {number} : attendu `secrets:` en tête")
        entry = ENTRY_RE.match(line)
        field = FIELD_RE.match(line)
        if entry:
            current = {"line": number}
            entries.append(current)
            name, value = entry.groups()
        elif field and current is not None:
            name, value = field.groups()
        else:
            raise InventoryError(f"ligne {number} : format inattendu : {line!r}")
        if name not in FIELDS:
            raise InventoryError(f"ligne {number} : champ inconnu {name!r}")
        if name in current:
            raise InventoryError(f"ligne {number} : champ {name!r} en double")
        current[name] = _scalar(value)
    if not seen_root:
        raise InventoryError("liste `secrets:` absente")
    return entries


def slug(heading):
    """Ancre GitHub d'un titre Markdown (accents gardés, ponctuation retirée)."""
    text = re.sub(r"[^\w\- ]", "", heading.strip().lower())
    return text.replace(" ", "-")


def anchors(markdown):
    found, fenced = set(), False
    for line in markdown.splitlines():
        if line.startswith("```"):
            fenced = not fenced
        elif not fenced and line.startswith("#"):
            found.add(slug(line.lstrip("#")))
    return found


def parse_date(value):
    try:
        return datetime.date.fromisoformat(str(value))
    except ValueError:
        return None


def validate(entries, keys_by_file, today, root=ROOT):
    """Erreurs (chaînes) : couverture des fichiers SOPS et champs de chaque entrée."""
    errors, seen, anchor_cache = [], set(), {}
    for entry in entries:
        where = f"{INVENTORY}:{entry['line']}"
        key, file = entry.get("key"), entry.get("file")
        if not key or not file:
            errors.append(f"{where} : `key` et `file` sont obligatoires")
            continue
        label = f"{where} {key} ({file})"
        if file not in keys_by_file:
            errors.append(f"{label} : fichier inconnu, attendu l'un de {', '.join(SOPS_FILES)}")
            continue
        if (file, key) in seen:
            errors.append(f"{label} : entrée en double")
        seen.add((file, key))
        if key not in keys_by_file[file]:
            errors.append(f"{label} : la clé n'existe plus dans {file}, retirer l'entrée")
        kind = entry.get("kind")
        if kind not in KINDS:
            errors.append(f"{label} : nature {kind!r} inconnue, attendu l'une de {', '.join(KINDS)}")
            continue
        if kind == "identifier":
            extra = [name for name in DATED_FIELDS if name in entry]
            if extra:
                errors.append(f"{label} : un identifiant ne porte ni {', '.join(extra)}")
            continue
        missing = [name for name in DATED_FIELDS if name not in entry]
        if missing:
            errors.append(f"{label} : champ(s) manquant(s) : {', '.join(missing)}")
            continue
        date = parse_date(entry["last_rotated"])
        if date is None:
            errors.append(f"{label} : last_rotated {entry['last_rotated']!r} n'est pas une date AAAA-MM-JJ")
        elif date > today:
            errors.append(f"{label} : last_rotated {date} est dans le futur")
        if not isinstance(entry["estimated"], bool):
            errors.append(f"{label} : estimated doit valoir true ou false")
        errors.extend(f"{label} : {error}" for error in check_link(entry["how"], root, anchor_cache))
    for file, keys in keys_by_file.items():
        for key in sorted(keys):
            if (file, key) not in seen:
                errors.append(f"{file} : la clé {key} manque à {INVENTORY}")
    return errors


def check_link(how, root, cache):
    path, _, anchor = str(how).partition("#")
    target = root / path
    if not path or not target.is_file():
        return [f"how {how!r} : fichier introuvable"]
    if anchor:
        if path not in cache:
            cache[path] = anchors(target.read_text(encoding="utf-8"))
        if anchor not in cache[path]:
            return [f"how {how!r} : ancre absente de {path}"]
    return []


def add_months(date, months):
    month = date.month - 1 + months
    year, month = date.year + month // 12, month % 12 + 1
    for day in (date.day, 30, 29, 28):
        try:
            return date.replace(year=year, month=month, day=day)
        except ValueError:
            continue
    raise ValueError(date)


def due_entries(entries, today, window):
    """(échéance, entrée) des secrets à faire tourner d'ici `window` jours, les plus anciens d'abord."""
    due = []
    for entry in entries:
        months = KINDS.get(entry.get("kind"))
        date = parse_date(entry.get("last_rotated", ""))
        if months is None or date is None:
            continue
        deadline = add_months(date, months)
        if deadline <= today + datetime.timedelta(days=window):
            due.append((deadline, entry))
    return sorted(due, key=lambda item: (item[0], item[1]["key"]))


def report(due, today, window=30):
    """(status Uptime Kuma, message court, lignes du détail)."""
    if not due:
        return "up", f"aucun secret à faire tourner dans les {window} jours", []
    lines = []
    for deadline, entry in due:
        state = "dépassée" if deadline < today else "proche"
        guess = " (date estimée)" if entry.get("estimated") else ""
        lines.append(f"{entry['key']} ({entry['file']}, {entry['kind']}) : échéance {deadline} {state}{guess}, {entry['how']}")
    overdue = sum(1 for deadline, _ in due if deadline < today)
    names = ", ".join(entry["key"] for _, entry in due[:5]) + (" …" if len(due) > 5 else "")
    return "down", f"{len(due)} secret(s) à faire tourner, {overdue} en retard : {names}", lines


def push(url, status, msg):
    query = urllib.parse.urlencode({"status": status, "msg": msg, "ping": ""})
    separator = "&" if "?" in url else "?"
    with urllib.request.urlopen(url + separator + query, timeout=30) as response:
        response.read()


def load(root=ROOT):
    entries = parse_inventory((root / INVENTORY).read_text(encoding="utf-8"))
    keys = {file: sops_keys((root / file).read_text(encoding="utf-8")) for file in SOPS_FILES}
    return entries, keys


def main(argv=None, root=ROOT):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--due", action="store_true", help="lister les échéances et pousser au moniteur")
    parser.add_argument("--today", type=datetime.date.fromisoformat, default=datetime.date.today())
    parser.add_argument("--window", type=int, default=30)
    args = parser.parse_args(argv)

    try:
        entries, keys = load(root)
        errors = validate(entries, keys, args.today, root)
    except (InventoryError, OSError) as error:
        entries, errors = [], [str(error)]

    for error in errors:
        print(f"::error::{error}")
    if not args.due:
        if not errors:
            print(f"{INVENTORY} : {len(entries)} entrées, chaque clé SOPS couverte.")
        return 1 if errors else 0

    if errors:
        status, msg, lines = "down", f"inventaire {INVENTORY} invalide ({len(errors)} erreur(s)), voir le run", []
    else:
        status, msg, lines = report(due_entries(entries, args.today, args.window), args.today, args.window)
    print(f"{'::error::' if status == 'down' else ''}{msg}")
    for line in lines:
        print(f"- {line}")
    summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary:
        with open(summary, "a", encoding="utf-8") as handle:
            handle.write(f"{msg}\n\n" + "".join(f"- {line}\n" for line in lines))

    push_url = os.environ.get("PUSH_URL", "")
    if push_url:
        try:
            push(push_url, status, msg)
        except (OSError, ValueError, http.client.HTTPException) as error:
            # Sa classe seule : le message peut citer l'URL push, un secret.
            print(f"::error::push vers Uptime Kuma en échec : {type(error).__name__}")
            return 1
    else:
        print("::warning::PUSH_URL vide : rien n'est poussé.")
    return 1 if status == "down" else 0


if __name__ == "__main__":
    sys.exit(main())
