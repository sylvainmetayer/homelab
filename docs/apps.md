# Hosted apps

Each app is an Ansible role (`ansible/roles/<role>`) deployed by the playbook of its host, and its Pangolin route is an entry in `tofu/pangolin_config/website_<name>.tf`. Unless noted, Pangolin asks for SSO login before it lets a request through.

| App | Role | Host | What it is |
|---|---|---|---|
| [FreshRSS](https://freshrss.org/) | `rss` | Docker VM | RSS reader |
| Betisier | `betisier` | Docker VM | Small web app with a MariaDB database ([docker-betisier-tp](https://github.com/sylvainmetayer/docker-betisier-tp)), public without SSO |
| [Monica](https://www.monicahq.com/) | `monica_v4` | Docker VM | Personal CRM |
| [Meerkat CRM](https://github.com/fbuchner/meerkat-crm) | `meerkat_crm` | Docker VM | Personal CRM |
| [BookStack](https://www.bookstackapp.com/) | `wiki` | Docker VM | Wiki |
| [Nextcloud](https://nextcloud.com/) | `nextcloud` | Docker VM | File sync, public without SSO (clients log in to Nextcloud itself) |
| [Paperless-ngx](https://docs.paperless-ngx.com/) | `paperless_ngx` | Docker VM | Scanned documents with OCR |
| [Dawarich](https://dawarich.app/) | `dawarich` | Docker VM | Location history |
| [TREK](https://github.com/mauriceboe/trek) | `trek` | Docker VM | Trip planner |
| [Karakeep](https://karakeep.app/) | `karakeep` | Docker VM | Bookmarks and read-later |
| [Wishlist](https://github.com/cmintey/wishlist) | `wishlist` | Docker VM | Gift wishlists shared with family; a public list's link opens without SSO |
| [Immich](https://immich.app/) | `immich` | Raspberry Pi | Photo library |
| Immich Swipe | `immich` | Raspberry Pi | Swipe interface to sort Immich photos |
| Flip Planning | `flip_planning` | flip | Team scheduling app ([planning-equipes](https://github.com/sylvainmetayer/planning-equipes)), production |
| Flip Planning demo | `flip_planning` | flip | Demo instance of the same app |
| Flip Planning demo with Keycloak | `flip_planning` | flip | Demo instance with its own Keycloak under `/auth` |
| Promptoramix | `promptoramix` | flip | AI bot for the Marmelab Linkx tournament, public without SSO, requests checked by HMAC signature |
| [Pangolin](https://pangolin.net/) | `pangolin` | Pangolin VM | The reverse proxy itself and its dashboard |

Pangolin also publishes two pieces of home hardware that Ansible does not manage: the NAS admin page and Proxmox.

The playbooks are `ansible/docker.yml` (Docker VM), `ansible/pi.yml` (Raspberry Pi), `ansible/flip.yml` (flip) and `ansible/pangolin.yaml` (Pangolin VM). To add or remove an app, see the `new-app` and `remove-app` skills under `.claude/skills/` and the matching sections of [AGENTS.md](../AGENTS.md).
