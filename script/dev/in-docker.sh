#!/bin/sh
# Run arbitrary commands inside a pinned golang-alpine container with
# persistent go-mod and go-build caches. Used by Makefile when local Go
# is not installed.
#
# Builds a thin derived image once (adds gcc/musl-dev/git/ca-certificates
# on top of the pinned base) so cgo-requiring commands like `go test -race`
# work without re-installing tools on every invocation. The derived image
# is locally cached as DEV_DERIVED_TAG and rebuilt only when missing.
#
# Usage:
#   script/dev/in-docker.sh go test ./...
#   script/dev/in-docker.sh go test -race ./...
#   script/dev/in-docker.sh sh -c 'go version && ls -la /go/pkg/mod'
#
# Env overrides:
#   DEV_BASE_IMAGE    — base image (default: pinned golang-alpine)
#   DEV_DERIVED_TAG   — local tag of derived image (default: olcrtc-dev-go:cached)
#   DEV_CACHE_PREFIX  — volume name prefix (default: olcrtc-dev)
#   DEV_NETWORK       — docker --network value (default: host)
#   DEV_REBUILD       — set to 1 to force rebuild of the derived image
#
# CGO is NOT forced; Go's default applies (cgo enabled because the
# derived image carries gcc). For static builds, callers may pass
# `-e CGO_ENABLED=0` themselves via docker (advanced).

set -eu

# Pinned to match Dockerfile (build stage).
DEV_BASE_IMAGE="${DEV_BASE_IMAGE:-golang:1.26-alpine3.22@sha256:be93003ee861b3b91b6ebcb22678524947e0cd786c2df3f32af520006b1e54f5}"
DEV_DERIVED_TAG="${DEV_DERIVED_TAG:-olcrtc-dev-go:cached}"
DEV_CACHE_PREFIX="${DEV_CACHE_PREFIX:-olcrtc-dev}"
DEV_NETWORK="${DEV_NETWORK:-host}"
DEV_REBUILD="${DEV_REBUILD:-0}"

if [ "$#" -eq 0 ]; then
    echo "usage: $0 <command> [args...]" >&2
    exit 2
fi

if ! command -v docker >/dev/null 2>&1; then
    echo "error: docker not installed; install Docker Desktop or Podman with docker shim" >&2
    exit 127
fi

# Build the derived image if missing or DEV_REBUILD=1.
if [ "${DEV_REBUILD}" = "1" ] || ! docker image inspect "${DEV_DERIVED_TAG}" >/dev/null 2>&1; then
    echo "in-docker: building ${DEV_DERIVED_TAG} from ${DEV_BASE_IMAGE} (one-time)" >&2
    docker build --network="${DEV_NETWORK}" -t "${DEV_DERIVED_TAG}" - <<EOF
FROM ${DEV_BASE_IMAGE}
RUN apk add --no-cache git=2.49.1-r0 gcc=14.2.0-r6 musl-dev=1.2.5-r12 ca-certificates=20260413-r0
EOF
fi

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

exec docker run --rm \
    --network="${DEV_NETWORK}" \
    -v "${REPO_ROOT}:/src" \
    -w /src \
    -v "${DEV_CACHE_PREFIX}-gomod:/go/pkg/mod" \
    -v "${DEV_CACHE_PREFIX}-gocache:/root/.cache/go-build" \
    "${DEV_DERIVED_TAG}" \
    "$@"
