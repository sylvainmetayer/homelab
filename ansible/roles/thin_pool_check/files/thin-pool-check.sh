#!/bin/sh
# Remplissage des thin pools LVM de l'hôte (rôle thin_pool_check). Pousse up
# avec les pourcentages, ou down si les données ou les métadonnées d'un pool
# dépassent le seuil, si lvs échoue ou ne trouve aucun pool (silence ≠ santé),
# au moniteur push d'Uptime Kuma (THIN_POOL_CHECK_PUSH_URL ; vide : rien n'est
# poussé). Sort en erreur sur un down, pour que l'unité le montre aussi.
#
# Usage : thin-pool-check.sh <seuil en %>
# THIN_POOL_CHECK_LVS remplace lvs (faux lvs de test).
set -u

threshold="$1"
lvs="${THIN_POOL_CHECK_LVS:-lvs}"
# stderr à part : un WARNING de lvs n'est pas une ligne de pool.
err=$(mktemp)
trap 'rm -f "$err"' EXIT

# LC_ALL=C : point décimal. Une ligne par pool : « vg pool données métadonnées ».
if pools=$(LC_ALL=C "$lvs" --noheadings --separator ' ' \
    -o vg_name,lv_name,data_percent,metadata_percent \
    -S 'lv_layout=thin && lv_layout=pool' 2>"$err") && [ -n "$pools" ]; then
  status=up
  msg=$(printf '%s\n' "$pools" | awk -v t="$threshold" '
    { d = $3 + 0; m = $4 + 0
      line = sprintf("%s/%s données %.1f %%, métadonnées %.1f %%", $1, $2, d, m)
      if (d >= t || m >= t) { line = line " (seuil " t " %)"; bad = 1 }
      out = out (out == "" ? "" : "; ") line }
    END { print (bad ? "down " : "up ") out }')
  status=${msg%% *}
  msg=${msg#* }
else
  status=down
  msg="lvs en échec ou aucun thin pool : $(tail -n 1 "$err" | head -c 200)"
fi

echo "$status: $msg"

if [ -n "${THIN_POOL_CHECK_PUSH_URL:-}" ]; then
  # L'URL (jeton du moniteur) par la configuration curl lue sur stdin, pas en
  # argument (voir ansible/roles/uptime_push/README.md).
  printf 'url = "%s"\n' "$THIN_POOL_CHECK_PUSH_URL" \
    | "${UPTIME_PUSH:-uptime-push}" --agent thin-pool-check - "$status" "$msg"
fi

[ "$status" = up ]
