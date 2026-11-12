# 0036. Verrou des actions GitHub (`actions.lock`) en plus des SHA en ligne

- **Statut** : acceptée
- **Date** : 2026-11-12

## Contexte

Chaque `uses:` des workflows est déjà épinglé par SHA (50 sur 57, les 7 autres sont des actions locales `./`), avec la version en commentaire, par le préréglage Renovate `helpers:pinGitHubActionDigests`. Cela ne couvre pas les actions **transitives** : une action composite d'un tiers qui appelle `owner/repo@v1` charge ce tag au moment du run.

GitHub propose en préversion publique l'extension `gh` [`github/gh-actions-lock`](https://github.com/github/gh-actions-lock) (0.x, format du verrou encore mouvant) : `.github/workflows/actions.lock` fige chaque action, directe et transitive, à un commit, et le runner revérifie le verrou au démarrage du job (commit disparu de l'historique amont, dépôt remplacé sous le même nom, pin manquant : le job ne démarre pas).

## Décision

**Mode A : on garde les SHA en ligne et on ajoute le verrou.** Rien n'est défait, deux défenses au lieu d'une.

- `actions.lock` est généré par `gh actions-lock --ignore-local-actions --no-narrow` (extension épinglée `v0.4.1`), entrées clés par SHA : aucune version ne change dans la PR qui l'introduit. Sur ce dépôt, l'outil laisse les workflows intacts (mesuré, v0.4.1, politique « exiger des SHA complets » **désactivée**) : il n'a pas besoin de ce réglage.
- Le workflow `verify-lockfile.yaml` lance `gh actions-lock --verify --ignore-local-actions` sur chaque PR et chaque push sur `main`.
- Renovate regénère le verrou sur sa propre branche (gestionnaire `github-actions`, expérimental, même commande), extension fixée par `constraints.ghActionsLock`, suivie avec `GH_ACTIONS_LOCK_VERSION` de `verify-lockfile.yaml` dans un seul PR.
- Les 7 actions locales restent en `./` (`--ignore-local-actions`).

## Alternatives écartées

- **B : tags + verrou** (l'outil réécrit `@sha # v4.1` en `@v4.1`). Écartée : on perd le SHA en ligne, donc la lecture d'un diff sans l'outil ; zizmor 1.30.1 (ici) range un tag verrouillé en `unpinned-uses` haute (il n'honore le verrou qu'à partir de 1.32) ; les règles Renovate (« jamais le digest d'une action en automerge », `minimumReleaseAge`) supposent des digests en ligne.
- **Actions locales en `$/` (`--migrate-local-actions`)** : verrouille aussi les actions qu'utilise `secrets-checkout`. Écartée : actionlint (1.7.12, dernière version) rejette `$/` (« ref is missing »), et l'outil fait télécharger au job l'archive du dépôt (issue #268 de l'outil). À reprendre quand actionlint le comprend.
- **Politique « exiger des SHA complets »** (`sha_pinning_required`) : pas nécessaire ici, voir `docs/conventions/ci.md` ; ni la politique « Require lockfile », d'organisation ou d'entreprise.

## Conséquences

- Bon : une action transitive ou un tag déplacé ne s'exécute plus sans qu'un diff du verrou le montre ; un pin manquant échoue avant le premier pas du job.
- Bon : Renovate ne change pas de comportement visible, son PR contient en plus la ligne du verrou.
- Mauvais : un fichier machine de plus, format 0.x qui peut changer (une montée de l'extension peut le réécrire entièrement : relire le PR).
- Mauvais : l'extension s'installe par son tag (`gh extension install --pin`), sans somme ; le workflow n'a que `contents: read`.
- Non couvert : actions locales (`./.github/actions/*`, 7 usages) et leurs `uses:` propres (celui de `secrets-checkout` est présent dans le verrou parce que chaque workflow appelant utilise déjà le même `actions/checkout` ; l'issue #281 de l'outil dit que `--verify` ne le contrôle pas), workflows réutilisables d'un autre dépôt (aucun ici), images de conteneurs (déjà épinglées par digest, hors verrou).
- Le check `Actions lock` n'est pas un check requis du ruleset de `main` (changement de réglage laissé à Sylvain, `tofu/github/ruleset_homelab.tf`).

## Liens

- `docs/conventions/ci.md` (garanties, régénération, échec de `--verify`), `renovate.json`
- <https://github.com/github/gh-actions-lock>, `docs/troubleshooting.md` de l'outil
