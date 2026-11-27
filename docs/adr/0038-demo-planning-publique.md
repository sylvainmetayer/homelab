# 0038. Démo publique de Flip Planning sur son propre serveur, ouverte au monde

- **Statut** : proposée
- **Date** : 2026-11-27

## Contexte

Mise en place d'une démo publique de Flip Planning, en libre accès. Il y faut quatre comptes affichés sur la page (dont `admin/admin`), le scénario du site déjà chargé avec un plan calculé, un calcul de 40 s au plus, et une remise à zéro toutes les 30 min.

La démo existante, sur flip, est en pause depuis le 2026-11-11 : flip (cx23, 2 vCPU, 4 Gio) n'a pas de mémoire à lui donner à côté de la production, d'OpenPost et de Promptoramix. Une vague de visiteurs prendrait du CPU, de la mémoire et du disque à la production. Toutes les ressources Pangolin publiques ne laissent passer que FR et DE, alors que le public d'une démo publique vient de partout.

## Décision

**Un serveur à lui** : un VPS-1 d'OVH (2 vCPU, 4 Go, x86, environ 5,40 € TTC par mois sans engagement), commandé à la main dans la console, car le stock est irrégulier. Il est configuré à la main par `ansible/demo-planning.yml`, jamais par la CI.
- Il a une IP publique, mais rien n'y écoute pour le public : le trafic web arrive par son propre newt (site `demo-planning`, connexion sortante vers Pangolin).
- SSH n'est ouvert qu'à l'IP de Pangolin (ufw), par où Ansible rebondit comme pour flip.
- Sa clé d'hôte se lit sur l'hôte.

Le rôle `flip_planning` s'y applique avec le mode démo de l'application (`DEMO_INSTANCE`, `PUBLIC_INSTANCE`). Ce mode accepte les mots de passe affichés sans permettre de les changer, coupe la météo, les webhooks, les clés MCP et les vrais courriels, affiche un bandeau, et passe un calcul à la fois (40 s au plus, file de 3, environ 30 par heure).

**Ouverte à tous les pays, sans SSO, pour cette seule ressource** : une règle PASS sur `/*` en priorité 3 (`pangolin_resource_rule.demo_planning_worldwide`), devant les règles de pays. CrowdSec reste devant. Mailpit n'est pas exposé.

**Remise à zéro toutes les 30 min** (rôle `flip_planning_demo`). Un timer user arrête l'appli, supprime et recrée la base, y restaure le dump de référence, puis recrée le conteneur de l'appli (ses journaux ne couvrent qu'une demi-heure). Le dump est fabriqué une fois sur l'hôte par le script de l'application (`scripts/demo/generer-dump.sh`) : il n'est ni dans l'image ni dans ce dépôt, et le mot de passe des comptes de démo n'existe qu'en empreinte dans le dump. La démo n'a ni sauvegarde, ni moniteur Backup. Un préchauffage suit chaque remise (connexion admin, Accueil, Planning). Devant l'appli, un Traefik de l'hôte plafonne à 30 requêtes en cours pour toute la démo et sert au-delà une page statique « démo saturée » (429) : le test de charge du 27/11 tue l'appli (OOM) vers 60 arrivées en une minute.

**Sortie filtrée sur l'hôte** (nftables, table `demo_egress`, chargée avant Docker) :
- les conteneurs ne joignent que Pangolin (Newt, HTTPS et WireGuard) ;
- l'hôte ne joint que DNS, NTP et HTTP(S) ;
- personne ne joint les réseaux privés (10/8, 192.168/16), ni SMTP, IMAP ou SSH sortant.

Le filtre est sur l'hôte, en plus du pare-feu d'entrée (ufw) : un conteneur compromis ne doit rien pouvoir envoyer.

**Bugsink** : un projet à part pour la démo (DSN vide tant qu'il n'est pas créé), pour que son trafic ne consomme pas le quota de la production.

## Alternatives écartées

- **Un cx23 Hetzner sans IP publique, sur le modèle de flip** (première version de cette ADR) : le cx23 n'est plus en vente (7,19 € TTC quand il l'était), ni le cx33. Le cpx22 coûte environ 24 € TTC. Le cax11 (ARM, environ 7,80 € TTC) demande une image arm64 que l'application ne publie pas.
- **Scaleway DEV1-S** : 2 Go seulement, et environ 12 € TTC avec l'IPv4.
- **Contabo, Netcup** (allemands) : plus chers à 4 Go, ou avec des disques et un CPU réputés irréguliers, et sans provider Tofu officiel.
- **AWS** (EC2 en spot, CloudFormation) : environ 13 à 16 € TTC. **Cloud Run** : PostgreSQL y demande Cloud SQL, la JVM démarre à froid à chaque réveil, et la remise à zéro par timer ne s'y prête pas.
- **Rallumer la démo sur flip avec `cpu_shares`** : pas de mémoire disponible, et le disque et les deux vCPU restent partagés. La production ne serait pas protégée d'un afflux de visiteurs.
- **Une limite `cpus:`** : la doctrine l'interdit sur un service interactif, et elle ne protège ni la mémoire ni le disque.
- **Ajouter des pays (US, GB…) au filtre de cette ressource** : le public d'une démo publique vient de partout.
- **Remise à zéro par la route de dump de l'application** : c'est un outil de test, à ne pas ouvrir sur une instance publique.
- **Un conteneur cron pour la remise à zéro** : il lui faudrait le socket Docker.

## Conséquences

- Bon : la production de flip ne partage plus rien avec la démo, sauf Pangolin.
- Bon : une base cassée ou un mot de passe changé ne dure pas plus de 30 min.
- Mauvais : tout le trafic de la démo passe par la VM Pangolin, qui porte aussi Pocket ID, ntfy et le NAT de flip. À surveiller pendant une vague (Beszel).
- Mauvais : un hôte de plus, hors de Hetzner, à payer (VPS-1) et à tenir à jour à la main. Son IP publique est connue d'OVH et de quiconque scanne : SSH est fermé à tous sauf Pangolin, et aucun port web n'y est ouvert.
- Mauvais : la ressource est ouverte à tous les pays. Tout ce que le filtre FR/DE arrêtait passe : seuls CrowdSec et le mode démo de l'application la gardent.
- Mauvais : une coupure d'environ 20 s toutes les 30 min. Le moniteur Uptime Kuma (300 s, une reprise à 60 s) la tolère.
- L'ancienne démo, en pause sur flip, est à décommissionner (`decommission_app` sur flip, puis retirer son entrée de `flip.yml`). Son dépôt Borg est exclu du test de restauration d'ici là.

## Liens

- `ansible/inventory/hosts`, `tofu/pangolin_config/website_demo_planning.tf`, `tofu/pangolin_config/nodes.tf`, `ansible/demo-planning.yml`, `ansible/roles/flip_planning_demo/`.
- ADR de l'application sur son mode démo (dépôt `planning-equipes`).
- [0037](0037-ntfy-sur-la-vm-pangolin.md) (charge de la VM Pangolin).
