# Monter une base PostgreSQL d'une majeure

Procédure, pas un incident : Renovate propose `postgres:19` à une appli qui
tourne en 18. Jouée le 2026-11-22 (18.6 vers 19.0 : HealthLog, Jellystat).

## Le piège

Depuis la 18, l'image officielle range ses données sous
`/var/lib/postgresql/<majeure>/docker`, et nos compose montent
`/var/lib/postgresql`. Une image d'une autre majeure ne lit pas l'ancienne
grappe : à l'initialisation de la sienne, elle voit `18/docker` et **refuse de
démarrer** (« there appears to be PostgreSQL data in… », code 1). Merger la PR
Renovate telle quelle laisse donc la base arrêtée et l'appli en panne, données
intactes.

`pg_upgrade` demande les binaires des deux majeures, que l'image n'a pas : on
passe par un export (`pg_dumpall`) et un réimport.

## Procédure

Une appli à la fois, base par base. `ansible/files/pg-major.sh` fait les deux
moitiés ; il ne supprime rien.

1. **Ne pas merger la PR de montée avant l'étape 3** de chaque appli qu'elle
   touche : une PR par hôte, pas la PR groupée de Renovate. La nuit (19:00 à
   08:00) le merge ne déploie pas ; de jour il déploie aussitôt, donc arrêter
   l'appli d'abord.
2. Export et empreinte, appli en marche (rien n'est coupé) :

   ```bash
   cd ansible
   ansible <hôte> -m script -a "files/pg-major.sh prepare <conteneur_db> <dossier_appli>/pg-migration"
   ```

   Il écrit `dumpall.sql` (0600) et `before.txt` : une ligne par table, avec
   son nombre exact de lignes.
3. Arrêter **le seul conteneur de l'appli**, base en marche (`cd <dossier_appli>
   && docker compose stop app` sur l'hôte : `dc@<appli>` couperait aussi la
   base et l'export de l'étape 2, pris pendant que l'appli écrivait, serait
   le dernier : tout ce qui a été écrit depuis serait perdu). Refaire l'étape 2
   pour un export à jour, puis arrêter la base (`systemctl --user stop
   dc@<appli>`) et réimporter dans la nouvelle majeure :

   ```bash
   ansible <hôte> -m script -a "files/pg-major.sh restore <conteneur_db> <dossier_appli>/pg-migration <image>@<digest>"
   ```

   Il renomme l'ancienne grappe en `<majeure>/docker.avant-migration`, démarre
   la nouvelle image sans réseau sur les mêmes montages, réimporte, compare
   les tables une à une et s'arrête. `OK restore` : mêmes tables, mêmes
   nombres de lignes, aucune erreur inattendue (les « already exists » du rôle
   et de la base créés par l'image sont attendus).
4. Merger la PR et déployer l'appli (`deploy-docker-app` en
   `workflow_dispatch`, `tags=<rôle>`).

Après un `KO restore` : l'ancienne grappe est déjà en `docker.avant-migration`
et `<nouvelle majeure>/docker` est à moitié remplie. Corriger la cause, supprimer
`<nouvelle majeure>/docker`, relancer `restore` (l'export est réutilisé) ; pour
renoncer, remettre l'ancienne en `docker` (voir « Retour arrière »).

## Vérification

- `docker exec <conteneur_db> psql -U <utilisateur> -d <base> -Atc 'select version()'`
  rend la nouvelle majeure ; les conteneurs sont `healthy`.
- L'appli montre ses données (une page qui lit la base, pas seulement
  `/health`).
- Le dump borgmatic de la nuit suivante passe : moniteur `Backup <appli>` vert.

## Retour arrière

Arrêter l'appli, supprimer `<majeure nouvelle>/docker`, renommer
`<majeure>/docker.avant-migration` en `docker`, revenir à l'ancienne image
(revert de la PR), redéployer. Ce qui a été écrit depuis la bascule est perdu.

## Après

Quand l'appli a tourné quelques jours : supprimer
`<dossier_appli>/postgresql/<ancienne majeure>` (ou le dossier du volume) et
`<dossier_appli>/pg-migration` (l'export contient toute la base en clair).
