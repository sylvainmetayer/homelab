# MCP Homebox (lecture, création et modification de fiches)

Serveur MCP stdio d'environ 150 lignes (bibliothèque standard, aucune
dépendance), lancé par Claude Code sur le poste, comme `scripts/immich-mcp/`.
Rien n'est ouvert de plus, pas d'OAuth.

Outils : `search_items`, `get_item`, `list_locations`, `list_tags`,
`statistics` (lecture) ; `create_item` (nom, description, quantité, lieu,
étiquettes, fabricant, modèle) ; `update_item` (ces champs plus numéro de
série, achat, garantie, notes).

**Jamais de suppression.** Une clé d'API Homebox n'a pas de périmètre (elle
porte le rôle « user » du compte, `middleware.go` de la 0.27.1) : la
garantie est dans le serveur. `ALLOWED` liste les couples méthode/chemin
envoyés (sept) ; tout autre est refusé avant l'envoi, DELETE compris, et les
tests le vérifient (`test_refused_calls`). `update_item` relit la fiche puis
renvoie un PUT complet (le PUT de Homebox efface les champs absents), et
refuse un lieu. `create_item` n'accepte pas `entityTypeId` : pas de lieu
créé par ce biais.

API de la version épinglée (0.27.1, `swagger.json` du tag) : les objets et
les lieux sont des `entities` (`/api/v1/entities`), les « labels » des `tags`.

## Authentification : clé d'API du compte de Sylvain

Pas de mot de passe local ni de `/users/login` : Homebox 0.27 a des clés
d'API (`HBOX_AUTH_API_KEY_PEPPER` est déjà posé par le rôle), envoyées en
`Authorization: Bearer <clé>`, qui marchent pour un compte créé par Pocket ID.
La carte Homepage n'a pas de connexion à réutiliser : c'est un simple lien.

Geste : Homebox (homebox.sylvain.cloud), connecté par Pocket ID > profil >
clés d'API > créer `claude-mcp`, **avec une date d'expiration** (sans elle,
30 jours). La clé n'est montrée qu'une fois ; l'exporter en `HOMEBOX_API_KEY`
là où Karakeep et Immich tiennent les leurs. À refaire à l'échéance ; la
révoquer dans le même écran. Changer `homebox_api_key_pepper` les invalide
toutes.

## Activation

Dans le `.mcp.json` du checkout du homelab (exclu de git), ajouter :

```json
"homebox": {
  "command": "python3",
  "args": ["/home/sylvain/Documents/homelab/scripts/homebox-mcp/homebox_mcp.py"],
  "env": {
    "HOMEBOX_URL": "https://homebox.sylvain.cloud",
    "HOMEBOX_API_KEY": "${HOMEBOX_API_KEY}",
    "HOMEBOX_PANGOLIN_TOKEN_ID": "${HOMEBOX_PANGOLIN_TOKEN_ID}",
    "HOMEBOX_PANGOLIN_TOKEN": "${HOMEBOX_PANGOLIN_TOKEN}"
  }
}
```

Redémarrer Claude Code, approuver le serveur (`/mcp`).

## Joignabilité : jeton d'accès Pangolin

`website_homebox.tf` n'ouvre aucun chemin : tout `homebox.sylvain.cloud`, `/api`
compris, est derrière le mur SSO de Pangolin (et le filtre FR/DE). Le serveur
passe ce mur avec le jeton d'accès Pangolin `claude-code`
(`pangolin_resource_access_token.homebox_clients`), à lire une fois dans
`tofu/pangolin_config` :

    tofu output -json homebox_client_access_tokens

et à exporter dans `HOMEBOX_PANGOLIN_TOKEN_ID` (`P-Access-Token-Id`) et
`HOMEBOX_PANGOLIN_TOKEN` (`P-Access-Token`), là où vit `HOMEBOX_API_KEY`. La clé
d'API reste obligatoire : c'est elle qui authentifie auprès de Homebox.

## Non testé contre le vrai service

Aucun appel réel n'a été fait : le schéma vient du swagger du tag 0.27.1. À
vérifier au premier essai : `POST /entities` sans type (type d'objet par
défaut ?), l'aller-retour des dates et des champs personnalisés dans le PUT,
le sens de `locationId` face à `parentId`.

## Test

`cd scripts/homebox-mcp && python3 -I -m unittest -v`
