#!/usr/bin/env bash
# Pose dans le miroir local implicite de tofu/pangolin_config
# (terraform.d/plugins), où `tofu init` le trouve sans configuration, le
# provider Pangolin, que le registre ne sait pas servir. linux_amd64 seulement.
# Build du fork, la source reste stackopshq/pangolin, l'état ne change pas.
# ADR 0021. À retirer quand l'amont aura repris les correctifs.
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
