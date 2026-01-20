# Guide de Migration des Rôles Ansible

Ce document décrit la procédure standardisée pour migrer un rôle Ansible vers la nouvelle infrastructure (Traefik/Pangolin + Borgmatic).

## Contexte

La nouvelle infrastructure utilise :

- **Traefik/Pangolin** pour le routing HTTP (au lieu de Nginx + Certbot)
- **Borgmatic** pour les backups (au lieu de Restic)
- **Systemd user service** `dc@<service>` déjà créé par le rôle `docker_service`
- **compose.yaml** comme nom standard (au lieu de docker-compose.yml)

## Checklist de Migration

### 1. Structure des Répertoires

Assurer que le répertoire du projet existe dans `{{ docker_base_path }}/NOM_APPLICATION` :

```yaml
- name: Ensure <service> app folder exists
  loop:
    - "{{ service_base_path }}"
    - "{{ service_base_path }}/config"  # Si nécessaire
  ansible.builtin.file:
    mode: "0755"
    path: "{{ item }}"
    state: directory
    owner: "{{ ansible_facts['user_id'] }}"
    group: "{{ ansible_facts['user_gid'] }}"
```

**Note :** La variable `service_base_path` doit être définie dans `defaults/main.yml` comme :

```yaml
service_base_path: "{{ docker_base_path }}/service"
```

### 2. Supprimer les Références à Restic

**À SUPPRIMER :**

- Toutes les tâches contenant `restic`
- Variables `*_restic_*` dans `defaults/main.yml`
- Templates `restic-*.j2`

**À AJOUTER :** Configuration Borgmatic (voir exemples [betisier](../ansible/roles/betisier) ou [rss](../ansible/roles/rss))

```yaml
# Dans tasks/main.yml
- name: Configure borgmatic backup for <service>
  when: service_backup_enabled
  tags: backup
  block:
    - name: Create borgmatic configuration for <service>
      become: true
      ansible.builtin.template:
        src: "templates/borgmatic-service.yaml.j2"
        dest: "{{ borgmatic_config_dir }}/service.yaml"
        owner: "root"
        group: "root"
        mode: "0600"

    - name: Initialize borg repository for <service>
      become: true
      ansible.builtin.shell:
        cmd: "/root/.local/bin/borgmatic --config {{ borgmatic_config_dir }}/service.yaml repo-create --encryption {{ borgmatic_encryption_mode | default('repokey-aes-ocb') }}"
      register: borg_repo_create
      changed_when: "'repository already exists' not in borg_repo_create.stderr"
      failed_when: >
        borg_repo_create.rc != 0 and
        'repository already exists' not in borg_repo_create.stderr
```

**Template `borgmatic-service.yaml.j2` :**
```jinja
# Borgmatic configuration for <service> backup
# See https://torsion.org/borgmatic/reference/configuration/ for full reference

source_directories:
    - {{ service_base_path }}/config
    - {{ service_base_path }}/compose.yaml
    # Ajouter autres dossiers/fichiers à sauvegarder

# Si backup de base de données MySQL/PostgreSQL, ajouter section appropriée
# mysql_databases:
#     - container: service_db
#       port: 3306
#       name: dbname
#       username: user
#       password: {{ service_db_password }}

exclude_patterns:
    - '*.log'
    - '*.tmp'
    - 'cache/*'

local_path: /root/.local/bin/borg

repositories:
    - path: {{ service_backup_borgmatic_target }}
      label: service-s3

encryption_passphrase: {{ service_backup_borgmatic_password }}

compression: auto,zstd

archive_name_format: '{hostname}-service-{now:%Y-%m-%dT%H:%M:%S}'

retention:
    keep_daily: 7
    keep_weekly: 4
    keep_monthly: 6

consistency:
    checks:
        - name: repository
          frequency: 2 weeks
        - name: archives
          frequency: 4 weeks

before_backup:
    - echo "Starting backup for service at {now}"

after_backup:
    - echo "Completed backup for service at {now}"

on_error:
    - echo "Error during backup for service at {now}"

{% if service_backup_healthcheck_url is defined and service_backup_healthcheck_url %}
# https://torsion.org/borgmatic/reference/configuration/monitoring/uptime-kuma/
uptime_kuma:
    push_url: {{ service_backup_healthcheck_url }}
    states:
        - start
        - finish
        - fail
{% endif %}
```

**Variables dans `defaults/main.yml` :**
```yaml
service_backup_enabled: true
service_backup_borgmatic_target: ""  # À définir dans host_vars
service_backup_borgmatic_password: ""  # À définir dans secrets.sops.yaml
service_backup_healthcheck_url: ""  # Optionnel - URL de healthcheck Uptime Kuma
```

**Note importante :** La variable `borgmatic_config_dir` est définie globalement dans `group_vars/all/variables.yml` (valeur par défaut: `/etc/borgmatic.d`). Ne pas la redéfinir dans les rôles.

### 3. Template Docker Compose

**RENOMMER :** `docker-compose.yml` → `compose.yaml`

```yaml
- name: Template compose configuration
  notify: Restart <service>
  ansible.builtin.template:
    src: "templates/compose.yaml"
    dest: "{{ service_base_path }}/compose.yaml"
    owner: "{{ ansible_facts['user_id'] }}"
    group: "{{ ansible_facts['user_gid'] }}"
    mode: "0644"
```

### 4. Configuration Traefik/Pangolin (Labels Docker)

**À SUPPRIMER :**

- Templates nginx (`nginx-*.j2`, `default.conf.j2`, etc.)
- Tâches de configuration nginx
- Variable `certbot_certs`

**À AJOUTER dans `compose.yaml` :**

```yaml
services:
  service:
    container_name: service
    labels:
      # Configuration Pangolin pour routing public
      - pangolin.public-resources.service.name=Service Name
      - pangolin.public-resources.service.full-domain={{ service_domain }}
      - pangolin.public-resources.service.protocol=http
      - pangolin.public-resources.service.targets[0].method=http
      - pangolin.public-resources.service.targets[0].port=80

      # SSO (activer si nécessaire)
      - pangolin.public-resources.service.auth.sso-enabled=true

      # Healthcheck (optionnel mais recommandé)
      - pangolin.public-resources.service.healthcheck.hostname=service
      - pangolin.public-resources.service.healthcheck.port=80
      - pangolin.public-resources.service.healthcheck.enabled=true
      - pangolin.public-resources.service.healthcheck.path=/
      - pangolin.public-resources.service.healthcheck.interval=30
      - pangolin.public-resources.service.healthcheck.timeout=5
      - pangolin.public-resources.service.healthcheck.method=GET
      - pangolin.public-resources.service.healthcheck.status=200
    networks:
      - newt  # Réseau externe pour accès Pangolin/Traefik
    image: image:tag@sha256:hash
    environment:
      - PUID={{ ansible_facts['user_uid'] }}
      - PGID={{ ansible_facts['user_gid'] }}
      - TZ=Europe/Paris
    volumes:
      - ./config:/config
    restart: unless-stopped

networks:
  newt:
    external: true  # Réseau créé par le rôle newt
```

**Cas avec base de données :**

Si le service utilise une base de données, créer un réseau interne pour la communication inter-conteneurs :

```yaml
services:
  service:
    container_name: service
    labels:
      # ... labels Pangolin
    networks:
      - newt      # Réseau externe pour accès Pangolin/Traefik
      - service   # Réseau interne pour communication avec la DB
    # ... reste de la config
    restart: unless-stopped

  service_db:
    container_name: service_db
    networks:
      - service   # Même réseau interne que le service principal
    image: mariadb:tag@sha256:hash
    environment:
      - PUID={{ ansible_facts['user_uid'] }}
      - PGID={{ ansible_facts['user_gid'] }}
      - TZ=Europe/Paris
      - MYSQL_ROOT_PASSWORD={{ service_db_password }}
      - MYSQL_DATABASE=dbname
      - MYSQL_USER=dbuser
      - MYSQL_PASSWORD={{ service_db_password }}
    volumes:
      - ./db_data:/config
    restart: unless-stopped

networks:
  service:      # Réseau interne (créé automatiquement)
  newt:
    external: true  # Réseau créé par le rôle newt
```

**Notes importantes :**

- Le réseau `newt` doit être externe (créé par le conteneur Newt qui gère le socket Docker)
- **Si base de données présente** : créer un réseau interne (nommé d'après le service) pour la communication entre le service et sa DB
- Le service principal doit être dans **2 réseaux** : `newt` (externe) + `service` (interne)
- La base de données doit être **uniquement** dans le réseau interne (pas d'accès direct depuis Pangolin)
- Les labels Pangolin suivent le format : `pangolin.public-resources.<nom>.<propriété>`
- Le nom dans les labels doit correspondre au nom du service
- `sso-enabled=true` active l'authentification SSO via Pangolin

### 5. Supprimer la Variable certbot_certs

**À SUPPRIMER dans `defaults/main.yml` :**
```yaml
# ANCIEN - NE PLUS UTILISER
certbot_certs:
  - domains:
      - example.com
```

Le certificat SSL est maintenant géré automatiquement par Traefik/Pangolin via les labels Docker.

### 6. Gestion du Service Systemd

**À SUPPRIMER :**
- Tâches créant le service systemd (template du fichier `.service`)
- Le service `dc@<service>` existe déjà via le rôle `docker_service`

**À CONSERVER :**
```yaml
- name: Make sure <service> service is running
  ansible.builtin.systemd:
    state: started
    daemon_reload: true
    name: dc@service
    scope: user
    enabled: true
```

**Handler dans `handlers/main.yml` :**
```yaml
---
- name: Restart <service>
  ansible.builtin.systemd:
    state: restarted
    name: dc@service
    scope: user
    daemon_reload: true
  listen: Restart <service> service
```

## Exemples de Références

### Rôles Migrés (Bonnes Pratiques)
- **[betisier](../ansible/roles/betisier)** : Exemple complet avec DB MySQL + backup borgmatic + timer systemd
- **[rss](../ansible/roles/rss)** : Exemple simple avec backup borgmatic
- **[echo](../ansible/roles/echo)** : Exemple minimaliste

### Points d'Attention

1. **Réseau Docker** : Toujours inclure le réseau `newt` pour l'accès via Pangolin
2. **Permissions** : Utiliser `ansible_facts['user_uid']` et `ansible_facts['user_gid']` pour PUID/PGID
3. **Variables sensibles** : Stocker dans `secrets.sops.yaml` (chiffré avec SOPS/Age)
4. **Backup** : Toujours tester la création du repo borg avec `changed_when` et `failed_when` appropriés
5. **Naming** : Utiliser systématiquement `compose.yaml` (pas `docker-compose.yml`)


## Variables Standard à Définir

Dans `defaults/main.yml` :
```yaml
service_base_path: "{{ docker_base_path }}/service"
service_domain: "service.example.com"
service_backup_enabled: true
service_backup_borgmatic_target: ""
service_backup_borgmatic_password: ""
```

Dans `host_vars/<host>/variables.yaml` :
```yaml
service_domain: "service.sylvain.dev"
service_backup_enabled: true
service_backup_borgmatic_target: "rclone:backup:{{ backup_s3_bucket_name }}/service"
service_backup_encryption_passphrase: "{{ backup_passphrase }}"
```

Dans `secrets.sops.yaml` (chiffré) :
```yaml
service_backup_borgmatic_target: "s3://endpoint/bucket/service"
service_backup_borgmatic_password: "secure-password"
```

**IMPORTANT**: Penser à ajouter le rôle dans le playbook approprié (ex: `docker.yml`, `pangolin.yaml`) :
```yaml
roles:
  # ... autres rôles
  - name: service
    tags: service,app
```

## Validation Post-Migration

Après migration, vérifier :

```bash
# Check mode Ansible
mise run ansible-check

# Vérifier que le service démarre
sudo -u user systemctl --user status dc@service

# Vérifier les logs
sudo -u user journalctl --user -u dc@service -n 50

# Tester le backup borgmatic
sudo borgmatic --config /etc/borgmatic.d/service.yaml --list

# Vérifier l'accès via Pangolin
curl -I https://service.sylvain.dev
```

## Migration Checklist Finale

- [ ] Répertoires créés avec bonnes permissions
- [ ] Restic supprimé, borgmatic configuré
- [ ] `compose.yaml` templated (renommé depuis docker-compose.yml si besoin)
- [ ] Labels Pangolin ajoutés, templates nginx supprimés
- [ ] Variable `certbot_certs` supprimée
- [ ] Tâches de création de service systemd supprimées
- [ ] **Variables borgmatic ajoutées dans `host_vars/<host>/variables.yaml`**
- [ ] **Rôle ajouté dans le playbook approprié (docker.yml, pangolin.yaml, etc.)**
- [ ] Service testé avec `mise run ansible-check`
- [ ] Service déployé et fonctionnel
- [ ] Backup borgmatic testé et validé
- [ ] Accès HTTPS via Pangolin fonctionnel

