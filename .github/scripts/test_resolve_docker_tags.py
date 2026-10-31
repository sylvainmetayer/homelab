"""Tests of resolve_docker_tags.py (Lint workflow:
python -I -m unittest discover -s .github/scripts -p 'test_*.py')."""
import contextlib
import copy
import io
import json
import subprocess
import sys
import tempfile
import unittest
from unittest import mock
from pathlib import Path

import resolve_docker_tags as rdt

SCRIPT = Path(rdt.__file__)
# Same list as the resolve_docker_tags.py call in .github/workflows/deploy-docker-app.yaml.
DEPLOYED_PLAYBOOKS = ["ansible/docker.yml", "ansible/pi.yml", "ansible/pangolin.yaml", "ansible/flip.yml"]


def write_meta(roles_dir, role, deps, ext="yml"):
    meta = roles_dir / role / "meta"
    meta.mkdir(parents=True)
    (meta / f"main.{ext}").write_text("dependencies:\n" + "".join(f"  - role: {d}\n" for d in deps))


class AddDependents(unittest.TestCase):
    def test_reads_both_meta_extensions(self):
        with tempfile.TemporaryDirectory() as tmp:
            roles_dir = Path(tmp)
            write_meta(roles_dir, "app_yml", ["shared"])
            write_meta(roles_dir, "app_yaml", ["shared"], ext="yaml")
            roles, pulled_by = rdt.add_dependents({"shared"}, roles_dir)
        self.assertEqual(pulled_by["shared"], {"app_yml", "app_yaml"})
        self.assertEqual(roles, {"shared", "app_yml", "app_yaml"})

    def test_main_yml_wins_over_main_yaml(self):
        # Ansible reads only the first of main.yml, main.yaml: a stale
        # main.yaml beside main.yml declares nothing.
        with tempfile.TemporaryDirectory() as tmp:
            roles_dir = Path(tmp)
            write_meta(roles_dir, "app", ["shared"])
            (roles_dir / "app" / "meta" / "main.yaml").write_text("dependencies:\n  - role: stale\n")
            _, pulled_by = rdt.add_dependents({"shared", "stale"}, roles_dir)
        self.assertEqual(pulled_by, {"shared": {"app"}, "stale": set()})

    def test_transitive(self):
        with tempfile.TemporaryDirectory() as tmp:
            roles_dir = Path(tmp)
            write_meta(roles_dir, "mid", ["base"])
            write_meta(roles_dir, "top", ["mid"], ext="yaml")
            _, pulled_by = rdt.add_dependents({"base"}, roles_dir)
        self.assertEqual(pulled_by["base"], {"mid", "top"})


class UnreferencedRoles(unittest.TestCase):
    def test_dependency_of_a_never_role_is_reported(self):
        # Its only dependent is registered with tags [decommission, never].
        self.assertEqual(rdt.unreferenced_roles({"dep": {"gone"}}, {"gone"}, set()), {"dep"})

    def test_dependency_of_a_deployed_role_is_not_reported(self):
        self.assertEqual(rdt.unreferenced_roles({"dep": {"app"}}, {"app"}, {"app"}), set())

    def test_never_role_itself_is_not_reported(self):
        # decommission_app gets the "tagged never" notice instead.
        self.assertEqual(rdt.unreferenced_roles({"gone": set()}, {"gone"}, set()), set())

    def test_unknown_role_is_reported(self):
        self.assertEqual(rdt.unreferenced_roles({"ghost": set()}, set(), set()), {"ghost"})


class ResolveTags(unittest.TestCase):
    def test_never_tags_deploy_nothing(self):
        role_tags = {"gone": ["decommission", "never"], "app": ["app_tag", "app"]}
        _, resolved = rdt.resolve_tags(role_tags, {"gone"})
        self.assertEqual(resolved, set())
        _, resolved = rdt.resolve_tags(role_tags, {"gone", "app"})
        self.assertEqual(resolved, {"app_tag"})


def flip_playbook():
    with open(SCRIPT.parents[2] / "ansible" / "flip.yml") as f:
        return rdt.yaml.safe_load(f)


def entry_of(playbook, tag):
    return next(e for e in playbook[0]["roles"] if isinstance(e, dict) and tag in rdt.entry_tags(e))


class ChangedEntryTags(unittest.TestCase):
    def test_unchanged_deploys_nothing(self):
        self.assertEqual(rdt.changed_entry_tags(flip_playbook(), flip_playbook()), set())

    def test_vars_of_one_instance_deploy_that_instance_only(self):
        # flip_planning is applied three times: a change to the demo's vars
        # must deploy the demo, not the production.
        new = flip_playbook()
        entry_of(new, "demo_planning")["vars"]["flip_planning_sentry_environment"] = "demo2"
        self.assertEqual(rdt.changed_entry_tags(flip_playbook(), new), {"demo_planning"})

    def test_added_entry_deploys_its_tags(self):
        new = flip_playbook()
        new[0]["roles"].append({"role": "newapp", "tags": "newapp,app"})
        self.assertEqual(rdt.changed_entry_tags(flip_playbook(), new), {"newapp"})

    def test_tag_shared_with_other_entries_is_dropped(self):
        # beszel_agent,monitoring: monitoring would deploy log_agent,
        # mem_report and update_notify too.
        new = flip_playbook()
        entry_of(new, "beszel_agent")["vars"]["beszel_agent_hub_url"] = "https://x"
        self.assertEqual(rdt.changed_entry_tags(flip_playbook(), new), {"beszel_agent"})

    def test_duplicated_entry_deploys_its_tags(self):
        new = flip_playbook()
        new[0]["roles"].append(copy.deepcopy(entry_of(new, "promptoramix")))
        self.assertEqual(rdt.changed_entry_tags(flip_playbook(), new), {"promptoramix"})

    def test_removed_entry_deploys_nothing(self):
        new = flip_playbook()
        new[0]["roles"].remove(entry_of(new, "promptoramix"))
        self.assertEqual(rdt.changed_entry_tags(flip_playbook(), new), set())

    def test_generic_only_entry_deploys_its_generic_tag(self):
        new = flip_playbook()
        docker = next(e for e in new[0]["roles"] if e.get("role") == "geerlingguy.docker")
        docker["become"] = False
        self.assertEqual(rdt.changed_entry_tags(flip_playbook(), new), {"setup"})

    def test_never_entry_deploys_nothing(self):
        new = flip_playbook()
        entry_of(new, "decommission")["vars"] = {"x": 1}
        self.assertEqual(rdt.changed_entry_tags(flip_playbook(), new), set())

    def test_untagged_entry_is_the_whole_playbook(self):
        new = flip_playbook()
        new[0]["roles"].append({"role": "untagged"})
        self.assertIsNone(rdt.changed_entry_tags(flip_playbook(), new))
        new = flip_playbook()
        new[0]["roles"].append("bare_role")
        self.assertIsNone(rdt.changed_entry_tags(flip_playbook(), new))

    def test_pre_tasks_change_is_the_whole_playbook(self):
        new = flip_playbook()
        new[0]["pre_tasks"].append({"name": "x", "ansible.builtin.debug": {"msg": "x"}})
        self.assertIsNone(rdt.changed_entry_tags(flip_playbook(), new))

    def test_added_play_is_the_whole_playbook(self):
        new = flip_playbook()
        new.append(copy.deepcopy(new[0]))
        self.assertIsNone(rdt.changed_entry_tags(flip_playbook(), new))


class PlaybookAt(unittest.TestCase):
    def test_bad_base_reads_nothing(self):
        flip = rdt.ANSIBLE_DIR / "flip.yml"
        self.assertIsNone(rdt.playbook_at("", flip))
        self.assertIsNone(rdt.playbook_at("--output=/tmp/x", flip))
        self.assertIsNone(rdt.playbook_at("0" * 40, flip))

    def test_reads_the_playbook_at_head(self):
        head = subprocess.run(["git", "rev-parse", "HEAD"], cwd=SCRIPT.parents[2],
                              capture_output=True, text=True, check=True).stdout.strip()
        self.assertEqual(rdt.playbook_at(head, rdt.ANSIBLE_DIR / "flip.yml")[0]["hosts"], "flip")


class RealPlaybooks(unittest.TestCase):
    """End to end on the repo's playbooks, as deploy-docker-app runs it."""

    def run_script(self, *changed, base=""):
        out = subprocess.run(
            [sys.executable, "-I", str(SCRIPT), "--base", base, *DEPLOYED_PLAYBOOKS],
            input="\n".join(changed), capture_output=True, text=True, check=True,
            cwd=SCRIPT.parents[2],
        )
        return json.loads(out.stdout), out.stderr

    def test_decommission_app_deploys_nothing(self):
        result, stderr = self.run_script("ansible/roles/decommission_app/tasks/main.yml")
        self.assertEqual(set(result.values()), {""})
        self.assertNotIn("::warning::", stderr)

    def test_dependency_of_a_never_role_is_reported_by_main(self):
        # main() itself on the real playbooks, with a meta tree where the only
        # dependent of `dep` is decommission_app (tags [decommission, never]).
        with tempfile.TemporaryDirectory() as tmp:
            roles_dir = Path(tmp)
            write_meta(roles_dir, "decommission_app", ["dep"])
            real = rdt.add_dependents
            stdout, stderr = io.StringIO(), io.StringIO()
            with mock.patch.object(rdt, "add_dependents", lambda roles: real(roles, roles_dir)), \
                    mock.patch.object(sys, "argv", ["resolve_docker_tags.py", *(str(SCRIPT.parents[2] / p) for p in DEPLOYED_PLAYBOOKS)]), \
                    mock.patch.object(sys, "stdin", io.StringIO("ansible/roles/dep/tasks/main.yml\n")), \
                    contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(stderr):
                rdt.main()
        self.assertEqual(set(json.loads(stdout.getvalue()).values()), {""})
        self.assertIn("::warning::role 'dep' changed but is not deployed", stderr.getvalue())

    def test_role_of_a_manual_playbook_gets_a_notice(self):
        # jellyfin has an entry in nas.yml only, which CI never runs.
        result, stderr = self.run_script("ansible/roles/jellyfin/tasks/main.yml")
        self.assertEqual(set(result.values()), {""})
        self.assertIn("::notice::role 'jellyfin' changed, deployed by hand only (nas.yml), not by CI", stderr)
        self.assertNotIn("::warning::", stderr)

    def test_role_of_the_proxmox_host_gets_a_notice(self):
        # vzdump_restore_test has an entry in pve.yml only, which CI never runs.
        result, stderr = self.run_script("ansible/roles/vzdump_restore_test/files/vzdump_restore_test.py")
        self.assertEqual(set(result.values()), {""})
        self.assertIn("::notice::role 'vzdump_restore_test' changed, deployed by hand only (pve.yml), not by CI", stderr)
        self.assertNotIn("::warning::", stderr)

    def test_role_of_pve_and_of_deployed_hosts_deploys_on_those_hosts(self):
        # update_notify runs on pve (by hand) and on the four CI-deployed hosts:
        # a change deploys it on those four, with no manual-only notice.
        result, stderr = self.run_script("ansible/roles/update_notify/files/update_notify.py")
        for playbook in DEPLOYED_PLAYBOOKS:
            self.assertIn("update_notify", result[playbook].split(","))
        self.assertNotIn("deployed by hand only", stderr)
        self.assertNotIn("::warning::", stderr)

    def test_role_readme_deploys_nothing(self):
        result, stderr = self.run_script("ansible/roles/trek/README.md")
        self.assertEqual(set(result.values()), {""})
        self.assertNotIn("::warning::", stderr)

    def test_role_readme_does_not_hide_a_real_change(self):
        result, _ = self.run_script("ansible/roles/trek/README.md", "ansible/roles/trek/tasks/main.yml")
        self.assertIn("trek", result["ansible/docker.yml"].split(","))

    def test_nas_storage_without_dependent_is_reported(self):
        # Pulled in only through meta dependencies, none today: a change
        # deploys nothing and says so (AddDependents covers the dependents).
        result, stderr = self.run_script("ansible/roles/nas_storage/tasks/main.yml")
        self.assertEqual(set(result.values()), {""})
        self.assertIn("::warning::role 'nas_storage'", stderr)


    def run_main(self, *changed, old_flip=None):
        """main() in process, the base version of flip.yml being `old_flip`."""
        stdout, stderr = io.StringIO(), io.StringIO()
        with mock.patch.object(rdt, "playbook_at", lambda base, playbook: old_flip if playbook.name == "flip.yml" else None), \
                mock.patch.object(sys, "argv", ["resolve_docker_tags.py", "--base", "a" * 40, *DEPLOYED_PLAYBOOKS]), \
                mock.patch.object(sys, "stdin", io.StringIO("\n".join(changed))), \
                contextlib.chdir(SCRIPT.parents[2]), \
                contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(stderr):
            rdt.main()
        return json.loads(stdout.getvalue()), stderr.getvalue()

    def test_host_vars_deploy_the_whole_playbook_of_that_host(self):
        result, _ = self.run_script("ansible/host_vars/flip/variables.yaml")
        self.assertEqual(result, {p: ("all" if p == "ansible/flip.yml" else "") for p in DEPLOYED_PLAYBOOKS})

    def test_host_vars_of_a_manual_host_deploy_nothing(self):
        for host in ("nas", "pve", "newt-lxc"):
            result, _ = self.run_script(f"ansible/host_vars/{host}/variables.yaml")
            self.assertEqual(set(result.values()), {""}, host)

    def test_playbook_without_base_is_deployed_whole(self):
        result, stderr = self.run_script("ansible/flip.yml")
        self.assertEqual(result["ansible/flip.yml"], "all")
        self.assertEqual(result["ansible/docker.yml"], "")
        self.assertIn("no readable base", stderr)

    def test_playbook_role_entry_change_deploys_that_entry(self):
        old = flip_playbook()
        entry_of(old, "demo_planning")["vars"]["flip_planning_sentry_environment"] = "before"
        result, _ = self.run_main("ansible/flip.yml", old_flip=old)
        self.assertEqual(result["ansible/flip.yml"], "demo_planning")

    def test_playbook_entry_and_role_change_add_up(self):
        old = flip_playbook()
        entry_of(old, "demo_planning")["vars"]["flip_planning_sentry_environment"] = "before"
        result, _ = self.run_main("ansible/flip.yml", "ansible/roles/promptoramix/tasks/main.yml", old_flip=old)
        self.assertEqual(result["ansible/flip.yml"], "demo_planning,promptoramix")

    def test_playbook_comment_change_deploys_nothing(self):
        result, _ = self.run_main("ansible/flip.yml", old_flip=flip_playbook())
        self.assertEqual(set(result.values()), {""})

    def test_whole_playbook_wins_over_role_tags(self):
        old = flip_playbook()
        old[0]["pre_tasks"].pop()
        result, _ = self.run_main("ansible/flip.yml", "ansible/roles/promptoramix/tasks/main.yml", old_flip=old)
        self.assertEqual(result["ansible/flip.yml"], "all")


if __name__ == "__main__":
    unittest.main()
