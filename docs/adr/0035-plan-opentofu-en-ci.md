# 0035. Plan et apply OpenTofu en CI (#704) : plan de dérive de `pangolin_config` sur `main`, pas d'apply

- **Statut** : proposée
- **Date** : 2026-11-12

## Contexte

Aujourd'hui le plan et l'apply d'OpenTofu se font à la main ou par un agent (`pangolin-config-plan`). La CI ne fait que `fmt`, `validate` et `tofu test` mocké, sans secret. Dépôt **public** : logs et commentaires de PR lisibles par tous. Le corps de #704 date d'avant le chiffrement de tous les states (11/11) et `use_lockfile` (11/11).

Constats relus dans le dépôt :
- Onze modules sur douze lisent `secrets/secrets.sops.yaml` par `data "sops_file"` (`secrets.tf`) : la CI n'en est pas destinataire (`.sops.yaml`). Seul `pangolin_config` passe par `TF_VAR_*` (audit sc1, 11/11). Les donner à la CI, c'est lui donner la clé age du fichier racine : tous les jetons en lecture-écriture.
- La CI détient déjà `SOPS_AGE_KEY` (`ansible.sops.yaml` seul), la clé SSH root (0028), le client OLM `ci_runner`, et lit les sorties de `pangolin_config` avec la passphrase **dédiée** de ce state, des clés S3 en lecture seule d'un state (`ansible_state_reader`) : environnement `production`, `main` seulement, sans relecteur.
- Les environnements sont limités à `main` (`environments.tf`) : une PR n'en lit aucun. Le secret du dépôt `HOMELAB_SECRETS_SSH_KEY` est lisible par les PR (le submodule est chiffré). Une PR de fork n'a aucun secret.
- Un plan exécute le code de la PR (`data "external"`, provider bumpé par Renovate) : avec des secrets, c'est de l'exécution de code avec secrets, que `pull_request` ou `pull_request_target` ne changent pas.
- `pangolin_config` : API Pangolin derrière `int-api-allowlist` (IP maison et Pangolin : un runner GitHub est refusé, il faut OLM + passerelle `vpn-flip`, ou un runner sur le LAN) ; provider du fork et miroir `trozz/pocketid` à télécharger ; plan **jamais vide** (budgets IA mergés, non appliqués) ; « No changes » aveugle sur les attributs optional+computed non déclarés (deux pannes) ; un checkout ancien propose de détruire des objets mergés depuis.
- `proxmox` : provider en SSH root par agent vers `pve.internal` ; `github` écrit les secrets de la CI ; `keepass_backup` et `keycloak_demo_planning_kc` : clés S3 admin, Keycloak de démo éteint.

## Options comparées

| | (a) plan `pangolin_config` sur les PR | (b) plan de tous les modules | (c) plan nocturne de dérive sur `main`, alerte ntfy | (d) statu quo |
|---|---|---|---|---|
| Secrets à donner | clé API Pangolin (admin) et clé root, login Uptime Kuma, jeton Pocket ID, Telegram, ntfy, clé Anthropic, PIN, `home_ip`, passphrase dédiée, S3 lecture, OLM | tout (a) + clé age du fichier racine (OVH, Hetzner rw, Cloudflare, GitHub admin, Proxmox, S3 rw), passphrase commune, SSH root vers Proxmox | comme (a), sans PIN inutiles ; posés en secrets d'environnement par `tofu/github` (ni clé age ni 3e fichier SOPS) | aucun |
| Surface | PR = code non relu avec les jetons ; l'environnement `main` seul ne sert pas une PR ; branche de PR autorisée = tout contributeur ou Renovate exfiltre | pire : root cloud en CI, un plan écrit le state (verrou) | code déjà mergé, comme le déploiement ; environnement `main` seul | jetons sur le poste de Sylvain et dans le shell de l'agent (à confirmer vs audit du 05/11) |
| Jetons lecture seule | Pangolin : clé à actions limitées, à tester ; Uptime Kuma : non (login admin) ; Pocket ID : non (clé statique admin) ; S3 : lecture, donc `-lock=false` | OVH (droits par route), Cloudflare, GitHub (jeton fin), Hetzner, Proxmox (PVEAuditor) en permettent, pas Keycloak ; à confirmer, rien ne l'impose aujourd'hui | idem (a) | sans objet |
| Fuite dans les logs publics | plan en clair en commentaire : domaines, IP, noms ; le masquage ne couvre que les `sensitive` | idem, plus large | on ne publie **que** le code de sortie et les adresses changées, jamais le texte du plan | aucune |
| Entretien | fork, miroir, OLM, plan jamais vide : bruit à chaque PR | très lourd : 12 modules à refondre en `TF_VAR` | liste d'écarts attendus (budgets IA) à tenir ; OLM ou allowlist ; fork | nul, mais la dérive ne se voit qu'au prochain plan manuel |
| Ce que ça attrape | l'écart code/réalité avant le merge | idem, partout | la dérive faite dans l'UI (0006), un bump de provider, un plan qui ne converge plus | rien entre deux plans |
| Aveugle à | optional+computed non déclaré ; relecture humaine toujours requise | idem | idem ; pas avant le merge | tout |

## Apply en CI : non

- Il demande la lecture-écriture : Pangolin (qui joint quoi), GitHub admin (rulesets, environnements), Hetzner (supprime les VM), S3. C'est plus que la clé SSH de 0028, déjà équivalente à root.
- La règle (« appliquer le plan relu ») suppose un humain : l'environnement n'a pas de relecteur, un seul compte, et un plan avec `replace`/`delete` ou « No changes » trompeur exige un jugement (VM docker détruite par un `must be replaced`).
- Le plan enregistré n'est pas rejouable entre un run CI et un apply local sans verrou commun ; les rotations par `-replace` restent locales.
- Le `-target` d'un plan relu (budgets IA non appliqués) n'a pas d'équivalent en CI simple.

## Décision proposée

(c), limitée à `pangolin_config`, au lieu des autres : le seul module que l'UI fait dériver (objets faits main, 0006) et le seul déjà lisible par la CI (passphrase dédiée, `TF_VAR`). Plan nocturne sur `main` (workflow `schedule`, environnement `tofu-drift` limité à `main`), code de sortie et adresses comparés à un fichier d'écarts attendus, ntfy au moindre écart nouveau, un moniteur Uptime Kuma de présence ; aucun plan en commentaire ni en log. Pas d'apply en CI. (a), (b) écartées : exécuter du code non relu avec les jetons.

## Décisions à prendre

1. (c) pour `pangolin_config` seul, ou (d) ?
2. Accès à l'API Pangolin : OLM `ci_runner` sortant par `vpn-flip`, ou autre ; pas de runner auto-hébergé sur un dépôt public.
3. Secrets : environnement `tofu-drift` rempli par `tofu/github` (proposé), ou 3e fichier SOPS et 2e clé age.
4. Créer les jetons en lecture seule (Pangolin à actions limitées, S3 par state) et accepter Uptime Kuma et Pocket ID en admin.
5. Accepter `-lock=false` (S3 en lecture) et un plan sans relecture humaine, alerte seulement.
6. Étendre plus tard aux autres modules : ce serait un nouvel ADR, avec refonte `sops_file` en `TF_VAR`.

## Liens

#704 ; [0006](0006-objets-faits-main-audites.md), [0018](0018-secrets-depot-prive.md), [0021](0021-provider-pangolin-du-fork.md), [0024](0024-deploiement-au-merge.md), [0028](0028-cle-ssh-de-ci-root.md), [0029](0029-fenetre-de-calme-du-deploiement.md) ; `.claude/skills/pangolin-config-plan/SKILL.md`, `tofu/pangolin_config/README.md`, `docs/conventions/{ci,opentofu,secrets}.md`.
