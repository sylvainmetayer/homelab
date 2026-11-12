# MCP Immich (lecture, et tri des albums sur demande)

Serveur MCP stdio d'un fichier (bibliothèque standard, aucune dépendance),
lancé par Claude Code sur le poste. Rien n'est ouvert, pas d'OAuth. Écrit à la
main faute de serveur sérieux : les existants (`joeru/claw2immich`,
`whitehara/immich-mcp`, `barryw/ImmichMCP`) ont 1 à 4 étoiles, pas de licence
affichée, pas de version publiée, et exposent des outils d'écriture sans
garde-fou. API de la version épinglée (v3.4.0) : `album.controller.ts`,
`album.dto.ts`, `search.dto.ts` et `enum.ts` du dépôt amont.

## Deux modes, deux clés

| | Lecture (défaut) | Écriture |
|---|---|---|
| Activation | rien | `IMMICH_MCP_WRITE=1` |
| Entrée `.mcp.json` | `immich` | `immich-ecriture` |
| Clé d'API | `claude-mcp` | `claude-mcp-ecriture` |
| Outils | 9 | 14 |

**Lecture** : `search_smart`, `search_metadata`, `list_albums`, `get_album`,
`list_people`, `get_asset`, `asset_statistics`, plus deux outils composés,
`find_duplicate_albums` (albums de même nom à la casse et aux espaces près ;
avec `minOverlap` entre 0 et 1, aussi ceux dont les assets se recouvrent, en
part du plus petit album ; au plus 100 albums non vides) et
`assets_without_album` (photos d'aucun album, page par page).

**Écriture** (en plus), tous sur des albums : `create_album`, `update_album`
(nom, description), `add_assets`, `remove_assets` (le lien seul), `merge_albums`.

En mode lecture les cinq outils d'écriture ne sont pas listés, un appel est
refusé avant tout envoi (réponse d'erreur nommant `IMMICH_MCP_WRITE`), et la
couche HTTP refuse de toute façon les cinq appels d'écriture. Les tests le
vérifient.

## Deux temps : « après validation »

Chaque outil d'écriture est appelé deux fois :

1. **Sans `confirm`** : il lit l'état et rend un aperçu, rien n'est écrit :
   album, nombre d'assets ajoutés ou retirés, noms de fichiers d'un
   échantillon de dix ; pour une fusion, assets communs, propres à chaque
   album, et ce qui serait supprimé. Il rend aussi un jeton `confirm`.
2. **Avec `confirm`** : Sylvain a vu l'aperçu et dit oui, Claude rappelle le
   même outil avec les mêmes arguments et le jeton. L'outil relit l'état et
   recalcule le jeton ; s'il diffère (état changé entre-temps, autres
   arguments, jeton inventé), rien n'est écrit et un nouvel aperçu revient.

Le jeton est un SHA-256 tronqué de (outil, arguments, état lu : identifiants
des assets en jeu, noms, drapeau de suppression). Il ne vit nulle part sur
disque. Le jeton d'une fusion sans suppression ne vaut donc pas pour la même
fusion avec `deleteDuplicate`.

Limite : le jeton garantit que ce qui s'écrit est ce qui a été prévisualisé,
pas que Sylvain a dit oui : rien n'empêche techniquement le modèle de
rappeler l'outil avec le jeton dans le même tour. La vraie barrière humaine est
l'invite d'autorisation de Claude Code : ne pas mettre les outils
`immich-ecriture` en « toujours autoriser ».

Fusion : `merge_albums(keepId, duplicateId)` ajoute à l'album gardé les seuls
assets du doublon qui lui manquent. Avec `deleteDuplicate: true` (à demander
explicitement à Sylvain), l'objet album doublon est supprimé ensuite, mais
seulement après relecture de l'album gardé prouvant que tous les assets du
doublon y sont ; et refusé d'emblée si l'une des deux listes d'assets paraît
incomplète (nombre lu différent de `assetCount`, par exemple des archivés).

## Impossible par construction

`READ` et `WRITE_BODY` listent les gabarits méthode/chemin envoyés ; tout autre
est refusé avant l'envoi, même si la clé le permettrait. Les identifiants
doivent être des UUID, les champs du corps sont une liste fermée. Donc jamais :
`DELETE /assets` ni aucun chemin `/assets` en écriture (supprimer, corbeille,
modifier date, lieu, favori, archive), la corbeille, les personnes, les
partages, les utilisateurs d'album, `PUT /albums/assets`. Le seul `DELETE` qui
touche des assets retire leur lien à un album ; l'autre supprime un album, pas
ses photos. Tests : `test_write_mode_allowlist_never_reaches_assets_or_trash`.

## Clés API Immich

Immich (photos.sylvain.cloud) > Paramètres du compte > Clés d'API > Nouvelle
clé. Noms de permissions vérifiés dans `enum.ts` de la v3.4.0.

- **Lecture**, `claude-mcp` (inchangée) : `asset.read`, `asset.statistics`,
  `album.read`, `person.read`.
- **Écriture**, `claude-mcp-ecriture`, une seconde clé : les quatre ci-dessus
  (les aperçus lisent), plus `album.create`, `album.update`,
  `albumAsset.create`, `albumAsset.delete`, et `album.delete` **seulement** si
  tu veux la suppression de l'album doublon après fusion (sans elle, la
  fusion avec `deleteDuplicate` répond 403 et l'album est conservé).

Pas de `asset.update`, `asset.delete`, `person.*`, `sharedLink.*`,
`albumUser.*`. Si un outil répond 403, le message nomme la permission manquante.

## Activation

Dans le `.mcp.json` du checkout du homelab (exclu de git, comme celui de
Karakeep), ajouter les deux entrées ; n'activer `immich-ecriture` (`/mcp`)
que le temps d'un tri :

```json
"immich": {
  "command": "python3",
  "args": ["/home/sylvain/Documents/homelab/scripts/immich-mcp/immich_mcp.py"],
  "env": {
    "IMMICH_URL": "https://photos.sylvain.cloud",
    "IMMICH_API_KEY": "${IMMICH_API_KEY}"
  }
},
"immich-ecriture": {
  "command": "python3",
  "args": ["/home/sylvain/Documents/homelab/scripts/immich-mcp/immich_mcp.py"],
  "env": {
    "IMMICH_URL": "https://photos.sylvain.cloud",
    "IMMICH_API_KEY": "${IMMICH_API_KEY_ECRITURE}",
    "IMMICH_MCP_WRITE": "1"
  }
}
```

et exporter `IMMICH_API_KEY` et `IMMICH_API_KEY_ECRITURE` là où Karakeep tient
la sienne. Redémarrer Claude Code, approuver le serveur (`/mcp`).

## Joignabilité

`photos.sylvain.cloud` laisse entrer l'IP du domicile sans SSO
(`immich_home_ip`, `website_immich.tf`) : depuis chez soi, rien à ajouter.
Hors de chez soi, il faut les en-têtes Pangolin du jeton `mobile`
(`tofu output -json immich_client_access_tokens`) dans
`IMMICH_PANGOLIN_TOKEN_ID` et `IMMICH_PANGOLIN_TOKEN` (à ajouter à l'`env` des
deux entrées).

## Non testé contre le vrai service

Aucun appel réel : les tests jouent un Immich en mémoire. À vérifier au premier
essai, en lecture d'abord (`find_duplicate_albums`, `assets_without_album`) :

- en v3.4.0 `GET /albums/{id}` ne rend plus la liste des assets (seulement
  `assetCount`) : les assets d'un album se lisent par `POST /search/metadata`
  avec `albumIds`, `size` 1000 et `page`. Ces champs plats sont marqués
  obsolètes depuis la 3.2 (la forme `filter` + `cursor` les remplace, sans
  mélange possible) mais acceptés ; si Immich les refuse, c'est le premier
  endroit à adapter (`_album_assets`, `assets_without_album`).
- la recherche cache peut-être les assets archivés : la liste paraît alors
  incomplète, et le serveur le dit (`liste_de_l_album_complete: false`) et
  refuse la suppression de l'album doublon.
- le corps de `DELETE /albums/{id}/assets` (`{"ids": [...]}`) et la forme des
  résultats par asset (`id`, `success`, `error`), lus dans le code amont.

## Test

`cd scripts/immich-mcp && python3 -I -m unittest -v`
