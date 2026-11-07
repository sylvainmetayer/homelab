# Role `beszel`

Moved from `AGENTS.md` (agent-facing notes, kept in English); the index there links here.

## Monitoring (hub and agents)

The agent role is `beszel_agent`, whose README points here.

- Monitoring is Beszel (`docs/architecture.md`, « La supervision »): hub role `beszel` on the Docker VM, agent role `beszel_agent` on every host (`dc@beszel_agent` on docker/pi/flip, the same mode `dc` on the NAS, where `docker_service_scope: system` makes it a root system unit under `docker_base_path`, `docker compose up -d` on Pangolin, a systemd binary on the newt LXC and on the Proxmox host, `pve.yml`, which also reads S.M.A.R.T.). Agents dial the hub (no listening port): LAN hosts on `192.168.1.216:8090` (published by Docker, so before ufw: only the Beszel account guards the UI there), Pangolin and flip through the public resource's `/api/beszel/agent-connect` PASS with a per-agent Pangolin access token (`beszel_agent_hub_headers` output). The hub's `config.yml` is authoritative: a host removed from the SOPS dict `beszel_agent_tokens` loses its history. It only knows systems: alerts (`beszel_alerts`) are written by the role through the hub API at `127.0.0.1:8090`, authoritative too (tag `beszel_alerts`), logged in as the PocketBase **superuser** `beszel_api_email` (`tasks/api_login.yml`), not as the Beszel admin account, which signs in through Pocket ID only: a superuser reads and writes the `alerts` and `user_settings` records of any user, so the role looks the admin user up by `beszel_admin_email` and sets the `user` field itself (the `/api/beszel/user-alerts` routes would attach the alert to the superuser). See « API superuser » below. The channels (`user_settings`: Telegram plus the admin's e-mail, sent through the SMTP set in the hub's UI) are written, authoritatively, only once the optional SOPS keys `beszel_telegram_bot_token`/`beszel_telegram_chat_id` exist, which they do not today: until then the role warns and leaves the channels as set in the UI, and `--tags beszel_alerts_test` (Telegram only) refuses to run. S.M.A.R.T.: Beszel alerts by itself when a disk's state goes from PASSED to FAILED (`internal/alerts/alerts_smart.go`; 0.21.1's agent only yields PASSED/FAILED/UNKNOWN, so the code's WARNING never fires; to the users listed in `config.yml`, through their channels), the state being smartctl's overall verdict: no alert on SSD wear or pending sectors, nothing declarable in `beszel_alerts` (`docs/runbooks/sante-des-disques.md`, which also lists what only the hub's UI settles: SMTP, disks read). The agent never mounts the Docker socket: a `wollomatic/socket-proxy` sidecar (GET-only allowlist `beszel_agent_socket_proxy_allow_get`: container logs by hex ID yes, inspect no — Beszel strips only `Config.Env` from it, command args and labels would pass) does. The hub's `CONTAINER_DETAILS=true` serves the UI's container sheet, logs relayed on demand (last 200 lines, never stored) to any Beszel account with access to the system; its inspect pane stays empty (403 at each agent's proxy, logged on every sheet opening). Binary-mode hosts (newt LXC, pve) have no Docker, hence no container sheet, and no systemd service logs either: their unit's `DynamicUser` is in no journal group, so the agent finds the system journal unreadable and turns them off (`SupplementaryGroups=systemd-journal` would open the whole journal, not just `SERVICE_PATTERNS`).

## Pocket ID login

OAuth2 provider « Pocket ID » on PocketBase's `users` collection, entered by
hand in the hub's admin (`/_/`): Beszel does not take it from the
environment, and no role re-reads the secret (re-enter it after a rotation or
a hub restore). `USER_CREATION` stays unset (false): SSO creates no account,
it links the one whose e-mail matches a verified Pocket ID e-mail. Steps: [docs/runbooks/pocket-id.md](../../../docs/runbooks/pocket-id.md).

## API superuser

- Account `beszel_api_email` (`beszel-api@<beszel_domain>`), created or reset
  by `beszel superuser upsert` in the container whenever the hub refuses its
  login (first deploy, rebuilt hub, rotated hub key). Its password is
  `sha256(beszel_hub_private_key ~ ':beszel-api-superuser')` in hex (64
  characters, PocketBase takes up to 72): no SOPS key of its own, it follows
  the rotation of `beszel_hub_private_key`. Like Homepage's account, the
  password shows for an instant in the `docker exec` argument.
- **One manual step, once**: the hub only lets a superuser sign in from its
  « superuser IPs » (UI `/_/`, Settings, checked at login only). The role
  reaches the hub on `127.0.0.1:8090`, which the hub sees as the gateway of
  the `newt` network (`172.19.0.1`): add it next to the addresses already
  listed (Homepage's client address and the public one). LAN clients keep
  their own address, so this opens nothing to them. Without it the role stops
  at « Refuse an API superuser the hub does not open » (status 403) and every
  `docker.yml` deploy with it: check `docker network inspect newt` if the
  gateway ever changes.
- `beszel_admin_password` (SOPS) is now read only by the first start
  (`USER_PASSWORD` of the `.env`), kept because the `.env` and the guard of
  `tasks/main.yml` still need it; a changed or SSO-only password no longer
  breaks anything.
- Break glass: the superuser can be re-created by hand
  (`docker exec beszel /beszel superuser upsert <email> <password>`) or the
  role does it at the next run; the Beszel admin account itself is recovered
  from the PocketBase UI (`/_/`, as any superuser) or the Pocket ID runbook.
- `--check` on a hub where the account does not exist yet stops with a
  message: the creation needs a real run.
