#!/bin/bash
# Runs once on first cluster init (temp server up). Writes shared_preload_libraries
# to postgresql.conf so preload-only modules (pg_stat_statements, auto_explain,
# ...) are active from the real server start.
#
# Override at `docker run` time with:  -e PG_PRELOAD_LIBRARIES="timescaledb,age,..."
# (comma- or space-separated). timescaledb is always kept and listed first.
set -euo pipefail

: "${POSTGRES_USER:=postgres}"
: "${POSTGRES_DB:=$POSTGRES_USER}"

PRELOAD_RAW="${PG_PRELOAD_LIBRARIES:-timescaledb, pg_stat_statements, auto_explain, age}"

# Normalize separators -> newlines, drop blanks, prepend timescaledb, dedupe
# preserving order, then join back as PostgreSQL list syntax.
ORDERED="$(
  { printf 'timescaledb\n'; printf '%s\n' "$PRELOAD_RAW" | tr ', ' '\n'; } \
    | sed '/^[[:space:]]*$/d' \
    | awk '!seen[$0]++' \
    | paste -sd, - \
    | sed 's/,/, /g'
)"

echo "Setting shared_preload_libraries = '${ORDERED}'"
cat >> "${PGDATA}/postgresql.conf" <<-EOCONF

	# Added by timescaledb-ha-age init script
	shared_preload_libraries = '${ORDERED}'
EOCONF
