#!/bin/sh
# Faux docker du scénario mem_report : `ps --quiet --no-trunc` et `inspect
# --format …`, lus dans le fichier de fixtures du verify (une ligne par
# conteneur, au format INSPECT_FORMAT de mem_report.py).
set -eu
fixture="${FAKE_DOCKER_FIXTURE:?}"
case "$1" in
  ps) cut -f1 "$fixture" ;;
  inspect) cat "$fixture" ;;
  *) echo "fake docker: $1 non simulé" >&2; exit 1 ;;
esac
