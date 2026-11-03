# Rôle `ci_key_audit`

Depuis [l'ADR 0027](../../../docs/adr/0027-connexions-ssh-cles-connues.md), une connexion avec la clé de CI (`keys/github-actions.pub`) ne fait plus sonner le téléphone : le hook `ssh_login_notify` laisse une trace basse priorité. Ce rôle rend à cette clé une alerte, après coup : toutes les 10 minutes, la VM docker (`docker.yml`, tag `ci_key_audit`) compare ses connexions aux runs réels du déploiement.

`ci-key-audit.timer` lance `files/ci_key_audit.py` : bibliothèque standard seule, compte éphémère (`DynamicUser`), n'écrit que `/var/lib/ci-key-audit/state.json`.

## Ce qu'il compare

- **Connexions** : lignes du journal `identifier:="ssh-login-notify"` dans VictoriaLogs, dont le message contient `ci_key_audit_fingerprint`. Par empreinte : le message donne aussi utilisateur, IP et nom de clé, repris tels quels dans l'alerte (nettoyés : qui a la session peut écrire au journal). Les formats `clé connue :` (hook du lot 1) et `notifié :` (hook précédent) comptent tous deux ; `échec de la trace ntfy` non, doublon de la ligne `clé connue` de la même session.
- **Runs** : `GET /repos/sylvainmetayer/homelab/actions/workflows/deploy-docker-app.yaml/runs`, branche `main`, **sans authentification** (dépôt public). Ce workflow est le seul à avoir `SSH_PRIVATE_KEY`. Un run va de `run_started_at` à `updated_at` (à maintenant s'il n'est pas fini). Un essai précédent d'un run relancé n'est lu que si une connexion en a besoin.
- **Marge** : ± 120 s autour d'un run (horloges, dates de GitHub à la seconde). Une connexion hors run de moins de 300 s attend le passage suivant : l'API peut ne pas montrer encore le run qui démarre.
- **Hôtes** : tous sont jugés, sauf `ci_key_audit_excluded_hosts` (`newt-lxc`, où sa liste vide fait déjà sonner la clé de CI). Un hôte inconnu est jugé : il alerte, il ne se tait pas.

## Ce qui alerte

| Cas | Effet | Moniteur « Clé de CI : contrôle » |
|---|---|---|
| Rien à signaler | | `up` |
| Connexion hors de tout run | ntfy `scripts`, **priorité 5**, un message par passage (20 lignes au plus) | `down` avec le message, donc Telegram ; `up` au passage suivant |
| Déploiement réussi sans ligne du hook sur un hôte | ntfy priorité 4, une fois par 24 h par hôte | `down` puis `up` |
| ntfy refuse une alerte | rien de perdu : relue et réessayée à chaque passage | `down` avec le message, unité en échec |
| VictoriaLogs ou GitHub injoignable, réponse illisible, quota épuisé, plafond atteint | état inchangé, unité en échec, raison au journal | **aucun push** : DOWN à l'expiration (30 min, trois périodes) |
| Seule la lecture des étapes d'un run échoue | connexions jugées et alerte partie, curseur figé, unité en échec | aucun push (`down` s'il y a une alerte) |
| Journal d'un hôte de `ci_key_audit_hosts` silencieux depuis 3 h | curseur figé, le reste jugé quand même | aucun push, comme ci-dessus |

Pourquoi ntfy **et** le moniteur : un moniteur déjà DOWN ne renotifie pas (la raison de l'ADR 0027), donc ntfy porte chaque événement ; ntfy accepte une publication sans abonné (incident du 29/10), donc Telegram la double. Un unique battement manqué ne sonne pas : une panne passagère de GitHub se résorbe seule, une panne qui dure fait tomber le moniteur.

## Fenêtre et idempotence

- **Curseur persisté, recouvrement** : chaque passage lit depuis `cursor - 4 h` (24 h au premier, ou état perdu ; 29 jours au plus, la rétention). Le curseur n'avance qu'après un passage complet : un timer manqué (`Persistent=true`), une VM éteinte ou une panne de plusieurs jours ne laissent pas de trou. Un agent Vector arrêté non plus : le curseur avance jusqu'à ce que son hôte soit déclaré silencieux (3 h), et ses lignes rattrapées portent la date du début de la panne, d'où un recouvrement plus long que ce silence (le rôle le vérifie).
- **Une alerte par événement** : `seen` garde l'empreinte de chaque ligne jugée (hôte, date, message) tant qu'elle peut revenir dans la fenêtre. Elle n'y entre qu'une fois l'alerte **publiée** : une publication ratée est retentée, jamais perdue. État illisible : on repart de 24 h ; une alerte peut revenir, aucune n'est perdue.

## Les lignes arrivent-elles ?

L'absence de ligne ne veut rien dire seule : aucune connexion de la clé, c'est le cas normal, et le contrôle reste `up`. Deux contrôles disent si elle est suspecte :

1. **Journal de l'hôte** : chaque hôte de `ci_key_audit_hosts` doit avoir envoyé une ligne journald depuis 3 h, le canal même des lignes du hook. Agent Vector arrêté, identifiants refusés : pas de `up`.
2. **Après un déploiement** : pour chaque run fini, `GET …/attempts/N/jobs` donne les étapes `Deploy <hôte>` réussies (une étape sautée n'attend rien) ; 5 minutes après, chacun doit avoir au moins une ligne de la clé de CI dans le run, contrôle remis à plus tard tant qu'un journal est silencieux. Sinon : hook absent, empreinte remplacée ou format changé, et l'alerte priorité 4 le dit. Rien pour les runs antérieurs à l'installation. **Sans déploiement, ce contrôle-là ne dit rien** : un hook retiré d'un hôte reste invisible jusqu'au suivant.

À la main : `journalctl -u ci-key-audit -n 20` (« N ligne(s) du hook, M de la clé de CI, K run(s) »), le même résumé dans le message du moniteur, et dans https://logs.sylvain.cloud :

```
identifier:="ssh-login-notify" | stats by (host) count() n, max(_time) last
```

## Limites acceptées

- **Une connexion pendant un vrai run passe.** Rien ne distingue alors un voleur de la CI : l'IP de sortie n'est pas fixe. La fenêtre vaut la durée des déploiements.
- **C'est après coup** : 10 à 20 minutes dans le cas courant ; plus si le contrôle ou GitHub est en panne, et le moniteur le dit.
- Qui prend root assez vite peut couper Vector avant l'envoi (lot de 5 s) : le journal silencieux finit par se voir, pas la connexion. Il peut aussi écrire de fausses lignes : au pire, une fausse alerte.
- Relancer un run créé il y a plus de 48 h (`ci_key_audit_run_lookback_seconds`) : ses connexions alertent à tort, du bon côté.
- API sans jeton : 60 requêtes par heure, partagées avec l'IP publique de la maison (6 par heure ici, plus une par run fini, 10 au plus par passage, plus les réessais). Quota épuisé : unité en échec, date de retour au journal.
- Une rotation de la clé de CI : changer `ci_key_audit_fingerprint` avec la liste de `ssh_login_notify` (le scénario Molecule compare aux `keys/`). `perte-cle-ou-poste.md`, étape 7.

## Réagir à une alerte

« Clé de CI utilisée hors déploiement » : regarder hôte, IP et heure dans le message, comparer à https://github.com/sylvainmetayer/homelab/actions/workflows/deploy-docker-app.yaml. Sans explication (run relancé, voir les limites) : clé volée, [perte-cle-ou-poste.md](../../../docs/runbooks/perte-cle-ou-poste.md).

## Variables et secrets

Tout est dans `defaults/main.yml`. Aucune clé SOPS nouvelle :

- `victoria_logs_ui_password` : le compte de lecture de vmauth, déjà sur cet hôte dans `auth.yml`. Sa rotation redéploie aussi ce tag (`docs/runbooks/rotation-des-secrets.md`) ; sinon 401, et le moniteur tombe.
- `ntfy_scripts_token` : comme `mem_report` et `cost_report`.
- `ci_key_audit_push_url` : sortie `uptime_cron_ci_key_audit_url` de `tofu/pangolin_config` (`cron_ci_key_audit.tf`), donnée par l'entrée du rôle dans `docker.yml`. Vide avant l'apply : le contrôle alerte, sans battement, avec un avertissement au déploiement.

Les trois dans `/etc/ci-key-audit/secrets.env` (0600 root, `diff: false`, `no_log`), jamais sur la ligne de commande ; le script les retire de son environnement avant tout sous-processus ; le push passe par `uptime-push`, URL sur stdin. `MemoryMax=64M` : pic de 14 Mio mesuré par le scénario (`MemoryPeak`), 2x, plus de la place pour une longue fenêtre.

## Tests

- `ansible/molecule/ci_key_audit/files/test_ci_key_audit.py` : marge, runs en cours et relancés, pagination, hôte exclu, idempotence, publication ratée, curseur après un timer manqué, journal silencieux, déploiement sans ligne, réessais et quota, ce qui part vers le moniteur. À la main : copier le script à côté et lancer `python3 -I -m unittest discover -s . -p 'test_*.py'`.
- Scénario Molecule `ci_key_audit` : l'empreinte contre `keys/` et les étapes contre le workflow, droits, unités, tests unitaires, puis la vraie unité contre de faux services (`files/fake_api.py`) : vrai run, connexion hors run, pas de seconde alerte, VictoriaLogs et GitHub en panne, journal silencieux, déploiement sans ligne, retour au calme.
- Les requêtes LogsQL ont été essayées sur VictoriaLogs 1.53 réel, en local, le 03/11. **Non couvert** : le vrai GitHub, le vrai ntfy, le moniteur et ses transitions.
