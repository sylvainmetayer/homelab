# 0027. Connexions SSH : clés connues tracées, tout le reste sonne

- **Statut** : acceptée
- **Date** : 2026-11-03

## Contexte

`ssh_login_notify` alerte à chaque session. La CI et Ansible depuis le poste
sonnaient donc à chaque déploiement, et un moniteur déjà DOWN ne renotifie pas :
une connexion inconnue dans les 60 s suivant un push ne donnait aucun Telegram.

## Décision

Une clé connue (empreinte SHA256, défauts du rôle : `github-actions` et `perso`,
la clé d'Ansible) laisse une trace basse priorité sur ntfy (topic `scripts`) et
une ligne de journal, sans push. Tout le reste (autre clé, autre méthode,
empreinte illisible, liste vide) pousse comme avant. Même règle sur Pangolin.
newt-lxc a une liste vide : toute connexion y sonne, CI comme poste.

## Alternatives écartées

- Sauter le module PAM (`pam_succeed_if`, `[success=N …]`) : une pile PAM plus
  risquée pour un verrouillage, alors que le script décide déjà.
- Reconnaître une clé à son commentaire : modifiable par qui est connecté.
- Rendre `android` et `pro` connues : plus de silence pour un gain faible.

## Conséquences

- Risque accepté : une clé connue volée ne sonne plus que sur newt-lxc, ailleurs
  sa trace n'est que basse priorité (`perte-cle-ou-poste.md`, étape 7).
- Risque accepté : une connexion avec la clé d'Ansible ne se distingue pas d'un
  `ssh` à la main de Sylvain ou de Claude, qui prennent la même clé.
- Reste : deux connexions inconnues à moins de 60 s sur un hôte ne font qu'une
  alerte ; la seconde est au journal.
- Le lot 2, non fait ici : un timer compare les connexions de la clé de CI aux
  runs GitHub, pour rendre à cette clé une alerte sur un usage hors déploiement.

## Liens

`ansible/roles/ssh_login_notify/README.md` ; [perte-cle-ou-poste.md](../runbooks/perte-cle-ou-poste.md).
