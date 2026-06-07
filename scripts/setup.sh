#!/bin/bash
# Build-time setup: compile matching PostgreSQL server headers, the recommended
# contrib perf/tuning extensions, and Apache AGE — all from source against the
# PostgreSQL that already ships in the base TimescaleDB-HA image.
#
# Everything is driven by environment variables (supplied as Docker build args):
#   PG_VERSION          full PostgreSQL version of the base image (e.g. 17.9)
#   PG_MAJOR            PostgreSQL major version (e.g. 17) — selects the AGE release dir
#   AGE_VERSION         Apache AGE version to build (e.g. 1.7.0)
#   CONTRIB_EXTENSIONS  space-separated contrib modules to build & install
source /docker-scripts/common.sh

#-------------------------------------------------------------------------------
# Configuration (with sane defaults so the script is runnable standalone)
#-------------------------------------------------------------------------------
PG_VERSION="${PG_VERSION:-17.9}"
PG_MAJOR="${PG_MAJOR:-17}"
AGE_VERSION="${AGE_VERSION:-1.7.0}"
CONTRIB_EXTENSIONS="${CONTRIB_EXTENSIONS:-pg_stat_statements auto_explain pg_buffercache pg_prewarm pgstattuple pg_visibility pg_freespacemap pageinspect amcheck pg_trgm btree_gin btree_gist hstore pg_walinspect tablefunc}"

PG_CONFIG="$(command -v pg_config)"
if [ -z "$PG_CONFIG" ]; then
  echo "[Failure] pg_config not found on PATH — is this a PostgreSQL base image?"
  exit 1
fi
SERVER_INCLUDE_DIR="$("$PG_CONFIG" --includedir-server)"
SRC_DIR="/tmp/build"

print_heading "Build configuration"
echo "  PostgreSQL source : ${PG_VERSION} (major ${PG_MAJOR})"
echo "  Apache AGE        : ${AGE_VERSION} (PG${PG_MAJOR})"
echo "  pg_config         : ${PG_CONFIG}"
echo "  server headers    : ${SERVER_INCLUDE_DIR}"
echo "  contrib extensions: ${CONTRIB_EXTENSIONS}"

#-------------------------------------------------------------------------------
# Refresh Apt Cache
#-------------------------------------------------------------------------------
update_apt

#-------------------------------------------------------------------------------
# Build Deps
#-------------------------------------------------------------------------------
print_heading "Installing Build Deps"
apt-get install -y --no-install-recommends \
  wget ca-certificates build-essential libreadline-dev zlib1g-dev flex bison \
  libicu-dev pkg-config icu-devtools clang-15 llvm-15
early_exit $?

#-------------------------------------------------------------------------------
# Fetch Sources
#-------------------------------------------------------------------------------
print_heading "Downloading PostgreSQL ${PG_VERSION} and Apache AGE ${AGE_VERSION}"
mkdir -p "$SRC_DIR" && cd "$SRC_DIR"
early_exit $?

wget -q "https://ftp.postgresql.org/pub/source/v${PG_VERSION}/postgresql-${PG_VERSION}.tar.gz"
early_exit $?

AGE_TGZ="apache-age-${AGE_VERSION}-src.tar.gz"
# Current releases live on the CDN; older ones move to the Apache archive.
if ! wget -q "https://dlcdn.apache.org/age/PG${PG_MAJOR}/${AGE_VERSION}/${AGE_TGZ}"; then
  echo "CDN miss — falling back to the Apache archive"
  wget -q "https://archive.apache.org/dist/age/PG${PG_MAJOR}/${AGE_VERSION}/${AGE_TGZ}"
fi
early_exit $?

tar -xf "postgresql-${PG_VERSION}.tar.gz" && tar -xf "${AGE_TGZ}"
early_exit $?

#-------------------------------------------------------------------------------
# Build PostgreSQL (only to obtain version-matched, generated server headers)
#-------------------------------------------------------------------------------
print_heading "Configuring & building PostgreSQL ${PG_VERSION} (for headers)"
cd "${SRC_DIR}/postgresql-${PG_VERSION}"
./configure
early_exit $?
# A full build generates headers (pg_config.h, fmgroids.h, errcodes.h, …) that
# contrib and AGE need; we install the headers, not the binaries.
make -j"$(nproc)"
early_exit $?

print_heading "Installing matching server headers into ${SERVER_INCLUDE_DIR}"
cp -rL src/include/. "${SERVER_INCLUDE_DIR}/"
early_exit $?

#-------------------------------------------------------------------------------
# Build contrib perf/tuning extensions against the image's real PostgreSQL
#-------------------------------------------------------------------------------
print_heading "Building contrib extensions"
for ext in ${CONTRIB_EXTENSIONS}; do
  if [ -d "contrib/${ext}" ]; then
    echo ">> contrib/${ext}"
    make -C "contrib/${ext}" USE_PGXS=1 PG_CONFIG="${PG_CONFIG}" install
    early_exit $?
  else
    echo "WARN: contrib/${ext} not present in PostgreSQL ${PG_VERSION} source; skipping"
  fi
done

#-------------------------------------------------------------------------------
# Build Apache AGE
#-------------------------------------------------------------------------------
print_heading "Installing Apache AGE ${AGE_VERSION}"
cd "${SRC_DIR}/apache-age-${AGE_VERSION}"
make PG_CONFIG="${PG_CONFIG}" install
early_exit $?

#-------------------------------------------------------------------------------
# Cleanup
#-------------------------------------------------------------------------------
print_heading "Cleaning up sources"
cd / && rm -rf "$SRC_DIR"

apt-get remove -y wget build-essential libreadline-dev flex bison pkg-config icu-devtools clang-15
apt-get autoremove -y

#-------------------------------------------------------------------------------
# Purging Apt Cache
#-------------------------------------------------------------------------------
purge_apt
