#!/usr/bin/python3
"""Relève de la boîte Infomaniak dédiée à Papra (rôle papra, papra-intake.timer).

Lit en IMAPS le dossier --config["folder"] (INBOX par défaut) et, pour chaque
message :
  - expéditeur (From) hors de la liste autorisée : le message part tel quel
    dans le dossier « refusé » ; le journal ne garde que son UID et le
    domaine de l'expéditeur, jamais le sujet ni le contenu ;
  - expéditeur autorisé : chaque pièce jointe d'une extension acceptée et de
    25 Mo au plus est écrite dans le dossier d'ingestion de l'organisation
    Papra (ingestion/<id d'organisation>/), que Papra importe puis vide ;
    le message part ensuite dans le dossier « importé ».
Aucun message n'est jamais supprimé : il est déplacé (MOVE, ou COPY puis
\\Deleted et EXPUNGE de ce seul UID si le serveur n'a pas MOVE). Une erreur
d'écriture laisse le message en place, retenté au passage suivant.

Une pièce jointe est d'abord écrite hors du dossier surveillé (tmp_dir, même
système de fichiers), puis liée sous son nom final : Papra ne voit jamais un
fichier à moitié écrit, et le lien échoue plutôt que d'écraser (suffixe -1,
-2… sur collision).

Bibliothèque standard seule. La configuration (dont l'identifiant et le mot
de passe d'application Infomaniak) est un fichier JSON 0600 du compte de
l'unité, jamais la ligne de commande ; le mot de passe n'est jamais affiché.
Le certificat du serveur IMAP est vérifié (ssl.create_default_context).

Usage :
  papra_intake.py --config /etc/papra-intake.json
  papra_intake.py --config FICHIER --eml MESSAGE.eml   # hors réseau (tests)
"""

import argparse
import base64
import email
import email.policy
import email.utils
import imaplib
import json
import os
import re
import ssl
import sys
import tempfile
import unicodedata

# Au-delà, le message n'est même pas téléchargé : 25 Mo de pièce jointe font
# environ 34 Mo en base64, plusieurs pièces jointes davantage.
MAX_MESSAGE_FACTOR = 4
# Image en ligne référencée par Content-ID sous cette taille : un logo de
# signature, pas un document.
INLINE_LOGO_MAX_BYTES = 50 * 1024
SAFE_CHARS_RE = re.compile(r"[^\w.\- ]+")


def log(message):
    print(message, flush=True)


def load_config(path):
    # Chemin donné par l'unité systemd (ou le test), jamais par un message.
    with open(path, encoding="utf-8") as f:  # NOSONAR
        config = json.load(f)
    config["port"] = int(config.get("port", 993))
    config["max_bytes"] = int(config.get("max_bytes", 26214400))
    config.setdefault("folder", "INBOX")
    config["allowed_senders"] = [s.strip().lower() for s in config.get("allowed_senders", []) if s.strip()]
    config["extensions"] = {e.strip().lower().lstrip(".") for e in config.get("extensions", []) if e.strip()}
    return config


def sender_allowed(msg, allowed):
    """Adresse (minuscules) du From et son autorisation : adresse exacte, ou
    domaine écrit « @domaine » ou « domaine ». Un From à plusieurs adresses
    est refusé."""
    addresses = [addr for _, addr in email.utils.getaddresses(msg.get_all("From", [])) if addr]
    if len(addresses) != 1 or "@" not in addresses[0]:
        return None, False
    address = addresses[0].strip().lower()
    domain = address.rsplit("@", 1)[1]
    return address, any(entry in (address, domain, "@" + domain) for entry in allowed)


def safe_name(filename, extension):
    """Nom de fichier sûr : base seule, NFC, caractères hors [\\w.- ] remplacés,
    sans point en tête, 120 caractères au plus, extension gardée."""
    name = unicodedata.normalize("NFC", filename).replace("\\", "/").rsplit("/", 1)[-1]
    name = SAFE_CHARS_RE.sub("_", name).strip(" .")
    stem = name[: -(len(extension) + 1)] if name.lower().endswith("." + extension) else name
    stem = stem.strip(" ._")[:120] or "piece-jointe"
    return f"{stem}.{extension}"


def attachments(msg, extensions, max_bytes):
    """(nom sûr, contenu) des pièces jointes retenues, et le nombre d'écartées.

    Une partie compte si elle a un nom de fichier ; une petite image en ligne
    référencée par Content-ID (logo de signature) est ignorée sans compter."""
    kept, skipped = [], 0
    for part in msg.walk():
        if part.is_multipart():
            continue
        filename = part.get_filename()
        if not filename:
            continue
        extension = filename.rsplit(".", 1)[-1].lower() if "." in filename else ""
        payload = part.get_payload(decode=True)
        if (
            part.get_content_disposition() != "attachment"
            and part.get("Content-ID")
            and part.get_content_maintype() == "image"
            and len(payload or b"") < INLINE_LOGO_MAX_BYTES
        ):
            continue
        if extension not in extensions or not payload or len(payload) > max_bytes:
            skipped += 1
            continue
        kept.append((safe_name(filename, extension), payload))
    return kept, skipped


def inside(directory, name):
    """Chemin de name directement dans directory ; refuse tout autre
    (séparateur, « .. », lien) : défense en plus de safe_name."""
    base = os.path.realpath(directory)
    target = os.path.realpath(os.path.join(base, name))
    if os.path.dirname(target) != base or os.path.basename(target) != name:
        raise ValueError(f"nom de fichier refusé : {name!r}")
    return target


def deliver(items, dest_dir, tmp_dir):
    """Écrit chaque pièce jointe dans tmp_dir puis la lie dans dest_dir sans
    jamais écraser. Renvoie les noms finaux."""
    written = []
    for name, payload in items:
        fd, tmp_path = tempfile.mkstemp(dir=tmp_dir, prefix=".intake-")
        try:
            with os.fdopen(fd, "wb") as f:
                f.write(payload)
                f.flush()
                os.fsync(f.fileno())
            stem, dot, ext = name.rpartition(".")
            candidate, n = name, 0
            while True:
                target = inside(dest_dir, candidate)
                try:
                    os.link(tmp_path, target)  # NOSONAR - nom assaini (safe_name) et borné (inside)
                    break
                except FileExistsError:
                    n += 1
                    candidate = f"{stem}-{n}{dot}{ext}"
            written.append(candidate)
        finally:
            os.unlink(tmp_path)
    return written


def process(raw, config):
    """Décide du sort d'un message brut. Renvoie (autorisé, domaine, écrits, écartées)."""
    msg = email.message_from_bytes(raw, policy=email.policy.default)
    address, allowed = sender_allowed(msg, config["allowed_senders"])
    domain = address.rsplit("@", 1)[1] if address else "?"
    if not allowed:
        return False, domain, [], 0
    items, skipped = attachments(msg, config["extensions"], config["max_bytes"])
    written = deliver(items, config["dest_dir"], config["tmp_dir"])
    return True, domain, written, skipped


def imap_utf7(text):
    """Nom de dossier IMAP en UTF-7 modifié (RFC 3501, 5.1.3)."""
    out, buffer = [], []

    def flush():
        if buffer:
            encoded = "".join(buffer).encode("utf-16-be")
            out.append("&" + base64.b64encode(encoded).decode("ascii").rstrip("=").replace("/", ",") + "-")
            buffer.clear()

    for ch in text:
        if 0x20 <= ord(ch) <= 0x7E:
            flush()
            out.append("&-" if ch == "&" else ch)
        else:
            buffer.append(ch)
    flush()
    return "".join(out)


def quote(mailbox):
    return '"' + mailbox.replace("\\", "\\\\").replace('"', '\\"') + '"'


def check(result, what):
    typ, data = result
    if typ != "OK":
        raise RuntimeError(f"{what} : {typ} {data!r}")
    return data


def server_mailbox(imap, logical):
    """Nom serveur d'un dossier écrit avec « / » : séparateur du serveur, UTF-7."""
    data = check(imap.list('""', '""'), "LIST")
    match = re.search(rb'\) "(.)"', data[0] or b"")
    delimiter = match.group(1).decode() if match else "/"
    return imap_utf7(logical.replace("/", delimiter))


def ensure_mailbox(imap, mailbox):
    typ, _ = imap.create(quote(mailbox))
    # Déjà là : NO [ALREADYEXISTS], sans conséquence. Une autre erreur se
    # verra au MOVE.
    if typ == "OK":
        log(f"Dossier IMAP créé : {mailbox}")


def move(imap, uid, mailbox, has_move):
    if has_move:
        check(imap.uid("MOVE", uid, quote(mailbox)), "MOVE")
        return
    check(imap.uid("COPY", uid, quote(mailbox)), "COPY")
    check(imap.uid("STORE", uid, "+FLAGS.SILENT", r"(\Deleted)"), "STORE")
    check(imap.uid("EXPUNGE", uid), "UID EXPUNGE")


def handle(imap, uid, config, folders, has_move):
    """Traite un message ; renvoie "imported", "refused" ou "left"."""
    label = uid.decode()
    rejected_label = config["rejected_folder"]
    size_data = check(imap.uid("FETCH", uid, "(RFC822.SIZE)"), "FETCH SIZE")
    size = re.search(rb"RFC822\.SIZE (\d+)", size_data[0] or b"")
    if size and int(size.group(1)) > config["max_bytes"] * MAX_MESSAGE_FACTOR:
        log(f"Message {label} : {int(size.group(1))} octets, trop gros, déplacé vers {rejected_label}")
        move(imap, uid, folders["rejected"], has_move)
        return "refused"
    data = check(imap.uid("FETCH", uid, "(BODY.PEEK[])"), "FETCH")
    raw = next((item[1] for item in data if isinstance(item, tuple)), None)
    if raw is None:
        log(f"Message {label} : corps introuvable, laissé en place")
        return "left"
    try:
        allowed, domain, written, skipped = process(raw, config)
    except OSError:
        raise
    except Exception as e:  # noqa: BLE001 - un message illisible ne doit pas bloquer les suivants
        log(f"Message {label} : illisible ({type(e).__name__}), déplacé vers {rejected_label}")
        move(imap, uid, folders["rejected"], has_move)
        return "refused"
    if not allowed:
        log(f"Message {label} : expéditeur non autorisé (domaine {domain}), déplacé vers {rejected_label}")
        move(imap, uid, folders["rejected"], has_move)
        return "refused"
    log(f"Message {label} ({domain}) : {len(written)} pièce(s) jointe(s) déposée(s) {written}, {skipped} écartée(s)")
    move(imap, uid, folders["done"], has_move)
    return "imported"


def run(config):
    context = ssl.create_default_context()
    imap = imaplib.IMAP4_SSL(config["host"], config["port"], ssl_context=context, timeout=60)
    try:
        check(imap.login(config["user"], config["password"]), "LOGIN")
        # Relues après LOGIN : le serveur n'annonce pas tout avant.
        capabilities = set(check(imap.capability(), "CAPABILITY")[0].decode().upper().split())
        has_move = "MOVE" in capabilities
        if not has_move and "UIDPLUS" not in capabilities:
            raise RuntimeError("le serveur n'a ni MOVE ni UIDPLUS : pas de déplacement sûr")
        folders = {
            "done": server_mailbox(imap, config["done_folder"]),
            "rejected": server_mailbox(imap, config["rejected_folder"]),
        }
        for mailbox in folders.values():
            ensure_mailbox(imap, mailbox)
        check(imap.select(quote(server_mailbox(imap, config["folder"]))), "SELECT")
        uids = check(imap.uid("SEARCH", "UNDELETED"), "SEARCH")[0].split()
        outcomes = [handle(imap, uid, config, folders, has_move) for uid in uids]
        log(
            f"Relève terminée : {outcomes.count('imported')} message(s) traité(s), "
            f"{outcomes.count('refused')} refusé(s), {outcomes.count('left')} laissé(s)"
        )
    finally:
        try:
            imap.logout()
        except (OSError, imaplib.IMAP4.error):
            pass


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--config", required=True)
    parser.add_argument("--eml", help="traite ce fichier .eml sans réseau ni IMAP (tests)")
    args = parser.parse_args()
    os.umask(0o077)
    config = load_config(args.config)
    if args.eml:
        # Fichier de test donné par l'opérateur.
        with open(args.eml, "rb") as f:  # NOSONAR
            allowed, domain, written, skipped = process(f.read(), config)
        print(json.dumps({"allowed": allowed, "domain": domain, "written": written, "skipped": skipped}))
        return 0
    try:
        run(config)
    except (OSError, imaplib.IMAP4.error, RuntimeError) as e:
        log(f"Échec de la relève : {type(e).__name__}: {e}")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
