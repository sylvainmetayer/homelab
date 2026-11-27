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
  - blocked: everything else. Whatever the app's environment says, no SMTP, webhook or third-party API gets out.
- **Pangolin's IP** comes from the inventory (`hostvars['pangolin'].ansible_host`). After a Pangolin rebuild with a new IP, rerun `--tags egress`.
- **To check it:** `sudo nft list table inet demo_egress`.

## Reset

`demo-planning-reset.timer` is a user unit of `sylvain`, like `dc@`. It fires every 30 min (`flip_planning_demo_reset_schedule`) and runs `{{ docker_base_path }}/demo_planning_reset/reset.sh`, which:

1. gets the reference dump:
   - `flip_planning_demo_dump_source: image` (the default) copies `flip_planning_demo_dump_image_path` out of the image of the running app, so the dump always matches the deployed version;
   - `url` downloads it once with Ansible, checked against `flip_planning_demo_dump_sha256`;
2. runs `docker compose stop app`;
3. restores the database in a single transaction:
   - `custom` format: `pg_restore --clean --if-exists --no-owner --role=festival`;
   - `plain` format: `psql -v ON_ERROR_STOP=1`;

   A failure leaves the database as it was.
4. runs `docker compose start app`, whether the restore succeeded or not. An `EXIT` trap also starts it when the script is killed (systemd `TimeoutStartSec`) after the stop, and removes the temporary container and dump.

The outage is about 20 s. Uptime Kuma's monitor (300 s interval, one retry at 60 s) tolerates it.

- **To run it by hand:** `systemctl --user start demo-planning-reset`.
- **To read what it did:** `journalctl --user -u demo-planning-reset`.

## Molecule

The `flip_planning_demo` scenario checks:
- that the filter unit is enabled, active and ordered before Docker;
- the rules that matter;
- that a reload leaves a single table;
- the syntax of the script;
- that the timer is enabled and active.

It runs no restore, since there is no instance in the scenario.
