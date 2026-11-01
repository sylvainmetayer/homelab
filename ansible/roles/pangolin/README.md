# Role `pangolin`

Moved from `AGENTS.md` (agent-facing notes, kept in English); the index there links here.

## Response headers

- `security-headers@file` (`traefik_dynamic_config.yml.j2`) sits first on the `websecure` entrypoint, ahead of `crowdsec@file` and of every router's own middlewares (Badger included), so it covers Pangolin's dashboard and API, every resource, the domain redirects, and the 401/403 Traefik writes itself. It sets `Strict-Transport-Security: max-age=31536000`, replacing an app's own HSTS, and empties `Server` and `X-Powered-By`. No `includeSubDomains`, no `preload`: `nas.`, `media.` and `mediamanager.sylvain.cloud` are served by the NAS's Traefik, outside this proxy, and a preload entry cannot be taken back. Port 80 (ACME, redirects) gets no header. CSP, frame options and nosniff stay with each app: one global policy would break some of them. Rollback: take `security-headers@file` off the entrypoint first and keep the middleware defined until the stack has restarted (a later PR removes it): Traefik reloads the dynamic file at once but its static config only at the handler, and an entrypoint naming a missing middleware breaks every HTTPS route in between, as for `crowdsec@file`. A plain revert of this change opens that window.

## CrowdSec

- CrowdSec on Pangolin (`docs/runbooks/crowdsec.md`): container `crowdsec` (agent + LAPI + AppSec, digest-pinned, data under `/opt/pangolin/crowdsec`, never backed up) in the pangolin compose, reading Traefik's JSON access log (`config/traefik/logs`, rotated daily by `/etc/logrotate.d/traefik-access` with SIGUSR1, excluded from borgmatic); bouncer = Traefik plugin `maxlerebourg/crowdsec-bouncer-traefik-plugin` (tracked by the same Renovate regex as badger) as `crowdsec@file` on the `websecure` entrypoint only (port 80/ACME untouched), `stream` mode, failing open (`updateMaxFailure: -1`, AppSec `*Block: false`). AppSec is detect-only: every rule loaded `outofband` (`homelab/appsec-alert-only`), so alerts, never a 403 or a ban. Client IP = the TCP peer (no `forwardedHeaders`/`forwardedHeadersTrustedIPs`); `home_ip`, Pangolin's public IP, private ranges and `pangolin_crowdsec_whitelist_extra` are both an s02 whitelist and `clientTrustedIPs` (the latter is what protects them from the community blocklist). Bouncer key: SOPS `pangolin_crowdsec_bouncer_key`, re-registered on every container start (compose `entrypoint` deletes `traefik` and the `traefik@<ip>` rows the LAPI adds): a LAPI key that differs makes AppSec answer 401 and the plugin 403 every request. Rollback: `pangolin_crowdsec_enabled: false` (`pangolin_crowdsec_appsec_enabled: false` for AppSec only) and `pangolin.yaml --tags pangolin`; while disabled, `crowdsec@file` stays defined as a no-op headers middleware, since Traefik reloads the dynamic file at once but its static config only when the stack restarts (handlers flushed at the end of the role, before borgmatic).

- CrowdSec on Pangolin also sends a weekly summary to ntfy (`crowdsec-summary.timer`, Monday 07:30, pangolin role: `files/crowdsec-summary.py`, stateless, runs `docker exec crowdsec cscli alerts list --since 168h` and `decisions list`: alerts by scenario and country, active decisions, AppSec alert-only hits; priority low, high on any AppSec hit or a dead cscli). Topic and token of the `scripts` producer (`ntfy_scripts_token`, in the 0600 `/etc/crowdsec-summary/env`, never on a command line); removed with CrowdSec or without a token. `docs/runbooks/crowdsec.md`.

## GeoLite2

- GeoLite2 (the geo filter of every public resource) is refreshed weekly on Pangolin by `geoipupdate.timer` (pangolin role: the official MaxMind image, pinned; free account, `pangolin_maxmind_*` in `secrets/ansible.sops.yaml`), which restarts the `pangolin` container only when the database changed and pushes to the `GeoIP Pangolin` monitor (`uptime_cron_geoip_url`).

## Rebuild / restore

Server image, Hetzner backups and the rebuild order: `tofu/pangolin/README.md`.
