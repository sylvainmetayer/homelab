# Une appli répond 503, ou son moniteur Uptime Kuma est rouge

## Symptôme

- Le moniteur « Healthcheck <Appli> » d'Uptime Kuma passe DOWN (mail).
- Le navigateur affiche la page de maintenance de Pangolin, ou une erreur
  503 « no available server ».
- Les autres applis répondent (sinon : [pangolin-injoignable.md](pangolin-injoignable.md)).

Rappel : Pangolin sert sa page de maintenance (code 200) dès que **toutes**
les cibles de la ressource échouent à leur healthcheck. Le moniteur Uptime
Kuma y cherche le titre de cette page, mot-clé inversé
(`tofu/pangolin_config/maintenance.tf`) : la page de maintenance = DOWN.

## Diagnostic

Repérer l'hôte et le nom du service : `docs/apps.md` (colonne Rôle) et
`tofu/pangolin_config/website_<app>.tf` (`target.ip` = nom du conteneur,
`target.port`, `hc_path`). Exemple ci-dessous avec `rss` sur la VM docker.

1. L'unité systemd utilisateur tourne-t-elle ?

   ```bash
   cd ansible && mise run ssh
   systemctl --user status dc@rss
   journalctl --user -u dc@rss -n 200 --no-pager
   ```

   `activating (auto-restart)` en boucle : l'unité relance `docker compose
   up` toutes les 15 s sans jamais abandonner (`dc@.service.j2`). Lire la
   cause dans le journal (image introuvable, erreur de compose, conteneur
   qui sort).

2. Les conteneurs sont-ils sains ?

   ```bash
   cd /opt/apps/rss
   docker compose ps
   docker compose logs --tail 100
   docker inspect --format '{{json .State.Health}}' <conteneur>
   ```

   Un conteneur `unhealthy` ou `restarting` ; une base qui n'est pas
   `healthy` bloque les services qui en dépendent (`depends_on:
   condition: service_healthy`).

3. Le conteneur exposé est-il sur le réseau `newt` ?

   ```bash
   docker network inspect newt --format '{{range .Containers}}{{.Name}} {{end}}'
   ```

   Le nom attendu est `target.ip` de `website_<app>.tf`. Absent : Newt ne
   peut pas le joindre.

4. Newt tourne-t-il sur l'hôte ?

   ```bash
   systemctl --user status dc@newt
   docker logs --tail 100 newt
   ```

   Si Newt est tombé, **toutes** les applis de l'hôte sont DOWN en même temps.

5. Côté Pangolin : tableau de bord `https://pangolin.sylvain.cloud`, la
   ressource, onglet des cibles : état du healthcheck et site en ligne ou non.

6. Mémoire : un conteneur collé à son `mem_limit` ralentit ou se fait tuer.

   ```bash
   sudo dmesg | grep -i "memory cgroup out of memory"
   docker stats --no-stream
   ```

   Voir [disque-plein-vm-lente.md](disque-plein-vm-lente.md).

## Réparation

- **Conteneur planté, cause passagère** : `systemctl --user restart dc@rss`.
- **Unité arrêtée ou désactivée** :
  `systemctl --user enable --now dc@rss`.
- **Image absente ou introuvable** (digest retiré du registre, faute de
  frappe dans une montée Renovate) : revenir au digest précédent par une PR
  de revert (voir [deploiement-ci-casse.md](deploiement-ci-casse.md)).
- **Compose ou config cassés par un déploiement** : redéployer le rôle depuis
  le dépôt, en vérifiant d'abord.

  ```bash
  cd ansible
  ansible-playbook docker.yml --tags rss --check --diff
  ansible-playbook docker.yml --tags rss
  ```

  Les tags de chaque rôle sont dans le playbook (`tags: rss,app`). Pour
  flip : `flip.yml --tags flip_planning` (prod), `demo_planning`,
  `demo_planning_kc`, `promptoramix`.
- **Newt en panne** : `systemctl --user restart dc@newt`. Sur flip, faire ce
  redémarrage depuis une session ouverte par `mise run ssh_flip` (rebond par
  Pangolin), jamais par `flip.internal` qui passe par ce même Newt.
- **Cible ou healthcheck faux côté Pangolin** (après un changement dans
  `tofu/pangolin_config`) : `tofu plan` dans `tofu/pangolin_config`, corriger
  le `website_<app>.tf`, appliquer. Toute cible doit porter `hc_hostname`
  (posé par `websites.tf`).
- **Données corrompues** : [sauvegarde-et-restauration.md](sauvegarde-et-restauration.md).

## Vérification

```bash
systemctl --user is-active dc@rss
docker compose -f /opt/apps/rss/compose.yaml ps
```

Puis le moniteur Uptime Kuma repasse UP (intervalle 60 s, 2 essais) et la
page s'ouvre dans le navigateur.

## Prévention

- Toute base a un `healthcheck` et un `stop_grace_period: 60s` ; tout service
  un `mem_limit` à environ 2× son pic mesuré (doctrine dans AGENTS.md).
- Les images sont épinglées par digest : `dc@` ne télécharge qu'une image
  absente, un registre en panne n'empêche pas un redémarrage.
- Un changement de routage passe par `tofu plan` dans `tofu/pangolin_config`
  et ses tests (`mise run tofu-test`).
