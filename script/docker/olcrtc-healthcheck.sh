#!/bin/sh
# Mode-aware healthcheck.
# - cnc: verify the local SOCKS5 listener accepts connections (functional check)
# - srv/gen: only liveness — there is no local TCP listener to probe
set -eu

case "${OLCRTC_MODE:-srv}" in
    cnc)
        nc -z "${OLCRTC_SOCKS_HOST:-127.0.0.1}" "${OLCRTC_SOCKS_PORT:-8808}"
        ;;
    srv|gen)
        pidof olcrtc >/dev/null 2>&1
        ;;
    *)
        echo "olcrtc-healthcheck: unknown OLCRTC_MODE=${OLCRTC_MODE:-}" >&2
        exit 1
        ;;
esac
