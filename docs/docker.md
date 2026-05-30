<div align="center">

<img src="https://github.com/openlibrecommunity/material/blob/master/olcrtc.png" width="250" height="250">

![License](https://img.shields.io/badge/license-WTFPL-0D1117?style=flat-square&logo=open-source-initiative&logoColor=green&labelColor=0D1117)
![Golang](https://img.shields.io/badge/-Golang-0D1117?style=flat-square&logo=go&logoColor=00A7D0)

</div>


# Локальная настройка Docker

> **Важно:** Обязательно проверяйте, есть ли сервис видеозвонков у вас в белых списках. Если его там нет — используйте другой. Список всех сервисов в белых списках скоро будет опубликован.

> **Jitsi-провайдер:** если используете `jitsi`, выбирайте сервер в зависимости от того, что доступно в вашей сети:
> - `https://meet1.arbitr.ru/`
> - `https://meet.cryptopro.ru/`
>
> Откройте оба в браузере и используйте тот, который работает.


Запуск olcrtc через единый `compose.yaml` с профилями `server` / `client` / `gen`.

## Идея

- один `compose.yaml` в корне репо с тремя профилями (вместо двух раздельных файлов)
- секрет `crypto.key` через compose `secrets:`, а не env var
- остальные настройки — через `.env` (gitignored), шаблон в `.env.example`
- hardening-флаги (read-only fs, cap_drop ALL, no-new-privileges, лимиты, ротация логов) применяются ко всем сервисам

---

## Шаг 1: Клонирование репозитория

```bash
git clone --recursive https://github.com/blackden/olcrtc.git
cd olcrtc
```

---

## Шаг 2: Подготовить ключ шифрования

64 hex-символа, идентичный на server и client. Сгенерировать на сервере:

```bash
mkdir -p secrets
openssl rand -hex 32 > secrets/olcrtc.key
chmod 600 secrets/olcrtc.key
```

Этот же файл нужно скопировать на client (через защищённый канал).

---

## Шаг 3: Подготовить `.env`

```bash
cp .env.example .env
$EDITOR .env
```

Минимум, что нужно задать: `OLCRTC_CARRIER`, `OLCRTC_TRANSPORT`, `OLCRTC_ROOM_ID`.

Подробно про переменные — комментарии в `.env.example` и [`settings.md`](settings.md).

---

## Шаг 4: Запуск

### Сервер (egress на хосте за пределами whitelist)

```bash
docker compose --profile server up -d
docker compose --profile server logs -f srv
```

### Клиент (локальный SOCKS5 на 127.0.0.1:8808)

```bash
docker compose --profile client up -d
docker compose --profile client logs -f cnc
```

### Генератор room-id (для провайдеров, требующих pre-allocated)

```bash
docker compose --profile gen run --rm gen
```

---

## Шаг 5: Проверка состояния

```bash
docker compose ps                       # все запущенные сервисы
docker compose --profile client ps      # только client-профиль
```

Healthcheck для `cnc` проверяет, что локальный SOCKS5-listener принимает соединения. Для `srv` healthcheck — это liveness-проверка процесса (отдельная задача — добавить функциональный health).

---

## Шаг 6: Pull опубликованного образа (опционально)

Образ автоматически собирается и пушится на GHCR по адресу `ghcr.io/blackden/olcrtc:latest`, но **package приватный** — нужен `docker login` с PAT (scope `read:packages`):

```bash
echo "$GITHUB_PAT_READ_PACKAGES" | docker login ghcr.io -u <github-user> --password-stdin
docker compose pull
docker compose --profile server up -d
```

Альтернатива — собирать локально из исходников (build-блок уже прописан в `compose.yaml`):

```bash
git pull
docker compose --profile server build
docker compose --profile server up -d
```

Подробнее про GHCR — [`blackden/ghcr.md`](blackden/ghcr.md).

## Шаг 7: Обновление

Свежий код → новый билд:

```bash
git pull --recurse-submodules
docker compose --profile server build --pull
docker compose --profile server up -d
```

Или (если используете GHCR-pull) — просто `docker compose pull && docker compose up -d` после того, как CI прокатил новый коммит и спушил образ.

---

## Примечания

- `.env` — в `.gitignore`; в репо хранится только `.env.example`
- `secrets/olcrtc.key` — в `.gitignore`; должен быть `chmod 600`
- Volumes `olcrtc-srv-state` и `olcrtc-cnc-state` сохраняют состояние между перезапусками — в них entrypoint при первом запуске `srv` может сохранить сгенерированный ключ, если `secrets/olcrtc.key` пуст или отсутствует
- Все сервисы запускаются с `read_only: true`; `/tmp` доступен через `tmpfs`, конфиг и состояние — через volume

---

Используешь скрипты вместо Docker? -> [Быстрый старт](fast.md)

Хочешь собрать руками без контейнеров? -> [Мануальная сборка](manual.md)

Все настройки и матрица совместимости -> [settings.md](settings.md)
