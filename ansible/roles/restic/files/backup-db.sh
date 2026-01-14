#!/usr/bin/env bash

set -euo pipefail

# $1 user
# $2 password
# $3 database
# $4 restic repo

mysqldump -u "$1" -p"$2" "$3" | restic backup --host "$4" --verbose --stdin --stdin-filename backup-"$3.sql"
