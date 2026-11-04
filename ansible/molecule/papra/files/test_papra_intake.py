"""Tests de papra_intake.py (rôle papra), lancés par verify.yml du scénario
avec le python3 de l'hôte de test : messages fabriqués, faux serveur IMAP en
mémoire, aucun appel réseau. À la main : copier ce fichier à côté de
ansible/roles/papra/files/papra_intake.py, puis
python3 -I -m unittest discover -s . -p 'test_*.py'.
"""

import email
import email.message
import email.policy
import io
import json
import os
import tempfile
import unittest
from contextlib import redirect_stderr, redirect_stdout
from unittest import mock

import papra_intake as pi

ALLOWED = ["moi@exemple.test", "@partenaire.test", "banque.test"]
EXTENSIONS = {"pdf", "png"}
MAX_BYTES = 1000


def message(sender="moi@exemple.test", subject="Objet", body="Corps", date="Tue, 03 Nov 2026 10:00:00 +0100"):
    msg = email.message.EmailMessage(policy=email.policy.default)
    msg["From"] = sender
    msg["To"] = "papra@exemple.test"
    msg["Subject"] = subject
    msg["Date"] = date
    msg.set_content(body)
    return msg


def attach(msg, filename, payload=b"contenu", maintype="application", subtype="pdf"):
    msg.add_attachment(payload, maintype=maintype, subtype=subtype, filename=filename)
    return msg


def parsed(raw_headers):
    return email.message_from_bytes(raw_headers.encode() + b"\n\ncorps\n", policy=email.policy.default)


class Directories(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.dest = os.path.join(directory.name, "dest")
        self.tmp = os.path.join(directory.name, "tmp")
        os.mkdir(self.dest)
        os.mkdir(self.tmp)
        self.config = {
            "allowed_senders": ALLOWED,
            "extensions": EXTENSIONS,
            "max_bytes": MAX_BYTES,
            "body_marker": "[mail]",
            "dest_dir": self.dest,
            "tmp_dir": self.tmp,
            "rejected_folder": "Papra/Refusé",
        }


class LoadConfigTest(unittest.TestCase):
    def load(self, config):
        with tempfile.NamedTemporaryFile("w", suffix=".json", encoding="utf-8") as f:
            json.dump(config, f)
            f.flush()
            return pi.load_config(f.name)

    def test_defaults(self):
        config = self.load({})
        self.assertEqual(config["port"], 993)
        self.assertEqual(config["max_bytes"], 26214400)
        self.assertEqual(config["folder"], "INBOX")
        self.assertEqual(config["body_marker"], "[mail]")
        self.assertEqual((config["allowed_senders"], config["extensions"]), ([], set()))

    def test_normalisation(self):
        config = self.load(
            {
                "port": "143",
                "allowed_senders": [" Moi@Exemple.Test ", " "],
                "extensions": [".PDF", " png ", ""],
                "body_marker": "  [doc] ",
            }
        )
        self.assertEqual(config["port"], 143)
        self.assertEqual(config["allowed_senders"], ["moi@exemple.test"])
        self.assertEqual(config["extensions"], {"pdf", "png"})
        self.assertEqual(config["body_marker"], "[doc]")

    def test_null_marker_is_never(self):
        self.assertEqual(self.load({"body_marker": None})["body_marker"], "")


class SenderAllowedTest(unittest.TestCase):
    def check(self, from_header):
        return pi.sender_allowed(parsed(from_header), ALLOWED)

    def test_exact_address_any_case(self):
        self.assertEqual(self.check("From: MOI@Exemple.TEST"), ("moi@exemple.test", True))

    def test_domain_with_or_without_at(self):
        self.assertTrue(self.check("From: Une Personne <x@partenaire.test>")[1])
        self.assertTrue(self.check("From: x@banque.test")[1])

    def test_other_address_of_an_exact_entry_domain(self):
        self.assertEqual(self.check("From: autre@exemple.test"), ("autre@exemple.test", False))

    def test_subdomain_and_lookalike_are_refused(self):
        self.assertFalse(self.check("From: x@sous.banque.test")[1])
        self.assertFalse(self.check("From: x@fausse-banque.test")[1])
        self.assertFalse(self.check("From: x@banque.test.evil.test")[1])

    def test_allowed_address_in_the_display_name_does_not_count(self):
        self.assertEqual(self.check('From: "moi@exemple.test" <x@evil.test>'), ("x@evil.test", False))

    def test_several_addresses_are_refused(self):
        self.assertEqual(self.check("From: moi@exemple.test, x@evil.test"), (None, False))

    def test_two_from_headers_are_refused(self):
        self.assertEqual(self.check("From: moi@exemple.test\nFrom: x@evil.test"), (None, False))

    def test_no_or_unusable_from_is_refused(self):
        self.assertEqual(pi.sender_allowed(parsed("Subject: x"), ALLOWED), (None, False))
        self.assertEqual(self.check("From: pas-une-adresse"), (None, False))


class SafeNameTest(unittest.TestCase):
    def test_cases(self):
        cases = [
            ("facture.pdf", "pdf", "facture.pdf"),
            ("Facture.PDF", "pdf", "Facture.pdf"),
            ("../../etc/passwd.pdf", "pdf", "passwd.pdf"),
            ("..\\..\\windows\\x.pdf", "pdf", "x.pdf"),
            ("a b;c$d.pdf", "pdf", "a b_c_d.pdf"),
            ("  .caché.pdf", "pdf", "caché.pdf"),
            ("....pdf", "pdf", "pdf.pdf"),
            (".pdf", "pdf", "pdf.pdf"),
            ("___.pdf", "pdf", "piece-jointe.pdf"),
            ("sans-extension", "pdf", "sans-extension.pdf"),
        ]
        for filename, extension, expected in cases:
            with self.subTest(filename=filename):
                self.assertEqual(pi.safe_name(filename, extension), expected)

    def test_nfc(self):
        self.assertEqual(pi.safe_name("résumé.pdf", "pdf"), "résumé.pdf")

    def test_stem_is_capped_and_extension_kept(self):
        name = pi.safe_name("x" * 300 + ".pdf", "pdf")
        self.assertEqual(name, "x" * 120 + ".pdf")


class AttachmentsTest(unittest.TestCase):
    def run_attachments(self, msg):
        return pi.attachments(msg, EXTENSIONS, MAX_BYTES)

    def test_kept_and_skipped(self):
        msg = attach(message(), "../a.pdf")
        attach(msg, "b.exe", subtype="octet-stream")
        attach(msg, "sans_extension", subtype="octet-stream")
        attach(msg, "gros.pdf", b"x" * (MAX_BYTES + 1))
        attach(msg, "vide.pdf", b"")
        attach(msg, "limite.PDF", b"x" * MAX_BYTES)
        kept, skipped = self.run_attachments(msg)
        self.assertEqual([name for name, _ in kept], ["a.pdf", "limite.pdf"])
        self.assertEqual(kept[0][1], b"contenu")
        self.assertEqual(skipped, 4)

    def test_body_without_filename_is_not_an_attachment(self):
        self.assertEqual(self.run_attachments(message()), ([], 0))

    def inline_image(self, size, disposition="inline", cid="<logo@x>"):
        msg = message()
        msg.make_mixed()
        msg.add_attachment(b"x" * size, maintype="image", subtype="png", filename="logo.png", disposition=disposition)
        part = msg.get_payload()[-1]
        if cid:
            part["Content-ID"] = cid
        return msg

    def test_small_inline_logo_is_ignored_without_counting(self):
        self.assertEqual(self.run_attachments(self.inline_image(100)), ([], 0))

    def test_big_inline_image_counts_as_a_document(self):
        msg = self.inline_image(pi.INLINE_LOGO_MAX_BYTES)
        kept, skipped = pi.attachments(msg, EXTENSIONS, pi.INLINE_LOGO_MAX_BYTES)
        self.assertEqual(([name for name, _ in kept], skipped), (["logo.png"], 0))

    def test_small_image_attached_is_a_document(self):
        kept, skipped = self.run_attachments(self.inline_image(100, disposition="attachment"))
        self.assertEqual(([name for name, _ in kept], skipped), (["logo.png"], 0))

    def test_small_inline_image_without_cid_is_a_document(self):
        kept, _ = self.run_attachments(self.inline_image(100, cid=None))
        self.assertEqual([name for name, _ in kept], ["logo.png"])


class MarkedSubjectTest(unittest.TestCase):
    def test_cases(self):
        cases = [
            ("[mail] Facture", "Facture"),
            ("[MAIL]Facture", "Facture"),
            ("Fwd: [mail] Facture", "Facture"),
            ("FW : TR: Re: [mail] Facture", "Facture"),
            ("  fwd:[mail]", ""),
            ("Facture [mail]", None),
            ("Forward: [mail] Facture", None),
            ("", None),
        ]
        for subject, expected in cases:
            with self.subTest(subject=subject):
                self.assertEqual(pi.marked_subject(subject, "[mail]"), expected)

    def test_no_marker_configured_is_never(self):
        self.assertIsNone(pi.marked_subject("[mail] Facture", ""))


class HtmlToTextTest(unittest.TestCase):
    def test_hidden_parts_entities_and_breaks(self):
        markup = (
            "<html><head><title>Titre</title><style>p{color:red}</style></head><body>"
            "<script>alert('x')</script>"
            "<p>Caf&eacute; &amp; th&eacute;</p><div>a<br>b<br/>c</div>"
            "<ul><li>un</li><li>deux</li></ul>"
            "<table><tr><td>A</td><td>B</td></tr></table></body></html>"
        )
        self.assertEqual(pi.html_to_text(markup), "Café & thé\n\na\nb\nc\n\n- un\n- deux\nA B")

    def test_unclosed_head_is_closed_by_body(self):
        self.assertEqual(pi.html_to_text("<head><meta charset=utf-8><body>visible"), "visible")

    def test_stray_closing_tag_does_not_go_negative(self):
        self.assertEqual(pi.html_to_text("</style>avant<style>x</style>après"), "avantaprès")

    def test_whitespace_is_collapsed(self):
        self.assertEqual(pi.html_to_text("<p>  un\n   deux  </p><p></p><p></p><p>trois</p>"), "un deux\n\ntrois")


class BodyFilesTest(unittest.TestCase):
    def test_text_then_eml(self):
        msg = message(subject="[mail] Facture 10/2026", body="Bonjour")
        raw = msg.as_bytes()
        reparsed = email.message_from_bytes(raw, policy=email.policy.default)
        kept, skipped = pi.body_files(reparsed, raw, "Facture 10/2026", 10000)
        self.assertEqual(skipped, 0)
        self.assertEqual([name for name, _ in kept], ["2026-11-03 - Facture 10-2026.txt", "2026-11-03 - Facture 10-2026.eml"])
        text = kept[0][1].decode()
        self.assertIn("De : moi@exemple.test\n", text)
        self.assertIn("Objet : Facture 10/2026\n\nBonjour\n", text)
        self.assertEqual(kept[1][1], raw)

    def test_empty_title_keeps_the_date(self):
        msg = message()
        kept, _ = pi.body_files(msg, b"x", "", 10000)
        self.assertEqual(kept[0][0], "2026-11-03.txt")

    def test_html_only_body(self):
        msg = message()
        msg.set_content("<p>Bonjour <b>toi</b></p>", subtype="html")
        kept, _ = pi.body_files(msg, b"x", "o", 10000)
        self.assertIn("\n\nBonjour toi\n", kept[0][1].decode())

    def test_oversized_parts_are_skipped_one_by_one(self):
        msg = message()
        with redirect_stderr(io.StringIO()) as err:
            kept, skipped = pi.body_files(msg, b"x" * 2000, "o", 1000)
        self.assertEqual(([name.rsplit(".")[-1] for name, _ in kept], skipped), (["txt"], 1))
        self.assertIn(".eml du mail écarté", err.getvalue())

    def test_unknown_charset_falls_back(self):
        raw = (
            b"From: moi@exemple.test\nSubject: x\nDate: Tue, 03 Nov 2026 10:00:00 +0100\n"
            b"Content-Type: text/plain; charset=inconnu\n\ncaf\xc3\xa9\n"
        )
        msg = email.message_from_bytes(raw, policy=email.policy.default)
        kept, _ = pi.body_files(msg, raw, "x", 10000)
        self.assertIn("café", kept[0][1].decode())


class DeliverTest(Directories):
    def test_inside_refuses_anything_but_a_direct_child(self):
        os.symlink("/etc/passwd", os.path.join(self.dest, "lien.pdf"))
        for name in ("../x.pdf", "a/b.pdf", "..", "lien.pdf", ""):
            with self.subTest(name=name), self.assertRaises(ValueError):
                pi.inside(self.dest, name)
        self.assertEqual(pi.inside(self.dest, "x.pdf"), os.path.join(os.path.realpath(self.dest), "x.pdf"))

    def test_written_and_sas_left_empty(self):
        written = pi.deliver([("a.pdf", b"1"), ("b.pdf", b"2")], self.dest, self.tmp)
        self.assertEqual(written, ["a.pdf", "b.pdf"])
        with open(os.path.join(self.dest, "b.pdf"), "rb") as f:
            self.assertEqual(f.read(), b"2")
        self.assertEqual(os.listdir(self.tmp), [])

    def test_collision_never_overwrites(self):
        with open(os.path.join(self.dest, "a.pdf"), "wb") as f:
            f.write(b"ancien")
        written = pi.deliver([("a.pdf", b"1"), ("a.pdf", b"2")], self.dest, self.tmp)
        self.assertEqual(written, ["a-1.pdf", "a-2.pdf"])
        with open(os.path.join(self.dest, "a.pdf"), "rb") as f:
            self.assertEqual(f.read(), b"ancien")

    def test_refused_name_leaves_nothing_behind(self):
        with self.assertRaises(ValueError):
            pi.deliver([("../a.pdf", b"1")], self.dest, self.tmp)
        self.assertEqual((os.listdir(self.dest), os.listdir(self.tmp)), ([], []))

    def test_remove_stale_tmp_only_touches_its_own_files(self):
        for name in (".intake-reste", "autre"):
            with open(os.path.join(self.tmp, name), "wb"):
                pass
        os.mkdir(os.path.join(self.tmp, ".intake-dossier"))
        pi.remove_stale_tmp(self.tmp)
        self.assertEqual(sorted(os.listdir(self.tmp)), [".intake-dossier", "autre"])


class ProcessTest(Directories):
    def test_refused_sender_writes_nothing(self):
        raw = attach(message(sender="x@evil.test"), "a.pdf").as_bytes()
        self.assertEqual(pi.process(raw, self.config), (False, "evil.test", [], 0))
        self.assertEqual(os.listdir(self.dest), [])

    def test_unusable_sender_has_no_domain(self):
        raw = attach(message(sender="moi@exemple.test, x@evil.test"), "a.pdf").as_bytes()
        self.assertEqual(pi.process(raw, self.config), (False, "?", [], 0))

    def test_allowed_sender_attachments_only_without_marker(self):
        raw = attach(message(), "a.pdf").as_bytes()
        self.assertEqual(pi.process(raw, self.config), (True, "exemple.test", ["a.pdf"], 0))

    def test_marker_adds_the_mail_itself(self):
        raw = attach(message(subject="Fwd: [mail] Note"), "a.pdf").as_bytes()
        allowed, _, written, skipped = pi.process(raw, self.config)
        self.assertTrue(allowed)
        self.assertEqual(written, ["a.pdf", "2026-11-03 - Note.txt", "2026-11-03 - Note.eml"])
        self.assertEqual(skipped, 0)


class ImapNamesTest(unittest.TestCase):
    def test_imap_utf7(self):
        cases = {
            "INBOX": "INBOX",
            "Importé": "Import&AOk-",
            "A&B": "A&-B",
            # L'exemple de la RFC 3501, 5.1.3.
            "~peter/mail/台北/日本語": "~peter/mail/&U,BTFw-/&ZeVnLIqe-",
            "é/è": "&AOk-/&AOg-",
        }
        for text, expected in cases.items():
            with self.subTest(text=text):
                self.assertEqual(pi.imap_utf7(text), expected)

    def test_server_mailbox_uses_the_server_delimiter(self):
        self.assertEqual(pi.server_mailbox("Papra/Refusé", "."), "Papra.Refus&AOk-")

    def test_quote(self):
        self.assertEqual(pi.quote('a"b\\c'), '"a\\"b\\\\c"')

    def test_check(self):
        self.assertEqual(pi.check(("OK", [b"x"]), "X"), [b"x"])
        with self.assertRaisesRegex(RuntimeError, "LOGIN : NO"):
            pi.check(("NO", [b"x"]), "LOGIN")


class FakeImap:
    """Le serveur IMAP réduit à ce que handle et move appellent : journal des
    commandes UID, réponses données par le test."""

    def __init__(self, size=100, raw=b"", fetch_ok=True, create_ok=True, status_ok=True, listing=None):
        self.size, self.raw, self.fetch_ok = size, raw, fetch_ok
        self.create_ok, self.status_ok, self.listing = create_ok, status_ok, listing
        self.commands = []

    def uid(self, command, uid, *args):
        self.commands.append((command, *args))
        if command == "FETCH" and args[0] == "(RFC822.SIZE)":
            return "OK", [b"1 (UID 7 RFC822.SIZE %d)" % self.size]
        if command == "FETCH":
            return ("OK", [(b"1 (BODY[]", self.raw), b")"]) if self.raw else ("OK", [None])
        return ("OK", [b""]) if self.fetch_ok else ("NO", [b"refus"])

    def create(self, mailbox):
        self.commands.append(("CREATE", mailbox))
        return ("OK", [b""]) if self.create_ok else ("NO", [b"[ALREADYEXISTS]"])

    def status(self, mailbox, what):
        self.commands.append(("STATUS", mailbox))
        return ("OK", [b""]) if self.status_ok else ("NO", [b"refus"])

    def list(self, *_):
        return "OK", [self.listing]


FOLDERS = {"done": "Importe", "rejected": "Refuse"}


class HandleTest(Directories):
    def handle(self, imap, has_move=True):
        with redirect_stdout(io.StringIO()) as out:
            outcome = pi.handle(imap, b"7", self.config, FOLDERS, has_move)
        return outcome, out.getvalue()

    def test_allowed_goes_to_done_after_writing(self):
        imap = FakeImap(raw=attach(message(), "a.pdf").as_bytes())
        outcome, _ = self.handle(imap)
        self.assertEqual(outcome, "imported")
        self.assertEqual(imap.commands[-1], ("MOVE", '"Importe"'))
        self.assertEqual(os.listdir(self.dest), ["a.pdf"])

    def test_refused_goes_to_rejected_and_the_log_keeps_only_the_domain(self):
        raw = attach(message(sender="personne@evil.test", subject="Sujet privé"), "a.pdf").as_bytes()
        imap = FakeImap(raw=raw)
        outcome, log = self.handle(imap)
        self.assertEqual(outcome, "refused")
        self.assertEqual(imap.commands[-1], ("MOVE", '"Refuse"'))
        self.assertEqual(os.listdir(self.dest), [])
        self.assertIn("evil.test", log)
        self.assertNotIn("personne", log)
        self.assertNotIn("Sujet privé", log)

    def test_too_big_is_refused_without_being_downloaded(self):
        imap = FakeImap(size=MAX_BYTES * pi.MAX_MESSAGE_FACTOR + 1)
        self.assertEqual(self.handle(imap)[0], "refused")
        self.assertEqual(imap.commands, [("FETCH", "(RFC822.SIZE)"), ("MOVE", '"Refuse"')])

    def test_at_the_size_limit_is_downloaded(self):
        imap = FakeImap(size=MAX_BYTES * pi.MAX_MESSAGE_FACTOR, raw=message().as_bytes())
        self.assertEqual(self.handle(imap)[0], "imported")

    def test_missing_body_is_left_in_place(self):
        imap = FakeImap(raw=b"")
        self.assertEqual(self.handle(imap)[0], "left")
        self.assertEqual([c[0] for c in imap.commands], ["FETCH", "FETCH"])

    def test_write_error_leaves_the_message_and_stops(self):
        self.config["dest_dir"] = os.path.join(self.dest, "absent")
        imap = FakeImap(raw=attach(message(), "a.pdf").as_bytes())
        with self.assertRaises(OSError):
            self.handle(imap)
        self.assertNotIn("MOVE", [c[0] for c in imap.commands])

    def test_unreadable_message_goes_to_rejected(self):
        # Tout sauf une OSError : le message ne bloque pas les suivants.
        imap = FakeImap(raw=b"x")
        with mock.patch.object(pi, "process", side_effect=ValueError("x")):
            outcome, log = self.handle(imap)
        self.assertEqual(outcome, "refused")
        self.assertEqual(imap.commands[-1], ("MOVE", '"Refuse"'))
        self.assertIn("illisible (ValueError)", log)

    def test_move_without_move_expunges_this_uid_only(self):
        imap = FakeImap()
        pi.move(imap, b"7", "Importe", False)
        self.assertEqual(
            imap.commands,
            [("COPY", '"Importe"'), ("STORE", "+FLAGS.SILENT", r"(\Deleted)"), ("EXPUNGE",)],
        )

    def test_failed_copy_does_not_delete(self):
        imap = FakeImap(fetch_ok=False)
        with self.assertRaises(RuntimeError):
            pi.move(imap, b"7", "Importe", False)
        self.assertEqual([c[0] for c in imap.commands], ["COPY"])


class MailboxTest(unittest.TestCase):
    def ensure(self, imap):
        with redirect_stdout(io.StringIO()):
            pi.ensure_mailbox(imap, "Refuse")

    def test_created(self):
        imap = FakeImap()
        self.ensure(imap)
        self.assertEqual([c[0] for c in imap.commands], ["CREATE"])

    def test_already_there(self):
        imap = FakeImap(create_ok=False)
        self.ensure(imap)
        self.assertEqual([c[0] for c in imap.commands], ["CREATE", "STATUS"])

    def test_neither_created_nor_there_stops_before_any_delivery(self):
        with self.assertRaisesRegex(RuntimeError, "STATUS Refuse"):
            self.ensure(FakeImap(create_ok=False, status_ok=False))

    def test_server_delimiter(self):
        self.assertEqual(pi.server_delimiter(FakeImap(listing=b'(\\Noselect) "." ""')), ".")
        self.assertEqual(pi.server_delimiter(FakeImap(listing=None)), "/")


if __name__ == "__main__":
    unittest.main()
