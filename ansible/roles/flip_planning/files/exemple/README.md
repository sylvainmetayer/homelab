# Base de référence de la vitrine (exemple-planning.sylvain.dev)

`exemple-planning.dump` est la base que l'instance `exemple_planning` retrouve
chaque nuit (`flip_planning_reset_dump`, voir `defaults/main.yml` du rôle).
Données **entièrement fictives** : le scénario `gamme-16` livré avec
l'application, rien d'autre. Aucune donnée d'exploitation ne doit entrer ici :
ce dépôt est public, et cette base est servie à n'importe quel visiteur.

| | |
| --- | --- |
| Produite par | planning-equipes **v1.4.0** (Flyway V114) |
| Format | `pg_dump -Fc --no-owner --no-acl` (PostgreSQL 16, relu par `pg_restore` 18) |
| Édition | « Festival de Combelune 2027 », seule édition, par défaut |
| Scénario | `gamme-16-14j-25stands-72animateurs-mineurs-ferie-nocturnes.yaml` : 14 jours, 25 stands, 72 animateurs (un tiers de mineurs), 15 août férié, nocturnes |
| Événement | du lundi 9 au dimanche 22 août 2027 |
| Plan | 1 012 sièges, tous pourvus, 0 hard ; résolu en 60 s, réalisable dès ~4 s |
| Publication | version 1 publiée (61 envois ; adresses `@example.org`), instantané « Plan initial » |
| Horloge simulée | figée au mardi 10 août 2027, 15:00 — jour 2, l'écran Aujourd'hui et l'affichage mural ont une journée à montrer |
| Budget solveur de l'édition | 60 s, égal au plafond de l'instance |

## Pourquoi un dump d'une version ancienne marche encore

L'image de la vitrine suit les releases (`flip_planning_image_release`) : au
redémarrage qui suit chaque restauration, Flyway migre ce schéma V114 jusqu'à
la version de l'image. Inutile de régénérer le dump à chaque release. Il faut
le régénérer seulement si une migration le rend moins parlant (un écran
nouveau qui resterait vide), et **jamais avec une version plus récente que
l'image déployée** : l'application refuse un schéma en avance sur elle.

Les dates de l'événement sont en 2027 : la vitrine reste « avant l'événement »
pour le solveur, et l'horloge figée donne le jour J. Passé août 2027, rien ne
casse — l'horloge reste figée sur sa date — mais renouveler le scénario vers
une année future garde les écrans de préparation cohérents.

## Régénérer

Avec les sources de la version visée, JDK 25, Node ≥ 22 et un PostgreSQL vide :

```bash
git clone --branch vX.Y.Z --depth 1 https://github.com/sylvainmetayer/planning-equipes src && cd src
./mvnw -B package -DskipTests
psql -U postgres -c "CREATE ROLE festival LOGIN PASSWORD 'change-me'" -c "CREATE DATABASE festival OWNER festival"

DB_URL=jdbc:postgresql://127.0.0.1:5432/festival DB_USER=festival DB_PASSWORD=change-me \
ADMIN_PASSWORD=demo MAIL_MOCK=true HORLOGE_SIMULEE_AUTORISEE=true LEGAL_DEMO_INSTANCE=true \
SOLVER_SECONDS_LIMIT_MAX=60 PLANNING_SOLVER_SECONDS_LIMIT=60 PLANNING_SOLVER_UNIMPROVED_SECONDS_LIMIT=20 \
java -jar target/quarkus-app/quarkus-run.jar &

B=http://127.0.0.1:8080; C=cookies.txt
H=(-b $C -c $C -H 'X-Edition-Id: E1' -H 'Content-Type: application/json')
curl -s -c $C -o /dev/null -d j_username=admin -d j_password=demo $B/j_security_check
curl -s "${H[@]}" -X PUT  $B/api/editions/E1 -d '{"nom":"Festival de Combelune 2027"}'
curl -s "${H[@]}" -X POST "$B/api/reference-data/import-scenario?name=gamme-16-14j-25stands-72animateurs-mineurs-ferie-nocturnes.yaml"
curl -s "${H[@]}" -X PUT  $B/api/parametres-solveur -d '{"dureeResolutionSecondes":60,"plateauSecondes":null,"mailFinResolution":false}'
JOB=$(curl -s "${H[@]}" -X POST "$B/api/solve/async/reference-data?seconds=60&reamorcage=AUCUN" | jq -r .id)
until curl -s "${H[@]}" $B/api/jobs/$JOB | jq -e '.status=="COMPLETED"' >/dev/null; do sleep 5; done
curl -s "${H[@]}" -X POST $B/api/planning/snapshots -d '{"libelle":"Plan initial (résolution 60 s)"}'
curl -s "${H[@]}" -X POST $B/api/planning/publication -d '{}'
# L'horloge APRÈS la résolution : figée d'abord sur le jour 2, elle ferait du
# jour 1 un passé figé que le solveur ne remplit jamais.
curl -s "${H[@]}" -X PUT  $B/api/horloge -d '{"dateDuJour":"2027-08-10","heureDuJour":"15:00"}'
kill %1

pg_dump -Fc --no-owner --no-acl -U festival festival > exemple-planning.dump
```

Puis vérifier : restauration dans une base vide
(`pg_restore --no-owner --no-acl --exit-on-error`), démarrage de la même
version dessus (Flyway : « No migration necessary »), et
`pg_restore -f - exemple-planning.dump | grep -i <nom réel>` ne trouve rien.
Les routes ci-dessus sont celles de la v1.4.0 : une version ultérieure peut les
avoir déplacées, l'OpenAPI publiée par l'application fait foi.
