# syntax=docker/dockerfile:1

# Base TimescaleDB-HA image. Override to target a different PG/TS build, e.g.
#   --build-arg BASE_IMAGE=timescale/timescaledb-ha:pg16.9-ts2.17.2-all
ARG BASE_IMAGE=timescale/timescaledb-ha:pg17.9-ts2.25.2-all
FROM ${BASE_IMAGE}

LABEL maintainer="Keith Brings <keith.brings@noizu.com>"

#-------------------------------------------------------------------------------
# Build-time configuration (override with --build-arg)
#-------------------------------------------------------------------------------
# PostgreSQL source version + major — MUST match the PostgreSQL in BASE_IMAGE.
ARG PG_VERSION=17.9
ARG PG_MAJOR=17
# Apache AGE version (resolved under the PG${PG_MAJOR} release directory).
ARG AGE_VERSION=1.7.0
# contrib perf/tuning extensions to compile & install from source.
ARG CONTRIB_EXTENSIONS="pg_stat_statements auto_explain pg_buffercache pg_prewarm pgstattuple pg_visibility pg_freespacemap pageinspect amcheck pg_trgm btree_gin btree_gist hstore pg_walinspect tablefunc"
# Runtime defaults (baked as ENV below; still overridable at `docker run`).
ARG PRELOAD_LIBRARIES="timescaledb, pg_stat_statements, auto_explain, age"
ARG DEFAULT_EXTENSIONS="timescaledb,pg_stat_statements,age"

USER root
WORKDIR /docker-scripts

# Build PostgreSQL headers, contrib extensions, and Apache AGE from source.
# Build args are exposed to RUN as environment variables.
COPY ./scripts/common.sh ./scripts/setup.sh ./
RUN chmod u+x ./setup.sh && ./setup.sh

# Install first-boot scripts that set shared_preload_libraries and CREATE the
# configured extensions. Consumed by the base image entrypoint.
COPY ./scripts/initdb/ /docker-entrypoint-initdb.d/
RUN chmod +x /docker-entrypoint-initdb.d/*.sh

# Entrypoint wrapper that adds a boot-time hook on top of the base entrypoint:
# files in /docker-entrypoint-bootdb.d/ run on EVERY start, after the server is
# up (the base initdb.d flow only runs once, on first cluster init). The
# directory ships empty — mount or bake in your own
# *.sh / *.sql[.gz|.xz|.zst] files.
COPY ./scripts/entrypoint.sh /usr/local/bin/timescaledb-ha-age-entrypoint.sh
RUN chmod +x /usr/local/bin/timescaledb-ha-age-entrypoint.sh \
    && mkdir -p /docker-entrypoint-bootdb.d

# Runtime defaults read by the init scripts (override with `docker run -e ...`).
ENV PG_PRELOAD_LIBRARIES=${PRELOAD_LIBRARIES} \
    PG_DEFAULT_EXTENSIONS=${DEFAULT_EXTENSIONS} \
    PG_EXTENSION_DATABASES=""

WORKDIR /home/postgres
USER postgres

# Wrap the base entrypoint (/docker-entrypoint.sh) to add the bootdb.d hook.
# CMD is inherited from the base image (["postgres"]).
ENTRYPOINT ["/usr/local/bin/timescaledb-ha-age-entrypoint.sh"]
