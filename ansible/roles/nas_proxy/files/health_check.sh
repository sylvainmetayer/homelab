#!/bin/sh
# Santé des applis du NAS (rôle nas_proxy, nas-health-check.timer) : chaque
# appli interrogée par le Traefik du NAS, sur 127.0.0.1 au port publié, son
# nom en SNI et en Host, certificat vérifié contre le magasin du système.
# Pousse UN seul résultat au moniteur « Healthcheck NAS » : up si toutes les
# applis répondent, sinon down avec l'erreur de curl de chaque appli en échec.
# L'URL push : la configuration curl <dossier>/nas.curl (« url = "…" », 0600
# root) ; sans ce fichier, rien n'est poussé. Sort en erreur si une appli est
# en échec, pour que l'unité le montre aussi (systemctl --failed).
#
# Usage : health_check.sh <port> <dossier des .curl> <nom> <domaine> <chemin> [<nom> <domaine> <chemin>…]
set -u

if [ $# -lt 5 ] || [ $(( ($# - 2) % 3 )) -ne 0 ]; then
  echo "usage : health_check.sh <port> <dossier> <nom> <domaine> <chemin> [...]" >&2
  exit 2
fi

port="$1"
dir="$2"
shift 2
rc=0
fails=""

while [ $# -ge 3 ]; do
  name="$1"
  domain="$2"
  path="$3"
  shift 3

  # -q en tête : pas de ~/.curlrc. -f : un 5xx (Jellyfin « Unhealthy » en 503)
  # est un échec.
  if err=$(curl -q -fsS -o /dev/null --max-time 10 \
    --resolve "$domain:$port:127.0.0.1" "https://$domain:$port$path" 2>&1); then
    echo "$name up"
  else
    msg="$name https://$domain$path : $(printf '%s' "$err" | head -c 200)"
    echo "$name down: $msg"
    fails="${fails:+$fails ; }$msg"
    rc=1
  fi
done

if [ "$rc" -eq 0 ]; then
  status=up
  msg=OK
else
  status=down
  msg="$fails"
fi

# L'URL (jeton du moniteur) par le fichier, jamais en argument. uptime-push
# (rôle uptime_push) écrit l'échec d'un push sur stderr et sort en 0 : le
# code de sortie reste celui de la vérification. UPTIME_PUSH : posé par
# l'unité.
if [ -f "$dir/nas.curl" ]; then
  "${UPTIME_PUSH:-uptime-push}" --agent nas-health-check "$dir/nas.curl" "$status" "$msg"
fi

exit "$rc"
