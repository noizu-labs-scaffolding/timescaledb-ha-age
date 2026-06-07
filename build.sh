#!/usr/bin/env bash
# Build the TimescaleDB-HA + Apache AGE image with Docker Buildx. Everything is
# parameterized via environment variables so you can retarget PG/TS/AGE versions,
# platforms, and extensions without editing files, e.g.:
#
#   BASE_IMAGE=timescale/timescaledb-ha:pg16.9-ts2.17.2-all \
#   PG_VERSION=16.9 PG_MAJOR=16 AGE_VERSION=1.5.0 ./build.sh
#
set -euo pipefail

BASE_IMAGE="${BASE_IMAGE:-timescale/timescaledb-ha:pg17.9-ts2.25.2-all}"
PG_VERSION="${PG_VERSION:-17.9}"
PG_MAJOR="${PG_MAJOR:-17}"
AGE_VERSION="${AGE_VERSION:-1.7.0}"
IMAGE="${IMAGE:-noizu/timescaledb-ha-with-age}"
PLATFORMS="${PLATFORMS:-linux/amd64,linux/arm64}"
BUILDX_OUTPUT="${BUILDX_OUTPUT:---push}"
BUILDER="${BUILDER:-}"
# Image revision — bump when the image changes without an AGE/PG/TS version
# change (e.g. entrypoint/script updates). Set IMAGE_REVISION="" to omit.
IMAGE_REVISION="${IMAGE_REVISION:-r2}"

# Derive a descriptive version tag from the base image tag, e.g.
#   pg17.9-ts2.25.2-all  ->  pg17.9-ts2.25.2-all-age1.7.0-r2
BASE_TAG="${BASE_IMAGE##*:}"
VERSION_TAG="${BASE_TAG}-age${AGE_VERSION}${IMAGE_REVISION:+-${IMAGE_REVISION}}"

build_args=(
  --build-arg "BASE_IMAGE=${BASE_IMAGE}"
  --build-arg "PG_VERSION=${PG_VERSION}"
  --build-arg "PG_MAJOR=${PG_MAJOR}"
  --build-arg "AGE_VERSION=${AGE_VERSION}"
)

if [ -n "${CONTRIB_EXTENSIONS:-}" ]; then
  build_args+=(--build-arg "CONTRIB_EXTENSIONS=${CONTRIB_EXTENSIONS}")
fi
if [ -n "${PRELOAD_LIBRARIES:-}" ]; then
  build_args+=(--build-arg "PRELOAD_LIBRARIES=${PRELOAD_LIBRARIES}")
fi
if [ -n "${DEFAULT_EXTENSIONS:-}" ]; then
  build_args+=(--build-arg "DEFAULT_EXTENSIONS=${DEFAULT_EXTENSIONS}")
fi

builder_args=()
if [ -n "${BUILDER}" ]; then
  builder_args+=(--builder "${BUILDER}")
fi

docker buildx build \
  "${builder_args[@]}" \
  --platform "${PLATFORMS}" \
  "${build_args[@]}" \
  -t "${IMAGE}:latest" \
  -t "${IMAGE}:${VERSION_TAG}" \
  ${BUILDX_OUTPUT} \
  .
