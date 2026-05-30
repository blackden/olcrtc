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

## Одноразовый шаг: сделать package публичным

После **первого** push образ создаётся **приватным** — GitHub так делает по умолчанию для GHCR. **REST API для смены visibility нет** (проверено через docs.github.com/en/rest/packages — endpoint'а попросту не существует). Только через Web UI:

1. Открыть https://github.com/blackden?tab=packages (или https://github.com/blackden/packages)
2. Кликнуть на пакет `olcrtc`
3. На странице пакета — иконка шестерёнки **«Package settings»** справа внизу
4. Прокрутить до **«Danger Zone»** в самом низу
5. **«Change visibility»** → **«Public»**
6. Подтвердить вводом имени пакета (`olcrtc`) и нажатием «I understand the consequences, change package visibility»

> ⚠️ **Это нельзя откатить.** Раз сделанный package public нельзя сделать обратно private — будет только удалить и пересоздать заново.

После этого `docker pull ghcr.io/blackden/olcrtc:latest` работает без `docker login`.

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
| `denied: requested access to the resource is denied` | Package private | См. "сделать публичным" выше |
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
