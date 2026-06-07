# bootdb.d — boot-time hook scripts

Files placed in the container's `/docker-entrypoint-bootdb.d/` directory are run
on **every** container start, after PostgreSQL is accepting connections — unlike
`/docker-entrypoint-initdb.d/`, which the base image runs only once on first
cluster initialization.

The image ships this directory **empty**; mount or bake your own files in:

```bash
docker run -d \
  -e POSTGRES_PASSWORD=secret \
  -v "$PWD/my-boot-scripts:/docker-entrypoint-bootdb.d:ro" \
  noizu/timescaledb-ha-with-age:latest
```

## Conventions

Mirrors the base `initdb.d` flow. Files are processed in filename order:

| Pattern     | Action                                          |
| ----------- | ----------------------------------------------- |
| `*.sh`      | executed if executable, otherwise sourced       |
| `*.sql`     | piped to `psql`                                 |
| `*.sql.gz`  | `gunzip -c \| psql`                             |
| `*.sql.xz`  | `xzcat \| psql`                                 |
| `*.sql.zst` | `zstd -dc \| psql`                              |
| anything else | ignored                                       |

Scripts run as `POSTGRES_USER` against `POSTGRES_DB` over the local socket.

## Rules of thumb

- **Make them idempotent.** They run on every start, so use
  `CREATE ... IF NOT EXISTS`, `ALTER SYSTEM`, `INSERT ... ON CONFLICT`, etc.
- Failures are logged and never abort the container; the next script still runs.
- This runs in the background and never blocks the server from coming up.

See `example.sql.disabled` in this folder for a template. Remove the
`.disabled` suffix (and mount it into `/docker-entrypoint-bootdb.d/`) to use it.

## Tunables (env)

| Env                       | Default                      | Effect                                       |
| ------------------------- | ---------------------------- | -------------------------------------------- |
| `PG_BOOTDB_DIR`           | `/docker-entrypoint-bootdb.d`| Directory of boot scripts.                   |
| `PG_BOOTDB_TIMEOUT`       | `90`                         | Seconds to wait for the server before giving up. |
| `PG_BOOTDB_PROBE_HOST`    | `127.0.0.1`                  | Host probed for readiness.                   |
| `PG_BOOTDB_ON_ERROR_STOP` | `1`                          | `psql ON_ERROR_STOP` for `*.sql` files.      |
| `PG_SKIP_BOOTDB`          | `0`                          | Set to `1` to disable the boot hook.         |
