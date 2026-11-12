# MCP Grocy (lecture, liste de courses et corvées)

Serveur MCP stdio d'environ 200 lignes (bibliothèque standard, aucune
dépendance), lancé par Claude Code sur le poste, comme `scripts/homebox-mcp/`.
Rien n'est ouvert de plus, pas d'OAuth.

Outils : `stock`, `expiring` (bientôt périmés, périmés, expirés, manquants),
`list_products`, `get_product`, `shopping_list`, `list_chores` (avec leur
prochaine échéance), `get_chore`, `list_recipes` (avec ce qui manque en stock)
en lecture ; `add_shopping_item` (produit ou simple note), `update_shopping_item`
(modifier une ligne, `done: true` pour la marquer faite) et `complete_chore`
(marquer une corvée faite) en écriture.

**Jamais de suppression.** Une clé d'API Grocy n'a pas de périmètre (elle a
les droits de l'utilisateur qui la porte) : la garantie est dans le serveur.
`ALLOWED` liste les couples méthode/chemin envoyés (onze) ; tout autre est
refusé avant l'envoi, DELETE compris, et les tests le vérifient
(`test_refused_calls`). Les corps sont limités à leurs champs : une ligne de
courses (produit, note, quantité, liste, fait), une corvée (date, utilisateur,
jamais `skipped`). L'API générique `/objects/` n'est ouverte que pour
`products` (lecture) et `shopping_list`.

API de la version épinglée (4.7.1, `grocy.openapi.json` du dépôt amont) :
`/api/stock`, `/api/stock/volatile`, `/api/chores/{id}/execute`,
`/api/objects/shopping_list`.

## Authentification : clé d'API de Sylvain

Le rôle fait confiance à l'en-tête `Remote-User` de Pangolin (aucun
formulaire de connexion), mais l'API garde sa clé `GROCY-API-KEY`, essayée
d'abord : c'est aussi ce que fait l'appli Android. L'accès mobile existant
(`grocy_mobile_server_url`, identifiants Basic de
`pangolin_resource_header_auth.grocy_mobile`) n'est **pas** repris : il est
unique pour la ressource et partagé avec le téléphone. Le serveur MCP a son
jeton d'accès Pangolin à lui (ci-dessous), révocable seul.

Geste : Grocy (grocy.sylvain.cloud), compte `sylvain` > menu utilisateur >
Gérer les clés d'API > ajouter, description `claude-mcp`. Les lignes et
corvées modifiées le sont au nom de ce compte. L'exporter en `GROCY_API_KEY`
là où Karakeep, Immich et Homebox tiennent les leurs. La supprimer dans le même
écran pour la révoquer.

## Activation

Dans le `.mcp.json` du checkout du homelab (exclu de git), ajouter :

```json
"grocy": {
  "command": "python3",
  "args": ["/home/sylvain/Documents/homelab/scripts/grocy-mcp/grocy_mcp.py"],
  "env": {
    "GROCY_URL": "https://grocy.sylvain.cloud",
    "GROCY_API_KEY": "${GROCY_API_KEY}",
    "GROCY_PANGOLIN_TOKEN_ID": "${GROCY_PANGOLIN_TOKEN_ID}",
    "GROCY_PANGOLIN_TOKEN": "${GROCY_PANGOLIN_TOKEN}"
  }
}
```

Redémarrer Claude Code, approuver le serveur (`/mcp`).

## Joignabilité : jeton d'accès Pangolin

`website_grocy.tf` n'ouvre aucun chemin : tout `grocy.sylvain.cloud`, `/api`
compris, est derrière le mur SSO de Pangolin (et le filtre FR/DE). Le serveur
passe ce mur avec le jeton d'accès Pangolin `claude-code`
(`pangolin_resource_access_token.grocy_clients`), à lire une fois dans
`tofu/pangolin_config` :

    tofu output -json grocy_client_access_tokens

et à exporter dans `GROCY_PANGOLIN_TOKEN_ID` (`P-Access-Token-Id`) et
`GROCY_PANGOLIN_TOKEN` (`P-Access-Token`), là où vit `GROCY_API_KEY`. La clé
d'API reste obligatoire : c'est elle qui authentifie auprès de Grocy.

## Non testé contre le vrai service

Aucun appel réel n'a été fait : les chemins viennent de `grocy.openapi.json`.
À vérifier au premier essai : qu'un jeton d'accès Pangolin passe sur une
ressource qui porte aussi une authentification par en-tête (celle du mobile) ;
que le `PUT /objects/shopping_list/{id}` ne change que les champs envoyés ;
que `POST /objects/shopping_list` sans produit (note seule) est accepté ;
que la clé d'API passe avec `GROCY_AUTH_CLASS` en `ReverseProxyAuthMiddleware`.

## Test

`cd scripts/grocy-mcp && python3 -I -m unittest -v`
