#!/usr/bin/env bash
# Pose dans le miroir local implicite de tofu/pangolin_config
# (terraform.d/plugins), où `tofu init` les trouve sans configuration, les deux
# providers que le registre ne sait pas servir. linux_amd64 seulement.
# - Pangolin : build du fork, la source reste stackopshq/pangolin, l'état ne
#   change pas. ADR 0021. À retirer quand l'amont aura repris les correctifs.
# - Pocket ID : trozz/pocketid 2.5.0, dont l'amont a retiré releases et tags le
#   10/11/2026 (le registre liste encore la version, le zip répond 404). Le zip
#   servi ici est le paquet du cache de plugins d'avant le retrait, rezippé :
#   son SHA-256 n'est pas celui de l'amont, mais `tofu init` contrôle son
#   contenu contre les empreintes h1 du lockfile, inchangé. À retirer quand
#   l'amont republie (rm -rf terraform.d dans chaque checkout).
set -euo pipefail

root=$(git rev-parse --show-toplevel)
plugins="$root/tofu/pangolin_config/terraform.d/plugins/registry.opentofu.org"
# Un seul trap pour tous les appels de fetch : tmp, global, désigne le
# téléchargement en cours (déjà déplacé, rm -f n'y trouve rien).
tmp=""
trap 'rm -f "$tmp"' EXIT

# fetch <source du registre> <zip> <sha256> <URL>
fetch() {
  local mirror="$plugins/$1" target="$plugins/$1/$2"
  if ! echo "$3  $target" | sha256sum --check --status 2>/dev/null; then
    mkdir -p "$mirror"
    tmp=$(mktemp "$mirror/.download.XXXXXX")
    curl --proto '=https' --fail --silent --show-error --location --retry 3 --retry-all-errors --output "$tmp" "$4"
    echo "$3  $tmp" | sha256sum --check --quiet
    mv "$tmp" "$target"
  fi
}

version="1.7.0-sylvain.6"
sha256="764b6a4b4e77c444883f1c2237cf7188f60910330861fe8dec9f59d66384a154"
zip="terraform-provider-pangolin_${version}_linux_amd64.zip"
fetch stackopshq/pangolin "$zip" "$sha256" \
  "https://github.com/sylvainmetayer/terraform-provider-pangolin/releases/download/v$version/$zip"

pocketid_zip="terraform-provider-pocketid_2.5.0_linux_amd64.zip"
fetch trozz/pocketid "$pocketid_zip" e857bc067cf647d20380515b37d910ce2b4f5e4bb12760b3aef764f5334eaee4 \
  "https://github.com/sylvainmetayer/homelab/releases/download/provider-pocketid-2.5.0/$pocketid_zip"
