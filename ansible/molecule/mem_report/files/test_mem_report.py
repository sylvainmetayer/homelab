"""Tests de mem_report.py (rôle mem_report), lancés par verify.yml du scénario
avec le python3 de l'hôte de test. À la main : copier ce fichier à côté de
ansible/roles/mem_report/files/mem_report.py, puis
python3 -I -m unittest discover -s . -p 'test_*.py'.
"""

import argparse
import datetime
import http.client
import io
import os
import subprocess
import tempfile
import unittest
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path
from unittest import mock

import mem_report as mr

MIB = mr.MIB
GIB = mr.GIB
NOW = datetime.datetime(2026, 11, 4, 12, 0, tzinfo=datetime.timezone.utc)
ID_A = "a" * 64
ID_B = "b" * 64


def measure(**fields):
    base = {
        "name": "app",
        "limit": 1 * GIB,
        "drifted": False,
        "peak": 500 * MIB,
        "peak_is_current": False,
        "oom_kill": 0,
        "max_events": 0,
        "restarts": 0,
        "days": 30.0,
    }
    return {**base, **fields}


class SizesTest(unittest.TestCase):
    def test_suggested_limit_steps(self):
        cases = {
            0: 16 * MIB,
            1: 16 * MIB,
            8 * MIB: 16 * MIB,
            # 2x le pic pile sur un pas : pas d'arrondi en plus.
            128 * MIB: 256 * MIB,
            # Juste au-dessus de 256 Mio : pas de 64 Mio.
            129 * MIB: 320 * MIB,
            512 * MIB: 1 * GIB,
            513 * MIB: 1280 * MIB,
            3 * GIB: 6 * GIB,
        }
        for peak, expected in cases.items():
            with self.subTest(peak=peak):
                self.assertEqual(mr.suggested_limit(peak), expected)

    def test_compose_size(self):
        self.assertEqual(mr.compose_size(2 * GIB), "2g")
        self.assertEqual(mr.compose_size(1536 * MIB), "1536m")
        self.assertEqual(mr.compose_size(512 * MIB), "512m")

    def test_parse_compose_size(self):
        cases = {
            "512m": 512 * MIB,
            "2g": 2 * GIB,
            "2G": 2 * GIB,
            "1.5g": 1536 * MIB,
            "64mb": 64 * MIB,
            "64MiB": 64 * MIB,
            "1024": 1024,
            "1k": 1024,
            "1t": 1024 * GIB,
            1048576: MIB,
            " 512m ": 512 * MIB,
        }
        for value, expected in cases.items():
            with self.subTest(value=value):
                self.assertEqual(mr.parse_compose_size(value), expected)

    def test_parse_compose_size_refuses_the_rest(self):
        for value in ("", "abc", "12x", "-1m", "${LIMIT}"):
            with self.subTest(value=value), self.assertRaises(ValueError):
                mr.parse_compose_size(value)

    def test_human(self):
        self.assertEqual(mr.human(1536 * MIB), "1.5 Gio")
        self.assertEqual(mr.human(512 * MIB), "512 Mio")


class CgroupFilesTest(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.root = Path(directory.name)

    def test_read_bytes(self):
        (self.root / "value").write_text("123\n")
        (self.root / "max").write_text("max\n")
        self.assertEqual(mr.read_bytes(self.root / "value"), 123)
        self.assertIsNone(mr.read_bytes(self.root / "max"))
        self.assertIsNone(mr.read_bytes(self.root / "absent"))

    def test_read_events(self):
        (self.root / "events").write_text("low 0\nmax 12\noom 1\noom_kill 2\nbad x\n")
        self.assertEqual(mr.read_events(self.root / "events"), {"low": 0, "max": 12, "oom": 1, "oom_kill": 2})
        self.assertEqual(mr.read_events(self.root / "absent"), {})

    def test_find_scopes_systemd_cgroupfs_and_decoys(self):
        systemd = self.root / "system.slice" / f"docker-{ID_A}.scope"
        cgroupfs = self.root / "docker" / ID_B
        for path in (
            systemd / "init.scope",
            cgroupfs,
            # Un id nu hors de docker/, un nom trop court : pas des conteneurs.
            self.root / "other" / ("c" * 64),
            self.root / "system.slice" / "docker-abc.scope",
            self.root / "system.slice" / "docker.service",
        ):
            path.mkdir(parents=True)
        self.assertEqual(mr.find_scopes(self.root), {ID_A: systemd, ID_B: cgroupfs})

    def test_age_days(self):
        self.assertEqual(mr.age_days("2026-11-03T12:00:00.123456789Z", NOW), 1.0)
        self.assertIsNone(mr.age_days("inconnu", NOW))

    def scope(self, **files):
        path = self.root / f"docker-{ID_A}.scope"
        path.mkdir(exist_ok=True)
        for name, value in files.items():
            (path / name.replace("_", ".")).write_text(value + "\n")
        return path

    def run_measure(self, scope, declared):
        containers = [(ID_A, "app", 3, "2026-11-03T12:00:00Z", "/c.yaml", "svc")]
        return mr.measure(containers, {ID_A: scope}, NOW, declared)

    def test_measure_reads_the_cgroup(self):
        scope = self.scope(
            memory_current=str(10 * MIB),
            memory_peak=str(20 * MIB),
            memory_max=str(64 * MIB),
            memory_events="max 4\noom_kill 1",
        )
        measures, drifts, missing, compared = self.run_measure(scope, {ID_A: 64 * MIB})
        self.assertEqual((drifts, missing, compared), ([], 0, 1))
        found = measures[0]
        self.assertEqual(found["peak"], 20 * MIB)
        self.assertFalse(found["peak_is_current"])
        self.assertEqual((found["limit"], found["oom_kill"], found["max_events"]), (64 * MIB, 1, 4))
        self.assertEqual((found["restarts"], found["days"]), (3, 1.0))

    def test_measure_without_memory_peak_uses_current(self):
        scope = self.scope(memory_current=str(10 * MIB), memory_max="max")
        measures, _, _, _ = self.run_measure(scope, {})
        self.assertEqual(measures[0]["peak"], 10 * MIB)
        self.assertTrue(measures[0]["peak_is_current"])
        self.assertIsNone(measures[0]["limit"])

    def test_small_rounding_is_not_a_drift(self):
        scope = self.scope(memory_current="1", memory_peak="1", memory_max=str(64 * MIB - 16 * 1024))
        measures, drifts, _, compared = self.run_measure(scope, {ID_A: 64 * MIB})
        self.assertEqual((drifts, compared), ([], 1))
        self.assertFalse(measures[0]["drifted"])

    def test_max_with_a_declared_limit_is_a_drift(self):
        scope = self.scope(memory_current="1", memory_peak="1", memory_max="max")
        measures, drifts, _, _ = self.run_measure(scope, {ID_A: 64 * MIB})
        self.assertTrue(measures[0]["drifted"])
        self.assertEqual(drifts[0]["declared"], 64 * MIB)
        self.assertIsNone(drifts[0]["real"])
        self.assertFalse(drifts[0]["no_controller"])

    def test_limit_not_in_compose_is_a_drift(self):
        scope = self.scope(memory_current="1", memory_peak="1", memory_max=str(64 * MIB))
        _, drifts, _, _ = self.run_measure(scope, {ID_A: None})
        self.assertIsNone(drifts[0]["declared"])
        self.assertEqual(drifts[0]["real"], 64 * MIB)

    def test_container_outside_compose_is_not_compared(self):
        scope = self.scope(memory_current="1", memory_peak="1", memory_max=str(64 * MIB))
        measures, drifts, _, compared = self.run_measure(scope, {})
        self.assertEqual((drifts, compared), ([], 0))
        self.assertFalse(measures[0]["drifted"])

    def test_no_controller_with_declared_limit(self):
        measures, drifts, missing, compared = self.run_measure(self.scope(), {ID_A: 64 * MIB})
        self.assertEqual((measures, missing, compared), ([], 1, 1))
        self.assertTrue(drifts[0]["no_controller"])

    def test_no_controller_without_declared_limit(self):
        measures, drifts, missing, compared = self.run_measure(self.scope(), {})
        self.assertEqual((measures, drifts, missing, compared), ([], [], 1, 0))

    def test_cgroup_gone_between_walk_and_read(self):
        gone = self.root / "gone"
        measures, drifts, missing, _ = self.run_measure(gone, {ID_A: 64 * MIB})
        self.assertEqual((measures, drifts, missing), ([], [], 1))

    def test_container_without_scope(self):
        measures, _, missing, _ = mr.measure([(ID_B, "x", 0, "", "", "")], {}, NOW, {})
        self.assertEqual((measures, missing), ([], 1))


class ClassifyTest(unittest.TestCase):
    def classify(self, *measures):
        return mr.classify(list(measures), 80, 25, 64 * MIB)

    def test_high_percent_grows(self):
        grow, shrink, unlimited = self.classify(measure(peak=800 * MIB, limit=1000 * MIB))
        self.assertEqual((len(grow), shrink, unlimited), (1, [], []))
        self.assertEqual(grow[0]["percent"], 80)

    def test_just_under_high_stays_quiet(self):
        self.assertEqual(self.classify(measure(peak=799 * MIB, limit=1000 * MIB)), ([], [], []))

    def test_oom_kill_grows_and_never_suggests_a_reduction(self):
        grow, _, _ = self.classify(measure(peak=10 * MIB, limit=1 * GIB, oom_kill=1))
        self.assertEqual(grow[0]["suggested"], 2 * GIB)

    def test_low_percent_shrinks(self):
        _, shrink, _ = self.classify(measure(peak=100 * MIB, limit=1 * GIB))
        self.assertEqual(shrink[0]["suggested"], 208 * MIB)

    def test_exactly_low_percent_does_not_shrink(self):
        self.assertEqual(self.classify(measure(peak=250 * MIB, limit=1000 * MIB)), ([], [], []))

    def test_small_saving_does_not_shrink(self):
        # Limite 128 Mio, pic 8 Mio : suggestion 16 Mio, 112 Mio libérés.
        self.assertEqual(len(self.classify(measure(peak=8 * MIB, limit=128 * MIB))[1]), 1)
        # Limite 64 Mio, pic 8 Mio : 48 Mio libérés, sous le seuil.
        self.assertEqual(self.classify(measure(peak=8 * MIB, limit=64 * MIB)), ([], [], []))

    def test_recent_restart_does_not_shrink(self):
        low = {"peak": 100 * MIB, "limit": 1 * GIB}
        self.assertEqual(self.classify(measure(restarts=1, days=2.0, **low))[1], [])
        # Redémarré mais mesuré longtemps, ou jamais redémarré : réduit.
        self.assertEqual(len(self.classify(measure(restarts=1, days=8.0, **low))[1]), 1)
        self.assertEqual(len(self.classify(measure(restarts=0, days=2.0, **low))[1]), 1)

    def test_drifted_does_not_shrink(self):
        self.assertEqual(self.classify(measure(peak=100 * MIB, limit=1 * GIB, drifted=True))[1], [])

    def test_no_limit(self):
        _, _, unlimited = self.classify(measure(limit=None))
        self.assertEqual(len(unlimited), 1)

    def test_no_limit_but_drifted_is_left_to_the_drift_section(self):
        self.assertEqual(self.classify(measure(limit=None, drifted=True)), ([], [], []))

    def test_sort_orders(self):
        grow, shrink, unlimited = self.classify(
            measure(name="g-90", peak=900 * MIB, limit=1000 * MIB),
            measure(name="g-oom", peak=10 * MIB, limit=1000 * MIB, oom_kill=2),
            measure(name="g-99", peak=990 * MIB, limit=1000 * MIB),
            measure(name="s-small", peak=100 * MIB, limit=512 * MIB),
            measure(name="s-big", peak=100 * MIB, limit=4 * GIB),
            measure(name="u-small", limit=None, peak=1 * MIB),
            measure(name="u-big", limit=None, peak=2 * MIB),
        )
        self.assertEqual([m["name"] for m in grow], ["g-oom", "g-99", "g-90"])
        self.assertEqual([m["name"] for m in shrink], ["s-big", "s-small"])
        self.assertEqual([m["name"] for m in unlimited], ["u-big", "u-small"])


class LinesTest(unittest.TestCase):
    def test_grow_line_at_cap(self):
        m = measure(peak=1 * GIB, limit=1 * GIB, percent=100.0, suggested=2 * GIB, oom_kill=1, max_events=4, restarts=2)
        line = mr.grow_line(m)
        self.assertIn("OOM-kill x1", line)
        self.assertIn("plafond atteint x4", line)
        self.assertIn("redémarré x2", line)
        self.assertIn("mem_limit 2g au moins", line)

    def test_window_notes(self):
        self.assertEqual(mr.window_note(measure(days=30.0)), "")
        self.assertEqual(mr.window_note(measure(days=None)), "")
        self.assertEqual(mr.window_note(measure(days=3.0)), " (pic sur 3 j seulement)")
        self.assertEqual(mr.window_note(measure(days=0.5)), " (pic sur moins d'un jour)")
        self.assertIn("memory.current", mr.window_note(measure(peak_is_current=True)))

    def test_drift_lines(self):
        base = {"name": "app", "service": "svc", "declared": 64 * MIB, "real": None, "no_controller": False}
        self.assertIn("réel aucune limite -> docker compose up -d --force-recreate svc", mr.drift_line(base))
        self.assertIn("contrôleur mémoire absent", mr.drift_line({**base, "no_controller": True}))
        self.assertIn("déclaré rien, réel 64 Mio", mr.drift_line({**base, "declared": None, "real": 64 * MIB}))


class FitTest(unittest.TestCase):
    LINE = "x" * 200

    def test_short_report_is_untouched(self):
        message, full = mr.fit([("A :", ["- a"]), ("B :", [])], "pied")
        self.assertEqual(message, "A :\n- a\n\npied")
        self.assertEqual(full, message)

    def test_cut_from_the_longest_unprotected_section_first(self):
        sections = [
            ("Écarts :", [f"d{i} {self.LINE}" for i in range(5)]),
            ("Agrandir :", [f"g{i} {self.LINE}" for i in range(5)]),
            ("Réduire :", [f"s{i} {self.LINE}" for i in range(30)]),
            ("Sans limite :", [f"u{i} {self.LINE}" for i in range(5)]),
        ]
        message, full = mr.fit(sections, "pied")
        self.assertLessEqual(len(message.encode()), mr.MAX_MESSAGE)
        self.assertIn("d4 ", message)
        self.assertIn("g4 ", message)
        self.assertIn("s0 ", message)
        self.assertNotIn("s29 ", message)
        # Le journal garde tout, l'entrée n'est pas modifiée.
        self.assertIn("s29 ", full)
        self.assertEqual(len(sections[2][1]), 30)
        self.assertRegex(message, r"\.\.\. et \d+ ligne\(s\) de plus : journalctl -u mem-report")
        self.assertTrue(message.endswith("pied"))

    def test_protected_sections_go_only_when_the_rest_is_empty(self):
        sections = [
            ("Écarts :", [f"d{i} {self.LINE}" for i in range(30)]),
            ("Agrandir :", [f"g{i} {self.LINE}" for i in range(5)]),
            ("Réduire :", [f"s{i} {self.LINE}" for i in range(2)]),
        ]
        message, _ = mr.fit(sections, "pied")
        self.assertLessEqual(len(message.encode()), mr.MAX_MESSAGE)
        self.assertNotIn("s0 ", message)
        self.assertIn("d0 ", message)
        self.assertNotIn("d29 ", message)

    def test_limit_counts_bytes(self):
        message, _ = mr.fit([("A :", ["é" * 300 for _ in range(30)])], "pied")
        self.assertLessEqual(len(message.encode()), mr.MAX_MESSAGE)

    def test_oversized_footer_ends_without_looping(self):
        message, _ = mr.fit([("A :", ["- a"])], "p" * (mr.MAX_MESSAGE + 1))
        self.assertNotIn("- a", message)


class BuildReportTest(unittest.TestCase):
    ARGS = argparse.Namespace(high=80, low=25, min_saving_mb=64)

    def report(self, measures=(), drifts=(), unread=(), missing=0, compared=0):
        return mr.build_report("docker", list(measures), missing, self.ARGS, list(drifts), list(unread), compared)

    def test_nothing_running(self):
        report, journal = self.report()
        self.assertEqual(report["priority"], 2)
        self.assertEqual(journal, "Aucun conteneur en cours : rien à mesurer.")

    def test_all_fine(self):
        report, _ = self.report([measure()], compared=1)
        self.assertEqual((report["priority"], report["tags"]), (2, ["white_check_mark"]))
        self.assertIn("Rien à signaler", report["message"])
        self.assertIn("1 conteneur(s) lu(s), 1 comparé(s)", report["message"])

    def test_grow_is_high(self):
        report, _ = self.report([measure(peak=1 * GIB)])
        self.assertEqual((report["priority"], report["tags"]), (4, ["warning"]))
        self.assertIn("À agrandir", report["message"])

    def test_drift_is_high(self):
        drift = {"name": "a", "service": "s", "declared": MIB, "real": None, "no_controller": False}
        report, _ = self.report([measure()], drifts=[drift])
        self.assertEqual(report["priority"], 4)
        self.assertIn("Limite réelle différente du compose", report["message"])

    def test_shrink_unlimited_or_unread_are_normal(self):
        for report, _ in (
            self.report([measure(peak=100 * MIB)]),
            self.report([measure(limit=None)]),
            self.report([measure()], unread=["/c.yaml"]),
        ):
            with self.subTest(message=report["message"]):
                self.assertEqual(report["priority"], 3)

    def test_missing_cgroups_are_counted(self):
        report, _ = self.report([measure()], missing=2)
        self.assertIn("2 sans cgroup trouvé", report["message"])


def completed(stdout="", returncode=0, stderr=""):
    return subprocess.CompletedProcess([], returncode, stdout, stderr)


class DockerCallsTest(unittest.TestCase):
    def test_list_containers(self):
        inspect = (
            f"{ID_A}\t/app\t2\t2026-11-03T12:00:00Z\t/c.yaml\tweb\n"
            "ligne\ttronquée\n"
            f"{ID_B}\t/seul\t\t2026-11-03T12:00:00Z\t\t\n"
        )
        with mock.patch.object(mr.subprocess, "run", side_effect=[completed(f"{ID_A}\n{ID_B}\n"), completed(inspect)]):
            containers = mr.list_containers("docker")
        self.assertEqual(
            containers,
            [
                (ID_A, "app", 2, "2026-11-03T12:00:00Z", "/c.yaml", "web"),
                (ID_B, "seul", 0, "2026-11-03T12:00:00Z", "", ""),
            ],
        )

    def test_list_containers_none_running(self):
        with mock.patch.object(mr.subprocess, "run", return_value=completed("")) as run:
            self.assertEqual(mr.list_containers("docker"), [])
        self.assertEqual(run.call_count, 1)

    def test_inspect_keeps_the_others_when_one_vanished(self):
        calls = [completed(f"{ID_A}\n{ID_B}\n"), completed(f"{ID_A}\t/app\t0\ts\tf\tw\n", returncode=1)]
        with mock.patch.object(mr.subprocess, "run", side_effect=calls):
            self.assertEqual(len(mr.list_containers("docker")), 1)

    def test_inspect_total_failure_raises(self):
        calls = [completed(f"{ID_A}\n"), completed("", returncode=1)]
        with mock.patch.object(mr.subprocess, "run", side_effect=calls), self.assertRaises(subprocess.CalledProcessError):
            mr.list_containers("docker")

    def test_compose_limits(self):
        output = '{"services": {"web": {"mem_limit": "512m"}, "db": {}}}'
        with mock.patch.object(mr.subprocess, "run", return_value=completed(output)) as run:
            limits = mr.compose_limits("docker", "/a.yaml,/b.yaml", 60)
        self.assertEqual(limits, {"web": 512 * MIB, "db": None})
        argv = run.call_args.args[0]
        self.assertEqual(argv[:6], ["docker", "compose", "-f", "/a.yaml", "-f", "/b.yaml"])
        # Le script n'a pas à voir les secrets.
        self.assertIn("--no-interpolate", argv)
        self.assertIn("--no-env-resolution", argv)

    def test_read_declared(self):
        containers = [
            (ID_A, "a", 0, "", "/c.yaml", "web"),
            (ID_B, "b", 0, "", "/c.yaml", "gone"),
            ("c" * 64, "c", 0, "", "", ""),
        ]
        with mock.patch.object(mr, "compose_limits", return_value={"web": MIB}) as limits:
            declared, unread = mr.read_declared("docker", containers)
        self.assertEqual(declared, {ID_A: MIB})
        self.assertEqual(unread, ["/c.yaml : service gone absent"])
        # Un seul appel par projet.
        self.assertEqual(limits.call_count, 1)

    def test_read_declared_unreadable_compose_does_not_cite_the_error(self):
        containers = [(ID_A, "a", 0, "", "/c.yaml", "web"), (ID_B, "b", 0, "", "/c.yaml", "db")]
        for error in (
            ValueError("mot de passe en clair"),
            OSError("mot de passe en clair"),
            KeyError("mot de passe en clair"),
            AttributeError("mot de passe en clair"),
            TypeError("mot de passe en clair"),
            subprocess.TimeoutExpired("mot de passe en clair", 60),
            subprocess.CalledProcessError(1, "mot de passe en clair"),
        ):
            err = io.StringIO()
            with (
                self.subTest(error=type(error).__name__),
                mock.patch.object(mr, "compose_limits", side_effect=error) as limits,
                redirect_stderr(err),
            ):
                declared, unread = mr.read_declared("docker", containers)
                self.assertEqual((declared, unread), ({}, ["/c.yaml"]))
                self.assertEqual(limits.call_count, 1)
                self.assertNotIn("mot de passe", err.getvalue())

    def test_read_declared_shares_one_budget_between_composes(self):
        containers = [(ID_A, "a", 0, "", "/a.yaml", "web"), (ID_B, "b", 0, "", "/b.yaml", "web")]
        with (
            # Départ, premier compose tout de suite, second à 30 s de la fin.
            mock.patch.object(mr.time, "monotonic", side_effect=[0, 0, mr.COMPOSE_BUDGET_SECONDS - 30]),
            mock.patch.object(mr, "compose_limits", return_value={"web": MIB}) as limits,
        ):
            mr.read_declared("docker", containers)
        self.assertEqual([call.args[2] for call in limits.call_args_list], [mr.COMPOSE_TIMEOUT_SECONDS, 30])


class MainTest(unittest.TestCase):
    ARGV = ["--host", "docker", "--url", "http://ntfy.invalid", "--topic", "t", "--cgroup-root", "/nonexistent"]

    def main(self, env, **patches):
        err = io.StringIO()
        with (
            mock.patch.dict(os.environ, env, clear=False),
            mock.patch.object(mr, "list_containers", **patches.get("list", {"return_value": []})),
            mock.patch.object(mr, "publish", **patches.get("publish", {})) as publish,
            redirect_stdout(io.StringIO()),
            redirect_stderr(err),
        ):
            code = mr.main(self.ARGV)
        self.stderr = err.getvalue()
        return code, publish

    def test_ok(self):
        code, publish = self.main({mr.TOKEN_VARIABLE: "jeton"})
        self.assertEqual(code, 0)
        publish.assert_called_once()

    def test_read_failure_is_still_published(self):
        code, publish = self.main({mr.TOKEN_VARIABLE: "jeton"}, list={"side_effect": OSError("docker absent")})
        self.assertEqual(code, 1)
        report = publish.call_args.args[3]
        self.assertEqual(report["priority"], 4)
        self.assertIn("OSError", report["message"])
        self.assertNotIn("docker absent", report["message"])

    def test_no_token_publishes_nothing(self):
        code, publish = self.main({mr.TOKEN_VARIABLE: ""})
        self.assertEqual(code, 0)
        publish.assert_not_called()

    def test_read_failure_without_token_still_fails(self):
        code, publish = self.main({mr.TOKEN_VARIABLE: ""}, list={"side_effect": OSError("x")})
        self.assertEqual(code, 1)
        publish.assert_not_called()

    def test_failed_publication_is_exit_2_and_cites_its_class_only(self):
        for error in (OSError("requête citée"), ValueError("requête citée"), http.client.InvalidURL("requête citée")):
            with self.subTest(error=type(error).__name__):
                code, _ = self.main({mr.TOKEN_VARIABLE: "jeton"}, publish={"side_effect": error})
                self.assertEqual(code, 2)
                self.assertIn(type(error).__name__, self.stderr)
                self.assertNotIn("requête citée", self.stderr)


if __name__ == "__main__":
    unittest.main()
