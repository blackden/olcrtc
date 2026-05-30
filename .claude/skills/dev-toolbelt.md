---
name: dev-toolbelt
description: Triggers when running developer commands (go/mage/golangci-lint/docker) in the blackden/olcrtc repo. Reminds about the make-based toolbelt and the docker fallback when local Go is absent. Do NOT trigger this skill for production runtime concerns (compose up, GHCR push) — those have their own guides.
---

# Dev toolbelt (blackden/olcrtc)

В этом форке есть единый toolbelt — **`make`** в корне репо. Не вызывай `go test ./...` / `mage test` / `golangci-lint run` напрямую без причины.

## Что использовать

| Хочу… | Команда |
|-------|---------|
| Прогнать все unit-тесты | `make test` |
| Прогнать один тест N раз (поиск флака) | `make test-stress TEST='^TestX$' N=50 [RACE=1]` |
| Линт | `make lint` |
| Собрать бинарь | `make build` |
| Собрать docker-образ | `make docker` |
| `compose up` для профиля | `make up PROFILE=server\|client\|gen` |
| Понять, что вообще установлено | `make doctor` |
| Полный список | `make help` |

## Почему make, а не go/mage напрямую

- Пользователь работает с этим репо в окружении **без локального Go** — `make` детектирует это и фолбэчит на `script/dev/in-docker.sh` (`golang:1.26-alpine` с volume-cache)
- Каноничный раннер для CI — `mage`. Make — для повседневной локальной эргономики; правила выше дублирующиеся не пиши
- Если правишь `Makefile` или `script/dev/in-docker.sh`: смоук-тест `make doctor && make compose-check` обязательно

## Чего НЕ делать

- Не предлагай `go install …` если задача — просто запустить тесты. `make test` уже работает через docker
- Не дублируй mage-таргеты в Makefile без причины — Makefile вызывает либо go напрямую, либо mage, не оба
- Не убирай `--network=host` из `script/dev/in-docker.sh` (нужен для `go mod download` через корпоративные прокси, см. CLAUDE.md)

## Источники

- `docs/blackden/dev.md` — полный гайд для пользователя
- `Makefile` — сам toolbelt; `make help` показывает текущий список
- `script/dev/in-docker.sh` — docker-обёртка
