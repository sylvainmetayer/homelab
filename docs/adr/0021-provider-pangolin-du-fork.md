# 0021. Provider Pangolin : build du fork servi par un miroir local

- **Statut** : acceptée
- **Date** : 2026-11-02

## Contexte

`stackopshq/pangolin` 1.6.1 efface les liaisons d'une ressource privée à chaque
mise à jour, ne connaît ni le mode `gateway` ni les `response_headers`, et les
correctifs proposés en amont restent sans réponse depuis le 28/10/2026. Les 14
PR sont mergées sur le fork `sylvainmetayer/terraform-provider-pangolin`, et
leurs branches restent intactes pour être reproposées une par une.

## Décision

`tofu/pangolin_config` utilise `1.7.0-sylvain.5`, préversion du fork épinglée
exactement. `mise run provider-fork` télécharge le zip, vérifie son SHA-256 et
le pose dans `terraform.d/plugins`, miroir local implicite de `tofu init`. La
source reste `stackopshq/pangolin` : l'état ne change pas.

## Alternatives écartées

- **Publier le fork au registre OpenTofu** : pas d'étape en CI, mais une
  démarche publique chez un tiers, une clé GPG, et `tofu state replace-provider`
  à l'aller comme au retour.
- **Compiler le fork en CI** : rien à publier, mais Go dans deux jobs et une à
  deux minutes de plus à chaque exécution.

## Conséquences

- Une étape de plus avant `tofu init` dans ce module, en local comme en CI.
- linux_amd64 seulement, binaire non signé : la confiance tient au SHA-256
  épinglé dans `.github/scripts/fetch_pangolin_provider.sh`.
- Le zip du provider `trozz/pocketid` 2.5.0, dont l'amont a perdu les
  releases, vit dans la release `provider-pocketid-2.5.0` de ce dépôt, posée à
  la main, sans seconde copie (une reste dans le cache de plugins du poste) :
  la supprimer casse `tofu init` de `pangolin_config`.
- Renovate ne suit plus ce provider : une version amont ne se verra pas seule.
- Retour à l'amont dès qu'il a repris ce que la config utilise : la procédure
  est au README du module.

## Liens

PR #1124, [README du module](../../tofu/pangolin_config/README.md#provider-a-build-of-the-fork).
