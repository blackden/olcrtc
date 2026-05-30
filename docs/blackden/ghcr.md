# GHCR — публикация и использование образов

Multi-arch образы olcrtc публикуются в `ghcr.io/blackden/olcrtc` через GitHub Actions workflow [`docker.yml`](../../.github/workflows/docker.yml).

## Тег-схема

| Тег | Что значит | Когда обновляется |
|-----|------------|-------------------|
| `:latest` | Последний коммит в `blackden/master` | На каждый push в default branch |
| `:blackden-master` | То же что `:latest`, но явное имя ветки | На каждый push в `blackden/master` |
| `:sha-<full-sha>` | Конкретный коммит | На каждый push |
| `:<version>` (например `:1.4.2`) | Семвер-тег | На push тега `v*` |
| `:<major>.<minor>` (например `:1.4`) | Скользящий semver | На push тега `v*` |

## Платформы

`linux/amd64` + `linux/arm64`. ARM64 собирается через QEMU emulation (медленнее нативного ~5–10×, но достаточно для нашего профиля).

## OCI labels

В образе:
- `org.opencontainers.image.source=https://github.com/blackden/olcrtc`
- `org.opencontainers.image.licenses=WTFPL`
- `org.opencontainers.image.description=...`
- `org.opencontainers.image.revision=<sha>` (через `metadata-action`)
- `org.opencontainers.image.created=<RFC3339>` (через `metadata-action`)

Plus SLSA provenance attestation и SBOM (включены в workflow).

## Visibility — пакет остаётся приватным

Решение по этому форку: **package на GHCR остаётся private**. Причина — операция «private → public» через GHCR Web UI **необратима** (вернуть в private нельзя, можно только удалить пакет и пересоздать с нуля), а REST API для этого нет.

Это значит, что для `docker pull ghcr.io/blackden/olcrtc:<tag>` нужен логин:

```bash
# PAT с scope read:packages — создать на https://github.com/settings/personal-access-tokens
echo "$GITHUB_PAT_READ_PACKAGES" | docker login ghcr.io -u blackden --password-stdin

docker pull ghcr.io/blackden/olcrtc:latest
```

Для MikroTik CHR — см. [`mikrotik-chr.md`](mikrotik-chr.md) (там в `/container/config/set` задаётся `username`/`password`).

### Если когда-нибудь понадобится публичный доступ

Не флипать GHCR (необратимо). Вместо этого — зеркалить образ в Docker Hub отдельным workflow:

- `ghcr.io/blackden/olcrtc:<tag>` (приватный, источник истины)
- `docker.io/blackden/olcrtc:<tag>` (публичная копия)

Эта работа — отдельный issue (открыт как опциональный follow-up).

## Использование

### Локально

```bash
docker pull ghcr.io/blackden/olcrtc:latest
```

В `compose.yaml` (наш дефолт):
```yaml
image: ${OLCRTC_IMAGE:-ghcr.io/blackden/olcrtc:latest}
```

Чтобы использовать конкретный тег — экспорт переменной:
```bash
OLCRTC_IMAGE=ghcr.io/blackden/olcrtc:sha-<commit> docker compose --profile client up -d
```

### MikroTik CHR

См. [`mikrotik-chr.md`](mikrotik-chr.md) (после Phase B).

## Если pull не работает

| Симптом | Причина | Что делать |
|---------|---------|------------|
| `denied: requested access to the resource is denied` | Не залогинены в GHCR | `docker login ghcr.io -u blackden -p <PAT>` |
| `manifest unknown` | Образ ещё не собрался | Проверить статус workflow: `gh run list -R blackden/olcrtc -w docker` |
| `no matching manifest for linux/arm64/v8` | Образ собрался только под amd64 | Запустить workflow заново (могла упасть arm64-сборка) |

## Локальный multi-arch build

Workflow всегда лучше, но для дебага:

```bash
docker buildx create --use --name olcrtc-mb --driver docker-container
docker buildx build \
    --platform linux/amd64,linux/arm64 \
    --network=host \
    --tag ghcr.io/blackden/olcrtc:local \
    --push \
    .
```

Для push нужен `docker login ghcr.io -u blackden -p <PAT с write:packages>`.

## Обновление action-версий

Workflow пинит actions по мажорному тегу (`@v7`, `@v6`, `@v4`). Перед апгрейдом — проверить changelog через context7:

```
mcp__plugin_context7_context7__query-docs /docker/build-push-action — breaking changes since v6
```

Если выпустили v8 — обновить `docker.yml` и проверить вручную dispatch'ем.

## TODO

- Cosign-подпись через GitHub OIDC (keyless) — отдельный issue
- Slim-вариант без ffmpeg (build-arg `WITH_FFMPEG=0`) — отдельный issue
- Trivy/Grype scan перед push — отдельный issue
