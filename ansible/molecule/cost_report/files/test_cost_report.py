"""Tests de cost_report.py (rôle cost_report) : réponses d'API enregistrées
ou fabriquées, aucun appel réel. Lancés par le verify du scénario, à côté
d'une copie du script ; à la main :
python3 -I -m unittest discover -s . -p 'test_*.py' dans un dossier qui
contient les deux fichiers.
"""

import datetime
import hashlib
import io
import json
import os
import tempfile
import unittest
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path
from unittest import mock

import cost_report as cr

NOW = datetime.datetime(2026, 11, 1, 7, 0)
MID_MONTH = datetime.datetime(2026, 11, 16, 0, 0)


def price(location, gross, net="0"):
    return {"location": location, "price_hourly": {"net": "0", "gross": "0"},
            "price_monthly": {"net": net, "gross": gross}}


# Forme des réponses de l'API Hetzner (champs inutiles retirés). Le serveur
# avec datacenter.location (ancienne forme), la Storage Box avec location.
HETZNER = {
    "pricing": {"pricing": {
        "currency": "EUR",
        "vat_rate": "19.00",
        "server_backup": {"percentage": "20.0000000000"},
        "volume": {"price_per_gb_month": {"net": "0.0440000000", "gross": "0.0500000000"}},
        "primary_ips": [
            {"type": "ipv4", "prices": [price("fsn1", "0.6100000000"), price("nbg1", "0.6100000000")]},
            {"type": "ipv6", "prices": [price("fsn1", "0.0000000000")]},
        ],
    }},
    "servers": [
        {"name": "pangolin", "backup_window": "22-02", "datacenter": {"location": {"name": "fsn1"}},
         "server_type": {"name": "cx22", "prices": [price("nbg1", "4.5100000000"), price("fsn1", "4.5100000000")]}},
        {"name": "flip", "backup_window": None, "location": {"name": "fsn1"},
         "server_type": {"name": "cx32", "prices": [price("fsn1", "8.0000000000")]}},
    ],
    "primary_ips": [
        {"name": "pangolin-v4", "type": "ipv4", "datacenter": {"location": {"name": "fsn1"}}},
        {"name": "pangolin-v6", "type": "ipv6", "datacenter": {"location": {"name": "fsn1"}}},
    ],
    "volumes": [{"name": "data", "size": 10, "location": {"name": "fsn1"}}],
    "storage_boxes": [
        {"name": "backups", "location": {"name": "fsn1"},
         "storage_box_type": {"name": "bx11", "prices": [price("fsn1", "3.8100000000")]}},
    ],
}

# GET /me/bill/{id} : une facture d'octobre, une de novembre, une de
# septembre (hors fenêtre, ignorée) ; mot de passe et URL jamais gardés.
OVH_BILLS = {
    "FR1": {"billId": "FR1", "date": "2026-10-01T04:12:00+02:00", "password": "x", "url": "https://example.invalid/1",
            "priceWithTax": {"currencyCode": "EUR", "value": 1.2, "text": "1.20 €"}},
    "FR2": {"billId": "FR2", "date": "2026-10-15T10:00:00+02:00", "password": "x", "url": "https://example.invalid/2",
            "priceWithTax": {"currencyCode": "EUR", "value": 11.99, "text": "11.99 €"}},
    "FR3": {"billId": "FR3", "date": "2026-11-01T03:00:00+01:00", "password": "x", "url": "https://example.invalid/3",
            "priceWithTax": {"currencyCode": "EUR", "value": 0.5, "text": "0.50 €"}},
    "FR0": {"billId": "FR0", "date": "2026-09-30T23:00:00+02:00", "password": "x", "url": "https://example.invalid/0",
            "priceWithTax": {"currencyCode": "EUR", "value": 100.0, "text": "100.00 €"}},
}
OVH_USAGE = {"period": {"from": "2026-11-01T00:00:00+01:00", "to": "2026-11-30T23:59:59+01:00"},
             "hourlyUsage": {}, "monthlyUsage": {}, "resourcesUsage": [],
             "totalPrice": {"currencyCode": "EUR", "value": 0.25, "text": "0.25 €"}}

SUBSCRIPTIONS = [
    {"name": "PikaPods", "amount": 6, "currency": "USD", "period": "monthly"},
    {"name": "kDrive", "amount": 60, "currency": "EUR", "period": "yearly"},
    {"name": "Abonnement IA", "amount": 0, "currency": "EUR", "period": "monthly"},
]


class FakeOvh:
    """Rejoue l'API OVH et note les chemins demandés."""

    def __init__(self):
        self.calls = []

    def get(self, path, params=None):
        self.calls.append((path, params))
        if path == "/me/bill":
            return list(OVH_BILLS)
        if path.startswith("/me/bill/"):
            return OVH_BILLS[path.rsplit("/", 1)[1]]
        if path.endswith("/usage/current"):
            return OVH_USAGE
        raise AssertionError(path)


class MonthsTest(unittest.TestCase):
    def test_previous_month_crosses_the_year(self):
        self.assertEqual(cr.previous_month(datetime.date(2027, 1, 1)), datetime.date(2026, 12, 1))
        self.assertEqual(cr.month_label(datetime.date(2026, 10, 1)), "octobre 2026")

    def test_elapsed_fraction(self):
        self.assertEqual(cr.elapsed_fraction(datetime.datetime(2026, 11, 1)), 0)
        self.assertAlmostEqual(cr.elapsed_fraction(MID_MONTH), 0.5)

    def test_money(self):
        self.assertEqual(cr.money(1234.5, "EUR"), "1 234,50 €")
        self.assertEqual(cr.money_total({"USD": 6, "EUR": 5.001}), "5,00 € + 6,00 USD")
        self.assertEqual(cr.money_total({}), "0,00 €")


class HetznerTest(unittest.TestCase):
    def test_items(self):
        currency, items = cr.hetzner_items(HETZNER)
        self.assertEqual(currency, "EUR")
        labels = dict(items)
        self.assertAlmostEqual(labels["pangolin (cx22)"], 4.51)
        self.assertAlmostEqual(labels["pangolin : sauvegardes"], 0.902)
        self.assertNotIn("flip : sauvegardes", labels)
        self.assertAlmostEqual(labels["flip (cx32)"], 8.0)
        self.assertAlmostEqual(labels["IP ipv4 pangolin-v4"], 0.61)
        self.assertNotIn("IP ipv6 pangolin-v6", labels)
        self.assertAlmostEqual(labels["volume data (10 Go)"], 0.5)
        self.assertAlmostEqual(labels["Storage Box backups (bx11)"], 3.81)

    def test_result_prorates_the_current_month(self):
        entry = cr.hetzner_result(HETZNER, 0.5)
        self.assertEqual(entry["status"], cr.OK)
        self.assertAlmostEqual(entry["previous"]["EUR"], 4.51 + 0.902 + 8 + 0.61 + 0.5 + 3.81)
        self.assertAlmostEqual(entry["current"]["EUR"], entry["previous"]["EUR"] / 2)

    def test_unknown_location_is_an_error(self):
        data = json.loads(json.dumps(HETZNER))
        data["servers"][1]["location"] = {"name": "hel1"}
        with self.assertRaises(cr.SourceError):
            cr.hetzner_items(data)

    def test_fetch_lists_every_resource(self):
        seen = []

        def fake_fetch(url, headers):
            seen.append((url, headers["Authorization"]))
            name = url.split("?")[0].rsplit("/", 1)[1]
            return HETZNER["pricing"] if name == "pricing" else {name: HETZNER[name]}

        with mock.patch.object(cr, "fetch_json", fake_fetch):
            data = cr.fetch_hetzner("molecule-token", "https://cloud.invalid/v1/", "https://api.invalid/v1")
        self.assertEqual(data, HETZNER)
        self.assertIn(("https://api.invalid/v1/storage_boxes?per_page=50", "Bearer molecule-token"), seen)
        self.assertIn(("https://cloud.invalid/v1/pricing", "Bearer molecule-token"), seen)


class OvhTest(unittest.TestCase):
    def test_signature_follows_the_ovh_protocol(self):
        expected = "$1$" + hashlib.sha1(b"AS+CK+GET+https://eu.api.ovh.com/1.0/me/bill++1700000000").hexdigest()
        self.assertEqual(cr.ovh_signature("AS", "CK", "GET", "https://eu.api.ovh.com/1.0/me/bill", "", 1700000000), expected)

    def test_client_signs_the_full_url(self):
        captured = {}

        def fake_fetch(url, headers):
            captured.update(url=url, headers=headers)
            return []

        client = cr.OvhClient("https://eu.api.ovh.com/1.0/", "AK", "AS", "CK", clock=lambda: 1700000000.5, fetch=fake_fetch)
        client.get("/me/bill", {"date.from": "2026-10-01"})
        self.assertEqual(captured["url"], "https://eu.api.ovh.com/1.0/me/bill?date.from=2026-10-01")
        self.assertEqual(captured["headers"]["X-Ovh-Application"], "AK")
        self.assertEqual(captured["headers"]["X-Ovh-Timestamp"], "1700000000")
        self.assertEqual(captured["headers"]["X-Ovh-Signature"],
                         cr.ovh_signature("AS", "CK", "GET", captured["url"], "", 1700000000))

    def test_fetch_keeps_only_date_and_price(self):
        fake = FakeOvh()
        data = cr.fetch_ovh(fake, "abc123", datetime.date(2026, 10, 1), NOW)
        self.assertEqual(fake.calls[0], ("/me/bill", {"date.from": "2026-10-01", "date.to": "2026-11-02"}))
        self.assertIn(("/cloud/project/abc123/usage/current", None), fake.calls)
        self.assertTrue(all(set(bill) == {"date", "priceWithTax"} for bill in data["bills"]))

    def test_fetch_without_project_reads_bills_only(self):
        fake = FakeOvh()
        data = cr.fetch_ovh(fake, "", datetime.date(2026, 10, 1), NOW)
        self.assertIsNone(data["usage"])
        self.assertFalse(any("usage" in path for path, _ in fake.calls))

    def test_result_buckets_bills_by_month(self):
        data = cr.fetch_ovh(FakeOvh(), "abc123", datetime.date(2026, 10, 1), NOW)
        entry = cr.ovh_result(data, "2026-10", "2026-11", 20)
        self.assertAlmostEqual(entry["previous"]["EUR"], 13.19)
        # Facture de novembre plus la consommation en cours, TVA ajoutée.
        self.assertAlmostEqual(entry["current"]["EUR"], 0.5 + 0.3)
        self.assertIn("2 facture(s) le mois dernier : 13,19 €", entry["lines"])


class SubscriptionsTest(unittest.TestCase):
    def test_yearly_is_spread_and_zero_is_to_fill(self):
        pika, kdrive, ai = cr.subscription_results(SUBSCRIPTIONS, 0.5)
        self.assertEqual(pika["previous"], {"USD": 6})
        self.assertEqual(pika["current"], {"USD": 3})
        self.assertAlmostEqual(kdrive["previous"]["EUR"], 5)
        self.assertEqual(kdrive["note"], "60,00 € par an, ramené au mois")
        self.assertEqual(ai["status"], cr.TO_FILL)


class ReportTest(unittest.TestCase):
    def results(self):
        return [
            cr.hetzner_result(HETZNER, 0),
            cr.result("OVH", cr.UNCONFIGURED),
            *cr.subscription_results(SUBSCRIPTIONS, 0),
        ]

    def test_report_totals_what_is_known_and_names_the_rest(self):
        title, message, priority = cr.build_report(self.results(), NOW)
        self.assertEqual(title, "Coûts du homelab : octobre 2026")
        self.assertTrue(message.startswith("Total : 23,33 € + 6,00 USD\n"))
        self.assertIn("- OVH : non configurée", message)
        self.assertIn("- Abonnement IA : à renseigner", message)
        self.assertIn("    Storage Box backups (bx11) : 3,81 €", message)
        self.assertIn("Incomplet, sans : OVH, Abonnement IA.", message)
        self.assertEqual(priority, 3)

    def test_a_failed_source_raises_the_priority(self):
        results = self.results() + [cr.result("Hetzner", cr.FAILED, note="HTTP 401")]
        _, message, priority = cr.build_report(results, NOW)
        self.assertIn("- Hetzner : en erreur : HTTP 401", message)
        self.assertEqual(priority, 4)

    def test_long_detail_is_cut_under_the_ntfy_limit(self):
        many = [cr.result(f"Abonnement {index:03d} au nom très long pour remplir", cr.TO_FILL) for index in range(200)]
        _, message, _ = cr.build_report(many, NOW)
        self.assertLessEqual(len(message.encode()), cr.MAX_MESSAGE)
        self.assertIn("ligne(s) coupée(s)", message)
        self.assertTrue(message.endswith("Mois en cours à date : 0,00 €."))

    def test_homepage_summary(self):
        summary = cr.homepage_summary(self.results(), NOW)
        self.assertEqual(summary, {
            "previous_label": "octobre 2026",
            "previous_total": "23,33 € + 6,00 USD",
            "current_total": "0,00 € + 0,00 USD",
            "missing": 2,
            "incomplete": "OVH (non configurée), Abonnement IA (à renseigner)",
            "updated": "01/11 07:00",
        })


class CollectTest(unittest.TestCase):
    CONFIG = {"hetzner_cloud_api": "https://cloud.invalid/v1", "hetzner_api": "https://api.invalid/v1",
              "ovh_endpoint": "https://ovh.invalid/1.0", "ovh_vat_percent": 20, "subscriptions": SUBSCRIPTIONS}

    def test_without_keys_every_api_source_is_unconfigured(self):
        with mock.patch.object(cr, "fetch_json", side_effect=AssertionError("aucun appel")):
            results = cr.collect(self.CONFIG, {}, NOW)
        self.assertEqual([(entry["name"], entry["status"]) for entry in results[:2]],
                         [("Hetzner", cr.UNCONFIGURED), ("OVH", cr.UNCONFIGURED)])

    def test_an_api_error_marks_its_source_only(self):
        env = {cr.HCLOUD_TOKEN: "t", **{name: "k" for name in cr.OVH_KEYS}}
        with mock.patch.object(cr, "fetch_json", side_effect=cr.SourceError("HTTP 403")):
            results = cr.collect(self.CONFIG, env, NOW)
        self.assertEqual(results[0]["status"], cr.FAILED)
        self.assertEqual(results[0]["note"], "HTTP 403")
        self.assertEqual(results[1]["status"], cr.FAILED)
        self.assertEqual(results[2]["status"], cr.OK)

    def test_an_unexpected_shape_is_an_error_not_a_crash(self):
        env = {cr.HCLOUD_TOKEN: "t"}
        with mock.patch.object(cr, "fetch_json", return_value={"unexpected": True}):
            results = cr.collect(self.CONFIG, env, NOW)
        self.assertEqual(results[0]["status"], cr.FAILED)
        self.assertIn("réponse inattendue", results[0]["note"])


class MainTest(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.TemporaryDirectory()
        self.path = Path(self.dir.name)
        config = {**CollectTest.CONFIG, "ntfy_url": "https://ntfy.invalid", "ntfy_topic": "scripts"}
        (self.path / "config.json").write_text(json.dumps(config))

    def tearDown(self):
        self.dir.cleanup()

    def run_main(self, now, env, *extra):
        out, err = io.StringIO(), io.StringIO()
        with mock.patch.dict(os.environ, env, clear=True), redirect_stdout(out), redirect_stderr(err):
            code = cr.main(["--config", str(self.path / "config.json"), "--state-dir", str(self.path), "--now", now, *extra])
        return code, out.getvalue(), err.getvalue()

    def test_publishes_once_a_month(self):
        with mock.patch.object(cr, "publish") as publish:
            self.assertEqual(self.run_main("2026-11-01T07:00", {cr.NTFY_TOKEN: "tk"})[0], 0)
            self.run_main("2026-11-02T07:00", {cr.NTFY_TOKEN: "tk"})
            self.run_main("2026-12-03T07:00", {cr.NTFY_TOKEN: "tk"})
        self.assertEqual(publish.call_count, 2)
        self.assertEqual(publish.call_args_list[0].args[3], "Coûts du homelab : octobre 2026")
        self.assertEqual(publish.call_args_list[1].args[3], "Coûts du homelab : novembre 2026")
        self.assertEqual(json.loads((self.path / "state.json").read_text()), {"published": "2026-11"})
        costs = json.loads((self.path / "costs.json").read_text())
        self.assertEqual(costs["updated"], "03/12 07:00")

    def test_without_token_nothing_is_published_nor_remembered(self):
        with mock.patch.object(cr, "publish") as publish:
            code, out, err = self.run_main("2026-11-01T07:00", {})
        self.assertEqual(code, 0)
        publish.assert_not_called()
        self.assertIn("rien n'est publié", err)
        self.assertIn("Coûts du homelab : octobre 2026", out)
        self.assertFalse((self.path / "state.json").exists())
        self.assertTrue((self.path / "costs.json").exists())

    def test_a_failed_publication_fails_the_run_and_is_retried(self):
        with mock.patch.object(cr, "publish", side_effect=OSError("https://ntfy.invalid tk")):
            code, _, err = self.run_main("2026-11-01T07:00", {cr.NTFY_TOKEN: "tk"})
        self.assertEqual(code, 1)
        self.assertNotIn("tk", err.replace("ntfy", ""))
        self.assertFalse((self.path / "state.json").exists())

    def test_a_failed_source_defers_the_report_a_few_days(self):
        env = {cr.NTFY_TOKEN: "tk", cr.HCLOUD_TOKEN: "t"}
        with mock.patch.object(cr, "publish") as publish, \
                mock.patch.object(cr, "fetch_json", side_effect=cr.SourceError("HTTP 503")):
            code, _, err = self.run_main("2026-11-01T07:00", env)
            self.assertEqual(code, 0)
            self.assertIn("rapport reporté", err)
            publish.assert_not_called()
            self.assertFalse((self.path / "state.json").exists())
            # Passé le jour de grâce, le rapport part quand même, partiel.
            self.run_main("2026-11-04T07:00", env)
        self.assertEqual(publish.call_count, 1)
        self.assertEqual(publish.call_args.args[5], 4)
        self.assertEqual(json.loads((self.path / "state.json").read_text()), {"published": "2026-10"})

    def test_invalid_subscription_is_refused(self):
        config = json.loads((self.path / "config.json").read_text())
        config["subscriptions"] = [{"name": "x", "amount": 1, "currency": "EUR", "period": "weekly"}]
        (self.path / "config.json").write_text(json.dumps(config))
        with self.assertRaises(ValueError):
            self.run_main("2026-11-01T07:00", {})


if __name__ == "__main__":
    unittest.main()
