"""Tests of renovate_digest.py: sorting the Renovate PRs, the failed deploy
runs, the message size and the failure path
(Lint workflow: python -I -m unittest discover -s .github/scripts -p 'test_*.py')."""

import datetime
import io
import os
import unittest
import urllib.error
from unittest import mock

import renovate_digest

NOW = datetime.datetime(2026, 11, 2, 13, 0, tzinfo=datetime.timezone.utc)


def merged(number, title, by="renovate"):
    return {"number": number, "title": title, "url": f"https://x/{number}", "mergedAt": "2026-11-01T08:00:00Z", "mergedBy": {"login": by}}


def opened(number, title, created, auto=False):
    return {
        "number": number,
        "title": title,
        "url": f"https://x/{number}",
        "createdAt": created,
        "isDraft": False,
        "autoMergeRequest": {"enabledAt": created} if auto else None,
    }


def answer(merged_nodes=(), open_nodes=(), merged_total=None):
    return {
        "merged": {"issueCount": len(merged_nodes) if merged_total is None else merged_total, "nodes": list(merged_nodes)},
        "open": {"issueCount": len(open_nodes), "nodes": list(open_nodes)},
    }


def runs(*numbers):
    return {
        "total_count": len(numbers),
        "workflow_runs": [
            {
                "run_number": n,
                "created_at": "2026-10-30T14:46:00Z",
                "event": "push",
                "display_title": f"fix: commit {n}",
                "html_url": f"https://github.com/o/r/actions/runs/{n}",
            }
            for n in numbers
        ],
    }


class BuildTest(unittest.TestCase):
    def test_automerged_and_manual_merges_are_split_and_grouped(self):
        report, _ = renovate_digest.build(
            answer(
                [
                    merged(1, "chore(deps): update planning-equipes main (demo_planning) to 12d83c7"),
                    merged(2, "chore(deps): update planning-equipes main (demo_planning) to be76643"),
                    merged(3, "chore(deps): update promptoramix main (flip) to 9e6040d", by="renovate[bot]"),
                    merged(4, "chore(deps): update docker.io/jellyfin/jellyfin docker tag to v12.4", by="sylvainmetayer"),
                ]
            ),
            runs(),
            "o/r",
            NOW,
        )
        message = report["message"]
        self.assertIn("Fusionnées automatiquement (3) :\n- update planning-equipes main (demo_planning) x2\n- update promptoramix main (flip)", message)
        self.assertIn("Fusionnées à la main (1) :\n- update docker.io/jellyfin/jellyfin docker tag", message)
        self.assertNotIn("12d83c7", message)
        self.assertEqual(report["priority"], 2)

    def test_open_pulls_oldest_first_with_age(self):
        report, _ = renovate_digest.build(
            answer(
                open_nodes=[
                    opened(9, "chore(deps): update vmauth docker tag to v1.155.0", "2026-11-02T08:00:00Z", auto=True),
                    opened(5, "chore(deps): update postgres docker tag to v19", "2026-10-20T13:00:00Z"),
                ]
            ),
            runs(),
            "o/r",
            NOW,
        )
        self.assertIn(
            "En attente de relecture (2) :\n- #5 update postgres docker tag to v19 : 13 j\n"
            "- #9 update vmauth docker tag to v1.155.0 : moins d'un jour (auto-merge en attente des checks)",
            report["message"],
        )
        self.assertEqual(report["priority"], 3)
        self.assertIn("author%3Aapp/renovate", report["click"])

    def test_failed_deploys_come_first_and_raise_the_priority(self):
        report, _ = renovate_digest.build(answer([merged(1, "chore(deps): update x to 1")]), runs(407, 336), "o/r", NOW)
        self.assertTrue(report["message"].startswith("Déploiements en échec (2) :\n- run #407 du 30/10 14:46 UTC (push) : fix: commit 407"))
        self.assertIn("https://github.com/o/r/actions/runs/336", report["message"])
        self.assertEqual((report["priority"], report["tags"]), (4, ["warning"]))

    def test_failures_caught_up_by_a_later_success_do_not_warn(self):
        failures = runs(336)
        failures["last_success"] = {"run_number": 340, "created_at": "2026-10-31T09:00:00Z"}
        report, _ = renovate_digest.build(answer(), failures, "o/r", NOW)
        self.assertIn("- run #336 du 30/10 14:46 UTC (push) (rattrapé par le run #340) :", report["message"])
        self.assertEqual((report["priority"], report["tags"]), (3, ["hourglass"]))

    def test_failure_after_the_last_success_still_warns(self):
        failures = runs(336)
        failures["last_success"] = {"run_number": 330, "created_at": "2026-10-29T09:00:00Z"}
        report, _ = renovate_digest.build(answer(), failures, "o/r", NOW)
        self.assertNotIn("rattrapé", report["message"])
        self.assertEqual(report["priority"], 4)

    def test_quiet_week(self):
        report, _ = renovate_digest.build(answer(), runs(), "o/r", NOW)
        self.assertIn("Rien cette semaine", report["message"])
        self.assertEqual(report["priority"], 2)

    def test_search_cap_is_stated(self):
        report, _ = renovate_digest.build(answer([merged(1, "chore(deps): update x to 1")], merged_total=140), runs(), "o/r", NOW)
        self.assertIn("140 PR fusionnées : les 1 plus récentes seules comptées.", report["message"])

    def test_long_message_is_cut_but_the_summary_keeps_everything(self):
        many = [merged(n, f"chore(deps): update package-number-{n:04d} docker tag to v1") for n in range(200)]
        report, full = renovate_digest.build(answer(many), runs(), "o/r", NOW)
        self.assertLessEqual(len(report["message"].encode()), renovate_digest.MAX_MESSAGE)
        self.assertIn("ligne(s) de plus : résumé du run", report["message"])
        self.assertIn("package-number-0199", full)

    def test_unexpected_answer_is_an_error(self):
        with self.assertRaises(renovate_digest.DigestError):
            renovate_digest.build({"merged": {}}, runs(), "o/r", NOW)

    def test_malformed_node_is_an_error(self):
        broken = runs(1)
        del broken["workflow_runs"][0]["html_url"]
        with self.assertRaises(renovate_digest.DigestError):
            renovate_digest.build(answer(), broken, "o/r", NOW)
        with self.assertRaises(renovate_digest.DigestError):
            renovate_digest.build(answer(open_nodes=[opened(1, "chore(deps): update x to 1", "2026-11-02")]), runs(), "o/r", NOW)

    def test_security_bumps_are_grouped_and_keep_their_marker(self):
        report, _ = renovate_digest.build(
            answer(
                [
                    merged(1, "fix(deps): update dependency foo to v1.2.3 [SECURITY]"),
                    merged(2, "fix(deps): update dependency foo to v1.2.4 [SECURITY]"),
                ]
            ),
            runs(),
            "o/r",
            NOW,
        )
        self.assertIn("- update dependency foo [SECURITY] x2", report["message"])

    def test_open_count_is_the_search_total(self):
        pulls = answer(open_nodes=[opened(5, "chore(deps): update x to 1", "2026-11-01T08:00:00Z")])
        pulls["open"]["issueCount"] = 120
        report, _ = renovate_digest.build(pulls, runs(), "o/r", NOW)
        self.assertIn("En attente de relecture (120) :", report["message"])


class MainTest(unittest.TestCase):
    def run_main(self, fetch, publish, env=None):
        environ = {"GITHUB_TOKEN": "gh-fake", "NTFY_TOKEN": "tk-fake"} | (env or {})
        with (
            mock.patch.dict(os.environ, environ, clear=True),
            mock.patch.object(renovate_digest, "fetch", fetch),
            mock.patch.object(renovate_digest, "publish", publish),
            mock.patch("sys.stdout", new_callable=io.StringIO) as stdout,
        ):
            code = renovate_digest.main(["--repo", "o/r"])
        return code, stdout.getvalue()

    def test_report_is_published_to_the_github_topic(self):
        publish = mock.Mock()
        code, _ = self.run_main(mock.Mock(return_value=(answer(), runs())), publish)
        self.assertEqual(code, 0)
        url, topic, token, report = publish.call_args.args
        self.assertEqual((url, topic, token), ("https://ntfy.sylvain.cloud", "github", "tk-fake"))
        self.assertIn("Rien cette semaine", report["message"])

    def test_api_failure_still_publishes_and_fails_the_run(self):
        publish = mock.Mock()
        error = urllib.error.HTTPError("https://api.github.com/graphql", 502, "Bad Gateway", None, None)
        code, out = self.run_main(mock.Mock(side_effect=error), publish)
        self.assertEqual(code, 1)
        self.assertIn("HTTP 502", publish.call_args.args[3]["message"])
        self.assertIn("::error::API GitHub : HTTP 502", out)

    def test_malformed_answer_still_publishes_and_fails_the_run(self):
        publish = mock.Mock()
        broken = runs(1)
        del broken["workflow_runs"][0]["run_number"]
        code, out = self.run_main(mock.Mock(return_value=(answer(), broken)), publish)
        self.assertEqual(code, 1)
        self.assertIn("réponse inattendue", publish.call_args.args[3]["message"])

    def test_ntfy_failure_fails_the_run_without_quoting_the_request(self):
        code, out = self.run_main(mock.Mock(return_value=(answer(), runs())), mock.Mock(side_effect=OSError("tk-fake leaked")))
        self.assertEqual(code, 1)
        self.assertIn("publication sur ntfy en échec : OSError", out)
        self.assertNotIn("tk-fake", out)

    def test_missing_ntfy_token_fails_the_run(self):
        publish = mock.Mock()
        code, _ = self.run_main(mock.Mock(return_value=(answer(), runs())), publish, {"NTFY_TOKEN": ""})
        self.assertEqual(code, 1)
        publish.assert_not_called()


if __name__ == "__main__":
    unittest.main()
