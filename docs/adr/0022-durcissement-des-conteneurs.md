# 0022. Conteneurs : `no-new-privileges` par défaut, contrôlé en CI, `cap_drop` au cas par cas

- **Statut** : acceptée
- **Date** : 2026-11-03

## Contexte

Certains services portaient déjà ces options, sans règle écrite. Molecule ne
démarre aucune image : une option perdue ne se voit pas, un conteneur cassé par
une option ne se voit qu'en prod. Motif du chantier non écrit : à confirmer.

## Décision

- **`no-new-privileges` sur tout service**, sauf exception listée avec sa raison.
  `check_container_hardening.py` (Lint) échoue sur un service sans l'option et
  sur une exception périmée. 27 services en exception au 2026-11-03.
- **`cap_drop: [ALL]`** quand l'image tourne sans privilège dès sa première
  instruction ; une image lancée en root ne l'a qu'avec un `cap_add` testé.
  Rien ne le contrôle en CI.
- `read_only` et réseau : au choix de chaque rôle (raison non écrite).

## Alternatives écartées

- **`cap_drop: [ALL]` partout** : les bases passent le dossier de données à un
  autre utilisateur, une capacité manquante se voit au redémarrage, sur les
  données ; les capacités des images s6 changent avec leurs scripts d'init.
- **Doctrine sans contrôle** : un oubli passerait inaperçu (voir Contexte).
- **Contrôle sur les templates rendus** : un `{% if %}` faux cacherait le
  service (Keycloak de `flip_planning`). Lecture ligne à ligne : une option
  sous un `{% if %}` compte comme présente, limite assumée (#1144).

## Conséquences

- Immich, Pangolin, Newt, `flip_planning`, Paperless et Monica restent hors
  périmètre **sans analyse de l'image** : à faire avant de lever l'exception.
- Non éprouvé au 2026-11-03 : file Sidekiq, crawl de Karakeep, mise à niveau
  automatique de MariaDB (QG homelab).
- Une image automergée peut casser son `cap_add` : revert **et** retrait de la
  liste d'automerge ([0008](0008-renovate-hebdomadaire.md)).

## Liens

PR #1132 à #1136, #1142 à #1144 ; [container-hardening.md](../conventions/container-hardening.md).
