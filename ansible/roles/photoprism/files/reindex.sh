#!/usr/bin/env bash

# Usage: nohup ./reindex.sh &

#docker compose exec photoprism photoprism index -f -c
docker compose exec photoprism photoprism faces index
docker compose exec photoprism photoprism faces update
docker compose exec photoprism photoprism faces optimize
docker compose exec photoprism photoprism faces audit
docker compose exec photoprism photoprism moments
