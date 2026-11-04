"""Tests de borgmatic-docker-dump (rôle borgmatic), lancés par verify.yml du
scénario avec le python3 de l'hôte de test : le script tourne pour de bon sous
bash, avec un faux docker qui note ses arguments et son entrée. Le verify le
joue une fois avec et une fois sans mot de passe ; ici, les formes d'arguments
et l'échappement du fichier d'options. À la main : copier ce fichier à côté de
ansible/roles/borgmatic/files/borgmatic-docker-dump, puis
python3 -I -m unittest discover -s . -p 'test_*.py'.
"""

import os
import stat
import subprocess
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
SCRIPT = HERE / "borgmatic-docker-dump"
EXTRA_FILE = "--defaults-extra-file=/dev/stdin"
VALEUR = "valeur-fictive"


class DumpTest(unittest.TestCase):
    def setUp(self):
        # À côté du test, pas /tmp : le faux docker doit pouvoir s'y exécuter.
        directory = tempfile.TemporaryDirectory(dir=HERE)
        self.addCleanup(directory.cleanup)
        self.dir = Path(directory.name)
        self.result_file = self.dir / "tube"
        self.docker(0)

    def docker(self, code):
        path = self.dir / "docker"
        path.write_text(
            "#!/bin/bash\n"
            f'printf "%s\\n" "$@" > "{self.dir}/argv"\n'
            f'env > "{self.dir}/env"\n'
            f'[[ " $* " == *" -i "* ]] && cat > "{self.dir}/stdin"\n'
            "echo contenu-du-dump\n"
            f"exit {code}\n",
            encoding="utf-8",
        )
        path.chmod(path.stat().st_mode | stat.S_IXUSR)

    def dump(self, *args, password=None):
        env = {key: value for key, value in os.environ.items() if key != "MYSQL_PWD"}
        env["PATH"] = f"{self.dir}:{env['PATH']}"
        if password is not None:
            env["MYSQL_PWD"] = password
        return subprocess.run(
            ["bash", str(SCRIPT), *args],
            capture_output=True,
            text=True,
            env=env,
            stdin=subprocess.DEVNULL,
            check=False,
            timeout=30,
        )

    def argv(self):
        return (self.dir / "argv").read_text(encoding="utf-8").splitlines()

    def stdin(self):
        return (self.dir / "stdin").read_text(encoding="utf-8")

    def test_usage(self):
        result = self.dump("conteneur")
        self.assertEqual(result.returncode, 2)
        self.assertIn("usage", result.stderr)
        self.assertFalse((self.dir / "argv").exists())

    def test_no_password_runs_the_client_as_is(self):
        result = self.dump("db", "mariadb-dump", "--databases", "app")
        self.assertEqual(result.returncode, 0)
        self.assertEqual(result.stdout, "contenu-du-dump\n")
        self.assertEqual(self.argv(), ["exec", "db", "mariadb-dump", "--databases", "app"])

    def test_empty_password_is_no_password(self):
        self.dump("db", "mariadb-dump", password="")
        self.assertNotIn(EXTRA_FILE, self.argv())

    def test_no_argument_for_the_client(self):
        self.assertEqual(self.dump("db", "mariadb-dump").returncode, 0)
        self.assertEqual(self.argv(), ["exec", "db", "mariadb-dump"])

    def test_result_file_in_both_forms_stays_on_the_host(self):
        for args in (["--result-file", str(self.result_file)], [f"--result-file={self.result_file}"]):
            with self.subTest(args=args):
                self.result_file.unlink(missing_ok=True)
                result = self.dump("db", "mariadb-dump", "--a", *args, "--b")
                self.assertEqual(result.returncode, 0)
                self.assertEqual(self.argv(), ["exec", "db", "mariadb-dump", "--a", "--b"])
                self.assertEqual(self.result_file.read_text(encoding="utf-8"), "contenu-du-dump\n")
                self.assertEqual(result.stdout, "")

    def test_arguments_with_spaces_stay_whole(self):
        self.dump("db", "mariadb-dump", "--where=a b")
        self.assertEqual(self.argv()[-1], "--where=a b")

    def test_password_goes_through_stdin_never_argv_nor_env(self):
        result = self.dump("db", "mariadb-dump", "--databases", "app", password=VALEUR)
        self.assertEqual(result.returncode, 0)
        # L'option doit être la première du client.
        self.assertEqual(self.argv(), ["exec", "-i", "db", "mariadb-dump", EXTRA_FILE, "--databases", "app"])
        self.assertEqual(self.stdin(), f'[client]\npassword="{VALEUR}"\n')
        self.assertNotIn("MYSQL_PWD", (self.dir / "env").read_text(encoding="utf-8"))

    def test_password_escaping(self):
        cases = {
            # Sans sens particulier entre guillemets doubles : gardés tels quels.
            "a#b;c'd e": "a#b;c'd e",
            'a"b': 'a\\"b',
            "a\\b": "a\\\\b",
            # « \ » d'abord : celui qu'ajoute l'échappement de « " » n'est pas redoublé.
            '\\"': '\\\\\\"',
            "a\nb": "a\\nb",
            # « \n » littéral : deux caractères, pas un saut de ligne une fois relu.
            "a\\nb": "a\\\\nb",
            "%s%d": "%s%d",
        }
        for password, escaped in cases.items():
            with self.subTest(password=password):
                self.dump("db", "mariadb-dump", password=password)
                self.assertEqual(self.stdin(), f'[client]\npassword="{escaped}"\n')

    def test_client_failure_fails_the_script_with_or_without_password(self):
        self.docker(3)
        for password in (None, VALEUR):
            with self.subTest(password=password):
                self.assertEqual(self.dump("db", "mariadb-dump", password=password).returncode, 3)

    def test_client_failure_with_a_result_file(self):
        self.docker(3)
        result = self.dump("db", "mariadb-dump", "--result-file", str(self.result_file), password=VALEUR)
        self.assertEqual(result.returncode, 3)


if __name__ == "__main__":
    unittest.main()
