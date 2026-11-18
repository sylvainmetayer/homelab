# Compacter la base SQLite de Pangolin (VACUUM)

Procédure, pas un incident. La base `/opt/pangolin/config/db/db.sqlite` ne
rétrécit jamais seule (`auto_vacuum = 0`) : après une baisse de la rétention des
journaux (`tofu/pangolin_config/org.tf`), les lignes effacées laissent des pages
libres que SQLite réutilise, sans rendre la place au disque. Un `VACUUM` réécrit
le fichier sans elles.

Jouée le 18/11/2026, six jours après le passage de la rétention du journal des
requêtes de 30 à 7 jours : 924 569 600 → 631 439 360 octets (−293 Mo),
Pangolin arrêté **1 min 15**.

## Faut-il le faire

Rien ne presse tant que le disque de la VM a de la place : sans `VACUUM`, la
base cesse seulement de grossir. Mesurer d'abord, en lecture seule, Pangolin en
marche :

```bash
sudo python3 -c "import sqlite3; c=sqlite3.connect('file:/opt/pangolin/config/db/db.sqlite?mode=ro', uri=True); print({p: c.execute('pragma '+p).fetchone()[0] for p in ('page_size','page_count','freelist_count')})"
```

`freelist_count × page_size` est la place qu'un `VACUUM` rendrait (69 941 pages
de 4096 octets le 18/11, soit 286 Mo, 31 % du fichier). En dessous de quelques
dizaines de Mo, ne rien faire.

Ne pas comparer deux tailles lues dans deux unités : 924 Mo (décimaux) et
882 Mio sont le même fichier (confusion du 13/11).

## Ce que ça coupe

Pangolin arrêté, Traefik et Gerbil restent en marche, mais badger ne peut plus
vérifier les sessions : toutes les applis derrière le mur SSO répondent en
erreur le temps de l'arrêt, ntfy et Pocket ID compris pour ce qui passe par
Pangolin. Les tunnels Newt se reconnectent seuls au redémarrage. À faire entre
08:00 et 19:00, hors d'un déploiement de la CI sur Pangolin.

Il faut sur le disque la taille de la base en libre, deux fois : la copie
d'avant, et le fichier temporaire du `VACUUM`.

## Procédure

Sur la VM Pangolin, en root. Le `trap` redémarre Pangolin quoi qu'il arrive.

```bash
set -euo pipefail
cd /opt/pangolin
DB=config/db/db.sqlite
COPIE=config/db/backups/db_$(date +%F_%H-%M-%S)_avant-vacuum.sqlite

trap 'docker compose start pangolin' EXIT
docker compose stop pangolin

# Ouvrir la base replie le -wal resté après l'arrêt : la copie est alors complète.
sqlite3 "$DB" 'PRAGMA wal_checkpoint(TRUNCATE);'
cp -p "$DB" "$COPIE"
[ "$(sqlite3 "$DB" 'PRAGMA integrity_check;')" = ok ] || { echo "intégrité KO avant VACUUM, rien fait" >&2; exit 1; }

sqlite3 "$DB" 'VACUUM;'
if [ "$(sqlite3 "$DB" 'PRAGMA integrity_check;')" != ok ]; then
  echo "intégrité KO après VACUUM : copie remise" >&2
  rm -f "$DB-wal" "$DB-shm"
  cp -p "$COPIE" "$DB"
  exit 1
fi
sqlite3 "$DB" 'PRAGMA journal_mode; PRAGMA freelist_count;'   # wal, 0
ls -l "$DB" "$COPIE"
```

Depuis le poste, le même script passe par Ansible :
`ansible pangolin -m script --become -a <fichier>` depuis `ansible/`.

## Vérifier

- `docker compose ps` dans `/opt/pangolin` : `pangolin` revient `healthy` en
  moins d'une minute (22 s le 18/11).
- `https://hall.sylvain.cloud` répond 200, une appli derrière le mur 401 sans
  session.
- Le mode du journal est toujours `wal` (`VACUUM` le garde) : la sauvegarde
  borgmatic en dépend ([README de borgmatic](../../ansible/roles/borgmatic/README.md)).

## Retour arrière

La copie d'avant reste dans `config/db/backups/`, purgée au bout de 30 jours
par `tmpfiles` comme les copies de migration
([README du rôle](../../ansible/roles/pangolin/README.md)). Pour la remettre :
`docker compose stop pangolin`, effacer `db.sqlite-wal` et `db.sqlite-shm`,
recopier la copie sur `db.sqlite`, `docker compose start pangolin`. Tout ce que
Pangolin a écrit depuis le `VACUUM` est perdu.
