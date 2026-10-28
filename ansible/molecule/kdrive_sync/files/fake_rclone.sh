#!/bin/sh
# Faux `docker compose run … rclone` (aucune image tirée ici) : note ses
# arguments, imite la sortie --use-json-log de rclone (une erreur si
# FAKE_RCLONE_RC n'est pas 0, puis les statistiques finales) et sort avec
# FAKE_RCLONE_RC.
printf '%s\n' "$*" > "$(dirname "$0")/args"
if [ "${FAKE_RCLONE_RC:-0}" -ne 0 ]; then
  printf '%s\n' '{"level":"error","msg":"Failed to copy: 401 Unauthorized","source":"sync/sync.go:1","time":"2026-10-28T04:00:00+01:00"}'
fi
printf '%s\n' 'not json: a plain line'
printf '%s\n' '{"level":"notice","msg":"Transferred: 1 MiB","source":"accounting/stats.go:1","stats":{"bytes":1048576,"checks":7,"elapsedTime":125.5,"errors":0,"transfers":3},"time":"2026-10-28T04:02:05+01:00"}'
exit "${FAKE_RCLONE_RC:-0}"
