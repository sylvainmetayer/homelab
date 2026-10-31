# docs_site

Le dossier `docs/` du dépôt (architecture, runbooks, ADR, conventions,
applis) publié en site statique sur **https://docs.sylvain.cloud**, derrière
le SSO Pangolin : lire un runbook depuis un téléphone pendant une panne. VM
docker, `dc@docs_site`, un conteneur `docs-site` (nginx unprivileged, en
lecture seule, sous l'uid de l'utilisateur : site et configuration en 0600) sur le réseau `newt`.

## Construction

MkDocs + Material (`mkdocs.yml` à la racine, versions d'`uv.lock`). Le rôle
construit le site **sur le contrôleur** (`delegate_to: localhost`,
`run_once`, `mkdocs build --strict` avec le Python qui lance Ansible), en fait
une archive reproductible (sha256 stable tant que le contenu ne change pas),
puis la dépose sous `releases/<sha256>/` sur l'hôte et bascule le lien
`releases/current`. Une archive déjà déposée ne redépose rien ; l'ancienne
version est supprimée. nginx n'est pas redémarré : il suit le lien.

En local : `uv run mkdocs serve`, puis http://127.0.0.1:8000.

## Déploiement

Un merge sur `main` qui touche `docs/**`, `mkdocs.yml` ou son hook
`.github/scripts/mkdocs_external_links.py` déploie le tag
`docs_site` sur la VM docker (`deploy-docker-app.yaml`,
`resolve_docker_tags.py`), comme un changement de ce rôle. À la main :

```bash
ansible-playbook docker.yml --tags docs_site
```

Le workflow Lint lance `mkdocs build --strict` sur chaque PR : un lien cassé,
une page absente de `nav:` font échouer la PR avant le merge.

## Liens hors de docs/

Un lien relatif vers un fichier hors de `docs/` (README d'un rôle,
`AGENTS.md`, un module tofu...) reste relatif dans le Markdown, juste sur
GitHub ; le hook `.github/scripts/mkdocs_external_links.py` le réécrit en URL
GitHub (`blob/main`) pour le site. Un lien vers un dossier de `docs/` (sans
fichier) n'a pas de page : viser un fichier, ou l'URL GitHub du dossier.

## Sans état

Rien à sauvegarder ni à tester en restauration : tout se reconstruit depuis
le dépôt. Pangolin ou la VM docker tombés, le site tombe avec eux : les mêmes
pages se lisent sur GitHub ou dans un clone.
