"""Tests unitaires de ci_key_audit.py : aucun appel réel, aucun jeton réel.

À la main : copier le script à côté et lancer
python3 -I -m unittest discover -s . -p 'test_*.py'
"""

import io
import json
import os
import sys
import tempfile
import unittest
import urllib.error
from unittest import mock

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import ci_key_audit as audit  # noqa: E402

NOW = 1_800_000_000
CI_FP = "SHA256:empreinte-de-test-ci"
OTHER_FP = "SHA256:empreinte-de-test-autre"
CONFIG = {
    "vl_url": "http://logs.invalid",
    "vl_user": "lecteur",
    "github_api": "http://github.invalid",
    "repository": "exemple/homelab",
    "workflow": "deploy.yaml",
    "branch": "main",
    "fingerprint": CI_FP,
    "hosts": ["docker", "pi"],
    "excluded_hosts": ["newt-lxc"],
    "margin_seconds": 120,
    "settle_seconds": 300,
    "overlap_seconds": 3600,
    "freshness_seconds": 10800,
    "initial_lookback_seconds": 86400,
    "run_lookback_seconds": 172800,
    "max_lines": 100,
    "max_pages": 3,
    "retry_delays": [],
    "ntfy_url": "http://ntfy.invalid",
    "ntfy_topic": "scripts",
    "uptime_push_bin": "/bin/uptime-push",
}
SECRETS = {"vl_password": "faux", "ntfy_token": "faux", "push_url": "http://kuma.invalid/api/push/faux"}


def line(moment, host="docker", fingerprint=CI_FP, prefix="clé connue : "):
    message = f"{prefix}sylvain@{host} depuis 192.0.2.7, clé github-actions (ssh-ed25519 {fingerprint})"
    return {"_time": audit.rfc3339(moment).replace("Z", ".123456789Z"), "host": host, "_msg": message}


def run(start, end, run_id=1, status="completed", attempt=1):
    return {
        "id": run_id,
        "status": status,
        "run_attempt": attempt,
        "created_at": audit.rfc3339(start),
        "run_started_at": audit.rfc3339(start),
        "updated_at": audit.rfc3339(end),
    }


class FakeChecker(audit.Checker):
    """Le vrai Checker, sans le réseau : ce que les trois services répondraient."""

    def __init__(self, now=NOW, lines=(), runs=(), fresh=("docker", "pi"), config=None):
        super().__init__(dict(CONFIG, **(config or {})), SECRETS, now, sleep=lambda _: None)
        self.lines, self.fake_runs, self.fresh = list(lines), list(runs), set(fresh)
        self.attempts = {}
        self.steps = {}
        self.published = []
        self.pushed = []
        self.starts = []
        self.github_calls = []
        self.fail_publish = False
        self.fail_github = False
        self.fail_jobs = False

    def logs_query(self, query, start, limit=None):
        if query.startswith("identifier"):
            self.starts.append(start)
            return list(self.lines)
        return [{"host": host, "n": "1"} for host in self.fresh]

    def github(self, path, query=None):
        self.github_calls.append(path)
        if self.fail_github:
            raise audit.CheckError("GitHub : HTTP 502")
        if path.endswith("/jobs"):
            if self.fail_jobs:
                raise audit.CheckError("GitHub : quota épuisé")
            run_id = int(path.split("/runs/")[1].split("/")[0])
            steps = [{"name": f"Deploy {h}", "conclusion": c} for h, c in self.steps.get(run_id, {}).items()]
            return {"jobs": [{"steps": steps}]}
        if "/attempts/" in path:
            return self.attempts[path.rsplit("/", 1)[1]]
        return {"workflow_runs": self.fake_runs}

    def publish(self, title, message, priority):
        if self.fail_publish:
            raise audit.CheckError("ntfy : HTTP 502")
        self.published.append((title, message, priority))

    def push(self, status, message):
        self.pushed.append((status, message))
        return True


def tick(checker, state=None):
    state = {} if state is None else state
    summary, published, errors = audit.tick(checker, state)
    return state, summary, published, errors


class Judgement(unittest.TestCase):
    def test_no_line_at_all_is_clean(self):
        checker = FakeChecker(runs=[run(NOW - 900, NOW - 800)])
        state, _, published, errors = tick(checker)
        self.assertEqual((published, errors, checker.published), ([], [], []))
        self.assertEqual(state["cursor"], NOW)

    def test_login_during_a_run_passes(self):
        checker = FakeChecker(lines=[line(NOW - 850)], runs=[run(NOW - 900, NOW - 800)])
        _, _, published, errors = tick(checker)
        self.assertEqual((published, errors, checker.published), ([], [], []))

    def test_login_during_a_run_still_in_progress_passes(self):
        checker = FakeChecker(lines=[line(NOW - 400)], runs=[run(NOW - 900, NOW - 800, status="in_progress")])
        _, _, published, _ = tick(checker)
        self.assertEqual(published, [])

    def test_margin_around_a_run(self):
        inside = FakeChecker(lines=[line(NOW - 800 + 119)], runs=[run(NOW - 900, NOW - 800)])
        self.assertEqual(tick(inside)[2], [])
        outside = FakeChecker(lines=[line(NOW - 800 + 122)], runs=[run(NOW - 900, NOW - 800)])
        self.assertEqual(len(tick(outside)[2]), 1)
        before = FakeChecker(lines=[line(NOW - 900 - 122)], runs=[run(NOW - 900, NOW - 800)])
        self.assertEqual(len(tick(before)[2]), 1)

    def test_login_out_of_any_run_alerts_urgently_with_who_and_where(self):
        checker = FakeChecker(lines=[line(NOW - 1100)], runs=[run(NOW - 900, NOW - 800)])
        _, _, published, errors = tick(checker)
        self.assertEqual(errors, [])
        self.assertEqual(len(published), 1)
        title, message, priority = checker.published[0]
        self.assertEqual(priority, 5)
        self.assertIn("hors déploiement", title)
        for needle in ("docker", "192.0.2.7", "sylvain", CI_FP, audit.RUNBOOK):
            self.assertIn(needle, message)

    def test_login_without_any_run_alerts(self):
        checker = FakeChecker(lines=[line(NOW - 1000)])
        self.assertEqual(len(tick(checker)[2]), 1)

    def test_a_line_of_the_former_hook_format_counts(self):
        checker = FakeChecker(lines=[line(NOW - 1000, prefix="notifié : ")])
        self.assertEqual(len(tick(checker)[2]), 1)

    def test_excluded_host_is_not_judged_an_unknown_host_is(self):
        excluded = FakeChecker(lines=[line(NOW - 1000, host="newt-lxc")])
        self.assertEqual(tick(excluded)[2], [])
        unknown = FakeChecker(lines=[line(NOW - 1000, host="nouveau")])
        self.assertEqual(len(tick(unknown)[2]), 1)

    def test_another_key_and_the_companion_line_are_ignored(self):
        lines = [
            line(NOW - 1000, fingerprint=OTHER_FP),
            line(NOW - 1000, prefix="échec de la trace ntfy : "),
        ]
        checker = FakeChecker(lines=lines)
        state, _, published, _ = tick(checker)
        self.assertEqual(published, [])
        self.assertEqual(state["seen"], {})

    def test_earlier_attempt_of_a_rerun_covers_its_logins(self):
        checker = FakeChecker(lines=[line(NOW - 1000)], runs=[run(NOW - 400, NOW - 350, attempt=2)])
        checker.attempts["1"] = run(NOW - 1100, NOW - 900)
        _, _, published, _ = tick(checker)
        self.assertEqual(published, [])

    def test_earlier_attempts_are_only_read_when_a_login_needs_them(self):
        checker = FakeChecker(lines=[line(NOW - 380)], runs=[run(NOW - 400, NOW - 350, attempt=2)])
        tick(checker)
        self.assertFalse([path for path in checker.github_calls if path.endswith("/attempts/1")])

    def test_control_characters_of_a_line_do_not_reach_the_alert(self):
        forged = line(NOW - 1000)
        forged["_msg"] = forged["_msg"] + "\nfausse ligne\x1b[2J"
        checker = FakeChecker(lines=[forged])
        tick(checker)
        self.assertNotIn("\x1b", checker.published[0][1])
        self.assertNotIn("\nfausse", checker.published[0][1])

    def test_many_events_are_one_bounded_message(self):
        checker = FakeChecker(lines=[line(NOW - 1000 - i) for i in range(30)])
        _, _, published, _ = tick(checker)
        self.assertEqual(len(checker.published), 1)
        self.assertIn("et 10 de plus", checker.published[0][1])
        self.assertTrue(published[0].startswith("30 connexion(s)"))


class Idempotence(unittest.TestCase):
    def test_same_event_alerts_once(self):
        checker = FakeChecker(lines=[line(NOW - 1000)])
        state, _, first, _ = tick(checker)
        again = FakeChecker(now=NOW + 600, lines=[line(NOW - 1000)])
        _, _, second, errors = tick(again, state)
        self.assertEqual(len(first), 1)
        self.assertEqual((second, errors, again.published), ([], [], []))

    def test_failed_publication_is_not_lost_and_retried(self):
        checker = FakeChecker(lines=[line(NOW - 1000)])
        checker.fail_publish = True
        state, _, published, errors = tick(checker)
        self.assertEqual(state["seen"], {})
        self.assertEqual(state["cursor"], NOW - 86400 + 3600)
        self.assertEqual(len(published), 1, "le down du moniteur dit l'alerte")
        self.assertEqual(errors, ["ntfy : HTTP 502"])
        retry = FakeChecker(now=NOW + 600, lines=[line(NOW - 1000)])
        tick(retry, state)
        self.assertEqual(len(retry.published), 1)

    def test_seen_is_pruned_once_out_of_the_window(self):
        checker = FakeChecker(lines=[line(NOW - 1000)])
        state = tick(checker)[0]
        later = FakeChecker(now=NOW + 7200)
        tick(later, state)
        self.assertEqual(state["seen"], {})

    def test_a_line_of_the_second_the_query_rounds_down_alerts_once(self):
        moment = NOW - 3600
        state = {"cursor": NOW - 600, "installed_at": NOW - 86400}
        first = FakeChecker(now=NOW + 0.5, lines=[line(moment)])
        state, _, published, _ = tick(first, state)
        self.assertEqual(len(published), 1)
        again = FakeChecker(now=NOW + 600.5, lines=[line(moment)])
        self.assertEqual(tick(again, state)[2], [])

    def test_young_login_waits_for_the_run_to_show_then_alerts_if_still_alone(self):
        checker = FakeChecker(lines=[line(NOW - 60)])
        state, _, published, _ = tick(checker)
        self.assertEqual(published, [])
        settled = FakeChecker(now=NOW + 600, lines=[line(NOW - 60)])
        self.assertEqual(len(tick(settled, state)[2]), 1)

    def test_young_login_covered_by_a_run_seen_later_passes(self):
        state = tick(FakeChecker(lines=[line(NOW - 60)]))[0]
        later = FakeChecker(now=NOW + 600, lines=[line(NOW - 60)], runs=[run(NOW - 70, NOW + 30)])
        self.assertEqual(tick(later, state)[2], [])


class Window(unittest.TestCase):
    def test_first_run_reads_the_initial_lookback(self):
        checker = FakeChecker()
        tick(checker)
        self.assertEqual(checker.starts, [NOW - 86400])

    def test_cursor_minus_overlap_after_a_missed_timer(self):
        state = tick(FakeChecker())[0]
        checker = FakeChecker(now=NOW + 3 * 86400, lines=[line(NOW + 86400)])
        _, _, published, _ = tick(checker, state)
        self.assertEqual(checker.starts, [NOW - 3600])
        self.assertEqual(len(published), 1, "connexion du trou : pas perdue")

    def test_window_is_capped_at_retention(self):
        state = tick(FakeChecker())[0]
        checker = FakeChecker(now=NOW + 60 * 86400)
        tick(checker, state)
        self.assertEqual(checker.starts, [NOW + 60 * 86400 - audit.MAX_WINDOW_SECONDS])

    def test_silent_host_is_an_error_and_freezes_the_cursor(self):
        state = tick(FakeChecker())[0]
        silent = FakeChecker(now=NOW + 600, fresh=["docker"])
        state, _, published, errors = tick(silent, state)
        self.assertEqual(published, [])
        self.assertIn("pi", errors[0])
        self.assertEqual(state["cursor"], NOW)
        # Ses lignes en retard arrivent après la panne : encore dans la fenêtre.
        back = FakeChecker(now=NOW + 7 * 3600, lines=[line(NOW + 300, host="pi")])
        self.assertEqual(len(tick(back, state)[2]), 1)
        self.assertEqual(back.starts, [NOW - 3600])

    def test_good_tick_after_a_failure_moves_the_cursor(self):
        state = {"cursor": NOW - 7200, "installed_at": NOW - 86400}
        self.assertEqual(tick(FakeChecker(), state)[0]["cursor"], NOW)


class Failures(unittest.TestCase):
    def test_github_down_raises_and_leaves_the_state_alone(self):
        state = {"cursor": NOW - 600, "seen": {}, "installed_at": NOW - 86400}
        before = json.dumps(state)
        checker = FakeChecker(lines=[line(NOW - 1000)])
        checker.fail_github = True
        with self.assertRaises(audit.CheckError):
            audit.tick(checker, state)
        self.assertEqual(checker.published, [])
        self.assertEqual(json.loads(before)["cursor"], state["cursor"])

    def test_truncated_lines_prove_nothing(self):
        checker = FakeChecker(lines=[line(NOW - 1000 - i) for i in range(100)])
        with self.assertRaisesRegex(audit.CheckError, "tronquée"):
            audit.tick(checker, {})


class RunPaging(audit.Checker):
    def __init__(self, pages):
        super().__init__(CONFIG, SECRETS, NOW)
        self.pages = pages
        self.queries = []

    def github(self, path, query=None):
        self.queries.append(query)
        return {"workflow_runs": self.pages[query["page"] - 1]}


class Paging(unittest.TestCase):
    def test_every_page_is_read(self):
        checker = RunPaging([[run(NOW, NOW)] * 100, [run(NOW, NOW)] * 3])
        self.assertEqual(len(checker.runs(NOW - 86400)), 103)
        self.assertEqual([query["page"] for query in checker.queries], [1, 2])
        self.assertEqual(checker.queries[0]["branch"], "main")
        self.assertEqual(checker.queries[0]["created"], ">=" + audit.rfc3339(NOW - 86400))

    def test_too_many_pages_prove_nothing(self):
        with self.assertRaisesRegex(audit.CheckError, "pages"):
            RunPaging([[run(NOW, NOW)] * 100] * 5).runs(NOW - 86400)


class HookGaps(unittest.TestCase):
    def state(self):
        return {"cursor": NOW - 3600, "installed_at": NOW - 86400}

    def deployed(self, lines=(), steps=None, **kwargs):
        checker = FakeChecker(lines=lines, runs=[run(NOW - 900, NOW - 800, run_id=7)], **kwargs)
        checker.steps[7] = steps or {"docker": "success", "pi": "skipped"}
        return checker

    def test_deployment_with_its_line_is_quiet(self):
        checker = self.deployed(lines=[line(NOW - 850)])
        state, _, published, _ = tick(checker, self.state())
        self.assertEqual(published, [])
        self.assertIn("7:1", state["checked_runs"])

    def test_deployment_without_any_line_warns_once(self):
        checker = self.deployed()
        state, _, published, errors = tick(checker, self.state())
        self.assertEqual(errors, [])
        self.assertIn("docker", published[0])
        self.assertEqual(checker.published[0][2], 4)
        self.assertIn("docker", checker.published[0][1])
        self.assertNotIn("pi", checker.published[0][1].split(":")[1].split(".")[0])
        again = self.deployed(now=NOW + 600)
        self.assertEqual(tick(again, state)[2], [])
        self.assertFalse([path for path in again.github_calls if path.endswith("/jobs")], "run déjà vérifié")

    def test_next_deployment_of_the_day_does_not_warn_again(self):
        state = tick(self.deployed(), self.state())[0]
        next_run = FakeChecker(now=NOW + 1800, runs=[run(NOW + 600, NOW + 700, run_id=8)])
        next_run.steps[8] = {"docker": "success"}
        self.assertEqual(tick(next_run, state)[2], [])

    def test_warning_repeats_after_a_day(self):
        state = tick(self.deployed(), self.state())[0]
        later = FakeChecker(now=NOW + 90000, runs=[run(NOW + 89000, NOW + 89100, run_id=9)])
        later.steps[9] = {"docker": "success"}
        self.assertEqual(len(tick(later, state)[2]), 1)

    def test_step_skipped_or_failed_expects_no_line(self):
        checker = self.deployed(steps={"docker": "skipped", "pi": "failure"})
        self.assertEqual(tick(checker, self.state())[2], [])

    def test_silent_host_postpones_the_run(self):
        checker = self.deployed(fresh=["pi"])
        state, _, published, _ = tick(checker, self.state())
        self.assertEqual(published, [])
        self.assertNotIn("7:1", state.get("checked_runs", {}))

    def test_silent_host_spends_no_job_lookup(self):
        checker = self.deployed(fresh=["pi"])
        tick(checker, self.state())
        self.assertFalse([path for path in checker.github_calls if path.endswith("/jobs")])

    def test_failed_job_lookup_does_not_hold_back_an_alert(self):
        checker = self.deployed(lines=[line(NOW - 3000)])
        checker.fail_jobs = True
        state, _, published, errors = tick(checker, self.state())
        self.assertEqual([item[2] for item in checker.published], [5])
        self.assertEqual(len(published), 1)
        self.assertEqual(errors, ["GitHub : quota épuisé"])
        self.assertNotIn("7:1", state["checked_runs"])
        self.assertLess(state["cursor"], NOW, "le curseur figé garde ce run")

    def test_run_just_finished_waits(self):
        checker = FakeChecker(runs=[run(NOW - 200, NOW - 100, run_id=7)])
        checker.steps[7] = {"docker": "success"}
        state, _, published, _ = tick(checker, self.state())
        self.assertEqual(published, [])
        self.assertNotIn("7:1", state["checked_runs"])

    def test_run_older_than_the_install_is_not_asked_for_lines(self):
        checker = FakeChecker(runs=[run(NOW - 900, NOW - 800, run_id=7)])
        checker.steps[7] = {"docker": "success"}
        _, _, published, _ = tick(checker, {"installed_at": NOW})
        self.assertEqual(published, [])
        self.assertFalse([path for path in checker.github_calls if path.endswith("/jobs")])

    def test_failed_warning_is_retried(self):
        checker = self.deployed()
        checker.fail_publish = True
        state, _, _, errors = tick(checker, self.state())
        self.assertEqual(errors, ["ntfy : HTTP 502"])
        self.assertNotIn("7:1", state["checked_runs"])

    def test_at_most_a_few_job_lookups_per_tick(self):
        runs = [run(NOW - 3000 + i, NOW - 2900 + i, run_id=100 + i) for i in range(audit.MAX_JOB_CHECKS + 5)]
        checker = FakeChecker(runs=runs)
        tick(checker, self.state())
        self.assertEqual(len([path for path in checker.github_calls if path.endswith("/jobs")]), audit.MAX_JOB_CHECKS)


class Response(io.BytesIO):
    def __enter__(self):
        return self

    def __exit__(self, *_):
        return False


def http_error(code, headers=None):
    message = mock.Mock()
    message.get = (headers or {}).get
    return urllib.error.HTTPError("http://secret.invalid/url", code, "x", message, None)


class Fetch(unittest.TestCase):
    def test_retries_a_5xx_then_succeeds(self):
        sleeps = []
        replies = [http_error(502), OSError("x"), Response(b"ok")]
        with mock.patch("urllib.request.urlopen", side_effect=replies):
            body = audit.fetch("X", "http://x.invalid", delays=(5, 20), sleep=sleeps.append)
        self.assertEqual((body, sleeps), (b"ok", [5, 20]))

    def test_gives_up_after_the_last_delay(self):
        with mock.patch("urllib.request.urlopen", side_effect=http_error(500)) as urlopen:
            with self.assertRaisesRegex(audit.CheckError, "HTTP 500"):
                audit.fetch("X", "http://x.invalid", delays=(1,), sleep=lambda _: None)
        self.assertEqual(urlopen.call_count, 2)

    def test_does_not_retry_a_4xx(self):
        with mock.patch("urllib.request.urlopen", side_effect=http_error(401)) as urlopen:
            with self.assertRaisesRegex(audit.CheckError, "HTTP 401"):
                audit.fetch("X", "http://x.invalid", delays=(1,), sleep=lambda _: None)
        self.assertEqual(urlopen.call_count, 1)

    def test_rate_limit_says_when_and_does_not_retry(self):
        error = http_error(403, {"X-RateLimit-Remaining": "0", "X-RateLimit-Reset": "1800000500"})
        with mock.patch("urllib.request.urlopen", side_effect=error) as urlopen:
            with self.assertRaisesRegex(audit.CheckError, "quota épuisé, retour à 1800000500"):
                audit.fetch("GitHub", "http://x.invalid", delays=(1,), sleep=lambda _: None)
        self.assertEqual(urlopen.call_count, 1)

    def test_error_never_quotes_the_url(self):
        error = urllib.error.URLError("http://secret.invalid/url")
        with mock.patch("urllib.request.urlopen", side_effect=error):
            with self.assertRaises(audit.CheckError) as caught:
                audit.fetch("X", "http://secret.invalid/url", sleep=lambda _: None)
        self.assertNotIn("secret", str(caught.exception))


class Requests(unittest.TestCase):
    def test_logs_are_queried_with_the_reader_account(self):
        checker = audit.Checker(CONFIG, {"vl_password": "faux"}, NOW)
        reply = Response(b'{"_time":"2027-01-15T08:00:00Z","host":"docker","_msg":"x"}\n')
        with mock.patch("urllib.request.urlopen", return_value=reply) as urlopen:
            lines = checker.login_lines(NOW - 3600)
        request = urlopen.call_args.args[0]
        self.assertEqual(lines[0]["host"], "docker")
        self.assertEqual(request.full_url, "http://logs.invalid/select/logsql/query")
        self.assertTrue(request.get_header("Authorization").startswith("Basic "))
        self.assertIn(b"limit=100", request.data)
        self.assertIn(b"ssh-login-notify", request.data)

    def test_push_url_goes_through_stdin_only(self):
        checker = audit.Checker(CONFIG, SECRETS, NOW)
        done = mock.Mock(returncode=0)
        with mock.patch("subprocess.run", return_value=done) as run_mock:
            self.assertTrue(checker.push("up", "résumé"))
        args = run_mock.call_args
        self.assertNotIn(SECRETS["push_url"], " ".join(args.args[0]))
        self.assertIn(SECRETS["push_url"], args.kwargs["input"])
        self.assertEqual(args.args[0][1:5], ["--strict", "--agent", "ci-key-audit", "-"])

    def test_empty_push_url_pushes_nothing(self):
        checker = audit.Checker(CONFIG, dict(SECRETS, push_url=""), NOW)
        with mock.patch("subprocess.run") as run_mock, mock.patch("sys.stderr", io.StringIO()):
            self.assertTrue(checker.push("up", "résumé"))
        run_mock.assert_not_called()

    def test_failed_push_is_false(self):
        checker = audit.Checker(CONFIG, SECRETS, NOW)
        with mock.patch("subprocess.run", return_value=mock.Mock(returncode=7)), mock.patch("sys.stderr", io.StringIO()):
            self.assertFalse(checker.push("up", "résumé"))


class Helpers(unittest.TestCase):
    def test_parse_time_accepts_nanoseconds(self):
        self.assertEqual(audit.parse_time("2027-01-15T08:00:00.123456789Z"), audit.parse_time("2027-01-15T08:00:00.123456Z"))

    def test_state_round_trip_and_damage(self):
        with tempfile.TemporaryDirectory() as folder:
            path = os.path.join(folder, "state.json")
            self.assertEqual(audit.load_state(path), {})
            audit.save_state(path, {"cursor": 1})
            self.assertEqual(audit.load_state(path), {"cursor": 1})
            with open(path, "w", encoding="utf-8") as file:
                file.write("{tronqué")
            with mock.patch("sys.stderr", io.StringIO()):
                self.assertEqual(audit.load_state(path), {})


class Main(unittest.TestCase):
    """main() : ce qui part vers le moniteur selon le passage."""

    def launch(self, checker, state=None):
        with tempfile.TemporaryDirectory() as folder:
            config = os.path.join(folder, "config.json")
            with open(config, "w", encoding="utf-8") as file:
                json.dump(CONFIG, file)
            with open(os.path.join(folder, "secrets.json"), "w", encoding="utf-8") as file:
                json.dump(SECRETS, file)
            path = os.path.join(folder, "state.json")
            if state is not None:
                with open(path, "w", encoding="utf-8") as file:
                    json.dump(state, file)
            env = {"CREDENTIALS_DIRECTORY": folder, "STATE_DIRECTORY": folder}
            with (
                mock.patch.object(audit, "CONFIG_FILE", config),
                mock.patch.dict(os.environ, env),
                mock.patch.object(audit, "Checker", lambda *_: checker),
                mock.patch("sys.stdout", io.StringIO()),
                mock.patch("sys.stderr", io.StringIO()),
            ):
                code = audit.main()
            saved = audit.load_state(path) if os.path.exists(path) else None
        return code, saved

    def test_clean_tick_pushes_up(self):
        checker = FakeChecker(lines=[line(NOW - 850)], runs=[run(NOW - 900, NOW - 800)])
        code, saved = self.launch(checker)
        self.assertEqual(code, 0)
        self.assertEqual([status for status, _ in checker.pushed], ["up"])
        self.assertEqual(saved["cursor"], NOW)

    def test_anomaly_pushes_down_with_the_alert_then_up_on_the_next_tick(self):
        checker = FakeChecker(lines=[line(NOW - 1000)])
        code, saved = self.launch(checker)
        self.assertEqual(code, 0)
        self.assertEqual(checker.pushed[0][0], "down")
        self.assertIn("192.0.2.7", checker.pushed[0][1])
        calm = FakeChecker(now=NOW + 600, lines=[line(NOW - 1000)])
        code, _ = self.launch(calm, saved)
        self.assertEqual((code, [status for status, _ in calm.pushed]), (0, ["up"]))

    def test_github_down_pushes_nothing_and_fails(self):
        checker = FakeChecker()
        checker.fail_github = True
        code, saved = self.launch(checker)
        self.assertEqual((code, checker.pushed, saved), (1, [], None))

    def test_silent_host_pushes_nothing_and_fails(self):
        checker = FakeChecker(fresh=["docker"])
        code, _ = self.launch(checker)
        self.assertEqual((code, checker.pushed), (1, []))

    def test_ntfy_down_pushes_the_alert_down_and_fails(self):
        checker = FakeChecker(lines=[line(NOW - 1000)])
        checker.fail_publish = True
        code, _ = self.launch(checker)
        self.assertEqual(code, 1)
        self.assertEqual(checker.pushed[0][0], "down")

    def test_failed_up_push_fails_the_unit_after_saving(self):
        checker = FakeChecker()
        checker.push = lambda *_: False
        code, saved = self.launch(checker)
        self.assertEqual((code, saved["cursor"]), (1, NOW))


if __name__ == "__main__":
    unittest.main()
