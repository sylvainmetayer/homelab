# 0031. Un certificat joker par domaine (DNS-01) au lieu d'un certificat par nom

- **Statut** : acceptée
- **Date** : 2026-11-09

## Contexte

Le Traefik de Pangolin obtenait un certificat Let's Encrypt par nom, en
HTTP-01 ; celui du NAS aussi, en DNS-01. Chaque certificat est publié dans les
journaux Certificate Transparency : la liste des sous-domaines du homelab
(applis, démos, outils d'administration) y est lisible par n'importe qui. Les
noms déjà émis y restent à vie ; l'objectif est de ne plus en ajouter.

## Décision

- **Un joker par zone** : `*.sylvain.cloud` et `*.sylvain.dev` pour Pangolin,
  `*.sylvain.cloud` pour le NAS (`nas_proxy_wildcard_domain`). Un seul niveau :
  `a.b.sylvain.cloud` n'est pas couvert, l'apex est servi par nom exact.
- **Placé par Pangolin** : `prefer_wildcard_cert` et `cert_resolver:
  letsencrypt-dns` au niveau du domaine (`server/lib/traefik/certResolver.ts`),
  dans `domain1` de sa configuration pour sylvain.cloud (réécrit en base à
  chaque démarrage, `copyInConfig.ts`) **et** dans `pangolin_domain.org`
  (Tofu), seul maître de sylvain.dev. Les routeurs fichier (tableau de bord,
  API, `id.sylvain.cloud`) portent `tls.domains` à la main.
- **Résolveur DNS-01 dédié** `letsencrypt-dns` (le `letsencrypt` global est en
  HTTP-01 et ne peut pas émettre de joker ; il reste pour les autres noms), par
  l'API OVH, avec une **clé dédiée** `pangolin_ovh_*` restreinte aux deux zones.
- **CAA** : `issuewild "letsencrypt.org; validationmethods=dns-01"` sur
  sylvain.cloud et sylvain.dev (`tofu/dns/caa.tf`), puis `accounturi` des
  comptes ACME de Pangolin et du NAS une fois créés. `issue` est inchangé.
- **Migration** : essai sur l'autorité de test (`pangolin_wildcard_staging`, nom
  neutre `acme-test.sylvain.cloud`), puis production. Traefik préfère un
  certificat par nom au joker : les certificats par nom sont retirés
  d'`acme.json` ensuite, sinon ils restent servis et renouvelés. Fait le 2026-11-13 (63 retirés sur Pangolin, 5 au NAS) ; restent sur Pangolin les apex, `memoire.epsi.sylvainmetayer.fr` et `print`, `bbox-internal`, `nas-internal` (routeurs de ressources privées en HTTP-01).
- **Surveillance** : les moniteurs HTTP d'Uptime Kuma existants
  (`expiry_notification`), et `nas-proxy-cert-check` au NAS ; pas de script.

## Alternatives écartées

- **Délégation `_acme-challenge`** vers une zone dédiée : les droits OVH portent
  sur une zone entière, il faudrait un domaine de plus ; la clé restreinte aux
  trois appels de lego suffit.
- **Garder un certificat par nom** : chaque nouvelle appli reste publiée dans
  les journaux CT.

## Conséquences

- Plus aucun nouveau nom de sylvain.cloud ou sylvain.dev dans les journaux CT
  (sauf les apex et les noms hors Pangolin : Cloudflare Pages, GitHub Pages,
  PikaPods, qui émettent par nom sous `issue`, inchangé).
- Une clé OVH de plus à faire tourner (`secrets-rotation.yaml`).
- Un joker expiré coupe tout le domaine d'un coup, au lieu d'un nom.
- La clé privée du joker sert tous les noms : une fuite d'`acme.json` vaut pour
  le domaine entier (elle valait déjà pour chaque nom).
- Sans la clé OVH (reconstruction sans le secret), le rôle revient de lui-même
  au certificat par nom pour les routeurs fichier et `domain1`, mais
  `pangolin_domain.org["sylvain.dev"]` désigne un résolveur absent.
- Retour arrière : `pangolin_wildcard_cert: false` (Ansible) et
  `prefer_wildcard_cert = false` dans `domains.tf`.

## Liens

- `ansible/roles/pangolin/README.md`, `ansible/roles/nas_proxy/README.md`
- `tofu/pangolin_config/domains.tf`, `tofu/dns/caa.tf`, `docs/runbooks/dmarc.md` (CAA)
- `docs/runbooks/rotation-des-secrets.md` (OVH)
