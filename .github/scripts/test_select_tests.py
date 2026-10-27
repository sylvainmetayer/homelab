"""Tests of select_tests.py (Lint workflow:
python -I -m unittest discover -s .github/scripts -p 'test_*.py')."""
import contextlib
import io
import json
import tempfile
import unittest
from pathlib import Path

import select_tests as st

REAL = st.Tree()


def write(root, path, text=""):
    target = root / path
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(text)


def fake_tree(files):
    """A Tree over a throwaway repository holding `files` ({path: text})."""
    tmp = tempfile.TemporaryDirectory()
    root = Path(tmp.name)
    for path, text in files.items():
        write(root, path, text)
    (root / "ansible" / "roles").mkdir(parents=True, exist_ok=True)
    return tmp, st.Tree(root)


def selected(changed, tree=REAL):
    scenarios, modules, _ = st.select(changed, tree)
    return sorted(scenarios), sorted(modules)



def scenario(name, converge):
    return {
        f"ansible/molecule/{name}/molecule.yml": f"scenario:\n  name: {name}\n",
        f"ansible/molecule/{name}/converge.yml": converge,
    }


class Globs(unittest.TestCase):
    def test_star_stays_in_one_segment(self):
        self.assertTrue(st.matches("ansible/flip.yml", ["ansible/*"]))
        self.assertFalse(st.matches("ansible/roles/x/tasks/main.yml", ["ansible/*"]))

    def test_double_star_crosses_directories(self):
        self.assertTrue(st.matches("ansible/roles/x/tasks/main.yml", ["ansible/roles/x/**"]))
        self.assertTrue(st.matches("docs/runbooks/README.md", ["**/*.md"]))
        self.assertTrue(st.matches("AGENTS.md", ["**/*.md"]))


class Roles(unittest.TestCase):
    def test_role_dependencies_reach_the_scenario(self):
        files = {
            **scenario("app", "- hosts: all\n  roles:\n    - role: app\n"),
            "ansible/roles/app/meta/main.yml": "dependencies:\n  - role: storage\n",
            "ansible/roles/app/tasks/main.yml": (
                "- ansible.builtin.include_role:\n    name: backup\n    tasks_from: app.yml\n"
            ),
            "ansible/roles/storage/tasks/main.yml": "",
            "ansible/roles/backup/tasks/main.yml": "- ansible.builtin.import_role:\n    name: base\n",
            "ansible/roles/base/tasks/main.yml": "",
            "ansible/roles/other/tasks/main.yml": "",
        }
        tmp, tree = fake_tree(files)
        with tmp:
            for role in ("app", "storage", "backup", "base"):
                self.assertEqual(selected([f"ansible/roles/{role}/tasks/main.yml"], tree), (["app"], []), role)
            self.assertEqual(selected(["ansible/roles/other/tasks/main.yml"], tree), ([], []))

    def test_role_applied_by_a_prepare_or_verify(self):
        # decommission_app's prepare deploys wiki and rss to remove them.
        self.assertIn("decommission_app", selected(["ansible/roles/wiki/templates/compose.yaml"])[0])
        # jellyfin's verify includes a role: include_role counts anywhere.
        tmp, tree = fake_tree({
            **scenario("a", "- hosts: all\n  tasks: []\n"),
            "ansible/molecule/a/verify.yml": "- hosts: all\n  tasks:\n    - ansible.builtin.include_role:\n        name: r\n",
            "ansible/roles/r/tasks/main.yml": "",
        })
        with tmp:
            self.assertEqual(selected(["ansible/roles/r/tasks/main.yml"], tree), (["a"], []))

    def test_deleted_role_still_applied_selects_what_applies_it(self):
        # The change deletes storage (gone from the tree) while app depends on it.
        tmp, tree = fake_tree({
            **scenario("app", "- hosts: all\n  roles:\n    - name: app\n"),
            "ansible/roles/app/meta/main.yml": "dependencies:\n  - role: storage\n",
        })
        with tmp:
            self.assertEqual(selected(["ansible/roles/storage/tasks/main.yml"], tree), (["app"], []))
            self.assertEqual(selected(["ansible/roles/app/tasks/main.yml"], tree), (["app"], []))

    def test_role_without_scenario_selects_nothing(self):
        tmp, tree = fake_tree({"ansible/roles/lonely/tasks/main.yml": ""})
        with tmp:
            self.assertEqual(selected(["ansible/roles/lonely/tasks/main.yml"], tree), ([], []))

    def test_borgmatic_reaches_every_app_including_it(self):
        scenarios = selected(["ansible/roles/borgmatic/templates/app.yaml.j2"])[0]
        for app in ("borgmatic", "karakeep", "flip_planning", "pangolin", "nginx_demo"):
            self.assertIn(app, scenarios)
        self.assertNotIn("security", scenarios)


class Scenarios(unittest.TestCase):
    def test_scenario_importing_another_scenario_depends_on_it(self):
        scenarios = selected(["ansible/molecule/security/tasks/verify_security.yml"])[0]
        for name in ("security", "security_flip", "security_pi", "security_lxc", "security_docker", "nat_gateway"):
            self.assertIn(name, scenarios)
        self.assertNotIn("karakeep", scenarios)

    def test_shared_prepare_named_in_molecule_yml(self):
        # nginx_demo's molecule.yml takes nas_storage's prepare.
        self.assertEqual(selected(["ansible/molecule/nas_storage/prepare.yml"])[0], ["nas_storage", "nginx_demo"])

    def test_deleted_file_still_read_selects_its_reader(self):
        tmp, tree = fake_tree(scenario("a", "- hosts: all\n  tasks:\n    - ansible.builtin.include_tasks: ../../tasks/gone.yml\n"))
        with tmp:
            self.assertEqual(selected(["ansible/tasks/gone.yml"], tree), (["a"], []))

    def test_own_scenario_only(self):
        self.assertEqual(selected(["ansible/molecule/wiki/verify.yml"]), (["wiki"], []))

    def test_shared_files_run_every_scenario(self):
        for path in ("ansible/molecule/_shared/Dockerfile", ".config/molecule/config.yml",
                     "ansible/group_vars/all/variables.yml", "ansible/requirements.yml", "uv.lock"):
            scenarios, _ = selected([path])
            self.assertEqual(scenarios, REAL.scenarios, path)


class HostVarsAndPlaybooks(unittest.TestCase):
    def test_host_vars_select_the_scenarios_loading_them(self):
        scenarios, _ = selected(["ansible/host_vars/pi/variables.yaml"])
        self.assertEqual(scenarios, ["beszel_agent", "host_tuning", "immich", "security_pi"])

    def test_any_file_of_the_host_directory_counts(self):
        tmp, tree = fake_tree(scenario("a", "- hosts: all\n  vars_files:\n    - ../../host_vars/h/variables.yaml\n"))
        with tmp:
            self.assertEqual(selected(["ansible/host_vars/h/other.yml"], tree), (["a"], []))

    def test_host_playbook_selects_its_host_scenarios(self):
        scenarios, _ = selected(["ansible/nas.yml"])
        self.assertEqual(scenarios, ["jellyfin", "nas"])
        self.assertIn("flip_planning", selected(["ansible/flip.yml"])[0])

    def test_hostless_playbook_selects_the_scenarios_of_its_roles(self):
        self.assertEqual(selected(["ansible/00-setup.yaml"])[0], ["ssh_login_notify"])

    def test_unknown_playbook_selects_everything(self):
        scenarios, modules = selected(["ansible/new-host.yml"])
        self.assertEqual((scenarios, modules), (REAL.scenarios, REAL.modules))

    def test_playbook_map_is_current(self):
        for playbook, host in st.PLAYBOOK_HOSTS.items():
            self.assertTrue((st.ROOT / playbook).is_file(), playbook)
            if host is not None:
                self.assertTrue((st.ROOT / "ansible" / "host_vars" / host).is_dir(), host)


class Tofu(unittest.TestCase):
    def test_module_alone(self):
        self.assertEqual(selected(["tofu/keepass_backup/main.tf"]), ([], ["tofu/keepass_backup"]))

    def test_files_read_by_another_module_tests(self):
        # tofu/github's tests read the workflows, tofu/pangolin the host_vars.
        self.assertIn("tofu/github", selected([".github/workflows/lint.yaml"])[1])
        self.assertIn("tofu/pangolin", selected(["ansible/host_vars/flip/variables.yaml"])[1])
        self.assertIn("tofu/pangolin_config", selected([".github/restore-test/apps.json"])[1])
        self.assertIn("tofu/s3_state", selected(["tofu/dns/backend.tf"])[1])

    def test_compose_listed_in_path_bypass_images(self):
        self.assertEqual(selected(["ansible/roles/trek/templates/compose.yaml"]),
                         (["trek"], ["tofu/pangolin_config"]))

    def test_interpolated_segment_and_fileset(self):
        tmp, tree = fake_tree({
            "tofu/m/tests/m.tftest.hcl": (
                'x = file("${path.module}/../../ansible/${playbook}")\n'
                'y = fileset("${path.module}/..", "*/backend.tf")\n'
                'z = file("${path.module}/../../${pin.compose}")\n'
            ),
        })
        with tmp:
            self.assertEqual(selected(["ansible/flip.yml"], tree)[1], ["tofu/m"])
            self.assertEqual(selected(["tofu/other/backend.tf"], tree)[1], ["tofu/m"])
            # Neither a whole-path interpolation nor fileset's base directory
            # makes every file a dependency.
            self.assertEqual(selected(["tofu/other/main.tf"], tree), ([], []))
            self.assertEqual(selected(["ansible/roles/r/tasks/main.yml"], tree), ([], []))

    def test_disabled_module_is_not_tested(self):
        self.assertNotIn("tofu/keycloak_demo_planning_kc", REAL.modules)
        self.assertEqual(selected(["tofu/keycloak_demo_planning_kc/main.tf"]), ([], []))

    def test_mise_toml_runs_every_module(self):
        self.assertEqual(selected(["mise.toml"]), ([], REAL.modules))


class Fallbacks(unittest.TestCase):
    def test_docs_select_nothing(self):
        self.assertEqual(selected(["docs/architecture.md", "AGENTS.md", "ansible/roles/trek/README.md"]), ([], []))

    def test_doc_read_by_a_test_still_selects_it(self):
        tmp, tree = fake_tree({"tofu/m/tests/m.tftest.hcl": 'x = file("${path.module}/../../docs/apps.md")\n'})
        with tmp:
            self.assertEqual(selected(["docs/apps.md"], tree), ([], ["tofu/m"]))

    def test_ci_only_files_select_nothing(self):
        for path in (".github/scripts/restore_test.py", "renovate.json", ".hadolint.yaml", ".gitleaks.toml"):
            self.assertEqual(selected([path]), ([], []), path)

    def test_workflow_and_script_select_everything(self):
        for path in (".github/workflows/test.yaml", ".github/scripts/select_tests.py"):
            self.assertEqual(selected([path]), (REAL.scenarios, REAL.modules), path)

    def test_unclassified_file_selects_everything(self):
        self.assertEqual(selected(["Makefile"]), (REAL.scenarios, REAL.modules))
        self.assertEqual(selected(["ansible/new_dir/thing.cfg"]), (REAL.scenarios, REAL.modules))

    def test_nothing_changed(self):
        self.assertEqual(selected([]), ([], []))


class History(unittest.TestCase):
    """Merged PRs of October 2026, with the files they changed."""

    def test_app_image_bump(self):
        # #873 meilisearch 1.56.0, #866 postgres 18.6, #865 promptoramix digest.
        self.assertEqual(selected(["ansible/roles/karakeep/templates/compose.yaml"]),
                         (["karakeep"], ["tofu/pangolin_config"]))
        self.assertEqual(selected(["ansible/roles/nginx_demo/templates/compose.yaml"]), (["nginx_demo"], []))
        self.assertEqual(selected(["ansible/roles/promptoramix/templates/compose.yaml"]),
                         (["promptoramix"], ["tofu/github"]))

    def test_tofu_change(self):
        # #875 pangolin_config, #843 OVH provider lock of keepass_backup.
        self.assertEqual(selected(["AGENTS.md", "tofu/pangolin_config/private_resources.tf",
                                   "tofu/pangolin_config/tests/invariants.tftest.hcl"]),
                         ([], ["tofu/pangolin_config"]))
        self.assertEqual(selected(["tofu/keepass_backup/.terraform.lock.hcl"]), ([], ["tofu/keepass_backup"]))

    def test_role_with_docs(self):
        # #876 Jellyfin: role, its scenario and docs.
        self.assertEqual(selected([
            "ansible/molecule/jellyfin/verify.yml", "ansible/roles/jellyfin/defaults/main.yml",
            "ansible/roles/jellyfin/templates/compose.yaml", "ansible/roles/jellyfin/templates/traefik.yml",
            "docs/apps.md", "docs/architecture.md", "docs/media.md",
        ]), (["jellyfin", "nas"], ["tofu/pangolin_config"]))

    def test_molecule_image(self):
        # #790 debian:trixie digest of the Molecule image.
        self.assertEqual(selected(["ansible/molecule/_shared/Dockerfile"]), (REAL.scenarios, []))

    def test_docs_only(self):
        # #834 docs: s'approprier le dépôt.
        self.assertEqual(selected(["README.md", "docs/architecture.md", "docs/runbooks/README.md"]), ([], []))


class Main(unittest.TestCase):
    def run_main(self, argv, stdin=""):
        out, err = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            st.main(argv, io.StringIO(stdin))
        return json.loads(out.getvalue()), err.getvalue()

    def test_all(self):
        result, _ = self.run_main(["--all"])
        self.assertEqual(result, {"scenarios": REAL.scenarios, "modules": REAL.modules})
        self.assertGreater(len(result["scenarios"]), 30)

    def test_changed_files_from_stdin_with_reasons(self):
        result, err = self.run_main([], "ansible/roles/wiki/tasks/main.yml\n\n")
        self.assertEqual(result["modules"], [])
        self.assertIn("wiki", result["scenarios"])
        self.assertIn("::notice::ansible/roles/wiki/tasks/main.yml -> scenarios", err)


if __name__ == "__main__":
    unittest.main()
