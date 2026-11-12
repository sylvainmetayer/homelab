# Rôle betisier

Bêtisier (VM docker, `betisier.sylvain.cloud`, public sans SSO) : l'appli (`betisier`) et sa base MariaDB jetable (`betisier_db`, image `linuxserver/mariadb`).

## Base jetable en mémoire

`betisier_db` repart du dump `./dump.sql` (téléchargé, somme épinglée) à chaque démarrage de conteneur ; `betisier-reset.timer` en fait un démarrage à neuf chaque nuit. Son `/config` (base, `custom.cnf`, journaux) est donc un **tmpfs** (`size=256m`, `noexec`), pas un volume : rien n'est écrit sur le SSD, rien sous `/var/lib/docker/volumes` (surveillé en récursif par auditd), et le `down` du reset suffit (plus de `-v`).

- Le tmpfs se vide à **chaque** arrêt du conteneur (déploiement, redémarrage, Renovate), pas seulement au reset de la nuit : le mot de passe de démonstration (`UPDATE personne`) est donc un second fichier d'`initdb.d` (`reset-password.sql`, chargé après le dump), et non plus une étape du reset.
- Taille mesurée (image épinglée, dump de 19 Ko, 13 personnes, 6 citations) : 160 Mio utilisés après chargement, dont le redo log InnoDB de 96 Mio (défaut de MariaDB 11.8), `ibdata1` 12, `ibtmp1` 12, trois `undo` de 10. 256 Mio laissent de la marge à `ibtmp1` ; plein, le tmpfs fait échouer la base (pas de swap disque à épuiser).
- Mémoire : un tmpfs compte dans le cgroup du conteneur. Pic estimé = 160 (tmpfs) + 146 (anon+swap relevé en production, ADR 0033) ≈ 310 Mio, `mem_limit: 640m` (×2, doctrine de `docs/conventions/resource-limits.md`), `mem_reservation: 320m`.
- `./dump.sql` est monté en lecture seule sur `/config/initdb.d/betisier.sql` : Docker monte `/config` d'abord, le fichier ensuite, il reste visible. L'image tente un `chown -R` final qui échoue sur ce fichier (« Permissions could not be set ») : déjà le cas avant le tmpfs, sans suite.
- Une base qui ne revient pas après un redémarrage : `docker logs betisier_db`, et `df` sur `/config` (tmpfs plein ?).

## Volumes anonymes d'avant le tmpfs

La tâche « Remove the dangling anonymous volumes » supprime les volumes orphelins de l'ancien `/config`. Le premier déploiement avec le tmpfs en crée un dernier (l'ancien conteneur recréé) : à retirer du rôle (tâche, et son jeu d'essai dans `ansible/molecule/betisier/prepare.yml` et `verify.yml`) après le déploiement suivant, quand `docker volume ls -qf dangling=true -f label=com.docker.volume.anonymous` n'en montre plus de ce type.

## Premier déploiement du tmpfs

Le conteneur `betisier_db` d'avant porte un volume anonyme sur `/config`, que `docker compose up` peut vouloir reprendre en plus du tmpfs (« Duplicate mount point: /config »). Si `dc@betisier` boucle sur cette erreur après le déploiement, `docker compose down` dans `/opt/apps/betisier` (ou `systemctl --user start betisier-reset.service`) supprime l'ancien conteneur ; le suivant démarre avec le tmpfs seul. Non vérifié sur la VM.
