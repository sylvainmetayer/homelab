#!/bin/sh
# Alerte « aucun abonné » de ntfy (rôle ntfy, ntfy-subscribers-check.timer).
# ntfy écrit chaque minute « INFO Server stats (…, subscribers=N, …) » ; le
# script relit les dernières minutes de son journal Docker et pousse up si
# un relevé y compte au moins un abonné, down sinon (zéro partout, aucune
# ligne, docker logs en échec), au moniteur push d'Uptime Kuma
# (NTFY_SUBSCRIBERS_CHECK_PUSH_URL ; vide : rien n'est poussé). Sort en
# erreur sur un down, pour que l'unité le montre aussi (systemctl --failed).
#
# Usage : ntfy-subscribers-check.sh <conteneur> <fenêtre en minutes>
# NTFY_SUBSCRIBERS_CHECK_DOCKER remplace docker (faux docker de Molecule).
set -u

container="$1"
window="$2"
docker="${NTFY_SUBSCRIBERS_CHECK_DOCKER:-docker}"

# ntfy journalise sur stderr.
if logs=$("$docker" logs --since "${window}m" "$container" 2>&1); then
  # Champs triés, « (clé=valeur, clé=valeur) » (log/event.go) : le
  # séparateur avant subscribers= écarte tout autre champ qui finirait ainsi.
  counts=$(printf '%s\n' "$logs" \
    | grep -F 'INFO Server stats (' \
    | grep -Eo '[(, ]subscribers=[0-9]+' \
    | cut -d= -f2)
  if [ -z "$counts" ]; then
    status=down
    msg="aucune ligne Server stats de $container sur ${window} min (ntfy arrêté ?)"
  else
    max=$(printf '%s\n' "$counts" | sort -n | tail -n 1)
    if [ "$max" -gt 0 ]; then
      status=up
      msg="jusqu'à $max abonné(s) sur ${window} min"
    else
      status=down
      msg="aucun abonné sur ${window} min : les téléphones ne reçoivent plus rien (abonnement refusé ?)"
    fi
  fi
else
  status=down
  msg="docker logs $container en échec : $(printf '%s' "$logs" | tail -n 1 | head -c 200)"
fi

echo "$status: $msg"

if [ -n "${NTFY_SUBSCRIBERS_CHECK_PUSH_URL:-}" ]; then
  # L'URL (jeton du moniteur) par la configuration lue sur stdin, pas en
  # argument : /proc/<pid>/cmdline la montrerait.
  printf 'url = "%s"\n' "$NTFY_SUBSCRIBERS_CHECK_PUSH_URL" \
    | curl -fsS -o /dev/null --max-time 10 --retry 3 --retry-connrefused --get --config - \
      --data-urlencode "status=$status" \
      --data-urlencode "msg=$msg" \
    || echo "push vers Uptime Kuma en échec" >&2
fi

[ "$status" = up ]
