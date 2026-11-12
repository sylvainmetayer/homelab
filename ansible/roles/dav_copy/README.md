# Rôle `dav_copy`

Copie **à sens unique** des agendas, tâches et contacts de Nextcloud
(`https://sylvain.cloud/remote.php/dav/`) vers Infomaniak
(`https://sync.infomaniak.com`), étape de la migration hors de Nextcloud.

Ce rôle ne contient pour l'instant que l'outil `files/dav_copy.py` : aucune
tâche, aucun timer, aucune entrée de playbook (le câblage sur la VM docker
vient plus tard). Ce `README.md` ne déploie rien. Tests :
`.github/scripts/test_dav_copy.py` (lancés par le job Lint, sans réseau).

Bibliothèque standard seule (urllib, xml.etree, argparse).

## Garanties

- **Nextcloud n'est jamais écrit** : son client refuse par construction toute
  méthode autre que PROPFIND, REPORT, GET, OPTIONS (`ReadOnlyError`, testé).
- **Simulation par défaut** : sans `--apply`, le client d'Infomaniak est lui
  aussi en lecture seule ; le compte rendu dit ce qui serait créé, modifié,
  supprimé. Le fichier d'état n'est écrit qu'avec `--apply`.
- HTTPS obligatoire, authentification Basic, aucune redirection suivie.
- La sortie ne contient ni mot de passe, ni URL avec identifiant, ni contenu
  d'objet : seulement des noms de ressource tronqués à 12 caractères.

## Utilisation

Simulation (depuis la racine du dépôt) :

```bash
python3 ansible/roles/dav_copy/files/dav_copy.py \
  --source-config ~/.config/nextcloud-dav --dest-config ~/.config/infomaniak-dav \
  --collections collections.json --state ~/.local/state/dav-copy.json
```

Ajouter `--apply` pour écrire, `--delete` (avec `--apply`) pour supprimer chez
Infomaniak ce qui a disparu de Nextcloud, `--json` pour un compte rendu
lisible par machine. `--list nextcloud` ou `--list dest` liste les collections
d'un compte et leur nombre d'objets, sans rien copier (lecture seule).

Code de sortie : 0 ; 1 si une collection est en erreur ; 2 si la
configuration ou la découverte échoue.

## Identifiants

Un fichier par serveur, `0600`, lignes `CLE: valeur` ou `CLE=valeur` (espaces
autour ignorés) :

| Clé | Rôle |
|---|---|
| `USER` | identifiant ; absent, il est lu dans l'URL (`/calendars/<id>/…`, cas d'Infomaniak) |
| `MDP` | mot de passe (ou `PASSWORD`) |
| `URL` | adresse DAV ; absente, `--source-url` (défaut `https://sylvain.cloud/remote.php/dav/`) ou `--dest-url` |

`~/.config/nextcloud-dav` : `USER`, `MDP`. `~/.config/infomaniak-dav` : `URL`
(une URL d'agenda Infomaniak), `MDP`.

## Liste d'inclusion (`--collections`)

Rien n'est copié hors de cette liste. `source` est le nom de dossier ou le nom
affiché de la collection chez Nextcloud, `dest` son nom affiché chez
Infomaniak :

```json
{
  "calendars":    [{"source": "personnel", "dest": "Personnel"}],
  "addressbooks": [{"source": "contacts",  "dest": "Contacts"}]
}
```

Jamais copiés, même listés : abonnements (`subscribed`), inbox/outbox de
planification. Les agendas d'anniversaires générés et « Repas » sont à ne pas
mettre dans la liste.

## Comportement

- Objet par objet, même nom de ressource : relançable sans doublon. Un objet
  inchangé n'est pas réécrit : comparaison par contenu normalisé (pas par
  ETag, ceux des deux serveurs ne se comparent pas) ; `--state` mémorise
  ETag source → ETag destination pour ne pas tout relire.
- Normalisation : propriétés triées, noms en majuscules, repliage défait,
  `PRODID` ignoré ; vCard 4 et 3 jugées égales (groupes `item1.`, `VERSION`,
  `REV`, `TYPE` sans `voice`/`pref`, `tel:`, anniversaire sans année,
  `PHOTO` comparée par empreinte du contenu décodé).
- **Invitations** : tout `ORGANIZER`/`ATTENDEE` d'un VEVENT/VTODO reçoit
  `SCHEDULE-AGENT=CLIENT` (Infomaniak n'envoie alors rien ; repliage et
  paramètre existant gérés).
- **Agendas** absents : créés par MKCALENDAR (nom, couleur, composants
  repris), puis écriture avec reprises (`--retries 5`, `--retry-delay 3`),
  l'écriture suivant immédiatement la création échouant chez Infomaniak.
- **Carnets** absents : erreur claire pour ce carnet (Infomaniak refuse la
  création par CardDAV, 403 : à créer à la main), le reste continue.
- **Suppressions** : les objets présents chez Infomaniak mais plus chez
  Nextcloud sont comptés (« à supprimer »). Attention, c'est un miroir : un
  objet créé directement chez Infomaniak dans une collection copiée est aussi
  « à supprimer ». Supprimés seulement avec `--apply --delete`, et jamais si
  plus de `--max-delete-pct` % (défaut 10) des objets de la collection
  disparaissent : la collection est sautée avec une erreur, en simulation
  aussi.

## Limites connues

- Comparaison des iCal : propriétés d'un même chemin de composant mises en
  vrac (deux VALARM ne se distinguent pas) ; un serveur qui réécrit une
  propriété autre que `PRODID` ferait réécrire l'objet à chaque passage.
- Le parseur XML est celui de la bibliothèque standard : serveurs de confiance.
