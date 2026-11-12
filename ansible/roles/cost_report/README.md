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
  retentée le lendemain. Une source en erreur jusqu'au 3 du mois reporte
  le rapport au lancement suivant (API passagèrement indisponible, réseau
  pas prêt juste après un redémarrage) ; ensuite il part, partiel, en
  priorité 4 (3 sinon).
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
| Abonnements | `defaults/main/abonnements.yml` : PikaPods (pas d'API publique), kDrive, mail, S3, domaines | montant mensuel, ou annuel / 12 | prorata | aucune |

- Une source sans clé est « non configurée », un abonnement à `amount: 0`
  « à renseigner » : le rapport sort quand même, partiel, les nomme et ne
  les compte pas. Une API en erreur (code HTTP ou classe de l'erreur,
  jamais l'URL ni le jeton) marque sa seule source « en erreur ».
- Pas de conversion de devise : les totaux s'additionnent par devise
  (« 30,32 € + 6,00 USD »).
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

OVH n'est pas interrogé : pas d'API de facturation lue, pas de clé. Un abonnement
OVH à montant fixe se déclare dans `defaults/main/abonnements.yml`.

## Pas de moniteur Uptime Kuma

Comme `mem_report`, le rapport est son propre signal : un message du 1er
qui ne vient pas se remarque, et la carte Coûts affiche l'heure du relevé
(une carte figée sur une vieille date, ou en erreur, dit que le timer ne
tourne plus). Un moniteur push mensuel est impossible (intervalle plafonné
à 24 jours) ; un moniteur quotidien aurait doublé ce que la carte montre
déjà.

## Tests

- `ansible/molecule/cost_report/files/test_cost_report.py` : analyse des
  réponses Hetzner (enregistrées, aucun appel réel),
  abonnements, rapport, découpage sous la limite de ntfy, publication une
  fois par mois. À la main : copier le script à côté et lancer
  `python3 -I -m unittest discover -s . -p 'test_*.py'`.
- Scénario Molecule `cost_report` : droits des fichiers, jetons dans le seul
  fichier d'environnement, unités (`systemd-analyze verify`), tests
  unitaires, puis la vraie unité deux fois contre de fausses API Hetzner
  et ntfy (`files/fake_api.py`) : une seule publication, montants
  attendus.
- La source `costs` d'`apps-summary` : `ansible/molecule/homepage/files/test_apps_summary.py`.
