# Infra 2026

## Deps

- mise install
- uv sync

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
