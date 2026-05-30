# Docker learnings (staging area)

Заметки, накопленные при работе с Docker в этом репо. Когда наберётся достаточно — превращаются в правки `docs/blackden/principles.md` или `.claude/skills/docker-hygiene.md`, либо передаются `devops-engineer` агенту.

## Воспроизводимая сборка — три слоя пинов

Полная reproducibility требует **три** уровня:

1. **Base image digest** (`FROM alpine:3.22@sha256:…`) — слой картинки на момент пина
2. **apk-пакеты по версии** (`apk add ca-certificates=20260413-r0`) — alpine допиливает версии пакетов внутри 3.22 (security updates), digest базы их не фиксит
3. **Go-модули** (`go.sum`) — уже есть

Без слоя 2 build сегодня и через месяц с тем же digest'ом могут затащить разные версии пакетов. Это hadolint DL3018 — реальная, не косметическая претензия.

### Процедура обновления пинов

```bash
# 1. Новый digest базы
docker buildx imagetools inspect alpine:3.22 --format '{{.Manifest.Digest}}'

# 2. Версии пакетов внутри обновлённой базы
docker run --rm <new-base-digest-ref> sh -c \
    'apk update -q && for p in ca-certificates ffmpeg tzdata netcat-openbsd; do
        v=$(apk search -x "$p" | sed -E "s/^${p}-//")
        echo "${p}=${v}"
    done'
```

Записать оба обновления одним коммитом — иначе расхождение базы и пакетов даёт нерепродьюсибельность.

## hadolint — какие правила НЕ подавлять

| Rule | Что значит | Решение |
|------|------------|---------|
| DL3018 | Pin apk versions | **Пинить**, не игнорировать. См. процедуру выше. |
| DL3006 | Tag the version of an image explicitly | Использовать digest-pin (`@sha256:…`) |
| DL3008 | Pin apt versions | Аналогично DL3018, но для apt |
| DL4006 | Use SHELL with pipefail | Если есть пайпы в RUN — `SHELL ["/bin/sh", "-o", "pipefail", "-c"]` |

Принцип форка: **никаких `# hadolint ignore=` для удобства** (см. memory `feedback-quality-over-speed`). Только если правило неприменимо (например, DL3025 на multiline JSON ENTRYPOINT — там подавление законно).

## Build network

Build container использует `--network=host` (commit 587c13e умышленно). Применять в:
- локально: `docker build --network=host …`
- compose: `build: { network: host }`
- CI: `docker/build-push-action` → `network: host`

## Healthcheck — функциональный, не liveness

Для контейнеров с локальным listener'ом — реальный probe. `pidof` это liveness, не health.

Пример (mode-aware):
```sh
case "${OLCRTC_MODE:-srv}" in
    cnc) nc -z "${OLCRTC_SOCKS_HOST:-127.0.0.1}" "${OLCRTC_SOCKS_PORT:-8808}" ;;
    srv|gen) pidof olcrtc >/dev/null 2>&1 ;;  # honestly liveness — нет local listener'а
esac
```

Для функциональной проверки `srv` нужно либо: side-channel timestamp last-pong в файл (требует правки Go), либо HTTP /health endpoint (новый код). Отдельный issue, не блокер.

## netcat в alpine

Базовый `busybox nc` **ненадёжно** поддерживает `-z` (port-scan mode) — на разных alpine-минорах разное поведение. Для healthcheck с `nc -z` ставим явно `netcat-openbsd`.

## Hardening flags для compose

Применять ко всем сервисам (через YAML anchor `x-hardening: &hardening`):

```yaml
init: true
restart: unless-stopped
read_only: true
tmpfs:
  - /tmp:size=16m
security_opt:
  - no-new-privileges:true
cap_drop: [ALL]
pids_limit: 256
mem_limit: 256m
cpus: "1.0"
logging:
  driver: json-file
  options: { max-size: "10m", max-file: "3" }
```

Если контейнеру нужно писать в `/var/lib/<app>` — volume mount (read_only обходится для конкретного пути).

## Secrets — через compose secrets, не env

```yaml
secrets:
  olcrtc_key: { file: ./secrets/olcrtc.key }

services:
  srv:
    secrets: [olcrtc_key]
    environment:
      OLCRTC_KEY_FILE: /run/secrets/olcrtc_key
```

Если entrypoint умеет читать `$KEY_FILE` — никаких патчей не нужно, просто маппинг.

## .dockerignore

Что точно исключать:
- VCS: `.git`, `.gitignore`, `.github`
- Tooling: `.claude`, `.remember`, `.golangci.yml`, `magefile.go`
- Docs: `*.md`, `docs/`
- Compose itself: `Dockerfile`, `compose.yaml`, `docker-compose*.yml`, `.env*`, `secrets/`
- Heavy test data: `internal/e2e/testdata/`

Не исключать: `data/` (если COPY из неё в образ), `go.mod`, `go.sum`.

## Multi-arch build

Локально — `mage docker` пока single-arch. CI workflow → `docker/build-push-action@v6` с `platforms: linux/amd64,linux/arm64`, QEMU emulation через `setup-qemu-action@v3`.

ARM64 build через QEMU медленный (~5–10 раз медленнее нативного). Если нужна нативная сборка — self-hosted ARM runner или GitHub-hosted `ubuntu-24.04-arm` (когда станут доступны для public репо).

## ffmpeg в образе

Сейчас в runtime установлен ffmpeg=6.1.2-r2 (~70 MB). Нужен только для `videochannel` transport. Slim-вариант без ffmpeg — отдельный issue, build-arg `WITH_FFMPEG=0`.

## Smoke-test образа после build

```bash
DOCKER_BUILDKIT=1 docker build --network=host -t olcrtc:test .
docker run --rm --entrypoint id olcrtc:test                          # не root
docker run --rm --entrypoint sh olcrtc:test -c 'which nc && nc -h'   # nc присутствует
docker images olcrtc:test --format '{{.Size}}'                       # размер vs prev
```

ENTRYPOINT нашего образа — это wrapper-скрипт, он перехватывает arg'и и пытается их передать в `olcrtc`. Для интроспекции нужен `--entrypoint`.

## Открытые вопросы / TODO

- Cosign-подпись образов после push в GHCR (Sigstore keyless через GitHub OIDC) — отдельный issue
- Renovate/Dependabot для авто-обновления digest + apk-pins — отдельный issue
- SBOM генерация (`syft`) → attach to release
- Trivy/Grype scan в CI before push

## Полезные источники

Использовать `mcp__plugin_context7_context7__query-docs` или `WebSearch` для:
- Docker reference (Dockerfile syntax, build flags)
- Alpine package versions / repo layout
- hadolint rule docs (https://github.com/hadolint/hadolint/wiki)
- GitHub Actions docker-related actions
