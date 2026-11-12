# MCP Immich en lecture seule

Serveur MCP stdio d'une centaine de lignes (bibliothèque standard, aucune
dépendance), lancé par Claude Code sur le poste. Rien n'est ouvert, pas
d'OAuth. Écrit à la main faute de serveur sérieux : les existants
(`joeru/claw2immich`, `whitehara/immich-mcp`, `barryw/ImmichMCP`) ont 1 à 4
étoiles, pas de licence affichée, pas de version publiée, et exposent des
outils d'écriture.

Outils : `search_smart`, `search_metadata`, `list_albums`, `get_album`,
`list_people`, `get_asset`, `asset_statistics`. Seuls des GET et les deux POST
de recherche partent vers Immich ; la clé n'a de toute façon aucun droit
d'écriture.

## Clé API Immich

Immich (photos.sylvain.cloud) > Paramètres du compte > Clés d'API > Nouvelle
clé, nommée `claude-mcp`, avec **seulement** ces permissions :
`asset.read`, `asset.statistics`, `album.read`, `person.read`. Si un outil
répond 403, le message nomme la permission de lecture manquante.

## Activation

Dans le `.mcp.json` du checkout du homelab (exclu de git, comme celui de
Karakeep), ajouter :

```json
"immich": {
  "command": "python3",
  "args": ["/home/sylvain/Documents/homelab/scripts/immich-mcp/immich_mcp.py"],
  "env": {
    "IMMICH_URL": "https://photos.sylvain.cloud",
    "IMMICH_API_KEY": "${IMMICH_API_KEY}"
  }
}
```

et exporter `IMMICH_API_KEY` là où Karakeep tient la sienne. Redémarrer Claude
Code, approuver le serveur (`/mcp`).

## Joignabilité

`photos.sylvain.cloud` laisse entrer l'IP du domicile sans SSO
(`immich_home_ip`, `website_immich.tf`) : depuis chez soi, rien à ajouter.
Hors de chez soi, il faut les en-têtes Pangolin du jeton `mobile`
(`tofu output -json immich_client_access_tokens`) dans
`IMMICH_PANGOLIN_TOKEN_ID` et `IMMICH_PANGOLIN_TOKEN`.

## Test

`cd scripts/immich-mcp && python3 -I -m unittest -v`
