# Support à distance des PC de la famille : variante sans `tofu apply`

Quand on est sur place sans pouvoir passer par Tofu (pas de checkout, pas de
clé age, pas le temps d'une PR) : le site et la ressource Pangolin du PC se
créent **à la main dans l'interface de Pangolin**, le reste ne change pas.
Cette page remplace les sections **0.1 et 0.2** de
[support-a-distance-famille.md](support-a-distance-famille.md) ; tout le
reste (0.3, 0.4, l'installation sur le PC, les tests, le démontage du PC) se
suit tel quel.

> **Dette à rattraper.** Ce qui est créé ici n'existe pas dans le code ni dans
> le state de `tofu/pangolin_config`. Tant que ce n'est pas rattrapé
> (section R) :
>
> - **tout `tofu plan` de `tofu/pangolin_config` échoue**, pour n'importe
>   quel changement : la vérification de couverture de `rules.tf` refuse une
>   ressource active qu'aucune entrée ne déclare
>   (`Enabled Pangolin resources with no country rules: PC Papa (VNC)`) ;
> - les règles de pays, le rôle et la cible ne sont gardés par aucun test ni
>   aucun plan : une modification dans l'interface passe inaperçue.
>
> Le rattrapage se fait dès le retour, avant tout autre travail sur
> `tofu/pangolin_config`. Le noter tout de suite dans les actions manuelles en
> attente.

Exemple pour le PC de papa : site `pc-papa`, ressource `PC Papa (VNC)`. Les
noms doivent être **exactement** ceux que le code prendra au rattrapage : la
vérification de couverture et les clés des règles de pays se font par le nom
de la ressource.

## M.1 Le site (interface de Pangolin)

`https://pangolin.sylvain.cloud`, compte administrateur, organisation du
homelab :

1. **Sites → Ajouter un site**, type **Newt**, nom `pc-papa`.
2. L'écran de création affiche l'ID et le secret Newt **une seule fois** :
   les mettre aussitôt dans l'entrée KeePass « Newt pc-papa » (identifiant =
   ID, mot de passe = secret, endpoint `https://pangolin.sylvain.cloud`).
   Ils ne se relisent nulle part ensuite, pas même dans le state après le
   rattrapage (l'import d'un site ne récupère pas le secret).
3. Valider. Le site reste hors ligne jusqu'à l'installation de Newt sur le PC.

## M.2 La ressource (interface de Pangolin)

Modèle : la ressource **`PC Sylvain (VNC)`**, créée par le code, a déjà les
bons réglages ; l'ouvrir dans un autre onglet et recopier. Libellés de
l'interface non vérifiés (Pangolin 1.25.3) : à corriger ici à la première
utilisation.

1. **Ressources → Ajouter**, ressource **publique**, type **VNC**.
2. Nom `PC Papa (VNC)`, domaine `sylvain.cloud`, sous-domaine `d-xxxxxx`
   (`tr -dc a-z0-9 </dev/urandom | head -c6` sur le téléphone ou un PC, sinon
   six lettres et chiffres tirés au hasard ; même raison que dans la page
   principale : les journaux Certificate Transparency sont publics).
3. **Cible** : site `pc-papa`, adresse `127.0.0.1`, port **5901** si GNOME
   (relais), **5900** sinon (x11vnc, UltraVNC). **Sonde de santé désactivée**
   (le PC est souvent éteint).
4. **Authentification** :
   - SSO **activé** ;
   - rôles : **`support` seul**. Aucun autre rôle, aucun utilisateur, pas de
     liste blanche d'e-mails, pas de PIN ni de mot de passe, pas de règle
     (politique) partagée. Une liaison faite à la main en trop restera
     invisible au plan, même après le rattrapage.
5. **Règles** : les **activer**, puis en ajouter trois, exactement :

   | Priorité | Action | Correspondance | Valeur |
   |---|---|---|---|
   | 10 | Passer (PASS) | Pays | FR |
   | 11 | Passer (PASS) | Pays | DE |
   | 99 | Bloquer (DROP) | Pays | ALL (tous) |

6. Le reste par défaut, comme le modèle : SSL activé, ressource activée,
   accès non bloqué, sessions persistantes désactivées.

Contrôle immédiat (avant même l'installation sur le PC), depuis le
téléphone : `https://d-xxxxxx.sylvain.cloud` doit présenter le mur SSO
Pocket ID. Une page servie sans SSO = SSO ou règles mal posés, corriger avant
d'aller plus loin.

Puis reprendre la page principale à la section **0.3**.

## R. Rattrapage du state (au retour, avec le dépôt et la clé age)

Le but : que le code décrive ce qui a été fait à la main, que le state le
connaisse, et qu'un plan soit **vide** pour ce PC. On importe, on ne recrée
pas : recréer le site changerait le secret Newt, et le PC sortirait du tunnel
jusqu'à la prochaine visite.

### R.1 La PR

Le code de la section 0.1 de la page principale (site, entrée de
`local.remote_desktops`, surcharges des tests ; à faire faire par Claude),
**sans les deux `output` `pc_papa_newt_id` / `pc_papa_newt_secret`** : après
un import ils seraient vides, les identifiants vivent dans KeePass seulement.
Un commentaire sur le site le dit (« créé à la main le JJ/MM, importé,
identifiants Newt dans KeePass »). Reprendre exactement le nom, le
sous-domaine et le port posés en M.2.

Merger. Ne **pas** lancer d'apply avant les imports : il tenterait de tout
créer une seconde fois.

### R.2 Lire les identifiants numériques

Depuis un checkout à jour de `main` (sous-module `secrets/` à jour) :

```bash
KEY=$(sops -d --extract '["pangolin_api_key"]' secrets/secrets.sops.yaml)
URL=$(sops -d --extract '["pangolin_url"]' secrets/secrets.sops.yaml)
ORG=$(sops -d --extract '["pangolin_org_id"]' secrets/secrets.sops.yaml)
api() { curl -fsS -H "Authorization: Bearer $KEY" "$URL/v1$1"; }

api "/org/$ORG/sites?pageSize=1000" | jq '.data.sites[] | select(.name=="pc-papa") | .siteId'
RES=$(api "/org/$ORG/resources?pageSize=1000" | jq '.data.resources[] | select(.name=="PC Papa (VNC)") | .resourceId'); echo "$RES"
api "/resource/$RES/targets" | jq '.data.targets[] | {targetId, ip, port}'
mise exec -- tofu -chdir=tofu/pangolin_config state show pangolin_role.support | grep -E '^\s+id\s'
```

Si la liste des sites ne répond pas, l'ID se lit aussi avec
`api "/org/$ORG/site/<niceId>" | jq .data.siteId`, le `niceId` étant la fin
de l'adresse de la page du site dans l'interface.

### R.3 Importer

Remplacer `<SITE>`, `<TARGET>` et `<ROLE>` par les valeurs lues en R.2 :

```bash
cd tofu/pangolin_config
mise exec -- tofu import pangolin_site.pc_papa <SITE>
mise exec -- tofu import 'pangolin_resource.remote_desktop["pc_papa_vnc"]' "$RES"
mise exec -- tofu import 'pangolin_target.remote_desktop["pc_papa_vnc"]' <TARGET>
mise exec -- tofu import 'pangolin_resource_role.remote_desktop["pc_papa_vnc"]' "$RES/<ROLE>"
unset KEY
```

**Pas les règles de pays** : le provider ne sait pas importer une règle (son
`ImportState` écrit `resource_id = 0`, la lecture suivante rend 404, voir le
message de `terraform_data.rule_inventory` dans `rules.tf`). Et tant qu'elles
existent à la main, ce même audit arrête le plan (`Rules live in Pangolin that
this configuration did not create`). Les supprimer dans l'interface
(Ressources → `PC Papa (VNC)` → Règles, les trois), juste avant le plan : le
SSO reste en place sans elles, et l'apply de R.4 les recrée aussitôt. Les
imports de la cible et de la liaison de rôle n'ont jamais été lancés : les
formats viennent du code du fork (`target.go` : l'identifiant seul,
`resource_role.go` : `{resource_id}/{role_id}`). En cas d'échec, `tofu state
rm` de ce qui a été écrit de travers et lire le message avant de réessayer.

Le CLI, jamais un bloc `import` : le module est testé (`tofu test` panique,
`docs/conventions/tests.md`).

### R.4 Plan, puis apply

Plan depuis `main` (skill `pangolin-config-plan`). Attendu pour ce PC :
**seulement la création des trois règles de pays** (FR, DE, ALL), aucune
autre création, aucune destruction, aucun remplacement. Acceptable en plus :
des mises à jour en place d'attributs que l'interface a posés autrement que
le code (champs `hc_*` de la cible, maintenance de la ressource), et la
création d'une règle `PASS` de priorité 20 si `var.travel_countries` ouvre un
pays en ce moment. Les lire une à une.

**Ne pas appliquer** si le plan :

- remplace `pangolin_site.pc_papa` (nouveau secret Newt : le PC tombe) ;
- crée une deuxième ressource, cible ou liaison de rôle pour ce PC (un
  import oublié ou fait sous la mauvaise adresse : `tofu state rm` de la
  mauvaise, refaire R.3) ;
- détruit quoi que ce soit du PC.

Plan propre : apply (par Sylvain), puis un second plan doit être vide. Le
rattrapage est fini : rayer l'action manuelle en attente.

## Démontage avant rattrapage

Si le PC est démonté avant que le rattrapage soit fait : démonter le PC
(section 5 de la page principale), puis supprimer à la main dans l'interface
la ressource `PC Papa (VNC)` et le site `pc-papa`. Rien à changer dans le
code, et la dette disparaît avec eux.
