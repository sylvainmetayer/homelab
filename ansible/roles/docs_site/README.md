# docs_site

Le dossier `docs/` du dépôt (architecture, runbooks, ADR, conventions,
applis) publié en site statique sur **https://docs.sylvain.cloud**, derrière
le SSO Pangolin : lire un runbook depuis un téléphone pendant une panne. VM
docker, `dc@docs_site`, un conteneur `docs-site` (nginx unprivileged, en
lecture seule, sous l'uid de l'utilisateur : site et configuration en 0600) sur le réseau `newt`.

## Construction

[Zensical](https://zensical.org/) (`mkdocs.yml` à la racine, qu'il lit
directement, variante `classic` ; version d'`uv.lock`). Le rôle construit le
site **sur le contrôleur** (`delegate_to: localhost`, `run_once`,
`.github/scripts/mkdocs_build.py` avec le Python qui lance Ansible), en fait
une archive reproductible (sha256 stable tant que le contenu ne change pas),
puis la dépose sous `releases/<sha256>/` sur l'hôte et bascule le lien
`releases/current`. Une archive déjà déposée ne redépose rien ; l'ancienne
version est supprimée. nginx n'est pas redémarré : il suit le lien.

Zensical ne prend pas les hooks de MkDocs. `mkdocs_build.py` travaille donc
sur une copie de `docs/` : contrôles, réécriture des liens hors de `docs/`,
`zensical build --strict`, puis dépôt de Mermaid. Zensical 0.0.x est jeune :
relire le site après une montée de version.

En local : `uv run python .github/scripts/mkdocs_build.py --site-dir site`. Pour
un aperçu, `uv run zensical serve` (http://127.0.0.1:8000), sans ces étapes :
liens hors de `docs/` morts, Mermaid chargé depuis unpkg.com.

## Déploiement

Un merge sur `main` qui touche `docs/**`, `mkdocs.yml` ou ses scripts
(`.github/scripts/mkdocs_*.py`) déploie le tag
`docs_site` sur la VM docker (`deploy-docker-app.yaml`,
`resolve_docker_tags.py`), comme un changement de ce rôle. À la main :

```bash
ansible-playbook docker.yml --tags docs_site
```

Le workflow Lint lance `mkdocs_build.py` sur chaque PR : un lien cassé, une
ancre inconnue (Zensical), une page absente de `nav:`, un lien absolu, une
cible hors `.md` absente ou un lien vers un dossier (contrôles du script, que
Zensical ne fait pas) font échouer la PR avant le
merge.

## Liens hors de docs/

Un lien relatif vers un fichier hors de `docs/` (README d'un rôle,
`AGENTS.md`, un module tofu...) reste relatif dans le Markdown, juste sur
GitHub ; `.github/scripts/mkdocs_external_links.py` le réécrit en URL
GitHub (`blob/main`) pour le site. Un lien vers un dossier de `docs/` (sans
fichier) n'a pas de page : viser un fichier, ou l'URL GitHub du dossier.

## Diagrammes Mermaid

Un bloc ` ```mermaid ` devient un diagramme grâce au `custom_fences` de
`pymdownx.superfences` (`mkdocs.yml`) ; sans lui, il reste un bloc de code.
Zensical chargerait Mermaid depuis `unpkg.com` dans le navigateur :
`.github/scripts/mkdocs_mermaid.py` dépose à la place une version épinglée
(version + sha256, téléchargée à la construction, en cache sous
`~/.cache/homelab-mkdocs/`) en `javascripts/mermaid.min.js`, qu'il ajoute
aux seules pages qui ont un diagramme. Le site ne charge rien d'un autre domaine.
En CI (Lint et `deploy-docker-app`), ce cache est un `actions/cache` dont la clé
est l'empreinte du script (qui porte la version et le sha256) : jsDelivr n'est
appelé qu'au premier build d'une nouvelle version dans une portée de cache
(`main`, puis chaque PR qui ne trouve pas la clé sur `main`), ou après sept
jours sans build (éviction de GitHub) ; sur le poste qui lance Ansible, c'est
le même dossier qui sert.

Renovate suit la version (`customManagers` de `renovate.json`, datasource
npm, PR à part, jamais en automerge, majeure bornée à celle qu'attend
Zensical : 12 pour Zensical 0.0.74). Il ne sait pas recalculer le sha256 : sur
sa branche, `curl -sL <url> | sha256sum`, puis mettre à jour
`MERMAID_SHA256` et `MERMAID_SHA256_OF`. Jusque-là, `test_mkdocs_mermaid.py`
et le build échouent en le disant.

## Sans état

Rien à sauvegarder ni à tester en restauration : tout se reconstruit depuis
le dépôt. Pangolin ou la VM docker tombés, le site tombe avec eux : les mêmes
pages se lisent sur GitHub ou dans un clone.
