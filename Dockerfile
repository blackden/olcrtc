# syntax=docker/dockerfile:1.7

ARG GO_VERSION=1.26
ARG ALPINE_VERSION=3.22
# Pinned to specific image digests for reproducible builds.
# Refresh with: docker buildx imagetools inspect <ref> --format '{{.Manifest.Digest}}'
ARG GO_IMAGE_DIGEST=sha256:be93003ee861b3b91b6ebcb22678524947e0cd786c2df3f32af520006b1e54f5
ARG ALPINE_IMAGE_DIGEST=sha256:310c62b5e7ca5b08167e4384c68db0fd2905dd9c7493756d356e893909057601

FROM golang:${GO_VERSION}-alpine${ALPINE_VERSION}@${GO_IMAGE_DIGEST} AS build

WORKDIR /src

# apk packages pinned to versions current in alpine 3.22 at the time of digest pin.
# Refresh with:
#   docker run --rm <pinned-base> sh -c 'apk update -q && apk search -x <pkg>'
RUN apk add --no-cache \
        ca-certificates=20260413-r0 \
        git=2.49.1-r0

COPY go.mod go.sum ./
RUN --mount=type=cache,target=/go/pkg/mod \
    go mod download

COPY . .

ARG TARGETOS=linux
ARG TARGETARCH=amd64

RUN --mount=type=cache,target=/go/pkg/mod \
    --mount=type=cache,target=/root/.cache/go-build \
    CGO_ENABLED=0 GOOS=${TARGETOS} GOARCH=${TARGETARCH} \
    go build -trimpath -ldflags="-s -w" -o /out/olcrtc ./cmd/olcrtc

FROM alpine:${ALPINE_VERSION}@${ALPINE_IMAGE_DIGEST} AS runtime

# netcat-openbsd: nc -z for cnc healthcheck (busybox nc lacks -z reliably).
# Versions pinned to alpine 3.22 snapshot — refresh procedure: see build stage above.
RUN apk add --no-cache \
        ca-certificates=20260413-r0 \
        ffmpeg=6.1.2-r2 \
        tzdata=2026b-r0 \
        netcat-openbsd=1.229.1-r0 && \
    addgroup -S olcrtc && \
    mkdir -p /usr/share/olcrtc /var/lib/olcrtc && \
    adduser -S -D -h /var/lib/olcrtc -s /sbin/nologin -G olcrtc olcrtc && \
    chown -R olcrtc:olcrtc /usr/share/olcrtc /var/lib/olcrtc

COPY --chown=olcrtc:olcrtc data /usr/share/olcrtc
COPY --from=build /out/olcrtc /usr/local/bin/olcrtc
COPY script/docker/olcrtc-entrypoint.sh /usr/local/bin/olcrtc-entrypoint
COPY script/docker/olcrtc-healthcheck.sh /usr/local/bin/olcrtc-healthcheck

RUN chmod 0755 /usr/local/bin/olcrtc /usr/local/bin/olcrtc-entrypoint /usr/local/bin/olcrtc-healthcheck

USER olcrtc:olcrtc
WORKDIR /var/lib/olcrtc

ENV OLCRTC_MODE=srv \
    OLCRTC_CARRIER= \
    OLCRTC_TRANSPORT=datachannel \
    OLCRTC_DATA_DIR=/usr/share/olcrtc \
    OLCRTC_DNS=8.8.8.8:53 \
    OLCRTC_KEY_FILE=/var/lib/olcrtc/key.hex \
    OLCRTC_SOCKS_HOST=127.0.0.1 \
    OLCRTC_SOCKS_PORT=8808 \
    OLCRTC_FFMPEG=ffmpeg

VOLUME ["/var/lib/olcrtc"]

HEALTHCHECK --interval=30s --timeout=3s --start-period=20s --retries=3 \
    CMD ["/usr/local/bin/olcrtc-healthcheck"]

ENTRYPOINT ["/usr/local/bin/olcrtc-entrypoint"]
