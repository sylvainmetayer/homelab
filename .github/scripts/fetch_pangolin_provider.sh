#!/usr/bin/env bash
# Pose le provider Pangolin du fork dans le miroir local implicite de
# tofu/pangolin_config (terraform.d/plugins), où `tofu init` le trouve sans
# configuration : la source reste stackopshq/pangolin, l'état ne change pas.
# ADR 0021. À retirer quand l'amont aura repris les correctifs.
set -euo pipefail

version="1.7.0-sylvain.1"
sha256="338ffb42cc8f3a6208e70a469c3f28afbd9099791741142725813027e6b8f77f"

root=$(git rev-parse --show-toplevel)
zip="terraform-provider-pangolin_${version}_linux_amd64.zip"
mirror="$root/tofu/pangolin_config/terraform.d/plugins/registry.opentofu.org/stackopshq/pangolin"
target="$mirror/$zip"

if ! echo "$sha256  $target" | sha256sum --check --status 2>/dev/null; then
  mkdir -p "$mirror"
  tmp=$(mktemp "$mirror/.download.XXXXXX")
  trap 'rm -f "$tmp"' EXIT
  curl --fail --silent --show-error --location --retry 3 --output "$tmp" \
    "https://github.com/sylvainmetayer/terraform-provider-pangolin/releases/download/v$version/$zip"
  echo "$sha256  $tmp" | sha256sum --check --status
  mv "$tmp" "$target"
fi
