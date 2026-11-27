# Role `flip_planning_demo`

The host side of the public Flip Planning demo (`ansible/demo-planning.yml`, ADR 0038). The instance itself is the `flip_planning` role. This role is applied twice: once before Docker for the egress filter, once after the instance for the reset timer.

## Egress filter

- **Where:** the nftables table `inet demo_egress`, file `/etc/demo-egress.nft`, loaded by `demo-egress.service` before `docker.service`.
- **Ordering:** the unit is `After=nftables.service`: Debian's `nftables.service` starts with `flush ruleset` and would wipe the filter if it ran later.
- **Why its own table:** it is replaced in one block (`delete table` then the definition), so Docker's and ufw's tables are never touched. That is also why it is never loaded by `nftables.service`: Debian's `/etc/nftables.conf` starts with `flush ruleset`.
- **Host (output chain):**
  - allowed: DNS, NTP, HTTP(S), for apt and the images;
  - blocked: the private network. The SSH replies to the bastion are `established`.
- **Containers (forward chain):**
  - allowed: the Docker bridges, the DNS resolvers `flip_planning_demo_dns_servers` (Docker's embedded DNS queries from the container's namespace, so Newt could not resolve Pangolin without them), and Pangolin's public IP on TCP 443 and on gerbil's UDP ports. That is what Newt uses.
  - containers, HTTPS to `flip_planning_demo_https_hosts` (Bugsink, for the demo's errors), resolved to IPv4 on the host at each `--tags egress` run: a changed IP loses the events until the next run;
  - blocked: everything else. Whatever the app's environment says, no SMTP, webhook or third-party API gets out.
- **Pangolin's IP** comes from the inventory (`hostvars['pangolin'].ansible_host`). After a Pangolin rebuild with a new IP, rerun `--tags egress`.
- **To check it:** `sudo nft list table inet demo_egress`.

## Reset

`demo-planning-reset.timer` is a user unit of `sylvain`, like `dc@`. It fires every 30 min (`flip_planning_demo_reset_schedule`) and runs `{{ docker_base_path }}/demo_planning_reset/reset.sh`, which:

1. runs `docker compose stop app`;
2. drops and recreates the database (`dropdb --force`, `createdb -O festival`), then restores `reference.dump` into it (`pg_restore --no-owner --role=festival --exit-on-error`): the application's own procedure (`site/src/docs/installer/instance-de-demo.md`); a `pg_restore --clean` would keep a table a newer version added, and the next migration would fail;
3. recreates the app container (`docker compose up --detach --force-recreate --no-deps app`), whether the restore succeeded or not, so its logs never cover more than half an hour. An `EXIT` trap does it too when the script is killed (systemd `TimeoutStartSec`) after the stop.

A missing dump makes the script fail before stopping anything.

The outage is about 20 s. Uptime Kuma's monitor (300 s interval, one retry at 60 s) tolerates it.

- **To run it by hand:** `systemctl --user start demo-planning-reset`.
- **To read what it did:** `journalctl --user -u demo-planning-reset`.

### The reference dump

Made once on the host by the application's `scripts/demo/generer-dump.sh` (a throwaway stack: PostgreSQL, Mailpit, the app; the showcase scenario, a solve, the published plan, the three local accounts `rh@`, `responsable@`, `lecteur@example.org`, and the fixed animateur space `/animateur/00000000-0000-4000-8000-0000000de305`). Neither in the image nor in this repo. Redo it when the showcase scenario changes; a dump made by an older version stays valid (the app migrates it at start-up).

```bash
sudo apt-get install -y jq
git clone --depth 1 --branch v4.2.1 https://github.com/sylvainmetayer/planning-equipes.git /tmp/pe
read -rs DEMO_PASSWORD && export DEMO_PASSWORD   # the password shown on /demo, 12 characters at least
APP_IMAGE=ghcr.io/sylvainmetayer/planning-equipes:4.2.1 POSTGRES_IMAGE=postgres:19.0 \
  /tmp/pe/scripts/demo/generer-dump.sh /opt/apps/demo_planning_reset/reference.dump
unset DEMO_PASSWORD; rm -rf /tmp/pe
systemctl --user start demo-planning-reset
```

Take the tag of the deployed image (`flip_planning_image_release`) and the PostgreSQL major of the role's `compose.yaml`. The password never goes into the repo nor into a variable of the playbook: it lives only in the dump, as a hash.

## Visitor cap

A Traefik of its own (`dc@demo_planning_proxy`, file provider only, no Docker socket, no access log) sits between newt and the app: the Pangolin target of the demo is `demo-planning-proxy:8080`. Load test of 2026-11-27 (2 vCPU, 4 GB, app at 2 GB): about 20 visitors hold (p95 < 1.5 s), a peak of 60 arrivals in one minute kills the app (OOM).

- `inFlightReq` with `sourceCriterion.requestHost`: one counter for the whole demo, `flip_planning_demo_proxy_max_in_flight` (30) requests in flight. Past it, `errors` answers 429 with the static page `demo-saturee.html.j2` (served by its own nginx, it reloads itself every 60 s).
- `/api/jobs/stream` (the solver's SSE stream, open as long as the screen is) has its own router outside the cap: counted in it, a handful of open screens would block everyone.
- Uptime Kuma goes through Pangolin, so a saturated demo shows as down (429) for the time it lasts.
- **To change the cap:** `flip_planning_demo_proxy_max_in_flight`, then `--tags proxy`.

## Warm-up

After recreating the app, `reset.sh` waits for it to be healthy, then signs in as `admin` (the password shown on the demo, `flip_planning_demo_warmup_password`) and reads the home page and `/api/planning/persisted` `flip_planning_demo_warmup_rounds` (5) times, straight to the container (host to Docker bridge, allowed by the egress filter). A failed warm-up is logged and does not fail the reset.

## Molecule

The `flip_planning_demo` scenario checks:
- that the filter unit is enabled, active and ordered before Docker;
- the rules that matter;
- that a reload leaves a single table;
- the syntax of the script;
- that the timer is enabled and active.

It runs no restore, since there is no instance in the scenario.
