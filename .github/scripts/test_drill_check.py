"""drill-check.py (rôle docker_drill) couvre chaque appli de la VM docker."""
import importlib.util
import json
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "ansible" / "roles" / "docker_drill" / "files" / "drill-check.py"
APPS = ROOT / ".github" / "restore-test" / "apps.json"
WEBSITES = ROOT / "tofu" / "pangolin_config"


def load():
    spec = importlib.util.spec_from_file_location("drill_check", SCRIPT)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class DrillCheck(unittest.TestCase):
    def test_http_table_covers_every_docker_backup(self):
        drill = load()
        repos = {v["repo"] for v in json.loads(APPS.read_text()).values() if v["host"] == "docker"}
        # Un dépôt ajouté à apps.json sans sonde ici ferait tomber le contrôle.
        self.assertEqual(set(drill.HTTP), repos - set(drill.EXCLUDED))
        self.assertFalse(set(drill.STATELESS) & repos)

    def test_probes_match_the_pangolin_targets(self):
        """Conteneur, port et chemin de chaque sonde sont ceux de website_*.tf (hc_path, sauf nextcloud)."""
        drill = load()
        targets = {}
        for tf in WEBSITES.glob("website_*.tf"):
            text = tf.read_text()
            ip, port = re.search(r'\bip\s*=\s*"([^"]+)"', text), re.search(r"\bport\s*=\s*(\d+)", text)
            if ip and port:
                targets[ip.group(1)] = int(port.group(1))
        for name, (container, port, _path, _host) in {**drill.HTTP, **drill.STATELESS}.items():
            self.assertIn(container, targets, f"{name} : conteneur {container} absent des website_*.tf")
            self.assertEqual(targets[container], port, f"{name} : port")


if __name__ == "__main__":
    unittest.main()
