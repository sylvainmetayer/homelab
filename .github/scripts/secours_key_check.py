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
   doit échouer, sinon l'isolement ne tient pas et l'étape 2 ne prouve rien.

Tout réussi : `dernier_test`, en tête du runbook, passe à la date du jour
(relu ensuite par check_secret_rotation.py). La clé n'est que passée par son
chemin à age-keygen et à sops : jamais lue, copiée ni affichée par ce
script ; la sortie déchiffrée va à /dev/null, les erreurs de sops sont
jetées. Seules s'affichent des lignes `ok …` / `ÉCHEC …`.

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
LAST_TEST_RE = re.compile(r"^(dernier_test:\s*)\S+(.*)$")


def secours_keys(config_text):
    """Les clés publiques des lignes `# secours` de .sops.yaml."""
    return {m.group(1) for m in map(SECOURS_RE.match, config_text.splitlines()) if m}


def public_key(age_keygen, keyfile, run=subprocess.run):
    """Clé publique de la clé privée (age-keygen -y), None si age-keygen échoue."""
    result = run(
        [age_keygen, "-y", str(keyfile)],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        text=True,
        check=False,
    )
    if result.returncode != 0:
        return None
    lines = result.stdout.split()
    return lines[0] if len(lines) == 1 else None


def decrypts(sops, path, keyfile, run=subprocess.run):
    """True si `sops decrypt path` réussit avec la seule clé keyfile (environnement et HOME vides)."""
    with tempfile.TemporaryDirectory(prefix="secours-home-") as home:
        result = run(
            [sops, "decrypt", str(path)],
            env={"PATH": ISOLATED_PATH, "HOME": home, "SOPS_AGE_KEY_FILE": str(keyfile)},
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            check=False,
        )
    return result.returncode == 0


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
    lines[i] = LAST_TEST_RE.sub(lambda m: f"{m.group(1)}{today.isoformat()}{m.group(2)}", lines[i])
    return "\n".join(lines)


def check(keyfile, sops, age_keygen, root=ROOT, run=subprocess.run, out=print):
    """Les trois contrôles ; True si tout est bon. N'affiche que des lignes ok/ÉCHEC."""
    expected = secours_keys((root / SOPS_CONFIG).read_text(encoding="utf-8"))
    if len(expected) != 1:
        out(f"ÉCHEC {SOPS_CONFIG} : attendu une seule clé `# secours`, trouvé {len(expected)}")
        return False
    actual = public_key(age_keygen, keyfile, run)
    if actual is None:
        out("ÉCHEC clé publique : age-keygen -y n'a pas lu la clé (abîmée, ou pas une clé age)")
        return False
    if actual not in expected:
        out(f"ÉCHEC clé publique : {actual} n'est pas la clé `# secours` de {SOPS_CONFIG}")
        return False
    out(f"ok clé publique {actual} (# secours)")

    ok = True
    for name in SOPS_FILES:
        if decrypts(sops, root / name, keyfile, run):
            out(f"ok déchiffrement {name}")
        else:
            out(f"ÉCHEC déchiffrement {name}")
            ok = False
    for name in SOPS_FILES:
        if decrypts(sops, root / name, "/dev/null", run):
            out(f"ÉCHEC contre-épreuve {name} : déchiffré sans la clé, l'isolement ne tient pas")
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

    if not check(keyfile, sops, args.age_keygen, root, run, out):
        out(f"ÉCHEC test de la clé secours : dernier_test inchangé, voir « En cas d'échec » de {RUNBOOK}")
        return 1
    runbook = root / RUNBOOK
    runbook.write_text(set_last_test(runbook.read_text(encoding="utf-8"), args.today), encoding="utf-8")
    out(f"ok dernier_test = {args.today.isoformat()} dans {RUNBOOK} : à committer (PR)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
