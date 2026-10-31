"""Tests of the expected databases of restore_test.py ("databases" of
.github/restore-test/apps.json; Lint workflow:
python -I -m unittest discover -s .github/scripts -p 'test_*.py')."""
import json
import pathlib
import re
import unittest

import restore_test as rt

ROOT = pathlib.Path(__file__).parents[2]
MANIFEST = json.loads((ROOT / ".github" / "restore-test" / "apps.json").read_text())
PG = ("postgresql", "immich", "x/postgresql_databases/immich_postgres/immich")
MY = ("mysql", "wiki", "x/mysql_databases/bookstack_db/bookstack")
COPY = ["var/lib/borgmatic-sqlite/trek/srv_trek_data_trek.db"]


class CheckDatabases(unittest.TestCase):
    def test_expected_dump_present(self):
        rt.check_databases({"databases": ["postgresql"]}, [PG], [])

    def test_expected_sqlite_present(self):
        rt.check_databases({"databases": ["sqlite"]}, [], COPY)

    def test_missing_dump_fails(self):
        with self.assertRaisesRegex(rt.RestoreError, "aucun dump ni copie postgresql"):
            rt.check_databases({"databases": ["postgresql"]}, [], [])

    def test_missing_sqlite_copy_fails(self):
        with self.assertRaisesRegex(rt.RestoreError, "aucun dump ni copie sqlite"):
            rt.check_databases({"databases": ["sqlite"]}, [], [])

    def test_wrong_engine_fails(self):
        with self.assertRaisesRegex(rt.RestoreError, "aucun dump ni copie mysql"):
            rt.check_databases({"databases": ["mysql"]}, [PG], [])

    def test_unexpected_dump_fails(self):
        with self.assertRaisesRegex(rt.RestoreError, "absent de databases"):
            rt.check_databases({"databases": ["sqlite"]}, [MY], COPY)

    def test_no_database_expected_and_none_found(self):
        rt.check_databases({"databases": []}, [], [])

    def test_missing_key_fails(self):
        with self.assertRaisesRegex(rt.RestoreError, "databases doit être"):
            rt.check_databases({}, [PG], [])

    def test_unknown_kind_fails(self):
        for value in (["postgres"], "postgresql", None, [{}], [["sqlite"]]):
            with self.subTest(value=value), self.assertRaises(rt.RestoreError):
                rt.check_databases({"databases": value}, [PG], [])


class Manifest(unittest.TestCase):
    # The role's borgmatic config (borgmatic_app_<kind>_databases in its
    # tasks) is what the archive holds: the manifest must say the same.
    # Not an explicit empty list: it backs up nothing of that kind.
    KIND_RE = re.compile(r"^\s*borgmatic_app_(postgresql|mysql|sqlite)_databases:(?!\s*\[\]\s*$)",
                         re.MULTILINE)

    def test_databases_match_the_role(self):
        for app, entry in MANIFEST.items():
            with self.subTest(app=app):
                self.assertIsInstance(entry.get("databases"), list)
                self.assertLessEqual(set(entry["databases"]), rt.DATABASE_KINDS)
                tasks = "\n".join(path.read_text() for path in
                                  (ROOT / "ansible" / "roles" / entry["role"] / "tasks").glob("*.y*ml"))
                self.assertEqual(sorted(set(entry["databases"])), sorted(set(self.KIND_RE.findall(tasks))))


if __name__ == "__main__":
    unittest.main()
