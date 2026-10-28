#!/bin/sh
# Vérification locale de Blocky (rôle blocky, blocky-check.timer) : un nom qui
# doit résoudre, un nom que les listes téléchargées bloquent. Pousse up, ou
# down avec la raison, au moniteur push d'Uptime Kuma (BLOCKY_CHECK_PUSH_URL,
# vide : rien n'est poussé). Sort en erreur sur un échec, pour que l'unité le
# montre aussi (systemctl --failed).
set -u

address="$1"
resolved_name="$2"
blocked_name="$3"

query() {
  name="$1"
  dig +short +time=3 +tries=2 @"$address" "$name" A 2>&1
}

resolved=$(query "$resolved_name")
blocked=$(query "$blocked_name")

if ! printf '%s\n' "$resolved" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' \
  || printf '%s\n' "$resolved" | grep -qx '0\.0\.0\.0'; then
  status=down
  msg="$resolved_name ne résout pas sur $address : $(printf '%s' "$resolved" | head -c 200)"
elif ! printf '%s\n' "$blocked" | grep -qx '0\.0\.0\.0'; then
  status=down
  msg="$blocked_name n'est pas bloqué sur $address (listes non chargées ?) : $(printf '%s' "$blocked" | head -c 200)"
else
  status=up
  msg=OK
fi

echo "$status: $msg"

if [ -n "${BLOCKY_CHECK_PUSH_URL:-}" ]; then
  # L'URL (jeton du moniteur) par la configuration lue sur stdin, pas en
  # argument : /proc/<pid>/cmdline la montrerait.
  printf 'url = "%s"\n' "$BLOCKY_CHECK_PUSH_URL" \
    | curl -fsS -o /dev/null --max-time 10 --retry 3 --get --config - \
      --data-urlencode "status=$status" \
      --data-urlencode "msg=$msg" \
    || echo "push vers Uptime Kuma en échec" >&2
fi

[ "$status" = up ]
