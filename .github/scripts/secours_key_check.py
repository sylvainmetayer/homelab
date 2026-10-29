#!/usr/bin/env python3
"""Test trimestriel de la clé age hors ligne `secours` (docs/runbooks/test-cle-secours.md).

Ce que le runbook faisait à la main (gardé en secours dans « À la main ») :

1. `age-keygen -y <clé>` doit donner la clé publique des lignes `# secours`
   de .sops.yaml ;
2. chaque fichier SOPS doit se déchiffrer avec cette clé seule : `sops
   decrypt` lancé dans un environnement vide (ni SOPS_AGE_KEY ni
   l'environnement de mise) avec un HOME temporaire vide (pas de
   ~/.config/sops/age/keys.txt ni de ~/.ssh/id_ed25519), sortie jetée ;
3. contre-épreuve : le même déchiffrement avec SOPS_AGE_KEY_FILE=/dev/null
   doit échouer sur « Failed to get the data key », sinon l'isolement ne
   tient pas (ou n'est pas prouvé) et l'étape 2 ne prouve rien.

Tout réussi : `dernier_test`, en tête du runbook, passe à la date du jour
(relu ensuite par check_secret_rotation.py). La clé n'est que passée par son
chemin à age-keygen et à sops : jamais lue, copiée ni affichée par ce
script ; la sortie déchiffrée va à /dev/null, les erreurs de sops sont
jetées (celles de la contre-épreuve, sans clair possible, lues pour la raison
du refus, jamais affichées). Seules s'affichent des lignes `ok …` / `ÉCHEC …`.

Usage (depuis la racine du dépôt) : mise run test-cle-secours <fichier de clé>
ou, sans mise : python3 -I .github/scripts/secours_key_check.py <fichier de clé>
"""

import argparse
import datetime
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SOPS_CONFIG = ".sops.yaml"
SOPS_FILES = ("secrets.sops.yaml", "ansible/secrets.sops.yaml")
RUNBOOK = "docs/runbooks/test-cle-secours.md"
ISOLATED_PATH = "/usr/bin:/bin"
SECOURS_RE = re.compile(r"^\s*-\s*(age1[0-9a-z]+)\s+#\s*secours\s*$")
# Le motif de check_secret_rotation.py (épinglé par le test) : -I implique -P,
# le script voisin ne s'importe pas.
LAST_TEST_RE = re.compile(r"^dernier_test:\s*([^\s#]*)\s*(?:#.*)?$")
# Le refus attendu de la contre-épreuve : aucune clé n'ouvre la clé de données.
# Tout autre échec de sops ne prouve pas l'isolement.
NO_DATA_KEY = "Failed to get the data key"


def secours_keys(config_text):
    """Les clés publiques des lignes `# secours` de .sops.yaml."""
    return {m.group(1) for m in map(SECOURS_RE.match, config_text.splitlines()) if m}


def public_keys(age_keygen, keyfile, run=subprocess.run):
    """Clés publiques des identités du fichier (age-keygen -y), None si age-keygen échoue."""
    result = run(
        [age_keygen, "-y", str(keyfile)],
        env={"PATH": ISOLATED_PATH},
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        text=True,
        check=False,
    )
    if result.returncode != 0:
        return None
    return result.stdout.split()


def decrypt(sops, path, keyfile, run=subprocess.run, stderr=subprocess.DEVNULL):
    """`sops decrypt path` avec la seule clé keyfile (environnement et HOME vides), sortie jetée.

    stderr=PIPE seulement pour la contre-épreuve (aucun clair ne peut s'y
    trouver, et il n'est jamais affiché)."""
    with tempfile.TemporaryDirectory(prefix="secours-home-") as home:
        return run(
            [sops, "decrypt", str(path)],
            env={"PATH": ISOLATED_PATH, "HOME": home, "SOPS_AGE_KEY_FILE": str(keyfile)},
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=stderr,
            text=True,
            check=False,
        )


def set_last_test(text, today):
    """Le runbook avec `dernier_test` (front matter) à today ; ValueError si la ligne manque."""
    lines = text.split("\n")
    if not lines or lines[0] != "---" or "---" not in lines[1:]:
        raise ValueError(f"{RUNBOOK} : front matter `---` absent en tête")
    end = lines.index("---", 1)
    hits = [i for i in range(1, end) if LAST_TEST_RE.match(lines[i])]
    if len(hits) != 1:
        raise ValueError(f"{RUNBOOK} : attendu une ligne `dernier_test:` dans le front matter")
    i = hits[0]
    m = LAST_TEST_RE.match(lines[i])
    lines[i] = f"{lines[i][: m.start(1)]}{today.isoformat()}{lines[i][m.end(1) :]}"
    return "\n".join(lines)


def check(keyfile, sops, age_keygen, root=ROOT, run=subprocess.run, out=print):
    """Les trois contrôles ; True si tout est bon. N'affiche que des lignes ok/ÉCHEC."""
    expected = secours_keys((root / SOPS_CONFIG).read_text(encoding="utf-8"))
    if len(expected) != 1:
        out(f"ÉCHEC {SOPS_CONFIG} : attendu une seule clé `# secours`, trouvé {len(expected)}")
        return False
    actuals = public_keys(age_keygen, keyfile, run)
    if not actuals:
        out("ÉCHEC clé publique : age-keygen -y n'a pas lu la clé (abîmée, ou pas une clé age)")
        return False
    if len(actuals) != 1:
        # Une autre identité du fichier (perso…) déchiffrerait à la place de secours.
        out(f"ÉCHEC clé publique : {len(actuals)} identités dans le fichier, attendu la seule clé secours")
        return False
    actual = actuals[0]
    if actual not in expected:
        out(f"ÉCHEC clé publique : {actual} n'est pas la clé `# secours` de {SOPS_CONFIG}")
        return False
    out(f"ok clé publique {actual} (# secours)")

    ok = True
    for name in SOPS_FILES:
        if decrypt(sops, root / name, keyfile, run).returncode == 0:
            out(f"ok déchiffrement {name}")
        else:
            out(f"ÉCHEC déchiffrement {name}")
            ok = False
    for name in SOPS_FILES:
        result = decrypt(sops, root / name, "/dev/null", run, stderr=subprocess.PIPE)
        if result.returncode == 0:
            out(f"ÉCHEC contre-épreuve {name} : déchiffré sans la clé, l'isolement ne tient pas")
            ok = False
        elif NO_DATA_KEY not in (result.stderr or ""):
            out(f"ÉCHEC contre-épreuve {name} : sops a échoué sans « {NO_DATA_KEY} », l'isolement n'est pas prouvé")
            ok = False
        else:
            out(f"ok contre-épreuve {name} (sans la clé : refusé)")
    return ok


def main(argv=None, root=ROOT, run=subprocess.run, out=print):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("keyfile", type=Path, help="fichier de la clé age secours (clé USB montée)")
    parser.add_argument("--sops", default=shutil.which("sops"), help="binaire sops (défaut : celui du PATH)")
    parser.add_argument("--age-keygen", default=shutil.which("age-keygen"), help="binaire age-keygen")
    parser.add_argument("--today", type=datetime.date.fromisoformat, default=datetime.date.today())
    args = parser.parse_args(argv)

    for label, binary in (("sops", args.sops), ("age-keygen", args.age_keygen)):
        if not binary:
            out(f"ÉCHEC {label} introuvable dans le PATH (mise install, ou --{label} $(mise which {label}))")
            return 1
    keyfile = args.keyfile.resolve()
    if not keyfile.is_file():
        out(f"ÉCHEC {args.keyfile} : pas un fichier lisible")
        return 1
    # sops tourne avec PATH=/usr/bin:/bin : il faut le vrai binaire, pas un
    # shim de mise (qui ne trouverait plus mise ni sa configuration).
    sops = str(Path(args.sops).absolute())
    if "/shims/" in sops:
        out(f"ÉCHEC {sops} est un shim de mise : passer --sops $(mise which sops)")
        return 1

    try:
        passed = check(keyfile, sops, args.age_keygen, root, run, out)
    except OSError as err:
        out(f"ÉCHEC {err.filename or 'binaire'} : {err.strerror or err} (chemin de sops ou d'age-keygen ?)")
        passed = False
    if not passed:
        out(f"ÉCHEC test de la clé secours : dernier_test inchangé, voir « En cas d'échec » de {RUNBOOK}")
        return 1
    runbook = root / RUNBOOK
    try:
        updated = set_last_test(runbook.read_text(encoding="utf-8"), args.today)
    except ValueError as err:
        out(f"ÉCHEC {err} : test réussi, mettre dernier_test à {args.today.isoformat()} à la main")
        return 1
    runbook.write_text(updated, encoding="utf-8")
    out(f"ok dernier_test = {args.today.isoformat()} dans {RUNBOOK} : à committer (PR)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
