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
        """Conteneur, port et chemin de chaque sonde sont ceux de website_*.tf (hc_path, « / » sans lui)."""
        drill = load()
        targets = {}
        for tf in WEBSITES.glob("website_*.tf"):
            ip = None
            for line in tf.read_text().splitlines():
                if m := re.search(r'\bip\s*=\s*"([^"]+)"', line):
                    ip = m.group(1)
                    targets[ip] = [None, "/"]
                elif ip and (m := re.search(r"\bport\s*=\s*(\d+)", line)):
                    targets[ip][0] = int(m.group(1))
                elif ip and (m := re.search(r'\bhc_path\s*=\s*"([^"]+)"', line)):
                    targets[ip][1] = m.group(1)
        for name, (container, port, path, _host) in {**drill.HTTP, **drill.STATELESS}.items():
            self.assertIn(container, targets, f"{name} : conteneur {container} absent des website_*.tf")
            self.assertEqual(targets[container][0], port, f"{name} : port")
            # Grocy : « / » voulu, le /robots.txt de Pangolin ne crée pas grocy.db.
            # Nextcloud : /status.php dit « installed », /login ne le dit pas.
            if name not in ("grocy", "nextcloud"):
                self.assertEqual(targets[container][1], path, f"{name} : chemin")

if __name__ == "__main__":
    unittest.main()
