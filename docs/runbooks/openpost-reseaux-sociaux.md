# OpenPost (posts.sylvain.cloud) : brancher une page Facebook et un compte Instagram, les rebrancher, publication en échec

Procédure, pas un incident. OpenPost tourne sur flip (rôle `openpost`,
`dc@openpost`, [README du rôle](../../ansible/roles/openpost/README.md)). Les
identifiants des réseaux ne sont ni dans SOPS ni dans le dépôt : ils se
saisissent dans l'interface et sont chiffrés dans la base avec
`OPENPOST_ENCRYPTION_KEY`. Ce qui suit est donc à refaire à la main après une
perte de la base sans sauvegarde, ou pour une nouvelle app Meta.

Réseaux branchés à ce jour, depuis le 2026-11-12 : **Facebook (une page)** et
**Instagram** (un compte professionnel lié à cette page), par la même app
Meta.

Guides amont, à relire si un écran ne correspond plus :
<https://openpo.st/docs/self-hosting/integrations/facebook>,
<https://openpo.st/docs/self-hosting/integrations/instagram>.

## Ce qu'il faut avoir

- Un compte développeur Meta (<https://developers.facebook.com/apps/>), celui
  du profil Facebook qui administre la page.
- Une **page** Facebook : OpenPost ne publie pas sur un profil personnel.
- Le rôle administrateur de l'instance OpenPost (le premier compte créé).

## 1. L'app Meta

1. Créer une app (ou ouvrir celle qui existe) avec le produit
   **Facebook Login**.
2. **Facebook Login → Settings → Valid OAuth Redirect URIs** :

   ```text
   https://posts.sylvain.cloud/api/v1/accounts/facebook/callback
   ```

3. Permissions demandées par OpenPost, à ajouter à l'app :

   | Permission | Sert à |
   |---|---|
   | `pages_show_list` | lister les pages du profil |
   | `pages_manage_posts` | publier |
   | `pages_read_engagement` | lire la page et ses publications |
   | `pages_read_user_content` | commentaires |
   | `pages_manage_engagement` | répondre aux commentaires |
   | `pages_manage_metadata` | conversations Messenger |
   | `pages_messaging` | demandée même si les messages restent coupés |
   | `business_management` | pages rangées dans un portefeuille d'entreprise |

4. **App settings → Basic** : relever l'**App ID** et l'**App Secret**.

L'app reste en **mode développement**, sans revue Meta : seuls les comptes qui
ont un rôle sur l'app (son créateur en est administrateur) peuvent se
connecter et publier. Cela suffit pour le foyer tant que c'est le même profil
qui gère les pages ; quelqu'un d'autre s'ajoute dans **App roles**.

## 2. L'app dans OpenPost

1. **Settings → Instance → Configuration → Provider apps**, choisir
   **Facebook**.
2. Saisir l'App ID, l'App Secret et la même URL de redirection, au caractère
   près.
3. Enregistrer. Si Facebook reste grisé dans l'espace de travail, redémarrer
   sur flip :

   ```bash
   systemctl --user restart dc@openpost
   ```

## 3. Connecter la page

1. **Settings → Workspace → Social accounts → Facebook**.
2. Se connecter avec le profil qui gère la page, accorder les permissions
   **en cochant la page** dans l'écran de Meta.
3. Choisir la page proposée.

## Vérification

1. Publier tout de suite un court message **texte** sur la page : statut
   « publié » dans OpenPost, message visible sur la page.
2. Puis une **image** : Meta télécharge le fichier depuis
   `https://posts.sylvain.cloud/media/<uuid>` par un lien signé, d'où le
   passage de `/media/*` hors SSO et hors filtre FR/DE
   (`tofu/pangolin_config/website_openpost.tf`).
3. Supprimer les deux publications de test sur la page.

## Instagram, par la page Facebook

Même app Meta, mêmes App ID et App Secret : Instagram passe par « Continue
with Facebook », pas par le login Instagram direct (autre produit Meta, autres
identifiants, non utilisé ici).

### Le compte Instagram

1. Compte **professionnel** (Entreprise ou Créateur), un compte personnel est
   refusé : dans l'app, ☰ → Type de compte et outils → Passer à un compte
   professionnel. Le profil affiche ensuite « Tableau de bord professionnel ».
2. Un compte créé depuis un autre compte Instagram partage sa connexion et
   **n'a pas de mot de passe** : lui en créer un (☰ → Espace Comptes → Mot de
   passe et sécurité), Meta le demande à l'étape suivante.
3. Le lier à la page : sur Facebook, en tant que la page, Paramètres →
   **Comptes liés** → Instagram → Connecter un compte. Vérifier que c'est bien
   ce compte qui y figure, pas le compte Instagram personnel.

### L'app Meta

1. **Cas d'usage** → ajouter « Gérer les messages et le contenu sur
   Instagram » → Personnaliser → **API setup with Facebook login**.
2. Y ajouter **toutes** les permissions ci-dessous. OpenPost les demande d'un
   bloc à la connexion ; une seule absente de l'app et Meta refuse tout
   (« Invalid Scopes: … », vécu le 2026-11-12 avec les deux dernières).

   | Permission | Sert à |
   |---|---|
   | `instagram_basic` | lire le compte |
   | `instagram_content_publish` | publier |
   | `instagram_manage_comments` | commentaires (coupés, mais demandée) |
   | `instagram_manage_messages` | messages (coupés, mais demandée) |
   | `instagram_manage_insights` | statistiques (coupées, mais demandée) |
   | `pages_show_list`, `pages_read_engagement`, `pages_read_user_content`, `pages_manage_metadata`, `business_management` | déjà là pour Facebook |

3. **Facebook Login → Settings → Valid OAuth Redirect URIs**, en plus de
   celle de Facebook :

   ```text
   https://posts.sylvain.cloud/api/v1/accounts/instagram/callback
   ```

### OpenPost

1. **Provider apps** → **Instagram** (pas « Instagram (direct login) ») : App
   ID, App Secret, l'URL ci-dessus. Enregistrer, puis
   `systemctl --user restart dc@openpost` sur flip.
2. **Social accounts → Instagram → Continue with Facebook**. Sur l'écran de
   Meta, cocher la page **et** le compte Instagram (« Modifier l'accès » si
   Meta ressert le choix fait pour Facebook).
3. Vérification : publier une **image JPEG** avec une courte légende
   (Instagram refuse un post sans média), la voir sur le compte, la supprimer.

## Si ça ne marche pas

| Symptôme | Vérifier |
|---|---|
| Erreur de redirection chez Meta | l'URL est identique dans Meta et dans OpenPost (pas de `/` final, `https`, `facebook` ou `instagram` dans le chemin) |
| Aucune page proposée | le profil connecté administre la page ; la page a été cochée pendant le consentement (sinon : retirer l'app dans les « intégrations professionnelles » du profil Facebook et recommencer) ; page d'un portefeuille d'entreprise : contrôle total exigé |
| Un autre membre du foyer ne peut pas se connecter | app en mode développement : lui donner un rôle dans **App roles**, il accepte l'invitation |
| Le texte passe, pas l'image | `curl -sI https://posts.sylvain.cloud/media/00000000-0000-4000-8000-000000000000` depuis l'extérieur doit répondre `401` d'OpenPost, pas la page de connexion de Pangolin ni un `403` (règle `/media/*` de Pangolin) |
| Connecté, publication refusée | l'erreur de Meta est dans le journal ; permission retirée ou ajoutée depuis : déconnecter et reconnecter la page |
| Instagram : « Invalid Scopes: … » chez Meta | les permissions nommées manquent à l'app : les ajouter au cas d'usage Instagram, relancer la connexion (rien à redémarrer). Introuvables dans la liste : app récente sous « Unified login », il faut un `config_id` (guide amont, non essayé ici) |
| Instagram : « exige un compte Business ou Créateur lié à une Page Facebook » | Meta ne renvoie aucun compte rattaché aux pages. Dans l'[explorateur de l'API Graph](https://developers.facebook.com/tools/explorer/), `me/accounts?fields=name,instagram_business_account` : page sans `instagram_business_account` = compte pas professionnel ou pas lié à la page ; avec = il n'a pas été coché au consentement (« Modifier l'accès », ou retirer l'app des intégrations professionnelles du profil, ce qui débranche aussi la page Facebook) ; page absente = accès à la page, portefeuille d'entreprise |
| Instagram montre le post, OpenPost annonce un échec | **ne pas republier** : OpenPost revérifie seul le conteneur déjà créé |
| Tout marchait, puis « reconnecter le compte » | jeton révoqué (mot de passe Facebook changé, app retirée du profil) : refaire l'étape 3 (Instagram : « Continue with Facebook ») |

Journal, sur flip (jamais par `flip.internal`, voir
[flip-injoignable.md](flip-injoignable.md)) :

```bash
docker logs --since 15m openpost
```

Il nomme l'opération, le code HTTP et le code d'erreur de Meta, sans jeton ni
contenu.

## Après une restauration

La sauvegarde Borg `openpost` porte la base et le `.env` : les identifiants de
l'app et les connexions (page, compte Instagram) reviennent avec eux. Si la clé
`OPENPOST_ENCRYPTION_KEY` a changé (`app_secrets_seed` différent), la base ne
se relit plus : refaire les étapes 2 et 3 et la partie « OpenPost » d'Instagram ;
l'app Meta, elle, n'a pas bougé.
