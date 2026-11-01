# Homepage : une carte en erreur (agenda, Supervision, cartes d'applis)

Homepage (rôle `homepage`, VM docker, `dc@homepage`, dossier
`/opt/apps/homepage`) lit trois services d'appoint du même projet Compose,
qui portent les clés à sa place et lui servent du JSON ou de l'iCal :

| Service (conteneur) | Cartes | URL vue de Homepage | Réseau |
|---|---|---|---|
| `ical-filter` (`homepage-ical-filter`) | agenda (Perso, Top nous) | `http://ical-filter:8080/<slug>.ics` (`perso`, `top-nous`) | `ical` |
| `kuma-summary` (`homepage-kuma-summary`) | Sondes en panne, Sauvegardes, Maintenance | `http://kuma-summary:8080/{down,backups,maintenance}.json` | `kuma` |
| `apps-summary` (`homepage-apps-summary`) | Grocy, Papra, Dawarich, Bus 31, Coûts | `http://homepage-apps-summary:8080/<source>.json` (`grocy`, `papra`, `dawarich`, `tbm`, `costs`) | `newt` |

Chacun garde une copie (300 s, 60 s pour Uptime Kuma et TBM) et la sert
tant que l'amont échoue ; sans copie, il répond `502`. Une source sans sa
clé n'existe pas (`404`), un service sans aucune source n'est pas rendu.
Détail : [README du rôle](../../ansible/roles/homepage/README.md).

## Symptôme

- Une carte affiche « API Error » ou reste vide.
- La carte n'apparaît pas du tout.
- L'agenda montre des tâches datées d'aujourd'hui (Homepage lit le
  calendrier sans le filtre).
- Carte Maintenance : une ligne « Absente ».

## Diagnostic

```bash
cd ansible && mise run ssh
cd /opt/apps/homepage && docker compose ps
docker logs --tail 50 homepage-kuma-summary     # ou homepage-ical-filter, homepage-apps-summary
```

Le journal nomme la source et l'erreur (`/metrics : …`, `perso : …`,
`grocy : …`), avec « copie de N s servie » tant qu'une copie couvre la
panne. Ni URL ni clé n'y figurent.

Interroger le service comme Homepage le fait :

```bash
docker exec homepage wget -O- -Y off http://kuma-summary:8080/down.json
docker exec homepage wget -O- -Y off http://homepage-apps-summary:8080/grocy.json
docker exec homepage wget -O- -Y off http://ical-filter:8080/perso.ics | head
```

| Réponse | Cause |
|---|---|
| `404` | source non configurée : clé SOPS absente ou vide, ou lien sans `internal_url` (Papra, Grocy, Dawarich) |
| `502` | l'amont échoue et aucune copie n'existe : lire le journal du service |
| nom introuvable | service non rendu (aucune clé), ou Homepage hors de son réseau |
| JSON correct, carte en erreur | côté Homepage : `services.yaml` (champs du `customapi`) |

Amonts, par service :

- **`kuma-summary`** : `<homepage_uptimekuma_url>/metrics` chez PikaPods,
  clé `homepage_uptimekuma_api_key` en Basic. `401` : clé révoquée dans
  Uptime Kuma. Plus de 60 requêtes par minute refusées. Une redirection
  n'est jamais suivie.
- **`ical-filter`** : URL de partage Nextcloud
  (`homepage_calendar_ics_url`, `homepage_calendar_top_nous_ics_url`), par
  Pangolin comme un client public. Partage retiré ou URL changée : `404` de
  Nextcloud. Plus de 2 Mio : refusé.
- **`apps-summary`** : Grocy, Papra, Dawarich par leur nom de conteneur sur
  `newt` (une appli arrêtée = `502`), TBM par Internet. Clés
  `homepage_grocy_api_key`, `homepage_papra_api_key`,
  `homepage_dawarich_api_key`. Coûts : le fichier `costs.json` du rôle
  `cost_report` (`/var/lib/cost-report`), réécrit chaque matin.

« Absente » sur Maintenance : le nom de `homepage_kuma_maintenance_monitors`
ne correspond plus à aucune sonde de `/metrics` (renommée dans
`tofu/pangolin_config`, supprimée, ou en pause).

## Réparation

- **Amont en panne** (appli arrêtée, Uptime Kuma, Nextcloud) : le réparer ;
  la carte revient au cache suivant. Appli du homelab :
  [appli-en-panne.md](appli-en-panne.md).
- **Clé révoquée, absente ou à changer** : la recréer dans l'application
  avec les droits minimaux de
  [rotation-des-secrets.md](rotation-des-secrets.md#widgets-de-homepage),
  `sops set` dans `secrets/ansible.sops.yaml` (avec son entrée dans
  `secrets/secrets-rotation.yaml`), puis :

  ```bash
  ansible-playbook docker.yml --tags homepage --check --diff
  ansible-playbook docker.yml --tags homepage
  ```

  Le changement du compose recrée les services d'appoint.
- **Nom de sonde changé** : mettre `homepage_kuma_maintenance_monitors` à
  jour par une PR (merger déploie `docker.yml --tags homepage`).
- **Service d'appoint planté** : `systemctl --user restart dc@homepage`
  (sa mémoire est bornée à 64 Mio : `docker stats --no-stream`).
- **Coûts vides** : voir le
  [README de cost_report](../../ansible/roles/cost_report/README.md).

## Vérification

- Les `wget` ci-dessus rendent du JSON (ou un `BEGIN:VCALENDAR` sans
  `VTODO`).
- La carte s'affiche dans Homepage après au plus la durée du cache.

## Prévention

- Une clé ajoutée ou retirée de SOPS fait apparaître ou disparaître sa
  carte au déploiement suivant : vérifier Homepage après chaque
  `--tags homepage`.
- Renommer une sonde de maintenance dans `tofu/pangolin_config` impose de
  renommer son entrée dans `homepage_kuma_maintenance_monitors`.
