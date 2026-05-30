# Локальная разработка — toolbelt

Кратко: `make help` показывает всё. Этот документ — про *как пользоваться* и *что под капотом*.

> **Важно:** Обязательно проверяйте, есть ли используемый сервис видеозвонков в актуальных белых списках. Если его там нет — выбирайте другой.

## Две дорожки

| Условие | Что использовать | Чем нагружено |
|---------|------------------|---------------|
| Установлен Go 1.26+ (`go version` работает) | `mage <target>` или `make <target>` | mage — каноничный; make — короче для повседневных задач |
| Нет Go локально | `make <target>` | Прозрачно фолбэчит в `script/dev/in-docker.sh` (`golang:1.26-alpine`) |

Проверить состояние тулчейна: `make doctor`.

## Часто используемые таргеты

| Команда | Что делает |
|---------|------------|
| `make help` | Список всех таргетов |
| `make doctor` | Диагностика: что установлено, что фолбэчится в docker |
| `make test` | `go test -race -count=1 ./...` (10–30 минут) |
| `make test-stress TEST='^TestName$' N=50 [RACE=1]` | Прогон одного теста N раз — для отлова флаков |
| `make build` | Бинарь в `build/olcrtc` |
| `make lint` | `golangci-lint run ./...` (по `.golangci.yml`) |
| `make tidy` | `go mod tidy` |
| `make docker` | Локальный образ `olcrtc:dev` |
| `make up PROFILE=server` | `docker compose --profile server up -d` |
| `make down` | Остановить все compose-сервисы |
| `make logs PROFILE=server` | Хвост логов |
| `make compose-check` | Валидация `compose.yaml` для всех профилей |
| `make clean` | Удалить `build/`, `dist/` |
| `make clean-cache` | Удалить docker-volume-кэши Go (форсит fresh `go mod download`) |

## Под капотом: docker-фолбэк

`script/dev/in-docker.sh` — тонкая обёртка над `docker run`:

- Образ: `golang:1.26-alpine3.22` (тот же digest, что в production-`Dockerfile`)
- Persistent volumes для `/go/pkg/mod` и `/root/.cache/go-build` (имена `olcrtc-dev-gomod`, `olcrtc-dev-gocache`)
- `--network=host` (нужно для go-mod-download через корпоративные прокси)
- `CGO_ENABLED=0`

Прямой вызов:

```sh
./script/dev/in-docker.sh go version
./script/dev/in-docker.sh sh -c 'go env && ls /go/pkg/mod | head'
```

Образ можно переопределить:

```sh
DEV_GO_IMAGE=golang:1.27-alpine ./script/dev/in-docker.sh go version
```

## Типичные рецепты

### Отловить флак-тест

```sh
make test-stress TEST='^TestFrequentReconnectsStillAllowNewSOCKSConnections$' N=100
```

Если хоть один из 100 упал — флак. `RACE=1` замедляет goroutines и часто прячет тайминг-баги — полезно для сравнения.

### Запустить SOCKS-клиент в Docker

```sh
cp .env.example .env
# отредактировать .env под свой room/key/carrier
echo '<64-hex>' > secrets/olcrtc.key
chmod 600 secrets/olcrtc.key
make up PROFILE=client
make logs PROFILE=client
```

Остановить: `make down`.

### Проверить compose-конфиг перед коммитом

```sh
make compose-check
```

### Регенерировать go.sum после правки go.mod

```sh
make tidy
git diff go.sum
```

## Что НЕ покрывает Makefile

- Релизные multi-arch-сборки → `mage docker` с `DOCKER_PLATFORMS`/`DOCKER_PUSH` (см. `docs/blackden/ghcr.md`)
- E2E против реальных провайдеров (`-olcrtc.real-e2e`) — нагружает чужие сервисы; запускается осознанно через прямой `go test`
- Mobile (`mage mobile` / `gomobile bind`) — требует Android SDK локально, docker-фолбэка нет

Эти задачи — для `mage`, который остаётся каноничным раннером (см. `magefile.go`).

## Когда что-то не так

| Симптом | Куда смотреть |
|---------|---------------|
| `docker: command not found` | Установить Docker Desktop или Podman + docker-shim |
| Первая команда висит минутами | Pull pinned base image; `docker pull golang:1.26-alpine3.22` руками |
| `make: *** missing separator` | Кто-то заменил табы пробелами в `Makefile`. `git diff Makefile` |
| Лимиты по CPU/RAM в compose не применились | `compose.yaml` использует `read_only` — нужен writable `tmpfs` для `/tmp`; см. `docs/blackden/principles.md` |
| `go: module ... cannot find` после смены ветки | `make clean-cache && make tidy` |

Глубже — `docs/blackden/principles.md` (правила) и корневой `CLAUDE.md` (архитектура).
