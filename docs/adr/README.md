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

Fichier `NNNN-titre-court.md` (numéro suivant, minuscules, tirets), 40 lignes
au plus :

```markdown
# NNNN. Titre

- **Statut** : proposée | acceptée | remplacée par NNNN
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
| [0002](0002-pangolin-seule-entree-publique.md) | Pangolin seule entrée publique, FR/DE seulement, chemins ouverts relus | acceptée |
| [0003](0003-crowdsec-sur-pangolin.md) | CrowdSec sur Pangolin, plugin Traefik, AppSec en détection seule | acceptée |
| [0004](0004-nextcloud-derriere-le-sso.md) | Nextcloud derrière le SSO, mots de passe d'application obligatoires | acceptée |
| [0005](0005-retention-journaux-pangolin.md) | Base de Pangolin : rétention des journaux 30/90 jours | acceptée (VACUUM à confirmer) |
| [0006](0006-objets-faits-main-audites.md) | Objets faits main dans Pangolin et Uptime Kuma audités au plan | acceptée |
| [0007](0007-donnees-sur-le-nas.md) | Données d'applis sur le NAS en NFSv3, Jellyfin sur le NAS, relais du 443 | acceptée |
| [0008](0008-renovate-hebdomadaire.md) | Renovate : PR hebdomadaires, images à état manuelles, automerge ciblé | acceptée |
| [0009](0009-sops-age-deux-fichiers.md) | SOPS + age, deux fichiers, clés nommées contre le masquage | acceptée |
| [0010](0010-supervision-beszel-uptime-kuma.md) | Supervision : Beszel et Uptime Kuma (PikaPods) | acceptée |
| [0011](0011-journaux-victorialogs.md) | Journaux centralisés dans VictoriaLogs | proposée |
| [0012](0012-filtrage-dns-blocky.md) | Filtrage DNS du réseau local par Blocky | proposée |
| [0013](0013-kubernetes-pas-maintenant.md) | Pas de Kubernetes en prod ; k3s + Flux pour apprendre | proposée |
| [0014](0014-homebox.md) | Homebox sur disque local, derrière le SSO, inscription fermée | acceptée |
| [0015](0015-acces-de-secours-wireguard.md) | Accès de secours au LAN par WireGuard sur le LXC newt, sans Pangolin (non mise en œuvre) | proposée |
| [0016](0016-login-unifie-oidc.md) | Login unifié : Authelia (passkey + mot de passe, ou mot de passe + TOTP), IdP OIDC du mur Pangolin et des applis, login local gardé en secours | proposée |
| [0017](0017-pas-de-verification-complete-des-donnees.md) | Pas de vérification complète des données Borg ; test de restauration et checks des hôtes | acceptée |
