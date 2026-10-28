#!/usr/bin/env bash
# Mots de passe d'application Nextcloud : quels clients parlent à Nextcloud,
# ont-ils déjà un mot de passe d'application, et en créer un. Procédure :
# nextcloud-mots-de-passe-application.md (même dossier).
#
#   ./nextcloud-app-passwords.sh                     audit (rien n'est modifié)
#   ./nextcloud-app-passwords.sh add <user> <nom>    crée un mot de passe d'application
#   ./nextcloud-app-passwords.sh delete <user> <id>  supprime un jeton (id de l'audit)
#
# À lancer dans un terminal à soi (pas par un agent) : « add » affiche le mot
# de passe en clair, une seule fois. NC_HOST (VM docker) et KNOWN_HOSTS se
# changent par l'environnement.
set -euo pipefail

HOST=${NC_HOST:-192.168.1.216}
KNOWN_HOSTS=${KNOWN_HOSTS:-$(dirname "$(readlink -f "$0")")/../../ansible/known_hosts}
SSH=(ssh -o UserKnownHostsFile="$KNOWN_HOSTS" -o StrictHostKeyChecking=yes "sylvain@$HOST")
# ssh recolle ses arguments en une ligne que le shell distant redécoupe : un
# nom de jeton à espaces (« GNOME Online Accounts ») deviendrait trois
# arguments. Chacun est donc remis entre apostrophes.
quote() { local a; for a; do printf "'%s' " "${a//\'/\'\\\'\'}"; done; }
occ() { "${SSH[@]}" "sudo docker exec nextcloud occ $(quote "$@")"; }

case "${1:-audit}" in
add)
  user=${2:?user}; name=${3:?nom du client, ex. "DAVx5 Pixel"}
  # Sans --password-from-env : jeton sans le mot de passe de connexion
  # (suffisant pour DAV/WebDAV ; seul le flux de connexion web en a besoin).
  occ user:auth-tokens:add --no-interaction --name "$name" "$user"
  echo "→ à coller dans le client, avec l'identifiant « $user »."
  ;;
delete)
  occ user:auth-tokens:delete "${2:?user}" "${3:?id}"
  ;;
audit)
  tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
  occ user:list --output=json > "$tmp/users.json"
  # Un uid Nextcloud peut contenir une espace : une ligne par compte, et
  # ssh sans stdin (il avalerait le reste de la liste).
  while IFS= read -r u; do
    occ user:auth-tokens:list "$u" --output=json < /dev/null > "$tmp/tokens.$u.json"
  done < <(python3 -I -c 'import json,sys; print("\n".join(json.load(open(sys.argv[1]))))' "$tmp/users.json")
  # Requêtes DAV/OCS de tous les journaux gardés (rotation hebdomadaire, 14
  # anciens : jusqu'à ~15 semaines) : utilisateur (Basic ou jeton), date,
  # agent. Le tri se fait dans le conteneur : ni IP ni URL ne sort de la VM.
  "${SSH[@]}" sudo docker exec -i nextcloud sh -s <<'SH' > "$tmp/log.tsv"
for f in /config/log/nginx/access.log*; do
  case $f in *.gz) gzip -dc "$f" ;; *) cat "$f" ;; esac
done 2>/dev/null | grep -E '"[A-Z]+ /(remote\.php|ocs|index\.php/apps/[a-z_]+/api)' \
  | awk -F'"' '{split($1,a," "); print a[3] "\t" substr(a[4],2,11) "\t" $6}' || true
SH
  python3 -I - "$tmp" <<'PY'
import json, sys, os, re, time
from collections import defaultdict
tmp = sys.argv[1]
# Agent → famille de client, et mots attendus dans le nom de son jeton.
FAMILIES = [
    ("DAVx5",          r"DAVx5|davdroid",            r"davx|davdroid"),
    ("Nextcloud Android", r"Nextcloud-android",      r"android"),
    ("Nextcloud desktop", r"mirall|Nextcloud-desktop", r"desktop|mirall|linux|fedora|windows|mac"),
    ("Thunderbird",    r"Thunderbird",               r"thunderbird"),
    ("Evolution",      r"Evolution",                 r"evolution"),
    ("GNOME Online Accounts", r"gnome-online-accounts", r"gnome|goa"),
    ("rclone",         r"rclone",                    r"rclone"),
    ("davfs2",         r"davfs2",                    r"davfs"),
    ("Go (script)",    r"Go-http-client",            r"\bgo\b|script|meerkat"),
    ("Exchange/Outlook", r"Microsoft Exchange|Outlook", r"outlook|exchange"),
]
def family(ua):
    for name, pat, _ in FAMILIES:
        if re.search(pat, ua, re.I): return name
    return None
seen = defaultdict(lambda: [0, ""])  # (user, famille) -> [requêtes, dernier jour]
days = set()
for line in open(os.path.join(tmp, "log.tsv"), errors="replace"):
    try:
        user, day, ua = line.rstrip("\n").split("\t", 2)
        day = time.strftime("%Y-%m-%d", time.strptime(day, "%d/%b/%Y"))
    except ValueError: continue
    days.add(day)
    fam = family(ua)
    if user in ("-", "") or not fam: continue
    s = seen[(user, fam)]; s[0] += 1; s[1] = max(s[1], day)
users = json.load(open(os.path.join(tmp, "users.json")))
span = f"du {min(days)} au {max(days)}" if days else "vides"
print(f"=== Clients vus dans les journaux ({span}) ===")
for (user, fam), (n, last) in sorted(seen.items()):
    if user not in users:
        # Basic porte le nom de connexion : une adresse e-mail n'est pas l'uid.
        print(f"- {user:10} {fam:22} {n:6} req., dernier {last}  compte inconnu de user:list"
              " (connexion par e-mail ?) : à vérifier à la main")
        continue
    toks = json.load(open(os.path.join(tmp, f"tokens.{user}.json")))
    words = next(w for f, _, w in FAMILIES if f == fam)
    match = [t for t in toks if t.get("type") == 1 and re.search(words, t.get("name", ""), re.I)]
    if match:
        verdict = "OK, mot de passe d'application : " + ", ".join(f"#{t['id']} « {t['name']} »" for t in match)
    else:
        # Un jeton actif le même jour que le dernier passage du client est un
        # candidat (nommé autrement) ; sinon, le mot de passe de connexion.
        same = [t for t in toks if t.get("type") == 1
                and time.strftime("%Y-%m-%d", time.localtime(t.get("lastActivity", 0))) == last]
        verdict = ("à vérifier, jeton actif le même jour : " + ", ".join(f"#{t['id']} « {t['name']} »" for t in same)) if same \
            else "AUCUN mot de passe d'application → sans doute le mot de passe de connexion : à migrer"
    print(f"- {user:10} {fam:22} {n:6} req., dernier {last}  {verdict}")
print("\n=== Mots de passe d'application existants (type 1) ===")
for user in users:
    for t in json.load(open(os.path.join(tmp, f"tokens.{user}.json"))):
        if t.get("type") != 1: continue
        last = time.strftime("%Y-%m-%d", time.localtime(t.get("lastActivity", 0)))
        print(f"- {user:10} #{t['id']:<6} {t.get('name','')[:70]:70} dernière activité {last}")
print("\nLa correspondance se fait sur le nom du jeton : un « OK » douteux se vérifie"
      "\ndans le client (Réglages → compte) ou par la dernière activité du jeton.")
PY
  ;;
*) echo "usage: $0 [audit | add <user> <nom> | delete <user> <id>]" >&2; exit 2 ;;
esac
