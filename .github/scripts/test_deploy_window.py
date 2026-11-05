"""Tests of deploy_window.py and of the crons that reopen the window
(Lint workflow: python -I -m unittest discover -s .github/scripts -p 'test_*.py')."""

import unittest
from datetime import datetime, timedelta, timezone
from pathlib import Path

import yaml

from deploy_window import PARIS, is_open

WORKFLOW = Path(__file__).parent.parent / "workflows" / "deploy-docker-app.yaml"


def utc(*args):
    return datetime(*args, tzinfo=timezone.utc)


class WindowTest(unittest.TestCase):
    def test_winter_bounds(self):  # CET = UTC+1
        self.assertFalse(is_open(utc(2026, 1, 15, 6, 59), "push"))  # 07:59
        self.assertTrue(is_open(utc(2026, 1, 15, 7, 0), "push"))  # 08:00
        self.assertTrue(is_open(utc(2026, 1, 15, 17, 59), "push"))  # 18:59
        self.assertFalse(is_open(utc(2026, 1, 15, 18, 0), "push"))  # 19:00

    def test_summer_bounds(self):  # CEST = UTC+2
        self.assertFalse(is_open(utc(2026, 7, 15, 5, 59), "push"))  # 07:59
        self.assertTrue(is_open(utc(2026, 7, 15, 6, 0), "push"))  # 08:00
        self.assertTrue(is_open(utc(2026, 7, 15, 16, 59), "push"))  # 18:59
        self.assertFalse(is_open(utc(2026, 7, 15, 17, 0), "push"))  # 19:00

    def test_dst_change_days(self):
        # 2026-03-29: CET -> CEST at 01:00 UTC; 2026-10-25: CEST -> CET.
        self.assertFalse(is_open(utc(2026, 3, 29, 5, 59), "push"))
        self.assertTrue(is_open(utc(2026, 3, 29, 6, 0), "push"))
        self.assertFalse(is_open(utc(2026, 10, 25, 6, 59), "push"))
        self.assertTrue(is_open(utc(2026, 10, 25, 7, 0), "push"))

    def test_weekend_is_like_a_weekday(self):
        self.assertFalse(is_open(utc(2026, 11, 7, 20, 0), "push"))  # Saturday 21:00
        self.assertTrue(is_open(utc(2026, 11, 8, 10, 0), "push"))  # Sunday 11:00

    def test_dispatch_is_always_open(self):
        self.assertTrue(is_open(utc(2026, 1, 15, 2, 0), "workflow_dispatch"))
        self.assertFalse(is_open(utc(2026, 1, 15, 2, 0), "schedule"))


class CronTest(unittest.TestCase):
    """Nothing is lost only if, every day, a scheduled run lands inside the
    window: it deploys what the night held back."""

    @classmethod
    def setUpClass(cls):
        doc = yaml.safe_load(WORKFLOW.read_text())
        cls.crons = [s["cron"] for s in doc[True]["schedule"]]  # YAML reads `on` as True

    def slots(self):
        for cron in self.crons:
            minute, hours, *rest = cron.split()
            self.assertEqual(rest, ["*", "*", "*"], "daily crons only")
            for h in hours.split(","):
                yield int(h), int(minute)

    def test_every_day_has_an_open_slot(self):
        day = utc(2026, 1, 1)
        while day.year < 2032:
            opened = [h for h, m in self.slots() if is_open(day.replace(hour=h, minute=m), "schedule")]
            self.assertTrue(opened, f"no cron lands in the window on {day:%Y-%m-%d}")
            day += timedelta(days=1)

    def test_a_cron_hits_the_opening_summer_and_winter(self):
        for d in (utc(2026, 1, 15), utc(2026, 7, 15)):
            hours = [d.replace(hour=h, minute=m).astimezone(PARIS).hour for h, m in self.slots()]
            self.assertIn(8, hours)


if __name__ == "__main__":
    unittest.main()
