# timescaledb-ha-age

TimescaleDB-HA Docker image with the [Apache AGE](https://age.apache.org/) graph
extension plus a curated set of PostgreSQL performance/observability extensions,
all built from source against the PostgreSQL that ships in the base image.

Available on Docker Hub:

```
noizu/timescaledb-ha-with-age:latest
```

## What's included

- **Apache AGE** — graph database extension (built from source).
- **Perf / tuning contrib extensions** — `pg_stat_statements`, `auto_explain`,
  `pg_buffercache`, `pg_prewarm`, `pgstattuple`, `pg_visibility`,
  `pg_freespacemap`, `pageinspect`, `amcheck`, `pg_trgm`, `btree_gin`,
  `btree_gist`, `hstore`, `pg_walinspect`, `tablefunc`.
- **Auto-enable on first boot** — `shared_preload_libraries` is configured and
  `CREATE EXTENSION` is run for a default set, with sensible
  `pg_stat_statements` / `auto_explain` tuning applied.

## Build

The build is fully parameterized. Defaults match the current published image:

```bash
./build.sh
```

`build.sh` uses Docker Buildx and defaults to a multi-architecture build for
`linux/amd64,linux/arm64`, pushing both `latest` and the versioned tag.

Retarget the PostgreSQL / TimescaleDB / AGE versions by setting env vars — note
`PG_VERSION` and `PG_MAJOR` **must** match the PostgreSQL inside `BASE_IMAGE`:

```bash
BASE_IMAGE=timescale/timescaledb-ha:pg16.9-ts2.17.2-all \
PG_VERSION=16.9 PG_MAJOR=16 AGE_VERSION=1.5.0 \
./build.sh
```

### Build arguments

| Arg / env             | Default                                             | Purpose                                                        |
| --------------------- | --------------------------------------------------- | -------------------------------------------------------------- |
| `BASE_IMAGE`          | `timescale/timescaledb-ha:pg17.9-ts2.25.2-all`      | Base TimescaleDB-HA image.                                     |
| `PG_VERSION`          | `17.9`                                               | PostgreSQL source version (match the base image).              |
| `PG_MAJOR`            | `17`                                                 | PostgreSQL major (selects the AGE release directory).          |
| `AGE_VERSION`         | `1.7.0`                                               | Apache AGE version.                                            |
| `PLATFORMS`           | `linux/amd64,linux/arm64`                             | Buildx target platforms.                                       |
| `BUILDX_OUTPUT`       | `--push`                                              | Buildx output mode, e.g. `--load` for a single local platform. |
| `BUILDER`             | _(empty)_                                             | Optional Buildx builder name.                                  |
| `IMAGE_REVISION`      | `r2`                                                 | Revision suffix on the version tag (e.g. `…-age1.7.0-r2`); set empty to omit. |
| `CONTRIB_EXTENSIONS`  | the list above                                       | Space-separated contrib modules to build & install.           |
| `PRELOAD_LIBRARIES`   | `timescaledb, pg_stat_statements, auto_explain, age` | Default `shared_preload_libraries` (runtime-overridable).      |
| `DEFAULT_EXTENSIONS`  | `timescaledb,pg_stat_statements,age`                | Extensions `CREATE`d on first boot (runtime-overridable).      |

For a local single-architecture test build without pushing:

```bash
PLATFORMS=linux/arm64 BUILDX_OUTPUT=--load ./build.sh
```

You can also pass `--build-arg` directly to `docker buildx build` if you prefer
not to use `build.sh`.

## Runtime configuration

The first-boot init scripts honor these environment variables (override at
`docker run` time without rebuilding):

| Env                       | Default                                             | Effect                                                          |
| ------------------------- | --------------------------------------------------- | -------------------------------------------------------------- |
| `PG_PRELOAD_LIBRARIES`    | from `PRELOAD_LIBRARIES`                             | `shared_preload_libraries`. `timescaledb` is always kept first. |
| `PG_DEFAULT_EXTENSIONS`   | from `DEFAULT_EXTENSIONS`                            | Extensions to `CREATE EXTENSION` on first boot.                |
| `PG_EXTENSION_DATABASES`  | _(empty)_                                            | Extra DBs to enable extensions in, e.g. `template1`.           |
| `PG_SKIP_TUNING`          | `0`                                                  | Set to `1` to skip the recommended tuning GUCs.                |

Example:

```bash
docker run -d \
  -e POSTGRES_PASSWORD=secret \
  -e PG_DEFAULT_EXTENSIONS="timescaledb,age,pg_stat_statements,pg_trgm" \
  -e PG_EXTENSION_DATABASES="template1" \
  noizu/timescaledb-ha-with-age:latest
```

> Auto-enable relies on the base image's `/docker-entrypoint-initdb.d` flow,
> which runs on first cluster initialization (the standard dev/single-node
> entrypoint). In a Patroni-managed HA deployment, cluster configuration is
> owned by Patroni — set `shared_preload_libraries` through your Patroni bootstrap
> config there instead.

## Boot-time scripts (`bootdb.d`)

`/docker-entrypoint-initdb.d` only runs **once**, on first cluster
initialization. This image adds a companion hook that runs on **every** start:

- **`/docker-entrypoint-initdb.d/`** — runs once, on first init (empty data dir).
- **`/docker-entrypoint-bootdb.d/`** — runs on every start/reload, after the
  server is accepting connections.

The image ships `bootdb.d` empty. Mount or bake in your own files — same
conventions as `initdb.d` (processed in filename order):
`*.sh` (executed if `+x`, else sourced), `*.sql`, `*.sql.gz`, `*.sql.xz`,
`*.sql.zst`. Anything else is ignored.

```bash
docker run -d \
  -e POSTGRES_PASSWORD=secret \
  -v "$PWD/my-boot-scripts:/docker-entrypoint-bootdb.d:ro" \
  noizu/timescaledb-ha-with-age:latest
```

Boot scripts run as `POSTGRES_USER` against `POSTGRES_DB` over the local socket,
in the background, and never abort the container — a failing script is logged
and the next one still runs. Because they run on every start, **make them
idempotent** (`CREATE ... IF NOT EXISTS`, `ALTER SYSTEM`, `INSERT ... ON
CONFLICT`, …). See `scripts/bootdb.d/` for a template.

Tunables (override at `docker run` time):

| Env                       | Default                       | Effect                                            |
| ------------------------- | ----------------------------- | ------------------------------------------------- |
| `PG_BOOTDB_DIR`           | `/docker-entrypoint-bootdb.d` | Directory of boot scripts.                        |
| `PG_BOOTDB_TIMEOUT`       | `90`                          | Seconds to wait for the server before giving up.  |
| `PG_BOOTDB_PROBE_HOST`    | `127.0.0.1`                   | Host probed for readiness.                         |
| `PG_BOOTDB_ON_ERROR_STOP` | `1`                           | `psql ON_ERROR_STOP` for `*.sql` files.           |
| `PG_SKIP_BOOTDB`          | `0`                           | Set to `1` to disable the boot hook.              |

> Like the `initdb.d` flow, this hook rides on the standard
> `/docker-entrypoint.sh` entrypoint. A Patroni-managed entrypoint bypasses it.

## Notes

- Using Apache AGE in a session: `LOAD 'age'; SET search_path = ag_catalog, "$user", public;`
  (with `age` in `shared_preload_libraries` it is loaded automatically).
- `PG_VERSION`/`PG_MAJOR` mismatches against the base image will fail the build
  when the source headers don't match the installed PostgreSQL ABI.
