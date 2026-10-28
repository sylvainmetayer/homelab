# DMARC et CAA : lire les rapports, durcir, ajouter un expéditeur ou une CA

Procédure, pas un incident. Les enregistrements SPF, DMARC, TLS-RPT et le MX
nul de sylvain.cloud sont dans `tofu/dns/mail.tf` (tests :
`tofu/dns/tests/dns.tftest.hcl`). Les DKIM ne le sont pas : chaque
fournisseur publie sa clé (Infomaniak, SimpleLogin).

| Zone | Envoie par | DKIM | DMARC |
|---|---|---|---|
| sylvainmetayer.fr | Infomaniak (boîte, et tous les hôtes et applis via `pangolin_smtp_user`) | `20230615._domainkey` (Infomaniak) | `p=none`, rapports |
| sylvain.dev | SimpleLogin (alias, réponses) | `dkim`, `dkim02`, `dkim03` (CNAME vers simplelogin.co) | `p=quarantine` strict, rapports |
| metayer.dev | SimpleLogin | idem | `p=quarantine` strict, rapports |
| sylvain.cloud | rien | aucun | `p=reject`, `v=spf1 -all` (MX nul en option, voir plus bas) |

Tous les rapports (DMARC agrégés `rua`, TLS-RPT) vont à
`dmarc_report_address` (`tofu/dns/variables.tf`, par défaut
`dmarc@sylvainmetayer.fr`, un alias de la boîte Infomaniak). Une adresse
sur un autre domaine que le domaine rapporté doit être autorisée par ce
domaine (RFC 7489 §7.1) : `mail.tf` publie `<zone>._report._dmarc` dans la
zone de l'adresse pour chaque autre zone.

## Premier apply (une fois)

1. Créer l'alias `dmarc@sylvainmetayer.fr` dans le Manager Infomaniak
   (Service Mail → Adresses → alias de la boîte), avant l'apply : sinon
   chaque rapport rebondit. Un filtre qui les range dans un dossier
   `DMARC` évite de les voir passer.
2. Importer les enregistrements qui existaient déjà, sinon l'apply en crée un
   second et deux DMARC (ou deux SPF) sur un même nom valent erreur. Pas de
   bloc `import` : `tofu test` le refuse. Depuis la racine, mise actif :

   ```bash
   cd tofu/dns
   tofu import 'ovh_domain_zone_record.dmarc["sylvain.dev"]'     5397217611.sylvain.dev
   tofu import 'ovh_domain_zone_record.dmarc["metayer.dev"]'     5397217722.metayer.dev
   tofu import 'ovh_domain_zone_record.spf["sylvainmetayer.fr"]' 5397225838.sylvainmetayer.fr
   tofu import 'ovh_domain_zone_record.spf["metayer.dev"]'       5397217672.metayer.dev
   tofu import 'ovh_domain_zone_record.spf["sylvain.dev"]'       5397217435.sylvain.dev
   tofu import 'ovh_domain_zone_record.spf["sylvain.cloud"]'     5305117000.sylvain.cloud
   tofu plan
   ```

   Le plan attendu : 9 créations (DMARC de sylvainmetayer.fr et
   sylvain.cloud, trois `_report._dmarc`, trois `_smtp._tls`, le SPF de
   sylvain.cloud recréé en TXT), 5 modifications (les deux DMARC gagnent
   `rua=…`, le SPF de metayer.dev passe de `~all` à `-all`, les SPF de
   sylvainmetayer.fr et sylvain.dev ne changent que de TTL, 0 → 300
   partout), 1 destruction (l'ancien
   enregistrement de type OVH `SPF` de sylvain.cloud, remplacé par un TXT).
   Rien d'autre.
3. `tofu apply`, puis supprimer à la main, dans la zone DNS du Manager OVH,
   ce que Tofu ne gère pas et qui contredirait `mail.tf` :
   - metayer.dev : l'enregistrement de type `SPF` `v=spf1 include:mx.ovh.com
     -all` et le TXT `v=spf1 include:mx.ovh.com -all 1|www.metayer.dev`
     (trois SPF à l'apex : permerror, SPF ne passait jamais). Garder le TXT
     `1|www.metayer.dev` seul : c'est le marqueur de la redirection web OVH.
4. Vérifier (TTL 300 : quelques minutes) :

   ```bash
   for d in sylvainmetayer.fr sylvain.dev metayer.dev sylvain.cloud; do
     echo "== $d"; dig +short MX $d; dig +short TXT $d | grep spf1
     dig +short TXT _dmarc.$d; dig +short TXT _smtp._tls.$d
   done
   dig +short TXT sylvain.dev._report._dmarc.sylvainmetayer.fr
   ```

   Un seul `v=spf1` par zone, un seul `v=DMARC1`. Puis s'envoyer un mail
   depuis la boîte Infomaniak vers une adresse Gmail : « Afficher
   l'original » doit montrer `SPF: PASS`, `DKIM: PASS`, `DMARC: PASS`.

### MX nul de sylvain.cloud (optionnel)

sylvain.cloud garde pour l'instant les trois MX OVH (offre « redirect »
sans redirection : OVH rebondit tout). Un MX nul (`0 .`, RFC 7505) fait
échouer l'expéditeur tout de suite, mais un fil du forum OVH dit que la zone
refuse la cible « . » : d'abord essayer d'ajouter `MX 0 .` à la main dans le
Manager. S'il l'accepte, le supprimer, puis :

```bash
tofu import 'ovh_domain_zone_record.sylvain_cloud_null_mx[0]' 5305117097.sylvain.cloud
tofu plan -var sylvain_cloud_null_mx=true   # le MX mx1 devient « 0 . »
```

passer `sylvain_cloud_null_mx` à `true` dans `variables.tf` (PR), appliquer,
et supprimer à la main `5 mx2.mail.ovh.net.` et `100 mx3.mail.ovh.net.` : un
MX nul doit être le seul MX. Il ne couvre que l'apex : `x@foo.sylvain.cloud`
retombe sur le A du joker (Pangolin, port 25 fermé), ce qui ne change rien à
l'usurpation, que `p=reject` couvre aussi pour les sous-domaines.

## Lire les rapports

Les récepteurs (Google, Microsoft, Yahoo, La Poste…) envoient un rapport
agrégé par jour et par domaine : un XML compressé (`.zip` ou `.gz`) en pièce
jointe, qui dit, par IP d'envoi, combien de messages, et si SPF et DKIM
passaient **alignés** (le domaine authentifié est celui du `From:`). Les
TLS-RPT (JSON) signalent les échecs de TLS des serveurs qui nous livrent.

Sans appli à installer : enregistrer les pièces jointes de la semaine dans un
dossier, puis

```bash
uvx parsedmarc --offline -o /tmp/dmarc ~/Téléchargements/dmarc/*
```

et lire `/tmp/dmarc/aggregate.csv` (une ligne par source : `source_ip_address`,
`source_reverse_dns`, `count`, `spf_aligned`, `dkim_aligned`,
`dmarc_aligned`, `header_from`). Pour chaque source :

- `dmarc_aligned` vrai : rien à faire ;
- faux, mais c'est un service légitime (newsletter, formulaire, notification
  d'une appli…) : l'ajouter, voir plus bas ;
- faux et inconnu (IP d'un FAI, d'un VPS au hasard) : usurpation, c'est
  exactement ce que la politique doit rejeter. Rien à faire.

Si dépouiller les XML devient une corvée : un parsedmarc auto-hébergé qui
lit la boîte en IMAP (nouvelle appli, `new-app`), ou un service gratuit
(digest hebdomadaire de dmarc.postmarkapp.com : son adresse s'ajoute au
`rua`, séparée par une virgule, ce que `dmarc_report_address` n'accepte pas
encore). Cloudflare DMARC Management demande une zone chez Cloudflare : pas
ici.

## Échelle de durcissement

Une zone ne monte d'un cran qu'avec, sur **deux semaines d'affilée** de
rapports d'au moins Google et Microsoft :

- 100 % des messages légitimes `dmarc_aligned` (les sources légitimes qui
  échouaient ont été ajoutées, ou retirées) ;
- aucune source légitime nouvelle depuis le dernier cran.

Les crans, dans `local.dmarc_policies` (`tofu/dns/mail.tf`) :

1. `p = "none"` : on observe, rien n'est filtré (sylvainmetayer.fr au
   départ).
2. `p = "quarantine", pct = 25` : un quart des messages en échec part en
   spam. Deux semaines.
3. `p = "quarantine", pct = 100` (sylvain.dev, metayer.dev aujourd'hui).
4. `p = "reject"` (sylvain.cloud) : refusés à la réception.

`strict = true` (`adkim=s; aspf=s`) exige le domaine exact, pas un
sous-domaine : à n'activer que si aucune source légitime n'authentifie un
sous-domaine (un service qui signe `d=mail.sylvainmetayer.fr` échouerait).

En cas de mails légitimes perdus après un cran : redescendre d'un cran
(`tofu apply`, TTL 300), trouver la source dans les rapports, l'ajouter, puis
remonter.

## Ajouter un service qui envoie en notre nom

Un service qui envoie avec un `From:` en `@sylvainmetayer.fr` (ou une autre
zone) doit passer DMARC par **au moins un** des deux chemins alignés :

- **DKIM (à préférer)** : le service donne un sélecteur et une clé (TXT
  `<sélecteur>._domainkey`, ou un CNAME vers chez lui). L'ajouter dans
  `tofu/dns` (un fichier par service, ou à côté de `mail.tf`), sélecteur
  unique par service. C'est le seul chemin qui survit au transfert d'un
  mail.
- **SPF** : seulement si le service envoie avec une enveloppe (`Return-Path`)
  sur notre domaine. Ajouter son `include:` à `local.spf_records` :
  `"v=spf1 include:spf.infomaniak.ch include:<service> -all"`. **Un seul**
  enregistrement SPF par zone, et 10 requêtes DNS au plus en tout (le SPF
  d'Infomaniak en consomme déjà une partie, `dig +short TXT
  spf.infomaniak.ch`) : au-delà, SPF est en permerror pour tout le monde.

La plupart des services (GitHub, Supabase, Cloudflare…) envoient depuis
**leur** domaine : ils n'ont rien à faire ici, ils n'apparaissent même pas
dans nos rapports. Ne s'inscrivent ici que ceux qu'on configure avec notre
domaine en expéditeur.

Une zone qui n'envoyait rien et se met à envoyer (sylvain.cloud) : enlever
son MX nul seulement si elle doit aussi recevoir, ajouter le SPF du service,
et repartir de `p = "none"` le temps de vérifier les rapports.

## CAA : qui peut délivrer un certificat

Pas du courrier, mais la même zone et le même destinataire de rapports :
`tofu/dns/caa.tf` (tests : `caa_*` dans `tofu/dns/tests/dns.tftest.hcl`)
publie à l'apex de chaque zone les autorités de certification (CA) qui ont
le droit de délivrer un certificat pour ses noms (RFC 8659). Une CA absente
de la liste refuse ; sans aucun CAA (le cas jusqu'au 2026-10-28), n'importe
laquelle pouvait.

| Zone | `issue` | Pourquoi |
|---|---|---|
| sylvainmetayer.fr, metayer.dev, sylvain.cloud | `letsencrypt.org` | Traefik de Pangolin (HTTP-01), Traefik du NAS (DNS-01, media et nas.sylvain.cloud) |
| sylvain.dev | `letsencrypt.org`, `pki.goog`, `ssl.com` | Pangolin, GitHub Pages (`*.talks`), et Cloudflare Pages (ref, www, r) |

Partout : `0 issuewild ";"` (aucun joker n'est délivré : Pangolin et le NAS
demandent un certificat par nom) et `0 iodef "mailto:<dmarc_report_address>"`.

Pourquoi trois CA sur sylvain.dev : Cloudflare Pages choisit seul l'autorité
de ses domaines personnalisés, entre Let's Encrypt, Google Trust Services
(`pki.goog`) et SSL.com, et peut en changer au renouvellement (aujourd'hui
ref, www et r ont un certificat Google Trust Services WE1). Ces noms sont des
CNAME vers `*.pages.dev`, qui ne publie aucun CAA : la CA remonte alors à
l'apex sylvain.dev. Retirer `pki.goog` ou `ssl.com` ne casse rien tout de
suite, mais fait échouer le prochain renouvellement, sans alerte. La liste
vient de developers.cloudflare.com/ssl/reference/certificate-authorities :
la relire si Cloudflare annonce un changement d'autorités.

L'adresse iodef est `dmarc_report_address`, pas `pangolin_le_email` : un CAA
est public, l'alias de rapports l'est déjà (DMARC, TLS-RPT), alors que
`pangolin_le_email` est un secret d'Ansible, illisible par `tofu/dns`. Peu
de CA envoient quoi que ce soit à iodef.

Vérifier après l'apply :

```bash
for d in sylvainmetayer.fr sylvain.dev metayer.dev sylvain.cloud; do
  echo "== $d"; dig +short CAA $d
done
dig +short CAA ref.sylvain.dev   # vide : pages.dev n'en publie pas, on remonte à sylvain.dev
```

puis `tofu plan` doit être vide (si OVH réécrit la valeur d'un CAA, le plan
le montre en modification perpétuelle : aligner `caa.tf` sur ce qu'OVH
renvoie).

Ajouter une CA (un nouveau service qui obtient ses certificats ailleurs, ou
un joker) : l'ajouter à `local.caa_issuers` de sa zone dans `caa.tf` (ou un
`issuewild` dédié pour un joker), et le test qui liste les CA hors Let's
Encrypt, dans la même PR. Symptôme d'un oubli : le service n'obtient pas son
certificat, avec une erreur « CAA record … prevents issuance » dans ses logs
ACME (sur Pangolin `docker logs traefik`, sur le NAS `docker logs nas-proxy`).
