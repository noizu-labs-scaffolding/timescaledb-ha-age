#!/bin/bash
# Auto-enable extensions on first boot. CREATE EXTENSION is attempted per
# extension per database; a failure (e.g. an extension that wasn't built into
# this image) is logged as a warning and does not abort init.
#
#   PG_DEFAULT_EXTENSIONS   comma/space list to enable (default below)
#   PG_EXTENSION_DATABASES  extra databases to enable them in, besides the
#                           default database (e.g. "template1" so new DBs inherit)
set -uo pipefail

: "${POSTGRES_USER:=postgres}"
: "${POSTGRES_DB:=$POSTGRES_USER}"

EXTS_RAW="${PG_DEFAULT_EXTENSIONS:-timescaledb,pg_stat_statements,age}"
DBS_RAW="${POSTGRES_DB} ${PG_EXTENSION_DATABASES:-}"

normalize() { printf '%s\n' "$1" | tr ', ' '\n' | sed '/^[[:space:]]*$/d' | awk '!seen[$0]++'; }

EXTS="$(normalize "$EXTS_RAW")"
DBS="$(normalize "$DBS_RAW")"

for db in $DBS; do
  for ext in $EXTS; do
    echo "[$db] CREATE EXTENSION IF NOT EXISTS $ext"
    if ! psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$db" \
         -c "CREATE EXTENSION IF NOT EXISTS \"$ext\" CASCADE;"; then
      echo "WARN: could not create extension '$ext' in '$db' (is it installed in this image?)"
    fi
  done
done
