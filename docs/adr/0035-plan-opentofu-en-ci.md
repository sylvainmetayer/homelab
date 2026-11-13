# 0035. Plan et apply OpenTofu en CI (#704) : plan de dérive de `pangolin_config` sur `main`, pas d'apply

- **Statut** : acceptée (2026-11-13)
- **Date** : 2026-11-12, acceptée le 2026-11-13 par Sylvain

## Contexte

Mise en œuvre : `.github/workflows/plan-pangolin-config.yaml`.

Aujourd'hui le plan et l'apply d'OpenTofu se font à la main ou par un agent (`pangolin-config-plan`). La CI ne fait que `fmt`, `validate` et `tofu test` mocké, sans secret. Dépôt **public** : logs et commentaires de PR lisibles par tous. Le corps de #704 date d'avant le chiffrement de tous les states (11/11) et `use_lockfile` (11/11). [0024](0024-deploiement-au-merge.md) avait écarté « Tofu en CI » le 2026-11-04 (#704 fermée) : cet ADR rouvre la question, restreinte au plan de dérive ; 0024 passe en « acceptée (Tofu en CI : voir 0035) ».

Constats relus dans le dépôt :
- Dix modules sur douze lisent `secrets/secrets.sops.yaml` par `data "sops_file"` (`secrets.tf`) : la CI n'en est pas destinataire (`.sops.yaml`). `pangolin_config` passe par `TF_VAR_*` (audit sc1, 11/11) et `dns` n'a pas de `sops_file` (passphrase par `TF_VAR_state_encryption_passphrase`, jetons de providers par l'environnement mise : à confirmer). Les donner à la CI, c'est lui donner la clé age du fichier racine : tous les jetons en lecture-écriture.
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
| Fuite dans les logs publics | plan en clair en commentaire : domaines, IP, noms ; le masquage ne couvre que les `sensitive` | idem, plus large | on ne publie **que** le code de sortie et le décompte « A to add, B to change, C to destroy », jamais le texte du plan ni les adresses | aucune |
| Entretien | fork, miroir, OLM, plan jamais vide : bruit à chaque PR | très lourd : 12 modules à refondre en `TF_VAR` | plan à tenir vide (aucun écart toléré) ; OLM ou allowlist ; fork | nul, mais la dérive ne se voit qu'au prochain plan manuel |
| Ce que ça attrape | l'écart code/réalité avant le merge | idem, partout | la dérive faite dans l'UI (0006), un bump de provider, un plan qui ne converge plus | rien entre deux plans |
| Aveugle à | optional+computed non déclaré ; relecture humaine toujours requise | idem | idem ; pas avant le merge | tout |

## Apply en CI : non

- Il demande la lecture-écriture : Pangolin (qui joint quoi), GitHub admin (rulesets, environnements), Hetzner (supprime les VM), S3. C'est plus que la clé SSH de 0028, déjà équivalente à root.
- La règle (« appliquer le plan relu ») suppose un humain : l'environnement n'a pas de relecteur, un seul compte, et un plan avec `replace`/`delete` ou « No changes » trompeur exige un jugement (VM docker détruite par un `must be replaced`).
- Le plan enregistré n'est pas rejouable entre un run CI et un apply local sans verrou commun ; les rotations par `-replace` restent locales.
- Le `-target` d'un plan relu (budgets IA non appliqués) n'a pas d'équivalent en CI simple.

## Décision

(c), limitée à `pangolin_config`, au lieu des autres : le seul module que l'UI fait dériver (objets faits main, 0006) et le seul déjà lisible par la CI (passphrase dédiée, `TF_VAR`). Plan nocturne sur `main` (workflow `schedule`, environnement `tofu-drift` limité à `main`), le plan doit être vide : tout plan non vide ou en erreur sonne sur ntfy (le décompte seul, pas les adresses ; pas de fichier d'écarts attendus), un moniteur Uptime Kuma de présence ; aucun plan en commentaire ni en log. Pas d'apply en CI. (a), (b) écartées : exécuter du code non relu avec les jetons.

## Décisions prises (2026-11-13)

1. (c) pour `pangolin_config` seul, pas (d). Plan nocturne (02:30 UTC) et `workflow_dispatch` ; aucun plan sur les PR, jamais d'apply.
2. Accès à l'API : un client OLM **à part**, `ci-plan` (`pangolin_client.ci_plan`), lié à la passerelle `vpn-flip` ; `ci_runner` et le déploiement ne changent pas (lier `ci_runner` à une passerelle aurait changé la route du déploiement, sur des identifiants partagés). Pas de runner auto-hébergé. Non vérifié avant le premier run : que la route par défaut de la passerelle laisse le runner joindre GitHub ; d'où le déclenchement manuel, des délais (job 40 min, plan 25 min) et le job d'alerte, séparé, qui sonne même si le job de plan expire. Le tunnel route `0.0.0.0/0` par flip pour tout le runner (une passerelle n'est pas limitée à l'API) : une ressource plus étroite (un hôte ou un CIDR `/32` de Pangolin seul) laisserait le reste direct, mais il faudrait l'adresse publique de Pangolin dans ce module ; à reprendre si le premier run montre un runner coupé de GitHub. Non vérifié non plus : l'adresse source que voit Traefik pour une requête de flip vers le nom public de Pangolin (rebouclage : celle de Pangolin ou le réseau privé), qui doit être dans `pangolin_api_allowed_ips`.
3. Secrets : environnement `tofu-drift` rempli par `tofu/github` (huit secrets, dont les variables du module en un seul JSON tiré de `secrets/secrets.sops.yaml` par `mise.toml`) ; ni clé age ni 3e fichier SOPS. Ces valeurs vivent donc aussi, chiffrées, dans le state de `tofu/github` (chiffré comme les autres) ; une rotation de l'une d'elles passe par `tofu -chdir=tofu/github apply`, sinon le plan nocturne sonne (runbook de rotation).
4. Jetons : pas de jeton à droits limités pour l'instant (la clé Pangolin à actions limitées reste « à tester », suite à part) ; seul le S3 du state est en lecture seule.
5. `-lock=false`, alerte seulement, aucune relecture humaine. Aucun fichier d'écarts attendus : le plan doit être vide (les budgets IA retirés par #1478 en étaient le seul écart) ; tout plan non vide ou en erreur sonne. Le décompte seul sort du job, pas les adresses.
6. Les autres modules : un nouvel ADR, avec refonte `sops_file` en `TF_VAR`.

## Liens

#704 ; [0006](0006-objets-faits-main-audites.md), [0018](0018-secrets-depot-prive.md), [0021](0021-provider-pangolin-du-fork.md), [0024](0024-deploiement-au-merge.md), [0028](0028-cle-ssh-de-ci-root.md), [0029](0029-fenetre-de-calme-du-deploiement.md) ; `.claude/skills/pangolin-config-plan/SKILL.md`, `tofu/pangolin_config/README.md`, `docs/conventions/{ci,opentofu,secrets}.md`.
