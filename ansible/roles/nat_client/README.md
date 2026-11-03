# Role `nat_client`

Internet egress of a Hetzner server with no public IP: the default route and the DNS resolvers, neither of which the private network's DHCP provides. The other half is `nat_gateway` on Pangolin.

Part of `flip.yml` only (tags `nat,setup`; a merge changing the role deploys tag `nat` there), **first role of the play**: everything after it needs the Internet. So nothing in this role may depend on the Internet: no package, no download. A first deployment follows the order at the top of `flip.yml`.

- **`nat-client-watchdog.service`** runs a shell loop as root, every `nat_client_watchdog_interval` seconds (30): it restores the default route via `nat_client_gateway` when it is missing, and speaks in the journal only when it repairs. A loop rather than a timer, which would log a unit start each minute; and rather than a config of the image's network stack, because a `systemd-networkd` restart removes a route it did not set and a lease renewal rewrites `/etc/resolv.conf`. IPv4 only.
- **DNS has two branches**, chosen at play time by what `/etc/resolv.conf` is, and rendered into the script:
  - a symlink into `/run/systemd/resolve/`: a `resolved.conf.d/50-nat.conf` drop-in, and the watchdog leaves the file alone;
  - anything else: reference `/etc/nat-client/resolv.conf`, which the watchdog copies over `/etc/resolv.conf` on any difference. A hand edit of `/etc/resolv.conf` lasts one interval at most.
- The last task fails the role after 5 retries if `getent ahostsv4 deb.debian.org` does not answer, rather than letting a later apt or `docker pull` time out unexplained. The resolvers being public, an answer also proves the route through the NAT.

## Variables

- `nat_client_gateway` (`10.0.0.1`): the Hetzner network's gateway, first address of `hcloud_network.main`, which applies `hcloud_network_route.nat`. **Not Pangolin's IP.** `tofu/pangolin/tests/pangolin.tftest.hcl` pins it to the network range.
- `nat_client_dns_servers`: Hetzner's recursive resolvers, reached through the NAT like the rest.

## Non-obvious or dangerous

- The role never removes anything: there is no off switch, and stopping the watchdog only means the next route or DNS loss is not repaired.
- Never run the play through `flip.internal` (served by flip's own Newt, itself going out through this NAT): `docs/conventions/ansible.md`.
- **Uncertain**: which DNS branch flip is on today is not recorded in the repo. `ls -l /etc/resolv.conf` on flip tells.

## Testing

`mise run molecule nat_client`: a dummy `enp7s0` plays the private network, so the watchdog really sets the route, and `/etc/resolv.conf` is a plain file (reference branch; the verify only checks that the resolved drop-in is absent, the resolved branch does not run). `deb.debian.org` resolves through `/etc/hosts`, so **the way out through the NAT is only proven on flip**: the commands of `docs/runbooks/flip-injoignable.md`.

## Pointers

Incident: `docs/runbooks/flip-injoignable.md`. Decision and accepted risk: `docs/adr/0019-flip-sans-ipv4-publique.md`. Route: `tofu/pangolin/nat.tf`.
