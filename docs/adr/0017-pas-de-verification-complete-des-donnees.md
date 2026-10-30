# 0017. Pas de vérification complète des données Borg

- **Statut** : acceptée
- **Date** : 2026-10-30

## Contexte

[0001](0001-sauvegardes-borgmatic.md) prévoyait un `borg check --verify-data`
trimestriel en CI, par le sous-compte en lecture seule. Ses deux runs (29 et
30/10) : tous les blocs vérifiés sans erreur, puis borg 1.4.5 écrit le
fichier `nonce` du dépôt et reçoit `EROFS` : impossible en lecture seule.

## Décision

- Le workflow `borg-check.yaml` et le mode `--verify-data` de
  `restore_test.py` sont retirés.
- Aucune vérification de tous les blocs ne le remplace : restent le test de
  restauration (échantillon de 20 fichiers, dumps rejoués, SQLite vérifiés,
  deux fois par mois) et les checks `repository` (15 jours) et `archives`
  (mensuel) de borgmatic sur les hôtes.

## Alternatives écartées

- Accepter l'échec `EROFS` quand 0 bloc n'est corrompu : code spécial pour
  un cas de borg, et la passe sur les métadonnées d'archives reste coupée.
- Un sous-compte CI en écriture : la CI pourrait modifier ou supprimer les
  dépôts, on perd l'isolation de [0001](0001-sauvegardes-borgmatic.md).
- Un check `data` trimestriel sur les hôtes : relecture et déchiffrement de
  chaque dépôt, lourd en I/O sur le SSD de la VM docker (Immich, Nextcloud).

## Conséquences

- Un bloc corrompu hors de l'échantillon du test n'est vu qu'à une vraie
  restauration ; en échange, moins de code et de charge, CI en lecture seule.

## Liens

PR #884 (check trimestriel), #1007 (diagnostic), #1010 (retrait) ;
[.github/restore-test/README.md](../../.github/restore-test/README.md).
