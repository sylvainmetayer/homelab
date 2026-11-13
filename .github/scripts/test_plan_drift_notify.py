import importlib.util
import unittest
from pathlib import Path

spec = importlib.util.spec_from_file_location("plan_drift_notify", Path(__file__).with_name("plan_drift_notify.py"))
notify = importlib.util.module_from_spec(spec)
spec.loader.exec_module(notify)

SUMMARY = "Plan: 2 to add, 1 to change, 0 to destroy."


class DecideTest(unittest.TestCase):
    def test_empty_plan_is_up_and_silent(self):
        self.assertEqual(notify.decide("success", "0", ""), ("up", "Aucune dérive", None))

    def test_non_empty_plan_alerts_with_counts_only(self):
        status, msg, payload = notify.decide("success", "2", SUMMARY)
        self.assertEqual(status, "up")
        self.assertIn("2 à ajouter, 1 à modifier, 0 à détruire", msg)
        self.assertEqual(payload["topic"], "github")

    def test_unreadable_summary_never_echoes_its_text(self):
        _, msg, _ = notify.decide("success", "2", "Plan: secret-value")
        self.assertNotIn("secret-value", msg)

    def test_failures_are_down_and_alert(self):
        for result, rc in (("failure", ""), ("cancelled", ""), ("success", "1"), ("success", "")):
            status, _, payload = notify.decide(result, rc, "")
            self.assertEqual(status, "down", (result, rc))
            self.assertIsNotNone(payload)


if __name__ == "__main__":
    unittest.main()
