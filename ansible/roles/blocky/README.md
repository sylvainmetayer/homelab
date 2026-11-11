# blocky

Blocky filtre le DNS du réseau local ([ADR 0012](../../../docs/adr/0012-filtrage-dns-blocky.md)) :
listes HaGeZi (publicité, traqueurs, malveillants), résolveurs amont en
DNS-over-TLS (Quad9, Mullvad). Deux instances, que le DHCP de la Bbox annonce
toutes les deux. Procédure d'incident et bascule du DHCP :
[docs/runbooks/dns-blocky.md](../../../docs/runbooks/dns-blocky.md).

## Deux modes (`blocky_mode`)

| Mode | Hôte | Playbook | Forme |
|---|---|---|---|
| `dc` | Raspberry Pi (`192.168.1.96`) | `pi.yml` | conteneur sous `dc@blocky` |
| `binary` | LXC newt (`192.168.1.200`) | `lxc.yml` (à la main) | binaire et unité systemd, sans Docker |

Même version des deux côtés : l'image (`blocky_image`) et le binaire
(`blocky_binary_version` et ses sommes `blocky_binary_sha256`, qu'une montée de
version doit changer aussi) sont suivis par Renovate (groupe `blocky`).

## À savoir

- `blocky_lan_ip` : l'IP LAN où Blocky répond ; une IP privée, vérifiée par un
  `assert` (jamais de réponse sur une IP publique).
- **DNS rebinding** : une réponse amont qui pointe dans le LAN est vidée. Un nom
  public qui pointe volontairement sur une IP du LAN (les A de `tofu/dns` vers le
  NAS : `media`, `nas`, `mediamanager`, `prowlarr`, `qbittorrent`) doit être dans
  `blocky_rebinding_allowed_domains`, sinon il ne résout plus à la maison.
- **Noms locaux** : la Bbox sert `lan` et la zone inverse (`blocky_conditional_mapping`) ;
  les hôtes à IP fixe qu'elle ne nomme pas sont dans `blocky_custom_dns`.
- **Mémoire** : `blocky_mem_limit` 384m, `GOMEMLIMIT` 160 MiB (mesures dans
  `defaults/main.yml`).
- **Supervision** : `blocky-check.timer` interroge Blocky et pousse sur le
  moniteur « DNS … » d'Uptime Kuma (rôle `uptime_push`, dépendance dans
  `meta/main.yml`) ; `blocky_stats.py` journalise les compteurs de la carte
  Homepage.
- Débloquer un domaine : `blocky_allowlist` (Blocky n'a pas d'interface).
