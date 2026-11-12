#!/usr/bin/env python3
"""Copie à sens unique des agendas, tâches et contacts d'un serveur DAV
(Nextcloud) vers un autre (Infomaniak) : rôle dav_copy, README.md.

Simulation par défaut ; --apply écrit chez la destination, --delete en plus
supprime ce qui a disparu de la source. La source n'est jamais écrite : son
client refuse toute méthode autre que PROPFIND, REPORT, GET, OPTIONS.
Bibliothèque standard seule. Aucun mot de passe, URL avec identifiant ni
contenu d'objet dans la sortie.
"""

import argparse
import base64
import hashlib
import http.client
import json
import os
import re
import signal
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET
from xml.sax.saxutils import escape

READ_METHODS = {"PROPFIND", "REPORT", "GET", "OPTIONS"}
D = "{DAV:}"
CAL = "{urn:ietf:params:xml:ns:caldav}"
CARD = "{urn:ietf:params:xml:ns:carddav}"
APPLE = "{http://apple.com/ns/ical/}"
CS = "{http://calendarserver.org/ns/}"
SKIPPED_TYPES = (CS + "subscribed", CAL + "schedule-inbox", CAL + "schedule-outbox")


class ReadOnlyError(Exception):
    pass


class _NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *a, **k):
        return None  # un 3xx remonte en erreur : jamais de suivi qui perdrait ou propagerait l'authentification


class Dav:
    def __init__(self, url, user, password, read_only, allow_http=False):
        if not allow_http and urllib.parse.urlsplit(url).scheme != "https":
            raise ValueError("URL non https refusée")
        self.url, self.read_only = url, read_only
        self.auth = "Basic " + base64.b64encode(f"{user}:{password}".encode()).decode()
        self.opener = urllib.request.build_opener(_NoRedirect)

    def request(self, method, url, body=None, headers=None):
        if self.read_only and method not in READ_METHODS:
            raise ReadOnlyError(f"méthode {method} refusée sur un client en lecture seule")
        full = urllib.parse.urljoin(self.url, url)
        if urllib.parse.urlsplit(full)[:2] != urllib.parse.urlsplit(self.url)[:2]:
            # un href absolu d'une réponse ne fait jamais partir l'Authorization vers un autre hôte
            raise ValueError("URL hors de l'hôte configuré refusée")
        h = {"Authorization": self.auth, **(headers or {})}
        data = body.encode() if isinstance(body, str) else body
        req = urllib.request.Request(full, data=data, headers=h, method=method)
        try:
            with self.opener.open(req, timeout=60) as r:
                return r.status, r.headers, r.read()
        except urllib.error.HTTPError as e:
            with e:
                return e.code, e.headers, e.read()
        except (urllib.error.URLError, OSError, http.client.HTTPException) as e:
            return 0, {}, type(e).__name__.encode()


def load_conf(path, default_url=None):
    conf = {}
    with open(path, encoding="utf-8") as f:
        for line in f:
            m = re.match(r"^\s*([A-Za-z_]+)\s*[:=]\s*(.*?)\s*$", line)
            if m:
                conf[m.group(1).upper()] = m.group(2)
    url = conf.get("URL") or default_url
    pw = conf.get("MDP") or conf.get("PASSWORD")
    if not url or not pw:
        raise ValueError(f"{os.path.basename(path)} : clés URL (ou --*-url) et MDP requises")
    user = conf.get("USER")
    if not user:  # Infomaniak : l'identifiant est le segment qui suit /calendars/ ou /addressbooks/
        m = re.search(r"/(?:calendars|addressbooks)/([^/]+)/", url)
        if not m:
            raise ValueError(f"{os.path.basename(path)} : clé USER absente")
        user = urllib.parse.unquote(m.group(1))
    return url, user, pw


# ---------------------------------------------------------------- découverte

def _props(resp):
    out = {}
    for ps in resp.findall(D + "propstat"):
        if " 200 " in (ps.findtext(D + "status") or ""):
            for p in ps.find(D + "prop"):
                out[p.tag] = p
    return out


def propfind(dav, url, props, depth):
    body = '<?xml version="1.0"?><d:propfind xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav" ' \
           'xmlns:cr="urn:ietf:params:xml:ns:carddav" xmlns:a="http://apple.com/ns/ical/">' \
           f"<d:prop>{props}</d:prop></d:propfind>"
    st, _, raw = dav.request("PROPFIND", url, body, {"Depth": str(depth), "Content-Type": "application/xml"})
    if st != 207:
        raise RuntimeError(f"PROPFIND {st}")
    root = ET.fromstring(raw)  # shortcut: parseur stdlib, serveurs de confiance ; à durcir si une source tierce arrive
    for r in root.findall(D + "response"):  # 507 (liste tronquée) ou autre erreur par réponse : jamais une liste partielle
        s = r.findtext(D + "status")
        if s and not re.search(r" 2\d\d ", s):
            raise RuntimeError("PROPFIND réponse partielle")
    return [(urllib.parse.urljoin(url, r.findtext(D + "href")), _props(r)) for r in root.findall(D + "response")]


def home_url(dav, user, kind):
    """Dossier des collections : découverte du principal, sinon chemin conventionnel."""
    section = "calendars" if kind == "calendar" else "addressbooks"
    m = re.match(rf"(.*/{section})/[^/]+/", dav.url)
    if m:  # l'URL donnée est déjà dans le dossier (Infomaniak)
        return m.group(0)
    tag = CAL + "calendar-home-set" if kind == "calendar" else CARD + "addressbook-home-set"
    try:
        (_, p), = propfind(dav, dav.url, "<d:current-user-principal/>", 0)
        href = p[D + "current-user-principal"].find(D + "href").text
        (_, p), = propfind(dav, href, "<c:calendar-home-set/><cr:addressbook-home-set/>", 0)
        return urllib.parse.urljoin(dav.url, p[tag].find(D + "href").text)
    except (RuntimeError, KeyError, AttributeError, ValueError, ET.ParseError):
        return dav.url.rstrip("/") + f"/{section}/{urllib.parse.quote(user)}/"


def slug(url):
    return urllib.parse.unquote(url.rstrip("/").rsplit("/", 1)[-1])


def list_collections(dav, user):
    out = []
    for kind in ("calendar", "addressbook"):
        home = home_url(dav, user, kind)
        try:
            entries = propfind(dav, home, "<d:resourcetype/><d:displayname/><a:calendar-color/>"
                               "<c:supported-calendar-component-set/>", 1)
        except RuntimeError:
            continue
        for url, p in entries:
            rt = {c.tag for c in p.get(D + "resourcetype", [])}
            if (CAL + "calendar" if kind == "calendar" else CARD + "addressbook") not in rt or rt & set(SKIPPED_TYPES):
                continue
            comps = [c.get("name") for c in p.get(CAL + "supported-calendar-component-set", [])]
            color = p.get(APPLE + "calendar-color")
            out.append({"kind": kind, "url": url, "slug": slug(url), "name": (p[D + "displayname"].text or "")
                        if D + "displayname" in p else "", "comps": comps,
                        "color": color.text if color is not None else None})
    return out


def list_objects(dav, coll_url):
    out = {}
    for u, p in propfind(dav, coll_url, "<d:getetag/>", 1):
        if u.rstrip("/") == coll_url.rstrip("/") or u.endswith("/"):
            continue
        if D + "getetag" not in p:  # 207 partiel : l'objet existe, la liste serait fausse
            raise RuntimeError("liste incomplète (getetag absent)")
        out[slug(u)] = p[D + "getetag"].text or ""
    return out


def find(colls, kind, wanted):
    w = wanted.casefold()
    return next((c for c in colls if c["kind"] == kind and w in (c["slug"].casefold(), c["name"].casefold())), None)


# ------------------------------------------------------------ iCal / vCard

def split_unquoted(s, ch, maxsplit=-1):
    parts, cur, q = [], [], False
    for c in s:
        if c == '"':
            q = not q
        if c == ch and not q and maxsplit != 0:
            parts.append("".join(cur)); cur = []; maxsplit -= 1
        else:
            cur.append(c)
    parts.append("".join(cur))
    return parts


def logical_lines(text):
    """Lignes logiques (repliage RFC 5545/6350 défait) ; chacune avec ses lignes physiques."""
    out = []
    for raw in text.replace("\r\n", "\n").split("\n"):
        if raw[:1] in (" ", "\t") and out:
            out[-1][0] += raw[1:]; out[-1][1].append(raw)
        elif raw:
            out.append([raw, [raw]])
    return out


def parse_prop(line):
    head, value = (split_unquoted(line, ":", 1) + [""])[:2]
    name, *params = split_unquoted(head, ";")
    ps = {}
    for p in params:
        k, _, v = p.partition("=")
        ps[k.upper()] = [x.strip('"') for x in split_unquoted(v, ",")]
    return name, ps, value


def fold(line):
    """Repliage à 75 octets (RFC 5545), jamais au milieu d'un caractère UTF-8."""
    out, cur, size, limit = [], "", 0, 75
    for ch in line:
        b = len(ch.encode())
        if size + b > limit:
            out.append(cur); cur, size, limit = "", 0, 74
        cur += ch; size += b
    out.append(cur)
    return "\r\n ".join(out)


def add_schedule_agent(ics):
    """SCHEDULE-AGENT=CLIENT sur ORGANIZER/ATTENDEE des VEVENT/VTODO : le serveur d'arrivée n'envoie rien."""
    out, stack = [], []
    for line, phys in logical_lines(ics):
        name, ps, value = parse_prop(line)
        u = name.upper()
        if u == "BEGIN":
            stack.append(value.upper())
        elif u == "END" and stack:
            stack.pop()
        if u in ("ORGANIZER", "ATTENDEE") and stack and stack[-1] in ("VEVENT", "VTODO"):
            if ps.get("SCHEDULE-AGENT") == ["CLIENT"] and len(ps["SCHEDULE-AGENT"]) == 1:
                out.extend(phys)
                continue
            head = split_unquoted(line, ":", 1)[0]
            kept = [p for p in split_unquoted(head, ";")[1:] if p.split("=")[0].upper() != "SCHEDULE-AGENT"]
            out.append(fold(";".join([name, *kept, "SCHEDULE-AGENT=CLIENT"]) + ":" + value))
        else:
            out.extend(phys)
    return "\r\n".join(out) + "\r\n"


def _bday(v):
    d = v.replace("-", "")
    if len(d) >= 8 and d[:4] != "1604":
        return d[:8]
    return "--" + d[-4:]


def normalize(text, vcard=False):
    """Représentation comparable : propriétés triées, noms en majuscules, repliage défait."""
    items, stack = [], []
    for line, _ in logical_lines(text):
        name, ps, value = parse_prop(line)
        n = name.split(".")[-1].upper()  # groupe retiré (item1.TEL)
        if n == "BEGIN":
            stack.append(value.upper()); continue
        if n == "END":
            stack and stack.pop(); continue
        if n == "PRODID" or (vcard and n in ("VERSION", "REV")):
            continue
        if vcard:
            types = sorted({t.casefold() for k in ("TYPE",) for v in ps.get(k, []) for t in [v]} - {"voice", "pref"})
            ps = {"TYPE": types} if types else {}
            if n == "PHOTO":
                ps = {}
                m = re.match(r"data:[^;]*;base64,(.*)", value, re.S)
                try:
                    value = "sha256:" + hashlib.sha256(base64.b64decode(m.group(1) if m else value)).hexdigest()
                except ValueError:
                    pass
            elif n == "BDAY":
                value = _bday(value)
            elif n == "TEL":
                value = re.sub(r"^tel:", "", value, flags=re.I)
        else:
            ps = {k: [x.casefold() for x in v] for k, v in ps.items()}
        items.append(("/".join(stack), n, tuple(sorted((k, tuple(sorted(v))) for k, v in ps.items())), value))
    return sorted(items)


# ------------------------------------------------------------------ copie

def short(name):
    return name[:12] + ("…" if len(name) > 12 else "")


def new_report(kind, name):
    return {"collection": name, "type": kind, "source": 0, "destination": 0, "created": 0, "modified": 0,
            "unchanged": 0, "to_delete": 0, "deleted": 0, "errors": []}


def write(dav, method, url, body, headers, retries, delay, fresh):
    """Écriture avec reprises : toujours sur 5xx/429/0, sur tout échec juste après un MKCALENDAR."""
    for attempt in range(retries + 1):
        st, h, _ = dav.request(method, url, body, headers)
        if st and st < 400:
            return st, h
        if attempt < retries and (fresh or st == 0 or st == 429 or st >= 500):
            time.sleep(delay)
        else:
            break
    return st, h


def copy_collection(src, dst, sc, dcoll, dest_name, dest_home, o, state, rep):
    kind, vcard = sc["kind"], sc["kind"] == "addressbook"
    sobjs = list_objects(src, sc["url"])
    rep["source"] = len(sobjs)
    fresh = False
    if dcoll is None:
        if vcard:
            rep["errors"].append("carnet absent chez la destination : à créer à la main")
            return
        rep["created"] = len(sobjs)
        if not o.apply:
            return
        seg = re.sub(r"[^a-z0-9]+", "-", dest_name.casefold()).strip("-") or \
            hashlib.sha256(dest_name.encode()).hexdigest()[:12]  # jamais un MKCALENDAR sur le dossier lui-même
        url = dest_home + seg + "/"
        comps = "".join(f'<c:comp name="{c}"/>' for c in (sc["comps"] or ["VEVENT", "VTODO"]))
        color = f"<a:calendar-color>{sc['color']}</a:calendar-color>" if sc["color"] else ""
        body = ('<?xml version="1.0"?><c:mkcalendar xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav" '
                'xmlns:a="http://apple.com/ns/ical/"><d:set><d:prop>'
                f"<d:displayname>{escape(dest_name)}</d:displayname>"
                f"{color}<c:supported-calendar-component-set>{comps}</c:supported-calendar-component-set>"
                "</d:prop></d:set></c:mkcalendar>")
        st, _ = write(dst, "MKCALENDAR", url, body, {"Content-Type": "application/xml"}, 0, 0, False)
        if st >= 400 or st == 0:
            rep["errors"].append(f"MKCALENDAR refusé ({st})")
            rep["created"] = 0
            return
        rep["created"] = 0  # recompté écriture par écriture
        dcoll, fresh, dobjs = {"url": url}, True, {}
    else:
        dobjs = list_objects(dst, dcoll["url"])
    rep["destination"] = len(dobjs)
    # État : nom -> [ETag source, ETag destination, créé par l'outil]. Seuls les objets que l'outil a
    # lui-même écrits sont « à lui » : jamais modifiés ni supprimés s'ils n'en viennent pas (677 objets
    # préexistants dans l'agenda par défaut d'Infomaniak). Clé par collection de destination : changer
    # la cible d'une source ne donne aucun droit sur les objets de la nouvelle.
    st_coll = state.setdefault(f"{kind}:{sc['slug']}>{urllib.parse.urlsplit(dcoll['url']).path}", {})
    owned = {n for n, v in st_coll.items() if len(v) > 2 and v[2] is True}
    managed = owned & set(dobjs)
    gone = sorted(managed - set(sobjs))
    rep["to_delete"] = len(gone)
    if gone and (not sobjs or 100 * len(gone) > o.max_delete_pct * len(managed)):
        rep["errors"].append(f"garde-fou : {len(gone)}/{len(managed)} objets copiés disparus de la source "
                             f"(> {o.max_delete_pct} %), collection sautée ; à voir : {', '.join(short(g) for g in gone[:5])}")
        rep["created"] = rep["modified"] = 0
        return
    ctype = "text/vcard; charset=utf-8" if vcard else "text/calendar; charset=utf-8"
    written = []
    for name, etag in sobjs.items():
        durl = dcoll["url"] + urllib.parse.quote(name)
        prev = st_coll.get(name)
        if name in dobjs and prev and prev[:2] == [etag, dobjs[name]]:
            rep["unchanged"] += 1
            continue
        code, _, raw = src.request("GET", sc["url"] + urllib.parse.quote(name))
        if code != 200:
            rep["errors"].append(f"lecture source {short(name)} : {code}")
            continue
        try:  # décodage strict : un octet UTF-8 coupé par le repliage n'est jamais remplacé par U+FFFD
            text = raw.decode("utf-8")
        except UnicodeDecodeError:
            try:
                text = re.sub(rb"\r?\n[ \t]", b"", raw).decode("utf-8")
            except UnicodeDecodeError:
                rep["errors"].append(f"lecture source {short(name)} : UTF-8 invalide")
                continue
        text = text if vcard else add_schedule_agent(text)
        if name in dobjs:
            code, _, draw = dst.request("GET", durl)
            if code == 200 and normalize(draw.decode("utf-8", "replace"), vcard) == normalize(text, vcard):
                rep["unchanged"] += 1
                st_coll[name] = [etag, dobjs[name], name in owned]
                continue
            if name not in owned:
                rep["errors"].append(f"conflit {short(name)} : déjà chez la destination, pas écrit par l'outil, "
                                     "laissé tel quel")
                continue
            hdr = {"If-Match": dobjs[name]} if dobjs[name] else {}
            field = "modified"
        else:
            hdr, field = {"If-None-Match": "*"}, "created"
        if not o.apply:
            rep[field] += 1
            continue
        st, h = write(dst, "PUT", durl, text, {**hdr, "Content-Type": ctype}, o.retries, o.retry_delay, fresh)
        if st >= 400 or st == 0:
            rep["errors"].append(f"écriture {short(name)} : {st}")
        else:
            rep[field] += 1
            st_coll[name] = [etag, h.get("ETag") or "", True]  # à l'outil dès l'écriture, même si la suite échoue
            written.append(name)
    if o.delete and o.apply:
        for name in gone:
            # If-Match sur l'ETag de notre dernière écriture : un objet retouché chez la destination reste
            recorded = st_coll[name][1] or dobjs[name]
            st, _ = write(dst, "DELETE", dcoll["url"] + urllib.parse.quote(name), None,
                          {"If-Match": recorded} if recorded else {}, 0, 0, False)
            if st >= 400 or st == 0:
                rep["errors"].append(f"suppression {short(name)} : {st}")
            else:
                rep["deleted"] += 1
                st_coll.pop(name, None)
    if o.apply and written:
        try:
            after = list_objects(dst, dcoll["url"])
        except (RuntimeError, ET.ParseError):
            after = {}  # ETag inconnu : la passe suivante compare le contenu
        for name in written:
            if name in after:
                st_coll[name][1] = after[name]


def save_state(path, state):
    """Écriture atomique, 0600."""
    tmp = path + ".tmp"
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    os.fchmod(fd, 0o600)
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        json.dump(state, f)
        f.flush()
        os.fsync(f.fileno())
    os.replace(tmp, path)


def run(src, dst, src_user, dst_user, cfg, o, state):
    """Une passe sur toutes les collections de la liste d'inclusion ; rend la liste des comptes rendus."""
    scolls, dcolls = list_collections(src, src_user), list_collections(dst, dst_user)
    homes = {k: home_url(dst, dst_user, k) for k in ("calendar", "addressbook")}
    reports = []
    for kind, section in (("calendar", "calendars"), ("addressbook", "addressbooks")):
        for entry in cfg.get(section, []):
            rep = new_report(kind, f"{entry['source']} -> {entry['dest']}")
            reports.append(rep)
            sc = find(scolls, kind, entry["source"])
            if sc is None:
                rep["errors"].append("collection absente de la source")
                continue
            try:
                copy_collection(src, dst, sc, find(dcolls, kind, entry["dest"]), entry["dest"],
                                homes[kind], o, state, rep)
            except (RuntimeError, ET.ParseError, ValueError) as e:
                rep["errors"].append(f"échec {type(e).__name__} {e}"[:120])
    return reports


def render(reports):
    lines = []
    for r in reports:
        lines.append(f"{r['collection']} ({r['type']}) : source {r['source']}, destination {r['destination']}, "
                     f"créés {r['created']}, modifiés {r['modified']}, inchangés {r['unchanged']}, "
                     f"à supprimer {r['to_delete']}, supprimés {r['deleted']}, erreurs {len(r['errors'])}")
        lines += [f"  erreur : {e}" for e in r["errors"]]
    return "\n".join(lines)


def main(argv=None):
    a = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    a.add_argument("--source-config", required=True)
    a.add_argument("--dest-config", required=True)
    a.add_argument("--source-url", default="https://sylvain.cloud/remote.php/dav/")
    a.add_argument("--dest-url", default=None)
    a.add_argument("--collections", help="JSON : liste d'inclusion {calendars:[{source,dest}], addressbooks:[…]}")
    a.add_argument("--state", help="fichier d'état local (ETag source -> ETag destination)")
    a.add_argument("--apply", action="store_true", help="écrit chez la destination (simulation sinon)")
    a.add_argument("--delete", action="store_true", help="avec --apply : supprime ce qui a disparu de la source")
    a.add_argument("--max-delete-pct", type=float, default=10)
    a.add_argument("--retries", type=int, default=5)
    a.add_argument("--retry-delay", type=float, default=3)
    a.add_argument("--json", action="store_true")
    a.add_argument("--list", choices=("nextcloud", "dest"), help="liste les collections et leurs objets, sans rien copier")
    o = a.parse_args(argv)
    if o.apply and not o.list and not o.state:
        a.error("--apply exige --state : il garde la liste des objets écrits par l'outil, seuls modifiables")
    try:
        su, suser, spw = load_conf(o.source_config, o.source_url)
        du, duser, dpw = load_conf(o.dest_config, o.dest_url)
        src = Dav(su, suser, spw, read_only=True)
        dst = Dav(du, duser, dpw, read_only=not o.apply)  # simulation : aucune écriture possible par construction
        if o.list:
            dav, user = (src, suser) if o.list == "nextcloud" else (dst, duser)
            reports = []
            for c in list_collections(dav, user):
                r = new_report(c["kind"], f"{c['slug']} [{c['name']}] {','.join(c['comps'])}")
                r["source"] = len(list_objects(dav, c["url"]))
                reports.append(r)
        else:
            cfg = json.load(open(o.collections, encoding="utf-8"))
            state = {}
            if o.state and os.path.exists(o.state):
                state = json.load(open(o.state, encoding="utf-8"))
            # systemd arrête par SIGTERM (TimeoutStartSec, stop, arrêt de la VM) : sans ce
            # handler, Python meurt sans passer par le finally et l'état de la passe est perdu.
            signal.signal(signal.SIGTERM, lambda *_: sys.exit(143))
            try:
                reports = run(src, dst, suser, duser, cfg, o, state)
            finally:  # même sur une exception : perdre l'état, c'est perdre la liste des objets à l'outil
                if o.apply:
                    save_state(o.state, state)
    except (OSError, ValueError, RuntimeError, ET.ParseError, KeyError) as e:
        print(f"erreur : {type(e).__name__} {e}"[:200], file=sys.stderr)
        return 2
    mode = "APPLIQUÉ" if o.apply else "SIMULATION (rien n'est écrit)"
    print(json.dumps(reports, ensure_ascii=False, indent=1) if o.json else f"{mode}\n{render(reports)}")
    return 1 if any(r["errors"] for r in reports) else 0


if __name__ == "__main__":
    sys.exit(main())
