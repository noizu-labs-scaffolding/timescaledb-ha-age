#!/bin/bash
# Recommended defaults for the observability/perf modules. These are stored in
# postgresql.auto.conf and take effect once the modules are preloaded (the real
# server start). Qualified GUCs are accepted as placeholders even before the
# owning module loads, but we run without ON_ERROR_STOP so a rejected setting
# never aborts cluster init.
#
# Disable entirely with:  -e PG_SKIP_TUNING=1
set -uo pipefail

: "${POSTGRES_USER:=postgres}"
: "${POSTGRES_DB:=$POSTGRES_USER}"

if [ "${PG_SKIP_TUNING:-0}" = "1" ]; then
  echo "PG_SKIP_TUNING=1 — skipping recommended tuning GUCs"
  exit 0
fi

echo "Applying recommended pg_stat_statements / auto_explain defaults"
psql --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-'EOSQL'
	-- pg_stat_statements: track everything, keep stats across restarts
	ALTER SYSTEM SET pg_stat_statements.max = 10000;
	ALTER SYSTEM SET pg_stat_statements.track = 'all';
	ALTER SYSTEM SET pg_stat_statements.track_utility = on;
	ALTER SYSTEM SET pg_stat_statements.save = on;

	-- auto_explain: log plans for slow statements (>= 3s) to the server log
	ALTER SYSTEM SET auto_explain.log_min_duration = '3s';
	ALTER SYSTEM SET auto_explain.log_analyze = on;
	ALTER SYSTEM SET auto_explain.log_buffers = on;
	ALTER SYSTEM SET auto_explain.log_verbose = on;
	ALTER SYSTEM SET auto_explain.log_nested_statements = on;
	ALTER SYSTEM SET auto_explain.log_format = 'text';
EOSQL
