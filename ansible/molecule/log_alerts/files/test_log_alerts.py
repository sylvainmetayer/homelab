"""Tests de log_alerts.py (rôle log_alerts), lancés par verify.yml du scénario.
À la main : copier ce fichier à côté de ansible/roles/log_alerts/files/log_alerts.py,
puis python3 -I -m unittest discover -s . -p 'test_*.py'.
"""

import json
import os
import tempfile
import unittest
from unittest import mock

import log_alerts

RULES = [
    {"name": "a", "title": "A", "priority": 3, "query": "qa", "window_seconds": 300, "threshold": 1, "repeat_seconds": 3600},
    {"name": "b", "title": "B", "priority": 3, "query": "qb", "window_seconds": 300, "threshold": 1, "repeat_seconds": 3600},
]


class MainStateTest(unittest.TestCase):
    def test_state_is_saved_when_a_later_rule_crashes(self):
        rows = {"qa": [{"router": "h1", "n": "5"}], "qb": [{"router": "h2"}]}  # sans n : KeyError
        with tempfile.TemporaryDirectory() as directory:
            config = os.path.join(directory, "config.json")
            with open(config, "w", encoding="utf-8") as file:
                json.dump({"rules": RULES}, file)
            env = {"LOG_ALERTS_VL_PASSWORD": "x", "LOG_ALERTS_NTFY_TOKEN": "x", "STATE_DIRECTORY": directory}
            with mock.patch.object(log_alerts, "CONFIG_FILE", config), \
                    mock.patch.dict(os.environ, env), \
                    mock.patch.object(log_alerts, "query_rows", lambda c, s, rule, now: rows[rule["query"]]), \
                    mock.patch.object(log_alerts, "publish") as publish:
                with self.assertRaises(KeyError):
                    log_alerts.main()
            publish.assert_called_once()
            with open(os.path.join(directory, "state.json"), encoding="utf-8") as file:
                self.assertEqual(list(json.load(file)), ["a|h1"])
