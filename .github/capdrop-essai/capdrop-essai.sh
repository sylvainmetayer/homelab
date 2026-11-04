#!/usr/bin/env bash
# Essai des capacités de rss et dawarich-app sur images jetables, données fictives.
# ENGINE=docker (rootful, CI) ou ENGINE=podman (rootless, USERNS=--userns=keep-id).
# Usage : capdrop-essai.sh rss|dawarich [jeu de capacités séparées par des virgules]...
set -u
ENGINE="${ENGINE:-docker}"; USERNS="${USERNS:-}"; VOPT="${VOPT:-}"
FR=docker.io/freshrss/freshrss:1.30.4@sha256:af44385229541bee24aa9148d0ff8f3b40e095373c63a2c0f74e09a27d3c59df
DW=docker.io/freikin/dawarich:1.19.0@sha256:d9385242202ae385a5d8064f41a59a0b58218399e60e7e499d2a6afb449bc304
DB=docker.io/postgis/postgis:17-3.5-alpine@sha256:894f570c0cf0664ed5576a8fd5d5bfb8fb1b19d592885b686c3a88c8bd90c41f
RD=docker.io/redis:8.2-alpine@sha256:489a769e0a54dc245896132a15c72d2bc7296719954da99398f43a3877e5f8eb
WORK="${WORK:-$(mktemp -d)}"; NET=capdrop-essai
e() { "$ENGINE" "$@"; }
caps_args() { # $1: liste ; "defaut" = pas de cap_drop
  [ "$1" = defaut ] && return
  printf -- '--cap-drop ALL '
  [ "$1" = aucune ] && return
  local c; for c in ${1//,/ }; do printf -- '--cap-add %s ' "$c"; done
}
status() { # conteneur : identité et capacités de chaque processus
  e exec "$1" sh -c 'for p in /proc/[0-9]*; do n=$(tr "\0" " " <$p/cmdline 2>/dev/null | cut -c1-50); [ -n "$n" ] || continue; echo "  ${p#/proc/} uid=$(awk "/^Uid/{print \$2}" $p/status) eff=$(awk "/^CapEff/{print \$2}" $p/status) bnd=$(awk "/^CapBnd/{print \$2}" $p/status) nnp=$(awk "/^NoNewPrivs/{print \$2}" $p/status) $n"; done' 2>&1
}

rss_seed() {
  mkdir -p "$WORK/rss/data" "$WORK/rss/ext/xExtension-Fake"
  echo fictif > "$WORK/rss/ext/xExtension-Fake/fictif.txt"
  e rm -f rss-seed >/dev/null 2>&1
  e run -d --name rss-seed $USERNS -e CRON_MIN= -v "$WORK/rss/data:/var/www/FreshRSS/data$VOPT" -v "$WORK/rss/ext:/var/www/FreshRSS/extensions$VOPT" "$FR" >/dev/null
  sleep 8
  # Comme la production : installé par l'interface, donc fichiers de www-data ;
  # dossiers de prepare.php à root:www-data ; extensions root:www-data 0750 (rôle).
  e exec rss-seed sh -c '
    chown root:www-data data data/* 2>/dev/null; chown -R root:www-data extensions; chmod 0750 extensions extensions/*
    su www-data -s /bin/sh -c "php cli/do-install.php --default-user fictif --auth-type none --environment production --base-url http://localhost --language fr --title essai --db-type sqlite; php cli/create-user.php --user fictif --language fr; php cli/actualize-user.php --user fictif"
    chmod 0770 data/users/fictif; ls -lan data data/users data/users/fictif | head -40'
  e stop -t 5 rss-seed >/dev/null; e rm -f rss-seed >/dev/null
}

rss_try() { # $1 jeu de capacités
  local caps="$1" c=rss-try t0 t1
  echo; echo "########## rss : $caps"
  e rm -f $c >/dev/null 2>&1
  # shellcheck disable=SC2046
  if ! e run -d --name $c $USERNS ${EXTRA:-} --security-opt no-new-privileges $(caps_args "$caps") -e TZ=Europe/Paris -e FRESHRSS_ENV=production -e 'CRON_MIN=*' \
    -v "$WORK/rss/data:/var/www/FreshRSS/data$VOPT" -v "$WORK/rss/ext:/var/www/FreshRSS/extensions$VOPT" "$FR" >/dev/null; then echo "RESULTAT $caps : run refusé"; return; fi
  sleep 10
  if [ "$(e inspect -f '{{.State.Running}}' $c)" != true ]; then
    echo "RESULTAT rss $caps : ARRET exit=$(e inspect -f '{{.State.ExitCode}}' $c)"; e logs --tail 15 $c 2>&1 | cut -c1-200; e rm -f $c >/dev/null; return; fi
  status $c
  echo "-- sonde"; e exec $c /var/www/FreshRSS/cli/health.php; echo "health rc=$?"
  echo "-- http : $(e exec $c php -r 'foreach (["/i/","/api/","/"] as $u) { $h=curl_init("http://localhost".$u); curl_setopt($h,CURLOPT_RETURNTRANSFER,true); curl_exec($h); echo $u,"=",curl_getinfo($h,CURLINFO_HTTP_CODE)," "; }')"
  echo "-- port 80 : ip_unprivileged_port_start=$(e exec $c cat /proc/sys/net/ipv4/ip_unprivileged_port_start)"
  echo "-- www-data écrit : $(e exec $c su www-data -s /bin/sh -c 'touch data/users/fictif/.t && echo ok && rm data/users/fictif/.t' 2>&1)"
  echo "-- attente du cron (65 s)"; sleep 65
  echo "-- cron log : $(e exec $c sh -c 'ls -la /tmp/FreshRSS.log; tail -c 300 /tmp/FreshRSS.log' 2>&1)"
  echo "-- db modifiée : $(e exec $c sh -c 'ls -lan --time-style=full-iso data/users/fictif/log.txt; date' 2>&1 | tr '\n' ' ')"
  t0=$(date +%s); e stop -t 15 $c >/dev/null; t1=$(date +%s)
  echo "-- arrêt : $((t1-t0)) s, exit=$(e inspect -f '{{.State.ExitCode}}' $c)"
  echo "-- journal, erreurs :"; e logs $c 2>&1 | grep -iE 'denied|not permitted|could not|⚠|❌|\[.*(emerg|alert|crit|error)\]|setuid|setgid|PAM|fail' | cut -c1-200 | sort | uniq -c | sort -rn | head -12
  # Redémarrage du même conteneur (entrypoint rejoué)
  e start $c >/dev/null; sleep 6; echo "-- après restart : running=$(e inspect -f '{{.State.Running}}' $c) health=$(e exec $c /var/www/FreshRSS/cli/health.php >/dev/null 2>&1; echo $?)"
  e rm -f $c >/dev/null
  echo "RESULTAT rss $caps : fin"
}

dw_seed() {
  mkdir -p "$WORK/dw/public" "$WORK/dw/watched/demo@dawarich.app" "$WORK/dw/storage"
  cat > "$WORK/dw/watched/demo@dawarich.app/fictif.gpx" <<'G'
<?xml version="1.0"?><gpx version="1.1" creator="essai" xmlns="http://www.topografix.com/GPX/1/1"><trk><trkseg><trkpt lat="0.1" lon="0.1"><time>2020-01-01T00:00:00Z</time></trkpt><trkpt lat="0.2" lon="0.2"><time>2020-01-01T00:10:00Z</time></trkpt></trkseg></trk></gpx>
G
  # Dossiers à 1000:1000 en 0700 comme le rôle.
  e run --rm $USERNS --entrypoint sh -v "$WORK/dw:/d$VOPT" "$DW" -c 'chown -R 1000:1000 /d/public /d/watched /d/storage; chmod -R go-rwx /d/public /d/watched /d/storage; chmod 0700 /d/public /d/watched /d/storage; ls -lan /d'
  echo "-- contrôle : root sans capacité ne doit pas traverser le 0700"
  e run --rm $USERNS --cap-drop ALL --entrypoint ls -v "$WORK/dw/watched:/w$VOPT" "$DW" /w; echo "rc=$? (attendu : non nul)"
  e network create $NET >/dev/null 2>&1
  DBPW=$(openssl rand -hex 16)
  e rm -f dawarich-db dawarich-redis >/dev/null 2>&1
  e run -d --name dawarich-db --network $NET -e POSTGRES_DB=dawarich -e POSTGRES_USER=dawarich -e POSTGRES_PASSWORD="$DBPW" "$DB" >/dev/null
  e run -d --name dawarich-redis --network $NET "$RD" redis-server --save 3600 1 --appendonly no >/dev/null
  { echo RAILS_ENV=production; echo REDIS_URL=redis://dawarich-redis:6379; echo DATABASE_HOST=dawarich-db; echo DATABASE_PORT=5432
    echo DATABASE_NAME=dawarich; echo DATABASE_USERNAME=dawarich; echo "DATABASE_PASSWORD=$DBPW"
    for k in JWT_SECRET_KEY AUTH_JWT_SECRET_KEY SECRET_KEY_BASE; do echo "$k=$(openssl rand -hex 32)"; done
    echo APPLICATION_HOSTS=localhost,127.0.0.1; echo APPLICATION_PROTOCOL=http; echo TIME_ZONE=Europe/Paris; echo PROMETHEUS_EXPORTER_ENABLED=false
    echo RAILS_LOG_TO_STDOUT=true; echo SELF_HOSTED=true; echo STORE_GEODATA=false; echo SIDEKIQ_EMBEDDED=true; echo WEB_CONCURRENCY=0; echo BACKGROUND_PROCESSING_CONCURRENCY=2
    echo DOMAIN=localhost; } > "$WORK/dw/.env"
  sleep 15
}

dw_try() {
  local caps="$1" c=dawarich-app i ok=
  echo; echo "########## dawarich-app : $caps"
  e rm -f $c >/dev/null 2>&1
  # shellcheck disable=SC2046
  e run -d -t --name $c $USERNS --network $NET --security-opt no-new-privileges $(caps_args "$caps") --entrypoint web-entrypoint.sh --env-file "$WORK/dw/.env" -e PUID=1000 -e PGID=1000 \
    -v "$WORK/dw/public:/var/app/public$VOPT" -v "$WORK/dw/watched:/var/app/tmp/imports/watched$VOPT" -v "$WORK/dw/storage:/var/app/storage$VOPT" "$DW" bin/rails server -p 3000 -b :: >/dev/null || { echo "RESULTAT $caps : run refusé"; return; }
  for i in $(seq 1 60); do
    [ "$(e inspect -f '{{.State.Running}}' $c)" = true ] || break
    if e exec $c sh -c "wget -qO - http://127.0.0.1:3000/api/v1/health | grep -q '\"status\"\\s*:\\s*\"ok\"'" 2>/dev/null; then ok=1; break; fi
    sleep 5
  done
  if [ -z "$ok" ]; then
    echo "RESULTAT dawarich $caps : ÉCHEC running=$(e inspect -f '{{.State.Running}}' $c) exit=$(e inspect -f '{{.State.ExitCode}}' $c)"; e logs --tail 12 $c 2>&1 | cut -c1-200; e rm -f $c >/dev/null; return
  fi
  status $c
  echo "-- propriétaires : $(e exec -u 1000:1000 $c sh -c 'stat -c "%n %u:%g %a" tmp db log public storage tmp/imports/watched 2>&1 | tr "\n" ";"')"
  echo "-- import du dossier surveillé (uid 1000) :"
  e exec -u 1000:1000 $c bundle exec rails runner 'puts "users=#{User.count} imports=#{Import.count}"; Imports::Watcher.new.call; puts "apres=#{Import.count}"' 2>&1 | tail -4 | cut -c1-200
  echo "-- écriture : $(e exec -u 1000:1000 $c sh -c 'touch storage/.t tmp/imports/watched/.t public/.t && rm storage/.t tmp/imports/watched/.t public/.t && echo ok' 2>&1)"
  echo "-- journal, refus : "; e logs $c 2>&1 | grep -iE 'denied|not permitted|EACCES|EPERM' | cut -c1-200 | sort | uniq -c | head -8
  e restart -t 20 $c >/dev/null
  ok=; for i in $(seq 1 40); do e exec $c sh -c "wget -qO - http://127.0.0.1:3000/api/v1/health | grep -q ok" 2>/dev/null && { ok=1; break; }; sleep 5; done
  echo "-- après restart du même conteneur : ok=$ok"
  local t0 t1; t0=$(date +%s); e stop -t 60 $c >/dev/null; t1=$(date +%s); echo "-- arrêt : $((t1-t0)) s, exit=$(e inspect -f '{{.State.ExitCode}}' $c)"
  e rm -f $c >/dev/null
  echo "RESULTAT dawarich $caps : OK"
}

what="$1"; shift
# open_by_handle_at (304 sur x86_64) : EPERM = refusé (seccomp ou capacité) ;
# autre erreur (EBADF sur ce fd -1) = l'appel atteint le noyau, voie de Shocker.
for s in defaut aucune DAC_OVERRIDE DAC_READ_SEARCH; do
  # shellcheck disable=SC2046
  echo "SONDE open_by_handle_at $s : $(e run --rm $USERNS $(caps_args "$s") --entrypoint ruby "$DW" -e 'begin; syscall(304, -1, 0, 0); rescue SystemCallError => x; puts x.class; end' 2>&1 | tail -1)"
done
case "$what" in
  rss) rss_seed; for s in "$@"; do rss_try "$s"; done ;;
  dawarich) dw_seed; for s in "$@"; do dw_try "$s"; done; e rm -f dawarich-db dawarich-redis >/dev/null; e network rm $NET >/dev/null ;;
esac
