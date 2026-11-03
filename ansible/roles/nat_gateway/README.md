# Role `nat_gateway`

NAT gateway of the Hetzner private network, for the servers with no public IP (flip): `hcloud_network_route.nat` (`tofu/pangolin/nat.tf`) sends the network's traffic to Pangolin, and this role forwards and masquerades it on the public interface. The other half is `nat_client` on flip.

Part of `pangolin.yaml` only (tag `nat`, deployed by a merge changing the role), **after `security`**: the forwarding rule is an ufw rule. The role entry has no `become`: the tasks that need it ask for it.

- **Interfaces are read from the routes**, since their names depend on the server type: public from the default route, private from `ip route get <nat_gateway_private_network_gateway>`. The role fails when both are the same (server not attached to the private network, or wrong gateway address).
- **`net.ipv4.ip_forward`** in `/etc/sysctl.d/90-nat-gateway.conf`: Docker already turns it on, but as a side effect, and flip's egress should not depend on that. `security_devsec_sysctl_overwrite` (role `security`) keeps it at 1 as well: devsec's default of 0 would cut this on its reload.
- **ufw route rule** from `nat_gateway_source_cidr`, private to public interface: the FORWARD policy is DROP. Return traffic is covered by the RELATED,ESTABLISHED rule of ufw's `before.rules`.
- **`nat-gateway.service`** (oneshot, `RemainAfterExit`) adds the MASQUERADE rule if missing. Not in `/etc/ufw/before.rules`: ufw would load it again on each `ufw reload`, since its nat table is never flushed, and flushing it would take Docker's rules along.

## Variables

`nat_gateway_source_cidr` (`10.0.0.0/16`) and `nat_gateway_private_network_gateway` (`10.0.0.1`) must match `hcloud_network.main`; `tofu/pangolin/tests/pangolin.tftest.hcl` greps this role's defaults for both.

## Non-obvious or dangerous

- **Restarting the unit cuts flip's egress** between `stop` (ExecStop removes the rule) and `start`. The handler runs `daemon-reload` between the two on purpose: stop must read the old parameters from the loaded unit, or the old rule stays. The unit is rendered with the interface name, so it needs a new play if that name changes.
- **Nothing watches the rule**: `RemainAfterExit` keeps the unit active even if the rule has disappeared (unlike the `nat_client` side, there is no loop). `iptables -t nat -S POSTROUTING` tells; `systemctl restart nat-gateway` puts it back.
- The role only adds: no off switch, and a changed CIDR or interface leaves the previous ufw rule behind (no task removes it).
- Rehearsing a Pangolin rebuild on a server not attached to the private network: the role fails by design, use `--skip-tags nat` (`docs/runbooks/reconstruction-pangolin.md`).

## Testing

`mise run molecule nat_gateway`: `security` then this role, a dummy `enp7s0` as the private interface. It checks forwarding (live and persisted), the ufw rule, the unit, the MASQUERADE rule present exactly once and removed by a stop. No real traffic goes through: real egress is checked from flip, `docs/runbooks/flip-injoignable.md`.

## Pointers

Incident: `docs/runbooks/flip-injoignable.md`, `docs/runbooks/pangolin-injoignable.md`. Rebuild: `docs/runbooks/reconstruction-pangolin.md`. Decision: `docs/adr/0019-flip-sans-ipv4-publique.md`.
