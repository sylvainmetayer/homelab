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
- **Fichier d'état** (`--state`, exigé par `--apply`, écrit en `0600` de façon
  atomique, même si la passe plante) : par collection de destination, les
  objets que l'outil a **lui-même écrits**. Seuls ceux-là peuvent être
  réécrits ou supprimés. Un objet déjà présent chez Infomaniak (les 677 de
  l'agenda par défaut, par exemple) n'est jamais touché : de même nom et
  d'autre contenu, c'est une erreur « conflit », laissé tel quel. **État
  perdu** : plus aucune suppression ni mise à jour des objets déjà copiés
  (tous en « conflit » dès qu'ils changent) ; ne pas le perdre.
- **Suppressions** : un objet écrit par l'outil, présent chez Infomaniak et
  disparu de Nextcloud est « à supprimer ». Supprimé seulement avec
  `--apply --delete`, sous `If-Match` de la dernière écriture de l'outil (un
  objet retouché chez Infomaniak reste), et jamais si plus de
  `--max-delete-pct` % (défaut 10) des objets copiés disparaissent ou si la
  source est vide : la collection est sautée avec une erreur, en simulation
  aussi. Une liste source incomplète (207 partiel, 507) fait sauter la
  collection.
- Aucune redirection suivie, aucune requête vers un autre hôte que celui
  configuré (un `href` absolu d'une réponse est refusé).

## Limites connues

- Comparaison des iCal : propriétés d'un même chemin de composant mises en
  vrac (deux VALARM ne se distinguent pas) ; un serveur qui réécrit une
  propriété autre que `PRODID` ferait réécrire l'objet à chaque passage.
- Le parseur XML est celui de la bibliothèque standard : serveurs de confiance.
- `SCHEDULE-AGENT=CLIENT` ne vaut que pour VEVENT/VTODO : l'`ATTENDEE` d'une
  alarme `ACTION:EMAIL` (VALARM) n'est pas modifié ; vérifier qu'Infomaniak
  n'envoie pas ces alarmes par courriel avant la première copie.
- Comparaison des iCal : valeurs des paramètres sans casse (un `CN` qui ne
  change que de casse n'est pas propagé) ; des exceptions (RECURRENCE-ID)
  dont on échangerait les propriétés seraient jugées égales.
