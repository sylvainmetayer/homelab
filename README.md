# Infra 2026

## Deps

- mise install
- uv sync

## Packer

Une image Packer est disponible pour déployer Pangolin Zero Trust sur Hetzner :

```bash
# Construire l'image (nécessite variable d'environnement HCLOUD_TOKEN)
mise run packer-build
```

L'image inclut :

- Docker et Docker Compose
- Pangolin installer pré-téléchargé dans `/opt/pangolin`
- Configuration de hardening (SSH, fail2ban, UFW, sysctl)
- cloud-init nettoyé pour permettre une reconfiguration au déploiement

## Notes

- [Donner accès en lecture seulement au socket docker](https://www.it-connect.fr/docker-comment-ameliorer-la-securite-avec-un-docker-socket-proxy/)
- pour que ça marche, pangolin newt doit être dans le même network docker que les conteneurs
- <https://github.com/orgs/fosrl/discussions/402#discussion-8123152>
- <https://pangolin.net/blog/posts/blueprints>

## Restauration

Pour restaurer une sauvegarde avec borgmatic (à améliorer), exemple avec betisier

```bash
sudo -s # root obligatoire
cd /opt/apps/betisier
borgmatic extract --archive latest --repo betisier-s3 -v 2 --strip-components all --path /opt/apps/betisier
mv betisier/* .
rm -rf betisier
# pour la partie DB
rm -rf borgmatic
# En tant qu'user
systemctl start dc@betisier --user
# pour le container db soit up
# retour root
sudo -s
borgmatic restore --archive latest --repo betisier-s3
```

### Test de restauration hebdomadaire

Chaque hôte qui a le rôle `borgmatic` lance `borgmatic-restore-test.timer` le
dimanche matin (`ansible/roles/borgmatic/files/borgmatic-restore-test.py`).
Pour chaque config de `/etc/borgmatic.d`, le script vérifie que la dernière
archive a moins de 48 h, extrait dans un dossier jetable tous les dumps de base
de données plus un échantillon aléatoire de fichiers, puis contrôle le résultat
(`pg_restore --list` dans le conteneur d'origine, fin de dump MySQL/SQLite
présente, tailles des fichiers). Rien n'est restauré dans une base en service.
Le résultat part sur le monitor push « Restore test <hôte> » d'Uptime Kuma.

```bash
sudo systemctl start borgmatic-restore-test.service   # à la demande
journalctl -u borgmatic-restore-test.service          # détail par config
```

### Mot de passe Postgres d'Immich

`POSTGRES_PASSWORD` n'est lu qu'à l'initialisation de la base. Pour changer
`immich_db_password`, il suffit de le modifier dans `secrets.sops.yaml` puis de
relancer `pi.yml --tags immich` : le rôle détecte que le mot de passe n'ouvre
plus la base et l'applique avec `ALTER ROLE` via le socket local du conteneur.
