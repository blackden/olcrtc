<div align="center">

<img src="https://github.com/openlibrecommunity/material/blob/master/olcrtc.png" width="250" height="250">

![License](https://img.shields.io/badge/license-WTFPL-0D1117?style=flat-square&logo=open-source-initiative&logoColor=green&labelColor=0D1117)
![Golang](https://img.shields.io/badge/-Golang-0D1117?style=flat-square&logo=go&logoColor=00A7D0)

</div>

## About

**olcRTC** — encrypted TCP-over-WebRTC tunnel. Парасайтит на легальных видеоконф-сервисах (Jitsi, Yandex Telemost, WB Stream) — туннелируемый трафик выглядит как обычный видеозвонок для whitelisted-хоста.

Это **blackden** — форк с усиленным Docker-стеком, multi-arch GHCR-образами, гайдами под MikroTik CHR и dev-toolbelt'ом. Совместим с апстримом по протоколу.

## Status

Beta. Issues / questions → [@openlibrecommunity](https://t.me/openlibrecommunity)
Community UI client: [alananisimov/olcbox](https://github.com/alananisimov/olcbox)

---

## Быстрый старт (blackden fork)

### Просто запустить и протестировать

1. На VPS и ноуте — Docker и `git clone https://github.com/blackden/olcrtc.git`
2. Подробный гайд end-to-end (srv на VPS + cnc на ноуте + curl-проверка): [`docs/blackden/manual-test.md`](docs/blackden/manual-test.md)

### Разрабатывать на форке

`make help` показывает toolbelt. Локального Go не требует — все таргеты прозрачно фолбэчат на `golang:1.26-alpine` в Docker'е. Подробно: [`docs/blackden/dev.md`](docs/blackden/dev.md)

```sh
make doctor          # что установлено локально, что через docker
make test            # go test -race ./... (~1 минута)
make build           # static binary в build/olcrtc
make compose-check   # валидация compose.yaml для всех профилей
```

### Деплой на MikroTik CHR / RouterBoard

[`docs/blackden/mikrotik-chr.md`](docs/blackden/mikrotik-chr.md) — поднять `cnc` прямо на роутере, раздать SOCKS5 в LAN.

### Получить образ из GHCR

```sh
docker pull ghcr.io/blackden/olcrtc:latest
```

Образ приватный (намеренно). Авторизация и теги: [`docs/blackden/ghcr.md`](docs/blackden/ghcr.md).

---

## Документация

### Практическая

- [Manual testing (Docker, srv+cnc)](docs/blackden/manual-test.md) — реальный first-run end-to-end
- [Development toolbelt](docs/blackden/dev.md) — `make`, тесты, линт, docker-wrapper
- [Docker setup](docs/docker.md) — детали `compose.yaml`, профили, secrets
- [MikroTik CHR deployment](docs/blackden/mikrotik-chr.md)
- [GHCR (образы и теги)](docs/blackden/ghcr.md)

### Справочная

- [Configuration](docs/configuration.md) — все `OLCRTC_*` env-переменные
- [Settings matrix](docs/settings.md) — совместимость carrier × transport
- [Manual build (без Docker)](docs/manual.md)
- [Fast mode (legacy scripts)](docs/fast.md)
- [Client URI format](docs/uri.md)
- [Client subscription format](docs/sub.md)
- [Architecture overview](docs/about.md)

### Принципы и workflow форка

- [Principles](docs/blackden/principles.md) — Docker/Go/Git hygiene, чего НЕ делать
- [Phase B summary](docs/blackden/phase-b.md) — что было сделано в Docker-hardening epic
- [GitHub MCP workflow](docs/blackden/github-mcp.md) — Issues → PR процесс

---

<div align="center">

---

Telegram: [zarazaex](https://t.me/zarazaexe)
<br>
Email: [zarazaex@tuta.io](mailto:zarazaex@tuta.io)
<br>
Site: [zarazaex.xyz](https://zarazaex.xyz)

</div>
