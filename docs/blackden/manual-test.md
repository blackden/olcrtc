# Ручное тестирование — srv на VPS + cnc на ноуте, через Docker

Гайд для первого реального запуска olcrtc end-to-end. Используется **только Docker** (без локальной Go-сборки) и наш `compose.yaml`. По итогу — рабочий SOCKS5-прокси на ноуте, трафик которого выходит из VPS, маскируясь под видеоконф.

> **Важно:** Обязательно проверяйте, есть ли используемый сервис видеозвонков в актуальных белых списках. Если его там нет — выбирайте другой.

## Что понадобится

| Машина | Требования |
|--------|------------|
| **VPS (server)** | Linux, root/sudo, Docker 20+, открытый исходящий 443/tcp к выбранному видеосервису. Минимум 256 MB RAM. |
| **Ноут (client)** | macOS или Linux, Docker Desktop / Docker Engine, локальная сеть с интернетом. |
| **Видеосервис** | Jitsi (рекомендую для первого раза) или WB Stream (вторым шагом). Аккаунт не нужен для Jitsi. |

Оба узла используют **один и тот же** образ из GHCR: `ghcr.io/blackden/olcrtc:latest`. Образ приватный — нужен GitHub PAT с `read:packages` для `docker login ghcr.io`. См. [`ghcr.md`](ghcr.md). Альтернатива: собрать локально через `make docker` и заюзать тег `olcrtc:dev`.

---

## Дорожка A — Jitsi + datachannel (рекомендую начать с этого)

Самый простой путь. `datachannel` использует нативный WebRTC `RTCDataChannel`, Jitsi его честно прокидывает.

### Шаг 0. Выбрать публичный Jitsi-инстанс

Открой в браузере на ноуте оба:

- https://meet1.arbitr.ru/
- https://meet.cryptopro.ru/

Выбери тот, который у тебя открывается без VPN. Запомни хост — он пойдёт в `OLCRTC_ROOM_ID`.

### Шаг 1. Сгенерировать `crypto.key` (64 hex)

На любой машине (проще на ноуте, потом скопируем на VPS):

```sh
mkdir -p secrets
openssl rand -hex 32 > secrets/olcrtc.key
chmod 600 secrets/olcrtc.key
cat secrets/olcrtc.key   # запиши, она понадобится для VPS
```

> Ключ должен быть **идентичен** на srv и cnc. Если разные — handshake не пройдёт, в логах будет тишина или decrypt-ошибка.

### Шаг 2. Придумать Room ID

Любая URL вида `https://<host>/<room>` где `<room>` — придуманная тобой строка (8–32 символа `[A-Za-z0-9-]`):

```
https://meet1.arbitr.ru/olcrtc-test-7f3a2b
```

`<room>` — это и есть твоя комната. Создавать заранее не надо: srv сам её «откроет» при подключении.

### Шаг 3. Подготовить `.env`

Шаблон есть в `.env.example`. Скопируй и отредактируй:

```sh
cp .env.example .env
```

Минимальный `.env` для Jitsi:

```sh
OLCRTC_CARRIER=jitsi
OLCRTC_TRANSPORT=datachannel
OLCRTC_ROOM_ID=https://meet1.arbitr.ru/olcrtc-test-7f3a2b

# Только для cnc:
OLCRTC_SOCKS_HOST=127.0.0.1
OLCRTC_SOCKS_PORT=8808

OLCRTC_DNS=8.8.8.8:53
OLCRTC_DEBUG=false
```

Этот же `.env` поедет на **обе** машины (VPS и ноут). Compose сам выберет роль через `--profile server` или `--profile client`.

### Шаг 4. Раскатать на VPS

Заходим на VPS:

```sh
ssh root@<vps>
git clone https://github.com/blackden/olcrtc.git
cd olcrtc
git checkout blackden/master
```

Скопируй ключ и `.env` с ноута (через scp с ноута):

```sh
# на ноуте
scp secrets/olcrtc.key root@<vps>:/root/olcrtc/secrets/
scp .env root@<vps>:/root/olcrtc/
```

На VPS — залогинься в GHCR (один раз):

```sh
echo $GITHUB_PAT | docker login ghcr.io -u <github-username> --password-stdin
```

Запусти `srv`:

```sh
docker compose --profile server up -d
docker compose ps                # status = running, healthy
docker compose --profile server logs -f srv
```

Что должен показать лог:

```
level=info msg="olcrtc starting" mode=srv carrier=jitsi transport=datachannel
level=info msg="connecting to jitsi" url=https://meet1.arbitr.ru/...
level=info msg="control: SERVER_WELCOME sent" peer=<id>
level=info msg="server ready, waiting for tunnel streams"
```

Если есть `connecting` но нет `SERVER_WELCOME` за 30 секунд — карриер не пускает (whitelist? сеть?). Смени Jitsi-хост (см. шаг 0).

### Шаг 5. Запустить cnc на ноуте

В корне репо на ноуте:

```sh
make up PROFILE=client
make logs PROFILE=client
```

Что ждать в логах:

```
level=info msg="olcrtc starting" mode=cnc carrier=jitsi transport=datachannel
level=info msg="control: CLIENT_HELLO sent"
level=info msg="control: SERVER_WELCOME received"
level=info msg="SOCKS5 listener accepting" addr=127.0.0.1:8808
```

### Шаг 6. Проверить тоннель

В **другом** терминале на ноуте:

```sh
curl --socks5-hostname 127.0.0.1:8808 https://ifconfig.me
```

Должен вернуться **IP твоего VPS**, не IP ноута. Если так — туннель работает.

Дополнительные проверки:

```sh
curl --socks5-hostname 127.0.0.1:8808 -sS https://api.github.com/zen
curl --socks5-hostname 127.0.0.1:8808 -sS https://www.google.com -o /dev/null -w '%{http_code}\n'
```

### Шаг 7. Остановить

На обеих машинах:

```sh
make down                          # ноут
docker compose --profile server down  # VPS (если нет make)
```

---

## Дорожка B — WB Stream + vp8channel

WB Stream guest-flow не пускает `datachannel` (нет capability `canPublishData`), поэтому туннель закатываем в видеопоток через `vp8channel` — KCP поверх VP8-фреймов.

### Шаг 0. Создать комнату

WB Stream требует комнату через UI. Открой https://stream.wb.ru, начни трансляцию или встречу, скопируй room ID из URL — это будет последний path-сегмент.

Пример формата `OLCRTC_ROOM_ID` для wbstream — см. сценарии в `internal/auth/wbstream/` или попроси live-помощь, формат меняется по мере того как WB ломает API.

### Шаг 1. Подменить `.env`

```sh
OLCRTC_CARRIER=wbstream
OLCRTC_TRANSPORT=vp8channel
OLCRTC_ROOM_ID=<id-из-URL>

# Опциональные параметры транспорта (см. .env.example):
# OLCRTC_VP8_FPS=60
# OLCRTC_VP8_BATCH=64
```

### Шаг 2. Перезапустить srv + cnc

VPS:

```sh
docker compose --profile server down
docker compose --profile server up -d
```

Ноут:

```sh
make down
make up PROFILE=client
make logs PROFILE=client
```

### Шаг 3. Проверить

Тот же `curl --socks5-hostname 127.0.0.1:8808 https://ifconfig.me`. Ожидай **больший пинг** (~300–800 ms vs ~50–100 ms на datachannel) и пропускную способность поменьше.

---

## Где смотреть когда что-то не так

| Симптом | Куда смотреть |
|---------|---------------|
| `srv` не стартует | `docker compose --profile server logs srv` — обычно ошибка валидации env (несовпадение типа carrier/transport) |
| `cnc` стартует, но curl зависает | logs `cnc` — должно быть `SERVER_WELCOME received`. Если только `CLIENT_HELLO sent` — srv не отвечает, проблема на той стороне. |
| `decrypt error` или `unexpected hmac` | Ключи на srv и cnc различаются. `sha256sum secrets/olcrtc.key` на обеих машинах должен совпадать. |
| `unexpected SOCKS5 reply: [5 4 0 1 ...]` | Туннель ещё в процессе reconnect. Подожди 10 секунд, повтори curl. Если воспроизводимо — баг в reconnect-логике. |
| Jitsi пишет `forbidden` или `404` | Хост заблокировал — смени `meet1.arbitr.ru` ↔ `meet.cryptopro.ru` или подними свой Jitsi. |
| WB Stream сразу падает | Их API меняется. Проверь актуальный room-id-формат в `internal/auth/wbstream/*.go`. |
| `image pull denied` от GHCR | PAT без `read:packages` или не залогинен `docker login ghcr.io`. См. [`ghcr.md`](ghcr.md). |
| Высокий CPU на VPS | `vp8channel` / `videochannel` грузят сильно. Нормально для них. `datachannel` — единицы процентов. |

Сбор логов одним архивом:

```sh
docker compose --profile server logs --no-color srv > srv.log    # на VPS
make logs PROFILE=client --no-color > cnc.log                    # на ноуте
```

---

## Что протестировать вторым проходом

- [ ] Перезагрузка VPS — `srv` должен автоподняться (`restart: unless-stopped` стоит в `compose.yaml`)
- [ ] Долгое окно — оставить curl/wget на 30 минут, убедиться что control-ping не падает
- [ ] Параллельные стримы — открыть 5 curl одновременно, должны работать через smux
- [ ] Failover — добавить `profiles[]` в YAML с двумя комнатами, убить одну на VPS, cnc должен переключиться (см. [`principles.md`](principles.md) про supervisor)
- [ ] Реальный браузер — поставить SOCKS5 в браузере (`127.0.0.1:8808`), посмотреть YouTube; нагрузка на canal должна быть стабильной

---

## Следующие шаги

- [`dev.md`](dev.md) — toolbelt для разработки (make/тесты/линт)
- [`principles.md`](principles.md) — правила работы, Docker hygiene
- [`ghcr.md`](ghcr.md) — образы, теги, видимость
- [`mikrotik-chr.md`](mikrotik-chr.md) — поднять `cnc` на RouterOS, чтобы SOCKS5 раздавался всему LAN'у
- Корневой `docs/configuration.md` / `docs/settings.md` — все 35+ `OLCRTC_*` env-vars, матрица carrier × transport
