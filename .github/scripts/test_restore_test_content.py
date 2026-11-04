"""Tests of the content checks of restore_test.py ("expected_tables" of
.github/restore-test/apps.json; Lint workflow:
python -I -m unittest discover -s .github/scripts -p 'test_*.py')."""
import json
import pathlib
import shutil
import sqlite3
import subprocess
import tempfile
import unittest
from unittest import mock

import restore_test as rt

MANIFEST = json.loads((pathlib.Path(__file__).parents[1] / "restore-test" / "apps.json").read_text())
ENTRY = {"expected_tables": {"festival": ["edition"]}}


class IsDatabase(unittest.TestCase):
    def test_dump_by_its_name(self):
        self.assertTrue(rt.is_database("festival", "festival"))

    def test_sqlite_copy_by_its_file_name(self):
        self.assertTrue(rt.is_database("db.sqlite", "opt_apps_papra_app-data_db_db.sqlite"))

    def test_another_file_ending_alike_is_not_it(self):
        self.assertFalse(rt.is_database("db.sqlite", "opt_apps_papra_app-data_db_tasks.sqlite"))
        self.assertFalse(rt.is_database("db.db", "srv_data_foodb.db"))


class CheckExpectedPresent(unittest.TestCase):
    def test_present(self):
        rt.check_expected_present(ENTRY, ["festival"])

    def test_no_expected_tables(self):
        rt.check_expected_present({}, [])

    def test_second_database_of_a_kind_gone_fails(self):
        entry = {"expected_tables": {"festival": ["edition"], "keycloak": ["realm"]}}
        with self.assertRaisesRegex(rt.RestoreError, "keycloak : base de expected_tables absente"):
            rt.check_expected_present(entry, ["festival"])

    def test_one_of_two_sqlite_files_gone_fails(self):
        entry = {"expected_tables": {"data.db": ["users"]}}
        with self.assertRaisesRegex(rt.RestoreError, "data.db"):
            rt.check_expected_present(entry, ["srv_beszel_auxiliary.db"])


class CheckContent(unittest.TestCase):
    def test_expected_table_with_rows_passes_and_reports_counts(self):
        report = rt.check_content(ENTRY, "festival", "pg", {"edition": True, "autre": False})
        self.assertEqual(report, "pg : 2 tables, 1 non vides")

    def test_expected_table_missing_fails(self):
        with self.assertRaisesRegex(rt.RestoreError, "attendue absente \\(edition\\)"):
            rt.check_content(ENTRY, "festival", "pg", {"autre": True})

    def test_expected_table_empty_fails_even_if_another_has_rows(self):
        with self.assertRaisesRegex(rt.RestoreError, "attendue vide \\(edition\\)"):
            rt.check_content(ENTRY, "festival", "pg", {"edition": False, "autre": True})

    def test_no_table_fails(self):
        with self.assertRaisesRegex(rt.RestoreError, "aucune table"):
            rt.check_content({}, "x", "pg", {})

    def test_schema_without_any_row_fails(self):
        with self.assertRaisesRegex(rt.RestoreError, "aucune ligne"):
            rt.check_content({}, "x", "pg", {"a": False, "b": False})

    def test_allow_empty_covers_that_database_only(self):
        entry = {"allow_empty_databases": ["queue.db"]}
        rt.check_content(entry, "srv_queue.db", "s", {})
        rt.check_content(entry, "srv_queue.db", "s", {"tasks": False})
        with self.assertRaises(rt.RestoreError):
            rt.check_content(entry, "srv_db.db", "s", {"a": False})

    def test_allow_empty_does_not_waive_expected_tables(self):
        entry = {**ENTRY, "allow_empty_databases": ["festival"]}
        with self.assertRaisesRegex(rt.RestoreError, "attendue absente"):
            rt.check_content(entry, "festival", "pg", {})


class TablesWithRows(unittest.TestCase):
    def test_no_table_runs_no_query(self):
        query = mock.Mock()
        self.assertEqual(rt.tables_with_rows(query, {}), {})
        query.assert_not_called()

    def test_one_statement_mapped_back_to_the_names(self):
        query = mock.Mock(return_value="1\n")
        found = rt.tables_with_rows(query, {"b": '"b"', "a": '"a"'})
        self.assertEqual(found, {"a": False, "b": True})
        query.assert_called_once()

    def test_identifiers_are_quoted(self):
        self.assertEqual(rt.quoted("user"), '"user"')
        self.assertEqual(rt.quoted('a"b'), '"a""b"')
        self.assertEqual(rt.quoted("a`b", "`"), "`a``b`")


@unittest.skipUnless(shutil.which("sqlite3"), "sqlite3 absent")
class CheckSqlite(unittest.TestCase):
    def test_reads_rows_and_leaves_out_the_engine_tables(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = pathlib.Path(tmp) / "copy.db"
            with sqlite3.connect(path) as db:
                db.executescript('create table "user" (id integer primary key autoincrement);'
                                 'create table vide (id integer);'
                                 'insert into "user" default values;')
            with mock.patch("builtins.print"):
                self.assertEqual(rt.check_sqlite(path, "s"), {"user": True, "vide": False})


class Quiet(unittest.TestCase):
    def test_sqlite_queries_do_not_show_in_the_log(self):
        outputs = [subprocess.CompletedProcess([], 0, stdout=text, stderr="") for text in ("ok\n", "user\n", "0\n")]
        with mock.patch("subprocess.run", side_effect=outputs), mock.patch("builtins.print") as printed:
            self.assertEqual(rt.check_sqlite("/srv/secret_path.db", "s"), {"user": True})
        self.assertNotIn("secret_path", " ".join(str(arg) for c in printed.call_args_list for arg in c.args))


class Manifest(unittest.TestCase):
    def test_every_app_with_a_database_says_what_it_must_hold(self):
        for app, entry in MANIFEST.items():
            with self.subTest(app=app):
                expected = entry.get("expected_tables")
                self.assertEqual(bool(expected), bool(entry["databases"]))
                for key, tables in (expected or {}).items():
                    self.assertTrue(key)
                    self.assertTrue(tables)
                    self.assertTrue(all(isinstance(table, str) and table for table in tables))


if __name__ == "__main__":
    unittest.main()
