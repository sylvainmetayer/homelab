# Rôle `cost_report`

Rapport mensuel des coûts du homelab, sur la VM docker (`docker.yml`, tag
`cost_report`). `cost-report.timer` lance chaque jour à 07:00 (et 2 minutes
après chaque démarrage du timer : déploiement, redémarrage)
`files/cost_report.py` sous `sylvain`, bibliothèque standard seule, unité
durcie qui n'écrit que dans son `StateDirectory` (`/var/lib/cost-report`).

- **ntfy** : le rapport du mois dernier, une fois par mois, sur le topic
  `scripts` (jeton `ntfy_scripts_token`, comme `mem_report`) : total, puis le
  détail par source et par ligne, les sources incomplètes, et le mois en
  cours à date. Il part au premier lancement d'un mois dont le rapport n'est
  pas encore parti : le 1er, ou plus tard si la VM était éteinte
  (`state.json`). Une publication en échec fait échouer l'unité et sera
  retentée le lendemain. Priorité 4 si une source est en erreur, 3 sinon.
- **Homepage** : chaque lancement réécrit `costs.json` (par renommage),
  que `apps-summary` lit dans le dossier monté en lecture seule
  (`homepage_costs_dir`, donné par `docker.yml`) et sert en
  `/costs.json` à la carte **Coûts** (groupe Administration) : mois dernier,
  mois en cours à date, nombre de sources à compléter, heure du relevé.
  Aucune clé ne quitte `cost_report`.
- À la main : `sudo systemctl start cost-report` (rafraîchit la carte ;
  ne republie pas un rapport déjà parti), sortie complète dans
  `journalctl -u cost-report`. Republier le rapport du mois dernier :
  `sudo rm /var/lib/cost-report/state.json && sudo systemctl start cost-report`
  (jamais les jetons sur une ligne de commande).

## Sources

| Source | Ce qui est compté | Mois dernier | Mois en cours | Clé |
|---|---|---|---|---|
| Hetzner | serveurs Cloud, leurs sauvegardes (pourcentage de `/pricing`), IP primaires payantes, volumes, Storage Box | prix mensuel TTC des ressources **actuelles** (l'API n'a pas de facture : estimation au tarif courant ; trafic excédentaire non compté) | même montant au prorata du mois écoulé | `hcloud_readonly_token` (existante) |
| OVH | factures du compte (domaines, Public Cloud du mois précédent, tout le reste), consommation Public Cloud pas encore facturée | factures **datées** du mois (TTC) | factures du mois à date + consommation en cours (HT dans l'API, + `cost_report_ovh_vat_percent` %) | `costs_ovh_*` (à créer) |
| Abonnements | `defaults/main/abonnements.yml` : PikaPods (pas d'API publique), kDrive, abonnement IA… | montant mensuel, ou annuel / 12 | prorata | aucune |

- Une source sans clé est « non configurée », un abonnement à `amount: 0`
  « à renseigner » : le rapport sort quand même, partiel, les nomme et ne
  les compte pas. Une API en erreur (code HTTP ou classe de l'erreur,
  jamais l'URL ni le jeton) marque sa seule source « en erreur ».
- Pas de conversion de devise : les totaux s'additionnent par devise
  (« 30,32 € + 6,00 USD »).
- OVH compte ce qui est **facturé** dans le mois : la consommation Public
  Cloud d'octobre est sur la facture datée de début novembre. Le Public
  Cloud n'est donc jamais compté deux fois (en cours tant qu'il n'est pas
  facturé, puis facture).
- Les abonnements se changent dans `defaults/main/abonnements.yml` (le rôle
  refuse au déploiement un montant non numérique, une devise qui n'est pas
  un code ISO, une période autre que `monthly`/`yearly`) ; un merge ne
  redéploie que le tag `cost_report`.

## Clés (toutes optionnelles)

Aucune n'est obligatoire : sans elles, le rapport ne compte que les
abonnements. Créées par Sylvain, `sops set` (règles communes de
`docs/runbooks/rotation-des-secrets.md`), une entrée chacune dans
`secrets/secrets-rotation.yaml`, puis `ansible-playbook docker.yml --tags cost_report`.

### Hetzner : rien à créer

`hcloud_readonly_token` (`secrets/ansible.sops.yaml`) existe déjà : le jeton
de projet **Read** du contrôle de la Storage Box. Hetzner n'a que deux
niveaux (Read, Read & Write) : Read est le moindre privilège possible, et la
Storage Box est dans le même projet (`hcloud_storage_box`), lue par la même
API (`api.hetzner.com/v1/storage_boxes`). Sa rotation (runbook, « Hetzner »)
redéploie aussi ce rôle.

### OVH : une application dédiée, en lecture des factures seulement

1. Connecté au compte OVH, ouvrir (remplacer `<projet>` par l'identifiant
   du projet Public Cloud, `OVH_CLOUD_PROJECT_ID` du fichier racine :
   `sops decrypt --extract '["OVH_CLOUD_PROJECT_ID"]' secrets/secrets.sops.yaml`) :

   ```
   https://eu.api.ovh.com/createToken/?GET=/me/bill&GET=/me/bill/*&GET=/cloud/project/<projet>/usage/current
   ```

   Nom `homelab-cost-report`, description « Rapport des coûts (lecture des
   factures) », validité **Unlimited** ; dans « Restricted IPs », l'IP
   publique de la maison (clé `home_ip`) si elle est fixe : la VM docker
   sort par elle. Vérifier que la page liste ces trois droits, `GET`
   seulement, et rien d'autre.
2. `sops set` dans `secrets/ansible.sops.yaml` : `costs_ovh_application_key`,
   `costs_ovh_application_secret`, `costs_ovh_consumer_key` (les trois
   valeurs affichées), et `costs_ovh_cloud_project_id` (l'identifiant du
   projet ; sans elle, les factures seules).
3. Entrées de `secrets/secrets-rotation.yaml` :

   ```yaml
     - key: costs_ovh_application_key
       file: secrets/ansible.sops.yaml
       kind: provider
       last_rotated: AAAA-MM-JJ
       estimated: false
       how: docs/runbooks/rotation-des-secrets.md#ovh
     # idem pour costs_ovh_application_secret et costs_ovh_consumer_key
     - key: costs_ovh_cloud_project_id
       file: secrets/ansible.sops.yaml
       kind: identifier
       last_rotated: AAAA-MM-JJ
       estimated: false
       how: docs/runbooks/rotation-des-secrets.md#ovh
   ```

4. Vérifier : `GET /me/api/credential` dans la console d'API montre les
   seules règles ci-dessus ; après le déploiement,
   `sudo systemctl start cost-report && journalctl -u cost-report -n 30` :
   OVH n'est plus « non configurée ».

## Pas de moniteur Uptime Kuma

Comme `mem_report`, le rapport est son propre signal : un message du 1er
qui ne vient pas se remarque, et la carte Coûts affiche l'heure du relevé
(une carte figée sur une vieille date, ou en erreur, dit que le timer ne
tourne plus). Un moniteur push mensuel est impossible (intervalle plafonné
à 24 jours) ; un moniteur quotidien aurait doublé ce que la carte montre
déjà.

## Tests

- `ansible/molecule/cost_report/files/test_cost_report.py` : analyse des
  réponses Hetzner et OVH (enregistrées, aucun appel réel), signature OVH,
  abonnements, rapport, découpage sous la limite de ntfy, publication une
  fois par mois. À la main : copier le script à côté et lancer
  `python3 -I -m unittest discover -s . -p 'test_*.py'`.
- Scénario Molecule `cost_report` : droits des fichiers, jetons dans le seul
  fichier d'environnement, unités (`systemd-analyze verify`), tests
  unitaires, puis la vraie unité deux fois contre de fausses API Hetzner,
  OVH et ntfy (`files/fake_api.py`) : une seule publication, montants
  attendus.
- La source `costs` d'`apps-summary` : `ansible/molecule/homepage/files/test_apps_summary.py`.
