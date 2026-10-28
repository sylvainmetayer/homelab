#!/usr/bin/env python3
"""Calendrier iCalendar (RFC 5545) de la maintenance du homelab, lu dans le dépôt.

Événements :

- échéances de rotation des secrets (secrets-rotation.yaml, mêmes périodes et
  même calcul que check_secret_rotation.py, chargé depuis son fichier) : un
  événement sur la journée par date d'échéance, les clés de cette date dans la
  description ;
- restore test et check data trimestriel de borg : la ligne `cron:` de leur
  workflow, traduite en règle de récurrence ;
- renouvellement des domaines : les zones de tofu/dns, un rappel annuel ; les
  dates d'expiration ne sont pas dans le dépôt (DOMAIN_EXPIRY, à renseigner).

Jamais publié : le workflow Maintenance calendar le dépose, un objet par
événement, dans un calendrier Nextcloud privé (maintenance_caldav.py, qui
appelle build_objects) ; le Lint l'exécute avec --check.

Bibliothèque standard seulement, lancé avec `python -I` : le répertoire du
script n'est alors pas dans sys.path, check_secret_rotation est chargé par son
chemin.

Usage (depuis la racine du dépôt) : maintenance_ics.py [--check] (sans option : le
.ics complet sur la sortie standard, pour le lire)
"""

import argparse
import datetime
import importlib.util
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
REPO_URL = "https://github.com/sylvainmetayer/homelab/blob/main"
UID_DOMAIN = "homelab.sylvain.dev"
PRODID = "-//sylvainmetayer//homelab maintenance//FR"
# Ancre fixe des récurrences : leur DTSTART ne bouge pas d'un rendu à l'autre.
EPOCH = datetime.date(2026, 1, 1)

# Workflows planifiés : (fichier, titre, durée, description).
SCHEDULED = (
    (
        ".github/workflows/restore-test.yaml",
        "Restore test des sauvegardes",
        datetime.timedelta(hours=1),
        "Restauration de la dernière archive de chaque dépôt borg sur un runner "
        "(.github/restore-test/README.md). Un échec : moniteur Uptime Kuma « Restore test ».",
    ),
    (
        ".github/workflows/borg-check.yaml",
        "Check data trimestriel des dépôts borg",
        datetime.timedelta(hours=3),
        "borg check --archives-only --verify-data de chaque dépôt. Pas de moniteur : "
        "un run en échec est la seule notification.",
    ),
)

DNS_DIR = "tofu/dns"
# Date d'expiration (MM-JJ) de chaque domaine, quand elle est connue. Aucune ne
# l'est dans le dépôt : TODO, la relever dans l'espace client OVH. Un domaine
# absent d'ici tombe dans le rappel annuel commun du 1er décembre.
DOMAIN_EXPIRY = {}
DOMAIN_NOTICE = datetime.timedelta(days=30)
DOMAIN_TODO_DAY = (12, 1)

CRON_RE = re.compile(r"""^\s*-\s*cron:\s*["']([^"']+)["']\s*(?:#.*)?$""", re.MULTILINE)
ZONE_RE = re.compile(r"""\bzone\s*=\s*"([a-z0-9.-]+)\"""")
MAP_KEY_RE = re.compile(r"""^\s*"([a-z0-9-]+(?:\.[a-z0-9-]+)+)"\s*=""", re.MULTILINE)
# Un domaine déposé (deux labels) : une clé de map en FQDN (media.sylvain.cloud)
# n'est pas un domaine à renouveler.
DOMAIN_RE = re.compile(r"^[a-z0-9-]+\.[a-z]{2,}$")


def load_rotation():
    """Le module check_secret_rotation, chargé par son chemin (sans sys.path)."""
    if "check_secret_rotation" in sys.modules:
        return sys.modules["check_secret_rotation"]
    path = Path(__file__).with_name("check_secret_rotation.py")
    spec = importlib.util.spec_from_file_location("check_secret_rotation", path)
    module = importlib.util.module_from_spec(spec)
    sys.modules["check_secret_rotation"] = module
    spec.loader.exec_module(module)
    return module


rotation = load_rotation()


class CalendarError(Exception):
    """Une source du calendrier est illisible."""


def escape(text):
    """Échappement d'une valeur TEXT (RFC 5545 §3.3.11)."""
    return text.replace("\\", "\\\\").replace(";", "\\;").replace(",", "\\,").replace("\n", "\\n")


def fold(line):
    """Lignes de 75 octets au plus, les suivantes préfixées d'une espace (§3.1)."""
    out, current, size = [], "", 0
    for char in line:
        width = len(char.encode("utf-8"))
        if size + width > (75 if not out else 74):
            out.append(current)
            current, size = char, width
        else:
            current, size = current + char, size + width
    out.append(current)
    return "\r\n ".join(out)


def cron_rule(expression):
    """(heure, minute, RRULE) d'un cron « M H JOURS MOIS * » à valeurs fixes."""
    fields = expression.split()
    if len(fields) != 5 or fields[4] != "*":
        raise CalendarError(f"cron {expression!r} : attendu « M H JOURS MOIS * »")
    minute, hour, days, months = fields[:4]
    if not (minute.isdigit() and hour.isdigit() and re.fullmatch(r"\d+(,\d+)*", days)):
        raise CalendarError(f"cron {expression!r} : minute, heure et jours fixes seulement")
    if months == "*":
        rule = f"FREQ=MONTHLY;BYMONTHDAY={days}"
    elif re.fullmatch(r"\d+(,\d+)*", months):
        rule = f"FREQ=YEARLY;BYMONTH={months};BYMONTHDAY={days}"
    else:
        raise CalendarError(f"cron {expression!r} : mois « * » ou liste fixe seulement")
    return int(hour), int(minute), rule


def first_occurrence(rule, start=EPOCH):
    """Première date de la règle à partir de `start` (DTSTART doit en être une)."""
    parts = {key: value for key, _, value in (part.partition("=") for part in rule.split(";"))}
    days = {int(day) for day in parts["BYMONTHDAY"].split(",")}
    months = {int(month) for month in parts.get("BYMONTH", "").split(",") if month} or set(range(1, 13))
    date = start
    for _ in range(366):
        if date.day in days and date.month in months:
            return date
        date += datetime.timedelta(days=1)
    raise CalendarError(f"règle {rule} : aucune date dans l'année")


def scheduled_events(root=ROOT):
    events = []
    for path, summary, duration, description in SCHEDULED:
        crons = CRON_RE.findall((root / path).read_text(encoding="utf-8"))
        if len(crons) != 1:
            raise CalendarError(f"{path} : attendu une seule ligne cron, trouvé {len(crons)}")
        hour, minute, rule = cron_rule(crons[0])
        start = datetime.datetime.combine(first_occurrence(rule), datetime.time(hour, minute))
        events.append({
            "uid": f"{Path(path).stem}@{UID_DOMAIN}",
            "summary": summary,
            "start": start,
            "end": start + duration,
            "rrule": rule,
            "description": f"{description}\n{REPO_URL}/{path}",
        })
    return events


def rotation_events(root=ROOT):
    """Un événement par date d'échéance de rotation (jamais tournée : inventaire)."""
    entries = rotation.parse_inventory((root / rotation.INVENTORY).read_text(encoding="utf-8"))
    by_date = {}
    for entry in entries:
        deadline = rotation.deadline_of(entry)
        if deadline is not None:
            by_date.setdefault(deadline, []).append(entry)
    events = []
    for deadline, group in sorted(by_date.items()):
        group.sort(key=lambda entry: (entry["file"], entry["key"]))
        keys = [entry["key"] for entry in group]
        lines = []
        for entry in group:
            guess = ", date estimée" if entry.get("estimated") else ""
            lines.append(
                f"- {entry['key']} ({entry['file']}, {entry['kind']}, dernière rotation "
                f"{entry['last_rotated']}{guess}) : {REPO_URL}/{entry['how']}"
            )
        events.append({
            "uid": f"rotation-{deadline.isoformat()}@{UID_DOMAIN}",
            "summary": f"Rotation des secrets ({len(keys)}) : {', '.join(keys[:3])}" + (" …" if len(keys) > 3 else ""),
            "date": deadline,
            "alarm": "-P7D",
            "description": "Échéance de rotation (secrets-rotation.yaml).\n" + "\n".join(lines)
            + "\nProcédure : docs/runbooks/rotation-des-secrets.md",
        })
    return events


def domains(root=ROOT):
    """Zones DNS gérées par tofu/dns : `zone = "…"` et clés de maps par zone."""
    found = set()
    for path in sorted((root / DNS_DIR).glob("*.tf")):
        text = path.read_text(encoding="utf-8")
        found.update(ZONE_RE.findall(text))
        found.update(MAP_KEY_RE.findall(text))
    found = {name for name in found if DOMAIN_RE.match(name)}
    if not found:
        raise CalendarError(f"{DNS_DIR} : aucune zone trouvée")
    return sorted(found)


def domain_events(root=ROOT):
    events, unknown = [], []
    for name in domains(root):
        expiry = DOMAIN_EXPIRY.get(name)
        if expiry is None:
            unknown.append(name)
            continue
        month, day = (int(part) for part in expiry.split("-"))
        date = datetime.date(EPOCH.year, month, day) - DOMAIN_NOTICE
        events.append({
            "uid": f"domain-{name}@{UID_DOMAIN}",
            "summary": f"Renouvellement du domaine {name}",
            "date": date,
            "rrule": "FREQ=YEARLY",
            "description": f"{name} expire le {day:02d}/{month:02d} : vérifier le renouvellement chez OVH.",
        })
    if unknown:
        month, day = DOMAIN_TODO_DAY
        events.append({
            "uid": f"domains-todo@{UID_DOMAIN}",
            "summary": f"Renouvellement des domaines ({len(unknown)})",
            "date": datetime.date(EPOCH.year, month, day),
            "rrule": "FREQ=YEARLY",
            "description": "Vérifier l'échéance et le renouvellement automatique chez OVH : "
            + ", ".join(unknown)
            + ".\nTODO : dates d'expiration absentes du dépôt, les renseigner dans DOMAIN_EXPIRY "
            f"({REPO_URL}/.github/scripts/maintenance_ics.py).",
        })
    return events


def utc(moment):
    return moment.strftime("%Y%m%dT%H%M%SZ")


def render_event(event, stamp):
    lines = ["BEGIN:VEVENT", f"UID:{event['uid']}", f"DTSTAMP:{utc(stamp)}"]
    if "date" in event:
        lines += [
            f"DTSTART;VALUE=DATE:{event['date']:%Y%m%d}",
            f"DTEND;VALUE=DATE:{event['date'] + datetime.timedelta(days=1):%Y%m%d}",
            "TRANSP:TRANSPARENT",
        ]
    else:
        lines += [f"DTSTART:{utc(event['start'])}", f"DTEND:{utc(event['end'])}"]
    if "rrule" in event:
        lines.append(f"RRULE:{event['rrule']}")
    lines += [f"SUMMARY:{escape(event['summary'])}", f"DESCRIPTION:{escape(event['description'])}"]
    if "alarm" in event:
        lines += [
            "BEGIN:VALARM",
            "ACTION:DISPLAY",
            f"DESCRIPTION:{escape(event['summary'])}",
            f"TRIGGER:{event['alarm']}",
            "END:VALARM",
        ]
    lines.append("END:VEVENT")
    return lines


def all_events(root=ROOT):
    return rotation_events(root) + scheduled_events(root) + domain_events(root)


def render(events, stamp, feed=True):
    """Un VCALENDAR (CRLF). feed=False : objet CalDAV, sans METHOD (RFC 4791 §4.1)
    ni propriétés de flux."""
    lines = ["BEGIN:VCALENDAR", "VERSION:2.0", f"PRODID:{PRODID}", "CALSCALE:GREGORIAN"]
    if feed:
        lines += ["METHOD:PUBLISH", "X-WR-CALNAME:Maintenance homelab", "X-WR-TIMEZONE:Europe/Paris"]
    for event in events:
        lines += render_event(event, stamp)
    lines.append("END:VCALENDAR")
    return "".join(fold(line) + "\r\n" for line in lines)


def now_utc():
    return datetime.datetime.now(datetime.timezone.utc)


def build(root=ROOT, now=None):
    """Le calendrier complet, en un fichier .ics."""
    return render(all_events(root), now or now_utc())


def build_objects(root=ROOT, now=None):
    """{UID: objet CalDAV} : un VCALENDAR par événement, pour un calendrier CalDAV."""
    stamp = now or now_utc()
    return {event["uid"]: render([event], stamp, feed=False) for event in all_events(root)}


REQUIRED = {"UID", "DTSTAMP", "DTSTART", "SUMMARY"}


def unfold(physical):
    """Lignes logiques : une ligne qui commence par une espace prolonge la précédente."""
    logical = []
    for line in physical:
        if line.startswith(" ") and logical:
            logical[-1] += line[1:]
        else:
            logical.append(line)
    return logical


class Structure:
    """Composants ouverts, propriétés du VEVENT courant, UID déjà vus."""

    def __init__(self):
        self.stack, self.uids, self.event, self.errors = [], set(), None, []

    def begin(self, value):
        self.stack.append(value)
        if value == "VEVENT":
            self.event = set()

    def end(self, value):
        if not self.stack or self.stack.pop() != value:
            self.errors.append(f"END:{value} sans BEGIN correspondant")
        if value == "VEVENT" and self.event is not None:
            missing = REQUIRED - self.event
            if missing:
                self.errors.append(f"VEVENT sans {', '.join(sorted(missing))}")
            self.event = None

    def prop(self, name, value):
        if self.event is None or not self.stack or self.stack[-1] != "VEVENT":
            return
        prop = name.split(";")[0]
        self.event.add(prop)
        if prop == "UID":
            if value in self.uids:
                self.errors.append(f"UID en double : {value}")
            self.uids.add(value)

    def feed(self, line):
        name, _, value = line.partition(":")
        if name == "BEGIN":
            self.begin(value)
        elif name == "END":
            self.end(value)
        else:
            self.prop(name, value)


def validate(text):
    """Erreurs (chaînes) de structure du calendrier rendu."""
    errors = []
    if not text.endswith("\r\n") or "\n" in text.replace("\r\n", ""):
        errors.append("fins de ligne autres que CRLF")
    physical = text.split("\r\n")[:-1]
    errors += [f"ligne {n} : plus de 75 octets" for n, line in enumerate(physical, 1) if len(line.encode("utf-8")) > 75]
    logical = unfold(physical)
    structure = Structure()
    for line in logical:
        structure.feed(line)
    errors += structure.errors
    if structure.stack:
        errors.append(f"composants non fermés : {', '.join(structure.stack)}")
    if not logical or logical[0] != "BEGIN:VCALENDAR" or logical[-1] != "END:VCALENDAR":
        errors.append("attendu BEGIN:VCALENDAR … END:VCALENDAR")
    if not structure.uids:
        errors.append("aucun événement")
    return errors


def main(argv=None, root=ROOT):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--check", action="store_true", help="construire et valider, sans rien afficher")
    args = parser.parse_args(argv)
    try:
        text = build(root)
    # KeyError : une entrée datée sans `file`, `key` ou `how`, que
    # check_secret_rotation signale dans le même job.
    except (CalendarError, rotation.InventoryError, OSError, ValueError, KeyError) as error:
        print(f"::error::{error}")
        return 1
    errors = validate(text)
    for error in errors:
        print(f"::error::{error}")
    if errors:
        return 1
    if args.check:
        print(f"Calendrier valide : {text.count('BEGIN:VEVENT')} événements.")
    else:
        sys.stdout.write(text)
    return 0


if __name__ == "__main__":
    sys.exit(main())
