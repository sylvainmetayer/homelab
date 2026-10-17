# Hosted apps

Each app is an Ansible role (`ansible/roles/<role>`) deployed by the playbook of its host, and each public address is an entry in `tofu/pangolin_config/website_<name>.tf`. Unless noted, Pangolin asks for SSO login before it lets a request through.

| App | Role | Host | Address | What it is |
|---|---|---|---|---|
| [FreshRSS](https://freshrss.org/) | `rss` | Docker VM | rss.sylvain.cloud | RSS reader |
| [SearXNG](https://docs.searxng.org/) | `searxng` | Docker VM | search.sylvain.cloud | Metasearch engine |
| Betisier | `betisier` | Docker VM | betisier.sylvain.dev | Small web app with a MariaDB database ([docker-betisier-tp](https://github.com/sylvainmetayer/docker-betisier-tp)), public without SSO |
| [Monica](https://www.monicahq.com/) | `monica_v4` | Docker VM | crm.sylvain.dev | Personal CRM |
| [Meerkat CRM](https://github.com/fbuchner/meerkat-crm) | `meerkat_crm` | Docker VM | crm.sylvain.cloud | Personal CRM |
| [BookStack](https://www.bookstackapp.com/) | `wiki` | Docker VM | wiki.sylvain.cloud | Wiki |
| [Nextcloud](https://nextcloud.com/) | `nextcloud` | Docker VM | sylvain.cloud | File sync, public without SSO (clients log in to Nextcloud itself) |
| [Paperless-ngx](https://docs.paperless-ngx.com/) | `paperless_ngx` | Docker VM | papiers.sylvain.cloud | Scanned documents with OCR |
| [Gramps Web](https://www.grampsweb.org/) | `gramps` | Docker VM | trees.sylvain.cloud | Family tree. Stopped for now (`gramps_enabled: false`), data and backups kept |
| [Dawarich](https://dawarich.app/) | `dawarich` | Docker VM | tracks.sylvain.cloud | Location history |
| [Scanopy](https://github.com/scanopy/scanopy) | `scanopy` | Docker VM | scan.sylvain.cloud | Network discovery and map |
| [TREK](https://github.com/mauriceboe/trek) | `trek` | Docker VM | travels.sylvain.cloud | Trip planner |
| [Karakeep](https://karakeep.app/) | `karakeep` | Docker VM | keep.sylvain.cloud | Bookmarks and read-later |
| Echo | `echo` | Docker VM | echo.sylvain.cloud | HTTP server that answers with the request it received |
| [Immich](https://immich.app/) | `immich` | Raspberry Pi | photos.sylvain.cloud | Photo library |
| Immich Swipe | `immich` | Raspberry Pi | swipe-photos.sylvain.cloud | Swipe interface to sort Immich photos |
| Flip Planning | `flip_planning` | flip | flip-planning.sylvain.cloud | Team scheduling app ([planning-equipes](https://github.com/sylvainmetayer/planning-equipes)), production |
| Flip Planning demo | `flip_planning` | flip | demo-planning.sylvain.dev | Demo instance of the same app |
| Flip Planning demo with Keycloak | `flip_planning` | flip | demo-planning-kc.sylvain.dev | Demo instance with its own Keycloak under `/auth` |
| Promptoramix | `promptoramix` | flip | promptoramix.sylvain.cloud | AI bot for the Marmelab Linkx tournament, public without SSO, requests checked by HMAC signature |
| [Pangolin](https://pangolin.net/) | `pangolin` | Pangolin VM | pangolin.sylvain.cloud | The reverse proxy itself and its dashboard |

Pangolin also publishes two pieces of home hardware that Ansible does not manage: the NAS admin page (nas.sylvain.cloud) and Proxmox (proxmox.sylvain.cloud).

The playbooks are `ansible/docker.yml` (Docker VM), `ansible/pi.yml` (Raspberry Pi), `ansible/flip.yml` (flip) and `ansible/pangolin.yaml` (Pangolin VM). To add or remove an app, see the `new-app` and `remove-app` skills under `.claude/skills/` and the matching sections of [AGENTS.md](../AGENTS.md).
