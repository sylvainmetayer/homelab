# Infra 2026

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
- https://github.com/orgs/fosrl/discussions/402#discussion-8123152
- https://pangolin.net/blog/posts/blueprints
