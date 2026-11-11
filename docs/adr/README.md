# Décisions d'architecture (ADR)

Un ADR (*Architecture Decision Record*) garde **pourquoi** le homelab est
fait comme il est : le contexte d'une décision, ce qui a été choisi, ce qui a
été écarté et pour quelle raison. Le *comment* reste dans
[AGENTS.md](../../AGENTS.md), la carte dans
[architecture.md](../architecture.md), les incidents dans
[runbooks/](../runbooks/README.md).

## Quand en écrire un

- Un choix structurant : un outil plutôt qu'un autre, une règle qui vaut pour
  toutes les applis, une exception assumée (un chemin ouvert, un réglage fait
  hors code).
- Une décision prise en discussion sans PR : statut « proposée », jusqu'à la
  PR qui la met en œuvre.
- Pas pour une appli de plus qui suit le modèle `new-app` sans écart.

Un ADR ne se réécrit pas : une décision qui change donne un nouvel ADR, et
l'ancien passe en « remplacée par NNNN ». Ce qui n'a pu être sourcé (PR,
commit, issue) est marqué « à confirmer ».

## Modèle

Fichier `NNNN-titre-court.md` (numéro suivant, minuscules, tirets), 60 lignes
au plus :

```markdown
# NNNN. Titre

- **Statut** : proposée | acceptée | rejetée | remplacée par NNNN
- **Date** : AAAA-MM-JJ

## Contexte
## Décision
## Alternatives écartées
(chacune avec sa raison)
## Conséquences
(les bonnes et les mauvaises)
## Liens
(PR, issues, runbooks, fichiers)
```

## Index

| N° | Décision | Statut |
|---|---|---|
| [0001](0001-sauvegardes-borgmatic.md) | Sauvegardes Borgmatic + Borg, un sous-compte par hôte, restauration testée en CI | acceptée (check trimestriel remplacé par 0017) |
| [0002](0002-pangolin-seule-entree-publique.md) | Pangolin seule entrée publique, FR/DE seulement, chemins ouverts relus | acceptée (exceptions : 0025, 0030, 0032) |
| [0003](0003-crowdsec-sur-pangolin.md) | CrowdSec sur Pangolin, plugin Traefik, AppSec en détection seule | acceptée |
| [0004](0004-nextcloud-derriere-le-sso.md) | Nextcloud derrière le SSO, mots de passe d'application obligatoires | acceptée |
| [0005](0005-retention-journaux-pangolin.md) | Base de Pangolin : rétention des journaux 30/90 jours | acceptée (VACUUM à confirmer) |
| [0006](0006-objets-faits-main-audites.md) | Objets faits main dans Pangolin et Uptime Kuma audités au plan | acceptée (passerelles VPN déclarées depuis 0021) |
| [0007](0007-donnees-sur-le-nas.md) | Données d'applis sur le NAS en NFSv3, Jellyfin sur le NAS, relais du 443 | acceptée (volet NFS non appliqué depuis le 2026-11-04) |
| [0008](0008-renovate-hebdomadaire.md) | Renovate : PR hebdomadaires, images à état manuelles, automerge ciblé | acceptée |
| [0009](0009-sops-age-deux-fichiers.md) | SOPS + age, deux fichiers, clés nommées contre le masquage | acceptée (emplacement des fichiers remplacé par 0018) |
| [0010](0010-supervision-beszel-uptime-kuma.md) | Supervision : Beszel et Uptime Kuma (PikaPods) | acceptée (journaux : voir 0011) |
| [0011](0011-journaux-victorialogs.md) | Journaux centralisés dans VictoriaLogs | acceptée |
| [0012](0012-filtrage-dns-blocky.md) | Filtrage DNS du réseau local par Blocky | acceptée (bascule du DHCP non constatée au 05/11, à confirmer) |
| [0013](0013-kubernetes-pas-maintenant.md) | Pas de Kubernetes en prod ; k3s + Flux pour apprendre | acceptée (pas de Kubernetes ; volet apprentissage écarté le 2026-11-04) |
| [0014](0014-homebox.md) | Homebox sur disque local, derrière le SSO, inscription fermée | acceptée |
| [0015](0015-acces-de-secours-wireguard.md) | Accès de secours au LAN par WireGuard sur le LXC newt, sans Pangolin | rejetée (couvert par les runbooks) |
| [0016](0016-login-unifie-oidc.md) | Login unifié : Authelia (passkey + mot de passe, ou mot de passe + TOTP), IdP OIDC du mur Pangolin et des applis, login local gardé en secours | remplacée par 0030 |
| [0017](0017-pas-de-verification-complete-des-donnees.md) | Pas de vérification complète des données Borg ; test de restauration et checks des hôtes | acceptée |
| [0018](0018-secrets-depot-prive.md) | Secrets SOPS et inventaire de rotation dans un dépôt privé, sous-module `secrets/` | acceptée |
| [0019](0019-flip-sans-ipv4-publique.md) | flip sans IPv4 publique : NAT et rebond SSH par Pangolin, point unique accepté | acceptée |
| [0020](0020-garder-le-raspberry-pi-pour-immich.md) | Garder le Raspberry Pi pour Immich, isolé de Proxmox et de la VM docker | acceptée |
| [0021](0021-provider-pangolin-du-fork.md) | Provider Pangolin : build du fork servi par un miroir local, en attendant l'amont | acceptée |
| [0022](0022-durcissement-des-conteneurs.md) | Conteneurs : `no-new-privileges` par défaut, contrôlé en CI, `cap_drop` au cas par cas | acceptée |
| [0023](0023-limites-de-ressources.md) | Limites : mémoire mesurée sur chaque service, pas de quota CPU hors traitements par lots | acceptée |
| [0024](0024-deploiement-au-merge.md) | Le merge sur `main` déploie : quatre playbooks en CI, Tofu et le reste à la main | acceptée (fenêtre de calme : 0029) |
| [0025](0025-promptoramix-ouverte-sur-flip.md) | Promptoramix sur flip, ouverte de partout, gardée par sa seule signature HMAC | acceptée |
| [0026](0026-vzdump-sur-le-nas-seul.md) | Sauvegardes vzdump sur le NAS seul, sans copie hors site | acceptée |
| [0027](0027-connexions-ssh-cles-connues.md) | Connexions SSH : clés connues tracées sur ntfy, tout le reste sonne sur Telegram | acceptée |
| [0028](0028-cle-ssh-de-ci-root.md) | La clé SSH de la CI reste équivalente à root : risque accepté | acceptée |
| [0029](0029-fenetre-de-calme-du-deploiement.md) | Fenêtre de calme : pas de déploiement automatique de 19:00 à 08:00 (Paris), rattrapage au matin | acceptée |
| [0030](0030-pocket-id-fournisseur-identite-pilote.md) | Pocket ID, fournisseur d'identité (remplace 0016 ; pilote clos le 2026-11-07), public hors du filtre FR/DE : exception à 0002 | acceptée |
| [0031](0031-certificats-jokers.md) | Un certificat joker par domaine (DNS-01) au lieu d'un certificat par nom | acceptée |
| [0032](0032-passerelle-ia-pangolin.md) | Passerelle IA de Pangolin : une clé et un budget par appli, sans filtre FR/DE (exception à 0002) | acceptée |
| [0033](0033-postgresql-partage-sur-la-vm-docker.md) | Un PostgreSQL partagé sur la VM docker : pas maintenant, 30 à 160 Mio gagnés pour une isolation perdue | proposée |
