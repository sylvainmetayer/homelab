# Immich Swipe (swipe-photos.sylvain.cloud) : erreur de connexion, mode aléatoire, clé d'API

Conteneur `immich-swipe` du projet Immich sur le Raspberry Pi (rôle `immich`,
`pi.yml`, `dc@immich`, dossier `/opt/apps/immich`), réseaux `newt` et
`immich`. Avec la clé SOPS `immich_swipe_api_key`, son nginx
(`immich-swipe.conf`, monté à la place du `default.conf` de l'image) passe
`/api/` à `immich-server:2283` en y posant la vraie clé, et préconfigure
l'appli (serveur = la page elle-même, clé = le leurre `server-side`). Détail :
[README du rôle](../../ansible/roles/immich/README.md).

## Symptôme

- L'appli affiche une erreur de connexion, ou l'écran de connexion au lieu
  des photos.
- Le mode aléatoire ne montre rien (400 « Validation failed »).
- Page de connexion de Pangolin, ou refus, alors que Sylvain passe le SSO
  d'Immich.
- Moniteur « Healthcheck Immich Swipe » DOWN.

## Diagnostic

Outils de développement du navigateur, onglet Réseau, sur les appels
`/api/...` de `swipe-photos.sylvain.cloud` :

| Réponse | Cause probable |
|---|---|
| `401` d'Immich | clé révoquée, expirée, ou permissions retirées |
| `403` d'Immich | permission manquante sur la clé (une action précise échoue : favori, corbeille, album) |
| `502` / `504` de nginx | `immich-server` arrêté ou injoignable sur le réseau `immich` |
| `400` sur `/api/assets/random` | appel non réécrit : mode préconfiguré absent (pas de clé SOPS), ou une montée d'Immich a changé `POST /api/search/random` |
| redirection vers le SSO | session Pangolin expirée, ou Sylvain hors du rôle `immich-swipe` |

Sur le Pi :

```bash
cd ansible && mise run ssh_pi
systemctl --user status dc@immich
cd /opt/apps/immich && docker compose ps immich-swipe immich-server
docker logs --tail 100 immich-swipe            # journal d'accès nginx : codes de retour
ls -l /opt/apps/immich/immich-swipe.conf       # absent = mode non préconfiguré
```

La clé est-elle acceptée par Immich ? Sans la mettre sur une ligne de
commande :

```bash
sed -n 's/.*x-api-key "\(.*\)";/x-api-key: \1/p' /opt/apps/immich/immich-swipe.conf | head -1 \
  | curl -s -o /dev/null -w '%{http_code}\n' -H @- http://127.0.0.1:2283/api/users/me
```

`200` : clé valide ; `401` : clé refusée.

Accès : le rôle Pangolin est `immich-swipe`, **pas** `immich`
(`tofu/pangolin_config/website_immich_swipe.tf`), créé sans membre ; être
membre d'`immich` ne suffit pas.

## Réparation

- **Clé refusée ou permission manquante** : nouvelle clé dans Immich, compte
  de Sylvain, Account Settings → API Keys, nom `immich-swipe`, permissions
  `user.read`, `asset.read`, `asset.view`, `asset.download`, `asset.update`,
  `asset.delete`, `album.read`, `albumAsset.create`. Puis, depuis
  `ansible/` :

  ```bash
  read -rs KEY && printf '%s' "$KEY" | jq -Rs . | sops set --value-stdin ../secrets/ansible.sops.yaml '["immich_swipe_api_key"]'; unset KEY
  ansible-playbook pi.yml --tags immich --check --diff
  ansible-playbook pi.yml --tags immich
  ```

  Le changement du fichier redémarre **tout** `dc@immich` (handler
  `Restart immich service`) : quelques minutes sans Immich. Ensuite :
  `last_rotated` dans `secrets/secrets-rotation.yaml`, commit et bump du
  sous-module `secrets/` ([rotation-des-secrets.md](rotation-des-secrets.md),
  « Secret d'appli lu par Ansible »), puis révoquer l'ancienne clé dans
  Immich.
- **Écran de connexion ou erreurs après retrait de la clé** : le navigateur
  garde la configuration injectée (serveur = `swipe-photos`, clé = le
  leurre). S'y déconnecter dans l'appli pour retrouver l'écran de connexion,
  ou remettre la clé SOPS.
- **Mode aléatoire en 400 malgré la préconfiguration** : comparer la forme
  `filter` de `location = /api/assets/random` (`immich-swipe.conf.j2`) avec
  `search.dto.ts` de la version d'Immich installée, corriger le modèle par
  une PR (merger sur `main` déploie `pi.yml`).
- **`immich-server` arrêté** : [appli-en-panne.md](appli-en-panne.md) (même
  procédure, sur le Pi).
- **Sylvain hors du rôle** : interface de Pangolin, rôles de son utilisateur
  dans l'organisation, ajouter `immich-swipe`.

## Vérification

- `https://swipe-photos.sylvain.cloud` montre une photo sans écran de
  connexion ; le mode aléatoire en charge plusieurs ; un favori se pose.
- La commande `curl` ci-dessus rend `200`.
- Moniteur « Healthcheck Immich Swipe » UP.

## Prévention

- Une montée d'Immich peut casser le mode aléatoire réécrit : l'essayer
  après chaque montée. Le vrai correctif (appeler `/search/random` dans le
  fork `sylvainmetayer/immich-swipe`) retirerait ce `location`.
- Qui passe ce SSO agit avec la clé de Sylvain : le rôle `immich-swipe` ne
  reçoit que lui. Un test d'invariant de `pangolin_config` garde Swipe lié à
  ce seul rôle.
