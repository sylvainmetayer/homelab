# 0033. Un PostgreSQL partagé sur la VM docker : pas maintenant

- **Statut** : proposée
- **Date** : 2026-11-10

## Contexte

Étude (aucun changement d'infra). Mesures du 2026-11-10 sur la VM docker (11,7 Gio, 1,4 Gio de swap utilisé, 4,7 Gio disponibles), compteurs cgroup en lecture. `pic` = `memory.peak` depuis le démarrage du conteneur (page cache compris) ; `anon+swap` = ce que l'instance occupe pour de bon ; `PSS` = mémoire résidente proportionnelle de ses processus.

| Base | Appli | Image | limite / réserv. | pic | anon+swap | PSS | Taille |
|---|---|---|---|---|---|---|---|
| jellystat-db | Jellystat | postgres 18.6 | 512 / 128 Mio | 156 | 17 | 30 | 18 Mo |
| healthlog-db | HealthLog | postgres 18.6 (+`pg_stat_statements`) | 1 Gio / 256 Mio | 209 | 27 | 75 | 50 Mo |
| dawarich-db | Dawarich | postgis 17-3.5 (PostGIS) | 3 Gio / 2 Gio | 3072 (= limite) | 85 | 222 | 5,1 Go |
| nextcloud_db | Nextcloud | mariadb 12.3.3 (LTS tenue) | 1 Gio / 512 Mio | 416 | 383 | 123 | 880 Mo |
| betisier_db, bookstack_db, monica_v4_db | Bétisier, BookStack, Monica | linuxserver/mariadb 11.8.9 | 512 / 512 / 768 Mio | 184, 109, 117 | 146, 96, 108 | 162, 7, 14 | 156, 275, 260 Mo |

Hors VM : Immich (Pi, PG 14 + VectorChord + pgvecto.rs), MediaManager (NAS, PG 17), Flip Planning (flip, PG 18.6) ne sont pas concernées. `shared_buffers` = 128 Mio partout (défaut), 3 à 4 connexions. Sur 11,7 Gio, les trois PostgreSQL pèsent 129 Mio d'`anon+swap` : le reste est du page cache, que le noyau partage déjà entre bases.

## Décision

Garder une instance par appli : pas de PostgreSQL partagé. **Statu quo**, à rouvrir si deux autres applis PG 18 sans extension arrivent.

Gain de mutualisation, **estimé** (PSS d'une instance au repos, pas mesuré sur une instance fusionnée) : une instance en moins économise ses ~10 processus et ses `shmem` (23 à 54 Mio), soit 30 à 75 Mio. Partielle (Jellystat + HealthLog, seules du même majeur 18 et sans extension) : 30 à 75 Mio, 0,3 à 0,6 % de la RAM, et 1,5 Gio de limites déclarées ramenés à 1 Gio. Complète (+ Dawarich) : au plus ~160 Mio (1,4 %), car ses 892 Mio de page cache et ses 5 Go restent ; il faudrait d'abord passer Dawarich de PG 17 à 18 avec une image PostGIS 18 (`pg_upgrade`, 5 Go).

## Alternatives écartées

- **Partielle** : Jellystat et HealthLog dans une instance. Coûts : le `pg_stat_statements` et le `shm_size` voulus par HealthLog vaudraient pour les deux ; une saturation de l'un gêne l'autre ; le prochain majeur PostgreSQL leur serait imposé le même jour ; chaque appli est un projet compose avec son `dc@<appli>`, la base commune serait un projet à part à démarrer avant elles, et son redémarrage coupe tout le monde ; `drill-restore-app` recrée et rejoue la base d'une appli dans sa propre instance, sur une instance commune il faudrait vérifier qu'il n'écrase pas celle d'une voisine ; un rôle PostgreSQL par base à créer et sauvegarder. Rejetée : 30 à 75 Mio ne paient pas cela. Renovate : les images restent épinglées par appli, une instance commune ferait de chaque majeur une migration de tout le monde (règle « stateful images » de `renovate.json`, déjà manuelle).
- **Complète** : même raisonnement, plus la montée de Dawarich, dont la lecture nocturne (2,9 à 6 Go, resource-limits.md) saturerait le disque lent des voisines. Rejetée.

## Conséquences

- Bon : isolation, restauration par appli et exercice (`drill-restore-app`) inchangés, droits par rôle PostgreSQL inutiles, aucune migration.
- Mauvais : ~30 à 75 Mio de RAM par PostgreSQL de plus, à chaque appli PG 18 nouvelle.
- Levier plus gros, hors du sujet : **MariaDB**. Trois instances en 11.8.9 occupent 96 à 146 Mio chacune (`anon+swap`, `innodb_buffer_pool_size` à 256 Mio) ; les fusionner libérerait ~200 Mio (estimé). Nextcloud reste seul (12.3 LTS). Étude séparée si la RAM manque.
- Dawarich est à son plafond de 3 Gio (`memory.peak`, page cache compris) : remesure en cours ailleurs, pas traitée ici.

## Liens

[0023](0023-limites-de-ressources.md), [resource-limits.md](../conventions/resource-limits.md), [reconstruction-vm-docker.md](../runbooks/reconstruction-vm-docker.md), `ansible/roles/borgmatic/README.md`.
