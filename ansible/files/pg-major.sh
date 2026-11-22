#!/bin/sh
# Migration d'une base PostgreSQL d'une majeure à la suivante par export/réimport.
# Les images postgres >= 18 rangent les données sous /var/lib/postgresql/<majeure>/docker :
# la nouvelle majeure initialise sa grappe à côté de l'ancienne, qui reste intacte (retour arrière).
#
# usage: pg-major.sh prepare <conteneur_db> <dossier_de_travail>
#          exporte la base (pg_dumpall) et l'empreinte des tables, conteneur en marche
#        pg-major.sh restore <conteneur_db> <dossier_de_travail> <image_nouvelle>
#          conteneur ARRÊTÉ : démarre la nouvelle image sur les mêmes montages, réimporte, compare
# shortcut: une seule grappe par conteneur, rôle et base de POSTGRES_USER/POSTGRES_DB ;
#           à revoir pour une base avec des tablespaces ou plusieurs super-utilisateurs.
set -eu
D=${DOCKER:-docker}
mode=$1; db=$2; work=$3
umask 077
mkdir -p "$work"

envof() { $D inspect -f '{{range .Config.Env}}{{println .}}{{end}}' "$db" | grep -E '^(POSTGRES_USER|POSTGRES_DB|POSTGRES_PASSWORD|TZ)=' ; }
val() { envof | sed -n "s/^$1=//p"; }

# Une ligne « base schema.table lignes » par table utilisateur, comptage exact.
fingerprint() { # $1 = conteneur
  u=$(val POSTGRES_USER)
  for b in $($D exec "$1" psql -U "$u" -d postgres -Atc "select datname from pg_database where not datistemplate order by 1"); do
    $D exec "$1" psql -U "$u" -d "$b" -Atc "select '$b '||table_schema||'.'||table_name||' '||(xpath('/row/c/text()', query_to_xml(format('select count(*) as c from %I.%I', table_schema, table_name), false, true, '')))[1]::text from information_schema.tables where table_type='BASE TABLE' and table_schema not in ('pg_catalog','information_schema') order by 1"
  done
}

case "$mode" in
prepare)
  u=$(val POSTGRES_USER)
  $D exec "$db" pg_dumpall -U "$u" > "$work/dumpall.sql"
  tail -n 5 "$work/dumpall.sql" | grep -q 'PostgreSQL database cluster dump complete' || { echo "KO: export incomplet"; exit 1; }
  fingerprint "$db" > "$work/before.txt"
  $D exec "$db" psql -U "$u" -d postgres -Atc "show server_version" > "$work/version-before.txt"
  echo "OK prepare: $(wc -c < "$work/dumpall.sql") octets, $(wc -l < "$work/before.txt") tables, version $(cat "$work/version-before.txt")"
  ;;
restore)
  image=$4
  [ -s "$work/dumpall.sql" ] && [ -s "$work/before.txt" ] || { echo "KO: pas d'export dans $work"; exit 1; }
  [ "$($D inspect -f '{{.State.Running}}' "$db")" = false ] || { echo "KO: $db tourne encore, l'arrêter d'abord"; exit 1; }
  tmp="pgmajor-$db"
  envof > "$work/env"
  # Mêmes montages que le conteneur d'origine (bind ou volume nommé), sans réseau.
  mounts=$($D inspect -f '{{range .Mounts}}{{if eq .Type "volume"}}-v {{.Name}}:{{.Destination}} {{else}}-v {{.Source}}:{{.Destination}} {{end}}{{end}}' "$db")
  $D rm -f "$tmp" >/dev/null 2>&1 || true
  # L'image refuse d'initialiser une grappe tant qu'elle voit celle d'une autre
  # majeure sous /var/lib/postgresql/*/docker : l'ancienne est mise de côté sous
  # <majeure>/docker.avant-migration (retour arrière : la renommer en docker).
  # shellcheck disable=SC2086,SC2016
  $D run --rm --network none $mounts --entrypoint sh "$image" -c '
    [ ! -e "$PGDATA" ] || { echo "KO: $PGDATA existe déjà"; exit 1; }
    for d in /var/lib/postgresql/*/docker; do
      [ -s "$d/PG_VERSION" ] && mv "$d" "$d.avant-migration"
    done; ls -d /var/lib/postgresql/*/docker.avant-migration'
  # shellcheck disable=SC2086
  $D run -d --name "$tmp" --network none --env-file "$work/env" $mounts "$image" >/dev/null
  rm -f "$work/env"
  u=$(val POSTGRES_USER)
  i=0; until $D exec "$tmp" psql -U "$u" -d postgres -Atc 'select 1' >/dev/null 2>&1; do i=$((i+1)); [ $i -lt 90 ] || { echo "KO: la nouvelle grappe ne démarre pas"; $D logs --tail 20 "$tmp"; exit 1; }; sleep 2; done
  sleep 3 # l'image redémarre postgres une fois après l'initialisation
  until $D exec "$tmp" psql -U "$u" -d postgres -Atc 'select 1' >/dev/null 2>&1; do sleep 2; done
  $D exec -i "$tmp" psql -U "$u" -d postgres -v ON_ERROR_STOP=0 < "$work/dumpall.sql" > "$work/restore.log" 2>&1 || true
  # Erreurs attendues : le rôle et la base de POSTGRES_USER/POSTGRES_DB existent déjà.
  grep -E '^(psql:.*)?(ERROR|FATAL)' "$work/restore.log" | grep -v -E 'already exists|current user cannot be dropped' > "$work/restore-errors.txt" || true
  dbs=$(val POSTGRES_DB)
  # fingerprint() lit l'env du conteneur d'origine, il suffit de viser le temporaire.
  fingerprint "$tmp" > "$work/after.txt"
  $D exec "$tmp" psql -U "$u" -d postgres -Atc "show server_version" > "$work/version-after.txt"
  $D stop -t 60 "$tmp" >/dev/null; $D rm "$tmp" >/dev/null
  if cmp -s "$work/before.txt" "$work/after.txt" && [ ! -s "$work/restore-errors.txt" ]; then
    echo "OK restore: version $(cat "$work/version-after.txt"), $(wc -l < "$work/after.txt") tables identiques (base $dbs)"
  else
    echo "KO restore: version $(cat "$work/version-after.txt")"
    echo "erreurs inattendues: $(wc -l < "$work/restore-errors.txt")"; head -5 "$work/restore-errors.txt"
    diff "$work/before.txt" "$work/after.txt" | head -10
    exit 1
  fi
  ;;
*) echo "mode inconnu"; exit 2 ;;
esac
