# Enclosed (pwpush.sylvain.cloud) : lien qui n'ouvre rien, création refusée, `enclosed-share` en échec

Rôle `enclosed`, VM docker, `dc@enclosed`, un conteneur `enclosed` (port
8787) sur `newt` et sur le réseau interne `enclosed-cli`. Notes chiffrées
chez le client, clé dans le fragment du lien (`#dar:<clé>`), jamais envoyée
au serveur. Pas de sauvegarde, exprès. Détail :
[README du rôle](../../ansible/roles/enclosed/README.md).

## Symptôme

- Le destinataire ouvre le lien et ne voit rien, une erreur, ou « note
  introuvable ».
- Le destinataire tombe sur la page de connexion de Pangolin.
- Sylvain ne peut pas créer de note dans le formulaire.
- `enclosed-share` sort en code 1 ou 2.
- Moniteur « Healthcheck Enclosed » DOWN.

## Diagnostic

**Le lien ne montre rien.** Dans l'ordre :

1. **Note déjà lue** : par défaut, une note est supprimée au premier
   `GET /api/notes/<id>` (formulaire : case cochée ; `enclosed-share` : sans
   `--keep`). Qui l'a ouverte en premier l'a consommée : c'est le
   fonctionnement normal, pas une panne.
2. **Note expirée** : 1 jour par défaut dans le formulaire, 3 jours avec
   `enclosed-share` (`--ttl`). Les expirées sont purgées chaque heure.
3. **Lien tronqué** : sans la partie `#dar:<clé>` (messagerie qui coupe au
   `#`, copie partielle), la note existe mais ne se déchiffre pas.
4. **Ouvertures de lecture cassées** (le destinataire voit le SSO de
   Pangolin) : les chemins `/0*`, `/assets/*`, `/api/notes/0*` et
   `/api/notes/0*/exists` doivent passer sans SSO, de n'importe quel pays
   (`local.enclosed_read_paths`, `tofu/pangolin_config/website_enclosed.tf`).

   ```bash
   curl -sI https://pwpush.sylvain.cloud/01AAAAAAAAAAAAAAAAAAAAAAAA | head -1
   ```

   Attendu : `200` (la page de l'appli), pas une redirection vers le SSO.
   Puis `mise exec -- tofu -chdir=tofu/pangolin_config plan` : une règle
   absente s'y voit. Après une montée d'Enclosed, une route a pu changer :
   relire les sources listées pour « Enclosed » dans
   `tofu/pangolin_config/path_bypass_images.json`.

**Création refusée.**

- Page de connexion de Pangolin sur `/` : normal, la création est derrière
  le SSO, rôle `enclosed` **sans membre**, donc administrateurs Pangolin
  seulement.
- Erreur à l'envoi : note de plus de 5 Mio une fois chiffrée
  (`enclosed_max_payload_bytes`), ou durée hors de 1 h, 1 j, 1 sem., 1 mois
  (« sans expiration » est refusé, `PUBLIC_IS_SETTING_NO_EXPIRATION_ALLOWED=false`).
- Serveur en panne : voir plus bas.

**`enclosed-share` en échec** (sur la VM docker, en `sylvain`) :

| Sortie | Cause |
|---|---|
| code 2, « le secret se lit sur l'entrée standard » | lancé au clavier : passer par un tube ou une redirection |
| code 2, « --ttl entre 600 et 2592000 secondes » | `--ttl` hors bornes, ou avec un zéro initial |
| code 1, « pas de conteneur enclosed » | serveur arrêté : `systemctl --user status dc@enclosed` |
| erreur de `npm ci` | premier appel, ou `package-lock.json` changé : le conteneur jetable n'atteint pas le registre npm |
| autre code 1 | entrée vide, ou refus du serveur (taille, durée) |

**Serveur.**

```bash
cd ansible && mise run ssh
systemctl --user status dc@enclosed
docker logs --tail 100 enclosed
docker network inspect enclosed-cli --format '{{range .Containers}}{{.Name}} {{end}}'
```

## Réparation

- **Note lue, expirée ou lien tronqué** : en recréer une et renvoyer le lien
  complet. Pour quelqu'un qui ouvre le lien deux fois (aperçu, autre
  appareil) : `enclosed-share --keep --ttl 86400`.
- **Ouvertures de lecture** : `tofu apply` dans `tofu/pangolin_config`
  (Sylvain), après lecture du plan.
- **Serveur** : `systemctl --user restart dc@enclosed` ; le reste,
  [appli-en-panne.md](appli-en-panne.md). Le volume `enclosed_data` perdu ne
  coûte que les notes en cours : les recréer.
- **`npm ci` qui échoue** : relancer une fois le registre npm joignable ;
  pour repartir de zéro, `rm -rf /opt/apps/enclosed/cli/node_modules`
  (réinstallé au prochain appel).
- **Script ou fichiers du client absents** :
  `ansible-playbook docker.yml --tags enclosed`.

## Vérification

```bash
printf %s test | enclosed-share --ttl 600
```

Le lien sort sur la sortie standard ; l'ouvrir dans une fenêtre privée, sans
session Pangolin : `test` s'affiche, et une seconde ouverture ne montre plus
rien.

## Prévention

- Renovate ne fusionne jamais seul une montée d'Enclosed, et monte
  `@enclosed/lib` (`files/cli/package.json`) dans la même PR : relire les
  chemins ouverts avant de merger.
- Prévenir le destinataire qu'un lien ne s'ouvre qu'une fois.
