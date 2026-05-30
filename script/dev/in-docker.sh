#!/bin/sh
# Run arbitrary commands inside a pinned golang-alpine container with
# persistent go-mod and go-build caches. Used by Makefile when local Go
# is not installed.
#
# Usage:
#   script/dev/in-docker.sh go test ./...
#   script/dev/in-docker.sh sh -c 'go version && ls -la /go/pkg/mod'
#
# Env overrides:
#   DEV_GO_IMAGE      — override image (default: pinned golang-alpine)
#   DEV_CACHE_PREFIX  — volume name prefix (default: olcrtc-dev)
#   DEV_NETWORK       — docker --network value (default: host)
#
# Note: CGO is forced off (CGO_ENABLED=0) to match the Dockerfile build
# profile. Override only if you have a specific cgo need.

set -eu

# Pinned to match Dockerfile (build stage).
DEV_GO_IMAGE="${DEV_GO_IMAGE:-golang:1.26-alpine3.22@sha256:be93003ee861b3b91b6ebcb22678524947e0cd786c2df3f32af520006b1e54f5}"
DEV_CACHE_PREFIX="${DEV_CACHE_PREFIX:-olcrtc-dev}"
DEV_NETWORK="${DEV_NETWORK:-host}"

if [ "$#" -eq 0 ]; then
    echo "usage: $0 <command> [args...]" >&2
    exit 2
fi

if ! command -v docker >/dev/null 2>&1; then
    echo "error: docker not installed; install Docker Desktop or Podman with docker shim" >&2
    exit 127
fi

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

exec docker run --rm \
    --network="${DEV_NETWORK}" \
    -v "${REPO_ROOT}:/src" \
    -w /src \
    -v "${DEV_CACHE_PREFIX}-gomod:/go/pkg/mod" \
    -v "${DEV_CACHE_PREFIX}-gocache:/root/.cache/go-build" \
    -e CGO_ENABLED=0 \
    "${DEV_GO_IMAGE}" \
    "$@"
