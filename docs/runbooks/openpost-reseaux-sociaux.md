# OpenPost (posts.sylvain.cloud) : brancher Facebook, Instagram, TikTok, YouTube et LinkedIn, les rebrancher, publication en échec

Procédure, pas un incident. OpenPost tourne sur flip (rôle `openpost`,
`dc@openpost`, [README du rôle](../../ansible/roles/openpost/README.md)). Les
identifiants des réseaux ne sont ni dans SOPS ni dans le dépôt : ils se
saisissent dans l'interface et sont chiffrés dans la base avec
`OPENPOST_ENCRYPTION_KEY`. Ce qui suit est donc à refaire à la main après une
perte de la base sans sauvegarde, ou pour une nouvelle app chez un réseau.
[LinkedIn](#linkedin) fait exception : son secret est dans SOPS, posé par le
rôle.

Réseaux branchés à ce jour, depuis le 2026-11-12 : **Facebook (une page)** et
**Instagram** (un compte professionnel lié à cette page), par la même app
Meta.

[TikTok](#tiktok) et [YouTube](#youtube) sont écrits le 2026-11-16 d'après les
guides amont, **pas encore essayés** : ce qui y est marqué « à confirmer » se
corrige au premier branchement, et cette phrase s'en va.

Guides amont, à relire si un écran ne correspond plus :
<https://openpo.st/docs/self-hosting/integrations/facebook>,
<https://openpo.st/docs/self-hosting/integrations/instagram>,
<https://openpo.st/docs/self-hosting/integrations/tiktok>,
<https://openpo.st/docs/self-hosting/integrations/youtube>,
<https://openpo.st/docs/self-hosting/integrations/linkedin>.

## Ce qu'il faut avoir (Facebook, Instagram)

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

## TikTok

Sans audit de TikTok, la **publication directe reste privée** : visibilité
« moi uniquement », compte passé en privé au moment de publier. TikTok
n'accorde pas l'audit à une app qui ne publie que sur les comptes de sa propre
équipe (*Content Sharing Guidelines*) : ne pas compter dessus. Le mode
**Upload** est la voie du foyer : la vidéo arrive dans la boîte de réception
de l'app TikTok, où l'on termine la publication (visibilité choisie là : à
confirmer).

### L'app TikTok

1. Avec un compte TikTok for Developers,
   <https://developers.tiktok.com/apps/> : créer une app, puis un **Sandbox**
   dedans (Client Key à lui, pas de revue ; le guide amont ne parle pas de
   sandbox : qu'il permette la vérification du domaine ci-dessous est à
   confirmer, sinon reprendre sur l'app elle-même).
2. Produits **Login Kit** et **Content Posting API** (« Direct Post » activé).
3. Login Kit, plateforme Web, Redirect URI :

   ```text
   https://posts.sylvain.cloud/api/v1/accounts/tiktok/callback
   ```

4. Les six scopes qu'OpenPost demande d'un bloc :

   | Scope | Sert à |
   |---|---|
   | `user.info.basic` | identité, nom affiché, avatar |
   | `video.publish` | publication directe |
   | `video.upload` | envoi dans la boîte de réception |
   | `user.info.profile` | nom d'utilisateur |
   | `user.info.stats`, `video.list` | statistiques, rapprochement des vidéos publiées |

   Si le sandbox refuse les trois derniers (API Display, à confirmer) : poser
   `OPENPOST_DISABLE_TIKTOK_DISPLAY_API=true` dans le `.env` du rôle
   (`ansible/roles/openpost/templates/env.j2`, non câblé à ce jour) ; OpenPost
   ne demande alors que les trois premiers.
5. **Sandbox settings → Target users** : ajouter le compte TikTok qui publiera.
6. Relever la **Client Key** et le **Client Secret** du sandbox.

### La preuve de propriété du domaine

OpenPost remet à TikTok une URL `https://posts.sylvain.cloud/media/<uuid>` à
venir chercher (`PULL_FROM_URL`) : TikTok exige que le domaine soit vérifié.
La vérification par fichier (préfixe d'URL) est impossible, OpenPost ne sert
rien d'autre que ses médias sous `/media/` : passer par le DNS.

1. Dans l'app, **URL properties → Verify → Domain** : `sylvain.cloud`
   (l'apex couvre `posts.` : à confirmer).
2. TikTok donne une valeur `tiktok-developers-site-verification=…` : un
   enregistrement TXT à l'apex dans `tofu/dns`, sur le modèle de
   `search_console.tf`, en PR, puis `tofu apply` du module.
3. « Verify » chez TikTok. L'enregistrement reste en place ensuite.

### OpenPost

1. **Settings → Instance → Configuration → Provider apps** → **TikTok** :
   Client Key, Client Secret, la même URL de redirection. Enregistrer ; TikTok
   grisé dans l'espace de travail : `systemctl --user restart dc@openpost` sur
   flip.
2. **Settings → Workspace → Social accounts → TikTok**, accorder les
   permissions.
3. Vérification : une courte vidéo en mode **Upload**, attendue dans la boîte
   de réception de l'app TikTok ; puis une en **Direct Post**, compte en
   privé, attendue en « moi uniquement ». Les supprimer.

### Si ça ne marche pas (TikTok)

| Symptôme | Vérifier |
|---|---|
| Échec à la connexion | URL de redirection identique des deux côtés ; scope demandé absent de l'app ; compte absent des *Target users* du sandbox |
| TikTok ne récupère pas le média (`url_ownership_unverified`) | domaine vérifié dans *URL properties* ; `curl -sI https://posts.sylvain.cloud/media/00000000-0000-4000-8000-000000000000` depuis l'extérieur répond `401` d'OpenPost, pas la page de connexion de Pangolin ni un `403` |
| Publication refusée ou privée | app non auditée : compte en privé et visibilité « moi uniquement » en Direct Post ; scope ajouté depuis : reconnecter le compte |

## YouTube

Rien dans le dépôt, pas de DNS : OpenPost envoie le fichier lui-même. Tant que
le projet Google n'a pas passé l'audit de l'API YouTube, les vidéos envoyées
par l'API restent **privées** (projets créés après le 2020-07-28), sans doute
verrouillées ainsi dans YouTube Studio (à confirmer). L'audit est un
formulaire à part chez Google, à demander si l'essai convainc.

### Le projet Google

1. Avec le compte Google propriétaire de la chaîne (ou un autre, la chaîne
   se choisit à la connexion), <https://console.cloud.google.com/> : créer un
   projet.
2. **APIs & Services → Library** : activer **YouTube Data API v3** et
   **YouTube Analytics API**.
3. **Google Auth Platform** : écran de consentement, audience **External**,
   nom de l'app et e-mail de contact, domaine autorisé `sylvain.cloud`, le
   compte Google de la chaîne en **test user**.
4. **Data Access** : les cinq scopes qu'OpenPost demande d'un bloc.

   ```text
   https://www.googleapis.com/auth/youtube.readonly
   https://www.googleapis.com/auth/yt-analytics.readonly
   https://www.googleapis.com/auth/youtube.upload
   https://www.googleapis.com/auth/youtube
   https://www.googleapis.com/auth/youtube.force-ssl
   ```

5. **Clients** : un **OAuth client ID** de type **Web application**,
   Authorized redirect URI :

   ```text
   https://posts.sylvain.cloud/api/v1/accounts/youtube/callback
   ```

6. Relever le **Client ID** et le **Client Secret**.

En « Testing », Google révoque la connexion au bout de **7 jours** : il faut
reconnecter la chaîne. Passer l'app en **In production** sans demander la
vérification garde l'écran « app non vérifiée » mais le jeton ne périme plus
(à confirmer).

### OpenPost

1. **Provider apps** → **YouTube** : Client ID, Client Secret, la même URL de
   redirection. Enregistrer ; YouTube grisé :
   `systemctl --user restart dc@openpost` sur flip.
2. **Social accounts → YouTube** : le compte Google propriétaire de la
   chaîne, passer l'écran « app non vérifiée », choisir la chaîne.
3. Vérification : une courte vidéo en **Private**, « Made for kids » sur
   **No** ; statut « publié » dans OpenPost, vidéo dans YouTube Studio. Y
   essayer de la passer en public : c'est ce qui dit si l'audit est
   indispensable. La supprimer.

Une publication programmée par YouTube (`publish_at`) part en **Private** avec
une date RFC 3339 ; OpenPost l'annonce publiée dès l'envoi terminé.

### Si ça ne marche pas (YouTube)

| Symptôme | Vérifier |
|---|---|
| Google bloque le consentement | compte dans les *test users* ; les cinq scopes dans *Data Access* |
| Aucune chaîne proposée | le compte Google choisi possède la chaîne |
| Envoi en échec, ou vidéo restée privée | YouTube Data API v3 activée ; projet non audité : privé seulement |
| « redirect_uri_mismatch » | URL identique chez Google et dans OpenPost |
| « Reconnecter le compte » chaque semaine | app en « Testing » : jeton de 7 jours |

## LinkedIn

Mis en place le 2026-11-20. Le **profil personnel** se branche tout de suite
(produits en libre-service) ; les **pages d'entreprise** demandent l'accès
« Community Management API », que LinkedIn approuve à la main et seulement sur
une app sans autre produit : d'où deux apps.

| | App « OpenPost » | App « OpenPost Pages » |
|---|---|---|
| Sert à | publier sur le profil | publier sur les pages, une fois approuvée |
| Réglages | <https://www.linkedin.com/developers/apps/266754818/auth> | <https://www.linkedin.com/developers/apps/266759747/products> |
| Produits | « Sign In with LinkedIn using OpenID Connect », « Share on LinkedIn » | aucun avant l'approbation |
| État | posée par le rôle, compte à connecter | demande à déposer (mail professionnel à valider) |

Les deux sont rattachées à la page LinkedIn « Sylvain homelab »
(<https://www.linkedin.com/company/146999613>), créée pour ça : LinkedIn exige
une page par app, et qu'elle « vérifie » l'app avant toute demande d'accès
(irréversible ; fait pour « OpenPost Pages »). La page ne sert à rien d'autre.

### L'app LinkedIn (profil)

À refaire seulement si l'app est perdue.

1. <https://www.linkedin.com/developers/apps/new> : nom, la page LinkedIn, un
   logo carré (obligatoire), accepter les conditions de l'API.
2. Onglet **Products** : « Request access » sur « Share on LinkedIn » et sur
   « Sign In with LinkedIn using OpenID Connect » (accordés aussitôt).
3. Onglet **Auth** → *Authorized redirect URLs* :

   ```text
   https://posts.sylvain.cloud/api/v1/accounts/linkedin/callback
   ```

   Les scopes affichés dessous : `openid`, `profile`, `email`,
   `w_member_social`.

### OpenPost

Rien à saisir dans l'interface : le rôle pose les identifiants dans le `.env`
(`LINKEDIN_CLIENT_ID`, `LINKEDIN_CLIENT_SECRET`) et
`OPENPOST_DISABLE_LINKEDIN_THREAD_REPLIES=true`, sans lequel OpenPost demande
`w_member_social_feed`, que l'app n'a pas : la connexion échoue.

1. **Client ID** (onglet Auth de l'app) : clé SOPS
   `openpost_linkedin_client_id`. Public, mais gitleaks le refuse dans ce
   dépôt.
2. **Client Secret** (même onglet) : clé SOPS
   `openpost_linkedin_client_secret`. Les deux se posent depuis la racine du
   dépôt (`docs/conventions/secrets.md` pour les deux commits) :

   ```bash
   sops set secrets/ansible.sops.yaml '["openpost_linkedin_client_id"]' '"…"'
   sops set secrets/ansible.sops.yaml '["openpost_linkedin_client_secret"]' '"…"'
   ```

3. `ansible-playbook flip.yml --tags openpost` (le merge le fait).
4. **Settings → Workspace → Social accounts → LinkedIn**, accepter chez
   LinkedIn, choisir le profil.
5. Vérification : un texte court, publié tout de suite, vu sur le profil ; le
   supprimer.

Le jeton d'accès dure 2 mois (réglage de l'app) : reconnecter le compte quand
OpenPost le signale.

Changer le secret (« Generate a new Client Secret » dans l'onglet Auth) :
étapes 2 et 3, puis `last_rotated` dans `secrets/secrets-rotation.yaml`. Les
comptes connectés le restent.

### Les pages d'entreprise

1. App « OpenPost Pages », onglet **Products** → « Community Management API »
   → « Request access » : LinkedIn demande une adresse e-mail professionnelle,
   y envoie un code, puis un formulaire (non vu à ce jour : à compléter ici).
2. Une fois l'accès accordé, ajouter à l'app la même URL de redirection, puis
   basculer OpenPost sur elle : son Client ID et son secret dans les deux clés SOPS, et dans
   `env.j2` :

   ```text
   OPENPOST_LINKEDIN_AUTH_MODE=community_management
   OPENPOST_LINKEDIN_ORGANIZATIONS_ENABLED=true
   OPENPOST_DISABLE_LINKEDIN_THREAD_REPLIES=false
   ```

3. **Reconnecter le compte** : changer d'app change l'identité du membre, les
   jetons de l'ancienne ne se reprennent pas. Le profil et les pages dont le
   compte est administrateur sont alors proposés, un compte OpenPost chacun.

Palier « Development » : 500 appels par app et 100 par membre sur 24 h.

### Si ça ne marche pas (LinkedIn)

| Symptôme | Vérifier |
|---|---|
| Erreur de redirection | URL identique, au caractère près, dans l'onglet Auth et `https://posts.sylvain.cloud` |
| Scope refusé à la connexion | `OPENPOST_DISABLE_LINKEDIN_THREAD_REPLIES=true` dans `/opt/apps/openpost/.env` sur flip ; les deux produits toujours dans l'onglet Products |
| LinkedIn grisé dans l'espace de travail | la clé SOPS est-elle arrivée : `grep -c '^LINKEDIN_CLIENT_' /opt/apps/openpost/.env` sur flip répond 2 ; sinon relancer le playbook |
| Pas de page proposée | app « OpenPost Pages » approuvée et en service, `OPENPOST_LINKEDIN_ORGANIZATIONS_ENABLED=true`, compte administrateur de la page |

## Si ça ne marche pas (Facebook, Instagram)

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
se relit plus : refaire les étapes 2 et 3 de Facebook et la partie
« OpenPost » d'Instagram, de TikTok et de YouTube ; les apps chez Meta, TikTok
et Google, elles, n'ont pas bougé.
