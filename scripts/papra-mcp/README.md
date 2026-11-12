# MCP Papra (lecture, tags)

Serveur MCP stdio d'environ 170 lignes (bibliothèque standard, aucune
dépendance), lancé par Claude Code sur le poste, comme `scripts/homebox-mcp/`.
Rien n'est ouvert de plus, pas d'OAuth.

Outils : `list_organizations`, `search_documents` (texte libre, sans le texte
OCR), `get_document`, `get_document_text` (le texte OCR seul), `list_tags`,
`statistics` en lecture ; `create_tag`, `add_tag` (poser un tag sur un
document) et `remove_tag` (le retirer) en écriture. Les identifiants
d'organisation, de document et de tag viennent de `list_organizations`,
`search_documents` et `list_tags`.

**Jamais de suppression de document ni de tag.** `ALLOWED` liste les couples
méthode/chemin envoyés (huit) ; tout autre est refusé avant l'envoi, et les
tests le vérifient (`test_refused_calls`). **Le seul DELETE est le retrait
d'un tag d'un document**, `DELETE /organizations/<org>/documents/<doc>/tags/<tag>` :
le document et le tag restent, seul le lien disparaît. La corbeille, le
`DELETE` d'un document ou d'un tag, `PATCH`, le retraitement, la restauration
et le téléchargement du fichier sont refusés, même si la clé les permettrait
(`documents:update` ouvre `PATCH` et le retraitement : c'est la liste blanche
qui les ferme, pas la permission).

API de la version épinglée (26.7.1) : routes de `documents.routes.ts` du dépôt
amont et page d'API de la documentation de Papra.

## Authentification : clé d'API à permissions

Papra a des clés d'API à permissions, envoyées en
`Authorization: Bearer <clé>` (celle du remplissage par l'IA,
`papra_enrich.py`, fait pareil).

Geste : Papra (papra.sylvain.cloud), compte de Sylvain > Clés d'API > créer
`claude-mcp` avec **seulement** : `organizations:read`, `documents:read`,
`documents:update`, `tags:read`, `tags:create`. Pas de `documents:delete`, pas
de `tags:update` ni `tags:delete`. L'exporter en `PAPRA_API_KEY` là où Karakeep,
Immich et Homebox tiennent les leurs. La révoquer dans le même écran ; si un
outil répond 403, le message nomme la permission manquante.

## Activation

Dans le `.mcp.json` du checkout du homelab (exclu de git), ajouter :

```json
"papra": {
  "command": "python3",
  "args": ["/home/sylvain/Documents/homelab/scripts/papra-mcp/papra_mcp.py"],
  "env": {
    "PAPRA_URL": "https://papra.sylvain.cloud",
    "PAPRA_API_KEY": "${PAPRA_API_KEY}",
    "PAPRA_PANGOLIN_TOKEN_ID": "${PAPRA_PANGOLIN_TOKEN_ID}",
    "PAPRA_PANGOLIN_TOKEN": "${PAPRA_PANGOLIN_TOKEN}"
  }
}
```

Redémarrer Claude Code, approuver le serveur (`/mcp`).

## Joignabilité : jeton d'accès Pangolin

`website_papra.tf` n'ouvre aucun chemin : tout `papra.sylvain.cloud`, `/api`
compris, est derrière le mur SSO de Pangolin (et le filtre FR/DE). Le serveur
passe ce mur avec le jeton d'accès Pangolin `claude-code`, une entrée de plus
du `pangolin_resource_access_token.papra_clients` de l'appli mobile (`mobile`),
à lire une fois dans `tofu/pangolin_config` :

    tofu output -json papra_client_access_tokens

et à exporter dans `PAPRA_PANGOLIN_TOKEN_ID` (`P-Access-Token-Id`) et
`PAPRA_PANGOLIN_TOKEN` (`P-Access-Token`), là où vit `PAPRA_API_KEY`. La clé
d'API reste obligatoire : c'est elle qui authentifie auprès de Papra.

## Non testé contre le vrai service

Aucun appel réel n'a été fait : les chemins viennent du code amont et de la
documentation. À vérifier au premier essai : que `POST /tags` accepte un corps
JSON (la documentation parle de form-data, `papra_enrich.py` n'écrit que des
corps JSON ailleurs) avec `name` et `color`, que `searchQuery` cherche aussi
dans le texte OCR, et que la clé ne demande pas d'autre permission pour
`POST/DELETE .../documents/<id>/tags` (la documentation dit `tags:read` et
`documents:update`).

## Test

`cd scripts/papra-mcp && python3 -I -m unittest -v`
