# Hosted apps

Each app is an Ansible role (`ansible/roles/<role>`) deployed by the playbook of its host, and its Pangolin route is an entry in `tofu/pangolin_config/website_<name>.tf`. Unless noted, Pangolin asks for SSO login before it lets a request through.

| App | Role | Host | What it is |
|---|---|---|---|
| [Homepage](https://gethomepage.dev/) | `homepage` | Docker VM | Start page on `home.sylvain.cloud`: one link per public app, generated from `local.websites` (the `homepage` field of each entry, `homepage_links` output read by `docker.yml`), plus Jellyfin and the Pangolin dashboard. Links only (no widget, API key or Docker socket), so nothing to back up |
| [FreshRSS](https://freshrss.org/) | `rss` | Docker VM | RSS reader |
| Betisier | `betisier` | Docker VM | Small web app with a MariaDB database ([docker-betisier-tp](https://github.com/sylvainmetayer/docker-betisier-tp)), public without SSO |
| [Monica](https://www.monicahq.com/) | `monica_v4` | Docker VM | Personal CRM |
| [Meerkat CRM](https://github.com/fbuchner/meerkat-crm) | `meerkat_crm` | Docker VM | Personal CRM |
| [BookStack](https://www.bookstackapp.com/) | `wiki` | Docker VM | Wiki |
| [Nextcloud](https://nextcloud.com/) | `nextcloud` | Docker VM | File sync, public without SSO (clients log in to Nextcloud itself) |
| [Paperless-ngx](https://docs.paperless-ngx.com/) | `paperless_ngx` | Docker VM | Scanned documents with OCR. **Paused** since October 2026 (`paperless_enabled: false`): stopped, not backed up, Pangolin resource disabled, data and borg repository kept; see [runbooks/app-en-pause.md](runbooks/app-en-pause.md) to resume |
| [Stirling-PDF](https://www.stirlingpdf.com/) | `stirling_pdf` | Docker VM | PDF tools (merge, split, OCR in French and English, conversions) on `pdf.sylvain.cloud`, behind the SSO with no login of its own, telemetry off. Stateless: only `configs/` persists (its `settings.yml` and the JVM's AOT cache, not backed up) |
| [Dawarich](https://dawarich.app/) | `dawarich` | Docker VM | Location history |
| [TREK](https://github.com/liketrek/TREK) | `trek` | Docker VM | Trip planner |
| [Karakeep](https://karakeep.app/) | `karakeep` | Docker VM | Bookmarks and read-later |
| [nginx](https://nginx.org/) | `nginx_demo` | Docker VM | Pilot of app data on the NAS (NFS): static page plus an unused Postgres, both on the NAS export |
| [Wishlist](https://github.com/cmintey/wishlist) | `wishlist` | Docker VM | Gift wishlists shared with family; a public list's link opens without SSO |
| [KitchenOwl](https://kitchenowl.org/) | `kitchenowl` | Docker VM | Shopping list, recipes and meal planner on `frigo.sylvain.cloud`, one KitchenOwl account each (no sign-up, no onboarding: accounts made with `manage.py`). The web interface is behind the SSO; `/api/*` and `/socket.io/*` are open without SSO, from any country, for the mobile app, guarded by KitchenOwl's own login |
| [Beszel](https://beszel.dev/) | `beszel` | Docker VM | Host monitoring hub (CPU, memory, disks, network, containers, S.M.A.R.T.) on `monitoring.sylvain.cloud`; one agent per host (`beszel_agent`: docker, pi, pangolin, flip, newt-lxc, NAS, the Proxmox host). Behind the SSO, plus its own Beszel account; the hub port is also published on the LAN (192.168.1.216:8090), where only the Beszel account protects it |
| [Immich](https://immich.app/) | `immich` | Raspberry Pi | Photo library |
| Immich Swipe | `immich` | Raspberry Pi | Swipe interface to sort Immich photos |
| Flip Planning | `flip_planning` | flip | Team scheduling app ([planning-equipes](https://github.com/sylvainmetayer/planning-equipes)), production |
| Flip Planning demo | `flip_planning` | flip | Demo instance of the same app |
| Flip Planning demo with Keycloak | `flip_planning` | flip | Demo instance with its own Keycloak under `/auth` |
| Promptoramix | `promptoramix` | flip | AI bot for the Marmelab Linkx tournament, public without SSO, requests checked by HMAC signature |
| [Pangolin](https://pangolin.net/) | `pangolin` | Pangolin VM | The reverse proxy itself and its dashboard |
| [Jellyfin](https://jellyfin.org/) | `jellyfin` | NAS | Media server (films, series, music, books, audiobooks from the `media` shared folder, read-only), Quick Sync transcoding. Not public, one name everywhere: **`https://media.sylvain.cloud:8443` on the LAN** and **`https://media.sylvain.cloud` outside, with the Pangolin client** (role `jellyfin`; the `:8443` URL works there too, so an app set up at home keeps working outside; the private resource of that alias, TCP 443 and 8443, served by the NAS's own Newt, site `nas`). The public A record points at the NAS's LAN IP (`tofu/dns/media.tf`); the NAS's Traefik (role `nas_proxy`, `dc@nas_proxy`, container `nas-proxy`) terminates TLS with a Let's Encrypt certificate (DNS-01, OVH key `nas_ovh_*`), listening on 443 and 8443, only 8443 published on the NAS since UGOS's nginx owns 80/443. Fallback: `http://192.168.1.137:8096` on the LAN. Jellyfin's "Known proxies" must hold Traefik's fixed IP on Jellyfin's `media` network, `172.30.96.10`. Jellyfin accounts of its own, no SSO. User guide (apps, casting, file naming, transcoding, ffmpeg): [media.md](media.md). **Not backed up yet**: its config and database (`/volume1/docker/jellyfin/config`) wait for borgmatic on the NAS; the media are only protected by the RAID 1 and the Btrfs snapshots |

The NAS admin page and Proxmox are not public: they are Pangolin private resources (`nas.sylvain.cloud`, `pve.internal`, `tofu/pangolin_config/private_resources.tf`), served by the Newt LXC. The NAS admin page (UGOS) is **`https://nas.sylvain.cloud:8443`** at home and through the Pangolin client, the same NAS Traefik in front of UGOS's nginx (public A record to the NAS's LAN IP, `tofu/dns/nas.tf`); fallback `http://192.168.1.137:9999`.

This table is the reference list of the apps; AGENTS.md points here instead of repeating it. The playbooks are `ansible/docker.yml` (Docker VM), `ansible/pi.yml` (Raspberry Pi), `ansible/flip.yml` (flip), `ansible/pangolin.yaml` (Pangolin VM), `ansible/lxc.yml` (the Newt LXC, no app) and `ansible/nas.yml` (the NAS, run by hand: NFS exports, the Beszel agent, its Newt and Jellyfin). To add or remove an app, see the `new-app` and `remove-app` skills under `.claude/skills/` and the matching sections of [AGENTS.md](../AGENTS.md).
