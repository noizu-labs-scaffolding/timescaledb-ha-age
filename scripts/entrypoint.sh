#!/usr/bin/env bash
# Custom entrypoint wrapper for timescaledb-ha-age.
#
# Adds a "boot" hook on top of the base image's entrypoint. The base entrypoint
# only runs /docker-entrypoint-initdb.d once, on first cluster initialization
# (empty PGDATA). This wrapper additionally runs every file in
#
#     /docker-entrypoint-bootdb.d/        (override with PG_BOOTDB_DIR)
#
# on EVERY container start, once the real server is accepting connections.
#
#     initdb.d  -> runs ONCE,  on first cluster init (empty data dir).
#     bootdb.d  -> runs EVERY  start / reload, against the live server.
#
# Conventions mirror the base initdb.d flow:
#     *.sh        executed if +x, otherwise sourced
#     *.sql       piped to psql
#     *.sql.gz    gunzip | psql
#     *.sql.xz    xzcat  | psql
#     *.sql.zst   zstd -dc | psql
#
# Boot scripts run in the background and NEVER abort the container: a failing
# script is logged and the next one still runs. Because they run on every start,
# make them idempotent (CREATE ... IF NOT EXISTS, ALTER SYSTEM, etc.).
#
# Tunables (env):
#     PG_BOOTDB_DIR            dir of boot scripts (default /docker-entrypoint-bootdb.d)
#     PG_BOOTDB_TIMEOUT        seconds to wait for the server (default 90)
#     PG_BOOTDB_PROBE_HOST     host to probe for readiness (default 127.0.0.1)
#     PG_BOOTDB_ON_ERROR_STOP  psql ON_ERROR_STOP for *.sql files (default 1)
#     PG_SKIP_BOOTDB=1         skip the boot hook entirely
set -Eeo pipefail

BASE_ENTRYPOINT="/docker-entrypoint.sh"
BOOTDB_DIR="${PG_BOOTDB_DIR:-/docker-entrypoint-bootdb.d}"

# True only when we're actually being asked to start the server, mirroring the
# base entrypoint's own argument heuristics (a leading flag implies `postgres`,
# and --help/--version style flags just print and exit).
_running_server() {
  case "${1:-}" in
    postgres) ;;
    -*) ;;
    *) return 1 ;;
  esac
  local arg
  for arg in "$@"; do
    case "$arg" in
      -'?'|--help|--describe-config|-V|--version) return 1 ;;
    esac
  done
  return 0
}

process_boot_files() {
  # Never let one failing command kill the rest of the boot sequence.
  set +e

  shopt -s nullglob
  local files=("$BOOTDB_DIR"/*)
  shopt -u nullglob
  if [ "${#files[@]}" -eq 0 ]; then
    echo "bootdb: no files in $BOOTDB_DIR; nothing to run"
    return 0
  fi

  : "${POSTGRES_USER:=postgres}"
  : "${POSTGRES_DB:=$POSTGRES_USER}"

  # Wait for the REAL server. The init-time temporary server listens with
  # listen_addresses='' (no TCP), so probing over TCP avoids racing boot
  # scripts onto it during first-boot initialization.
  local probe_host="${PG_BOOTDB_PROBE_HOST:-127.0.0.1}"
  local port="${PGPORT:-5432}"
  local timeout="${PG_BOOTDB_TIMEOUT:-90}"
  local waited=0
  until pg_isready -q -h "$probe_host" -p "$port" -U "$POSTGRES_USER" 2>/dev/null; do
    sleep 1
    waited=$((waited + 1))
    if [ "$waited" -ge "$timeout" ]; then
      echo "bootdb: timed out after ${timeout}s waiting for PostgreSQL on ${probe_host}:${port}; skipping $BOOTDB_DIR" >&2
      return 0
    fi
  done

  # Run the scripts over the local socket (trust auth for the postgres user),
  # not the TCP probe host, so no password is required.
  local on_err="${PG_BOOTDB_ON_ERROR_STOP:-1}"
  local psql_run=(psql -v ON_ERROR_STOP="$on_err" --no-password
                  --username "$POSTGRES_USER" --dbname "$POSTGRES_DB")

  echo "bootdb: running ${#files[@]} boot script(s) from $BOOTDB_DIR"
  local f rc
  for f in "${files[@]}"; do
    case "$f" in
      *.sh)
        if [ -x "$f" ]; then
          echo "bootdb: running $f"
          "$f"
        else
          echo "bootdb: sourcing $f"
          ( . "$f" )
        fi
        ;;
      *.sql)     echo "bootdb: running $f"; "${psql_run[@]}" -f "$f" ;;
      *.sql.gz)  echo "bootdb: running $f"; gunzip -c "$f" | "${psql_run[@]}" ;;
      *.sql.xz)  echo "bootdb: running $f"; xzcat "$f"     | "${psql_run[@]}" ;;
      *.sql.zst) echo "bootdb: running $f"; zstd -dc "$f"  | "${psql_run[@]}" ;;
      *) echo "bootdb: ignoring $f"; continue ;;
    esac
    rc=$?
    [ "$rc" -eq 0 ] || echo "bootdb: WARN $f exited $rc" >&2
  done
  echo "bootdb: done"
}

if [ "${PG_SKIP_BOOTDB:-0}" != "1" ] && _running_server "$@" && [ -d "$BOOTDB_DIR" ]; then
  # Fire the boot hook in the background, then hand off to the base entrypoint.
  # `exec` keeps PID 1; the backgrounded job survives the handoff and runs once
  # the base entrypoint finishes init and the server is up.
  process_boot_files &
fi

exec "$BASE_ENTRYPOINT" "$@"
