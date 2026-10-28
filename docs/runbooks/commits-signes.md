# Commits signés sur `main`

Procédure, pas un incident. Tout ce qui arrive sur `main` doit porter une
signature vérifiée par GitHub : ruleset `main-signed-commits`
(`tofu/github/ruleset_homelab.tf`), sans `bypass_actors`, derrière
l'interrupteur `homelab_require_signed_commits` (défaut `false`).

Qui signe quoi :

- une **PR** (la mienne, Renovate, Claude) entre par un commit que GitHub crée
  et signe lui-même : **squash** ou merge commit. GitHub vérifie aussi chaque
  commit de la branche de la PR avant de fusionner : ils doivent être signés
  (c'est déjà le cas des miens, de ceux de Claude et de Renovate) ;
- un **push direct** sur `main` (correctif urgent, bypass admin du ruleset
  `main`) doit porter **ma** signature SSH : le bypass du ruleset `main` ne
  couvre pas `main-signed-commits`.

## Pourquoi le squash

« Rebase and merge » réécrit les commits de la PR sans pouvoir les signer :
GitHub « adds commits to the base branch without commit signature
verification » et « can't therefore sign it »
([about merge methods](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/configuring-pull-request-merges/about-merge-methods-on-github#rebasing-and-merging-your-commits)).
Avec la règle active, une PR fusionnée en rebase est refusée. Le dépôt ne
fusionne aujourd'hui qu'en rebase : il faut basculer en squash **avant**
l'apply, et la précondition du ruleset refuse le plan tant que « Allow rebase
merging » est coché. Renovate (`automergeStrategy` par défaut) prend le rebase
tant qu'il est permis, puis le squash.

Conséquence : une PR = un commit sur `main`, titre de la PR (et `(#numéro)`),
messages des commits dans le corps. Les commits intermédiaires d'une PR ne
sont plus sur `main` ; `deploy-docker-app.yaml` diffe la plage depuis le
dernier push réussi, il n'en dépend pas.

## Sur le poste (déjà en place, à vérifier)

La clé est `keys/perso.pub`, tenue par l'agent SSH de KeePassXC. Le bloc
« SSH SIGNING » de `~/.ssh/allowed_signers` est posé par les dotfiles.

```bash
git config --global gpg.format ssh
git config --global user.signingkey "key::$(cut -d' ' -f1,2 keys/perso.pub)"   # la clé publique elle-même ; sans « key:: », forme dépréciée par git
git config --global commit.gpgsign true
git config --global tag.gpgsign true          # facultatif : tags signés aussi
git config --global gpg.ssh.allowedSignersFile ~/.ssh/allowed_signers
# ~/.ssh/allowed_signers : "<user.email> ssh-ed25519 AAAA…"
```

`user.email` (`git@sylvain.dev`) doit être une adresse **vérifiée** du compte
GitHub, sinon la signature est valide mais le commit « Unverified ».
KeePassXC doit être déverrouillé : sans l'agent, `git commit` échoue
(« Couldn't find key in agent ») au lieu de produire un commit non signé.

## Sur GitHub

La même clé doit être déclarée comme **Signing key** (une clé
« Authentication » ne vérifie aucun commit, même identique) :

```bash
gh auth refresh -h github.com -s admin:ssh_signing_key
gh ssh-key add keys/perso.pub --type signing --title "keepassxc perso (signature)"
gh ssh-key list          # la ligne doit dire « signing »
```

## Vérifier

```bash
git log --show-signature -3        # « Good "git" signature for git@sylvain.dev »
gh api repos/sylvainmetayer/homelab/commits/<sha> --jq .commit.verification
# reason: "valid", verified: true
```

## Bascule, dans l'ordre

1. Poste et clé de signature GitHub comme ci-dessus ; pousser un commit sur
   une branche de test et vérifier `verification.reason == "valid"`.
2. Fusion en squash seulement :
   ```bash
   gh api -X PATCH repos/sylvainmetayer/homelab \
     -F allow_squash_merge=true -F allow_rebase_merge=false \
     -f squash_merge_commit_title=PR_TITLE -f squash_merge_commit_message=COMMIT_MESSAGES
   ```
   Les PR déjà en auto-merge (Renovate) gardent la méthode choisie à
   l'activation : les désarmer puis réarmer (`gh pr merge --auto --squash`),
   ou laisser Renovate le refaire à son passage suivant.
3. `homelab_require_signed_commits = true` (par défaut de la variable dans
   `tofu/github/variables.tf`, par PR), `tofu -chdir=tofu/github plan` : un
   seul ajout, `github_repository_ruleset.homelab_main_signed_commits[0]`,
   puis `apply`.
4. Fusionner avec `gh pr merge --squash` (plus `--rebase`).

## Les anciens commits

Rien ne change pour eux : la règle ne s'applique qu'aux nouveaux pushs. Les
commits non signés déjà sur `main` y restent, sans réécriture d'historique
(le ruleset `main` interdit de toute façon le force-push).

## Retour arrière

`homelab_require_signed_commits = false` et `apply` : le ruleset est supprimé,
le rebase peut être réactivé.
