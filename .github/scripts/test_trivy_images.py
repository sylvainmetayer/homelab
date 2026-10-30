"""Tests of trivy_images.py (Lint workflow:
python -I -m unittest discover -s .github/scripts -p 'test_*.py')."""
import tempfile
import unittest
from pathlib import Path

import trivy_images as ti

D1 = "sha256:" + "1" * 64
D2 = "sha256:" + "2" * 64
D3 = "sha256:" + "3" * 64
D4 = "sha256:" + "4" * 64


def tree(files):
    tmp = tempfile.TemporaryDirectory()
    root = Path(tmp.name)
    for path, text in files.items():
        target = root / path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(text)
    return tmp, root


def scan(files):
    tmp, root = tree(files)
    with tmp:
        return ti.images(root)


class Extraction(unittest.TestCase):
    def test_compose_lines_quoted_or_not(self):
        entries = scan({
            "ansible/roles/a/templates/compose.yaml": (
                "services:\n"
                f"  app:\n    image: ghcr.io/org/app:1.0@{D1}\n"
                f"  db:\n    image: \"postgres:18@{D2}\"  # comment\n"
                f"  cache:\n    image: 'docker.io/valkey/valkey:9@{D3}'\n"
            ),
        })
        self.assertEqual(
            entries,
            [
                {"ref": f"ghcr.io/org/app:1.0@{D1}", "name": "org-app"},
                {"ref": f"postgres:18@{D2}", "name": "postgres"},
                {"ref": f"docker.io/valkey/valkey:9@{D3}", "name": "valkey-valkey"},
            ],
        )

    def test_jinja_and_comments_are_skipped(self):
        entries = scan({
            "ansible/roles/a/templates/compose.yaml.j2": (
                "services:\n"
                "  app:\n    image: \"{{ app_image }}\"\n"
                f"    # image: ghcr.io/org/old:1@{D1}\n"
                "  other:\n    image: {{ other_image }}\n"
                "{% if x %}\n    image: nginx:1.0\n{% endif %}\n"
            ),
        })
        self.assertEqual(entries, [{"ref": "nginx:1.0", "name": "nginx"}])

    def test_defaults_image_variables(self):
        entries = scan({
            "ansible/roles/a/defaults/main.yml": (
                f'a_image: "ghcr.io/org/a:1@{D1}"\n'
                'a_image_release: "ghcr.io/org/b:1.4.0"\n'
                'a_image: "{{ a_image_release }}"\n'
                'a_image_pull_policy: missing\n'
                f'a_other: "ghcr.io/org/c:1@{D2}"\n'
            ),
        })
        self.assertEqual(
            [entry["ref"] for entry in entries],
            [f"ghcr.io/org/a:1@{D1}", "ghcr.io/org/b:1.4.0"],
        )

    def test_compose_directory_is_read(self):
        entries = scan({"compose/x/compose.yaml": f"    image: ghcr.io/org/x:1@{D1}\n"})
        self.assertEqual(entries, [{"ref": f"ghcr.io/org/x:1@{D1}", "name": "org-x"}])


class Names(unittest.TestCase):
    def test_one_digest_is_scanned_once(self):
        entries = scan({
            "ansible/roles/a/templates/compose.yaml": f"    image: postgres:18@{D1}\n",
            "ansible/roles/b/templates/compose.yaml": f"    image: docker.io/library/postgres:18.6@{D1}\n",
        })
        self.assertEqual(len(entries), 1)
        self.assertEqual(entries[0]["name"], "postgres")

    def test_repository_pinned_twice_gets_its_role(self):
        entries = scan({
            "ansible/roles/a/templates/compose.yaml": f"    image: redis:7.4-alpine@{D1}\n",
            "ansible/roles/b/templates/compose.yaml": f"    image: redis:8@{D2}\n",
        })
        self.assertEqual(sorted(e["name"] for e in entries), ["redis-a", "redis-b"])

    def test_bump_keeps_the_category(self):
        # Renovate bumps one of two pins: neither category moves.
        before = scan({
            "ansible/roles/a/templates/compose.yaml": f"    image: docker.io/traefik:v3@{D1}\n",
            "ansible/roles/b/templates/compose.yaml": f"    image: docker.io/traefik:v3@{D2}\n",
        })
        after = scan({
            "ansible/roles/a/templates/compose.yaml": f"    image: docker.io/traefik:v3.1@{D3}\n",
            "ansible/roles/b/templates/compose.yaml": f"    image: docker.io/traefik:v3@{D2}\n",
        })
        self.assertEqual([e["name"] for e in before], ["traefik-a", "traefik-b"])
        self.assertEqual([e["name"] for e in after], ["traefik-a", "traefik-b"])

    def test_role_pinning_twice_gets_the_service_or_variable(self):
        entries = scan({
            "ansible/roles/a/templates/compose.yaml": (
                "services:\n"
                f"  web:\n    image: nginx:1@{D1}\n"
                f"  proxy:\n    image: nginx:2@{D2}\n"
            ),
            "ansible/roles/a/defaults/main.yml": f'a_image: "ghcr.io/org/x:1@{D3}"\na_image_smart: "ghcr.io/org/x:2@{D4}"\n',
        })
        self.assertEqual(
            sorted(e["name"] for e in entries),
            ["nginx-a-proxy", "nginx-a-web", "org-x-a-image", "org-x-a-image_smart"],
        )

    def test_playbook_role_vars_are_read(self):
        entries = scan({
            "ansible/flip.yml": (
                "    - role: a\n      vars:\n"
                '        a_image: "ghcr.io/org/a:pr-1"\n'
                '        a_image_main: "{{ a_image_main }}"\n'
            ),
            "secrets/ansible.sops.yaml": 'a_image: "ghcr.io/org/secret:1"\n',
        })
        self.assertEqual(entries, [{"ref": "ghcr.io/org/a:pr-1", "name": "org-a"}])

    def test_registry_with_port_is_dropped(self):
        self.assertEqual(ti.split_ref(f"registry:5000/org/app:1@{D1}"), ("org-app", "1", D1))
        self.assertEqual(ti.split_ref("org/app"), ("org-app", "", ""))


class RealTree(unittest.TestCase):
    def test_names_are_unique_and_every_role_image_is_found(self):
        entries = ti.images()
        names = [entry["name"] for entry in entries]
        self.assertEqual(len(names), len(set(names)))
        refs = {entry["ref"].split("@")[0].rsplit(":", 1)[0] for entry in entries}
        for expected in ("ghcr.io/immich-app/immich-server", "docker.io/fosrl/pangolin",
                         "docker.io/henrygd/beszel-agent", "ghcr.io/sylvainmetayer/planning-equipes",
                         "ghcr.io/sylvainmetayer/planning-equipes-keycloak"):
            with self.subTest(image=expected):
                self.assertIn(expected, refs)


if __name__ == "__main__":
    unittest.main()
