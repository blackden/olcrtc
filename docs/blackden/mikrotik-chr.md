# MikroTik CHR — развёртывание olcrtc через container package

Поднимаем `olcrtc cnc` (или `srv`) прямо на роутере под управлением RouterOS. Цель — SOCKS5-прокси в LAN без отдельной железки. Подходит и для CHR (Cloud Hosted Router, x86_64), и для физических RouterBoard'ов с поддержкой `container` (arm/arm64/x86_64).

> **Важно:** Обязательно проверяйте, есть ли используемый сервис видеозвонков в актуальных белых списках. Если его там нет — выбирайте другой.

## Требования

- RouterOS **v7.8+** (минимум для registry auth — нужно для GHCR-pull, если образ private; для public достаточно v7.4)
- Включённый `container` package (см. шаг 1)
- ≥ 256 MB свободной RAM (по реальному наблюдению; больше — лучше)
- Внешний диск/раздел (`disk1/`) для root-dir контейнера и mount'ов. Встроенный flash MikroTik отговаривает.
- На CHR-сценарии — `x86_64` образ (наш multi-arch покрывает); на ARM-RouterBoard — `arm64`/`arm` соответственно

Архитектуры, поддерживаемые `container`: arm, arm64, x86. Слабые SoC (EN7562CT, hEX Refresh) — только arm32v5, наш образ туда не пойдёт.

---

## Шаг 1. Включить container package

Делается один раз, требует **перезагрузки** и физического подтверждения (на CHR — просто reboot, на железе — short press кнопки reset во время boot).

```routeros
/system/device-mode/update container=yes
```

После reboot:

```routeros
/system/package/print
```

В списке должна появиться строка `container <enabled>`.

---

## Шаг 2. Сконфигурировать container

Указываем registry, временную папку для распаковки слоёв, мягкий лимит RAM:

```routeros
/container/config/set \
    registry-url=https://ghcr.io \
    tmpdir=disk1/cont/tmp \
    ram-high=256M
```

Если ваш image приватный — добавить:

```routeros
/container/config/set username=<github-user> password=<PAT-with-read:packages>
```

Для нашего публичного `ghcr.io/blackden/olcrtc` это не нужно (после флипа visibility в public; см. [`ghcr.md`](ghcr.md)).

---

## Шаг 3. Сеть для контейнера

veth + bridge + IP на bridge + NAT для исходящего трафика контейнера:

```routeros
/interface/veth/add name=veth-olcrtc address=172.20.0.2/24 gateway=172.20.0.1
/interface/bridge/add name=br-cont
/ip/address/add address=172.20.0.1/24 interface=br-cont
/interface/bridge/port/add bridge=br-cont interface=veth-olcrtc
/ip/firewall/nat/add chain=srcnat action=masquerade src-address=172.20.0.0/24
```

Если нужен SOCKS5 из LAN — добавить DNAT с LAN-bridge на `172.20.0.2:8808`:

```routeros
/ip/firewall/nat/add chain=dstnat action=dst-nat in-interface=bridge-lan \
    protocol=tcp dst-port=8808 to-addresses=172.20.0.2 to-ports=8808
```

(Подставьте свой `in-interface` под LAN.)

---

## Шаг 4. Подготовить storage и environment

```routeros
/container/envs/add list=ENV_OLCRTC key=OLCRTC_MODE value=cnc
/container/envs/add list=ENV_OLCRTC key=OLCRTC_CARRIER value=jitsi
/container/envs/add list=ENV_OLCRTC key=OLCRTC_TRANSPORT value=datachannel
/container/envs/add list=ENV_OLCRTC key=OLCRTC_ROOM_ID value=<room-id-from-server>
/container/envs/add list=ENV_OLCRTC key=OLCRTC_KEY value=<64-hex-from-server>
/container/envs/add list=ENV_OLCRTC key=OLCRTC_SOCKS_HOST value=0.0.0.0
/container/envs/add list=ENV_OLCRTC key=OLCRTC_SOCKS_PORT value=8808

# Persistent storage для key/конфига
/container/mounts/add list=MOUNT_OLCRTC src=disk1/cont/olcrtc/state dst=/var/lib/olcrtc
```

> **Внимание:** `OLCRTC_KEY` идёт в открытом виде в env-list. На RouterOS нет secrets-механизма уровня docker compose. Если параноишь — положи 64-hex в файл на `disk1/cont/olcrtc/state/key.hex` и через env `OLCRTC_KEY_FILE=/var/lib/olcrtc/key.hex` (этот путь уже дефолт в образе).

> **SOCKS_HOST=0.0.0.0** на контейнере вместо `127.0.0.1` — иначе SOCKS5 listener будет слушать только loopback внутри контейнера, и DNAT с роутера не пройдёт.

---

## Шаг 5. Создать и запустить контейнер

```routeros
/container/add \
    remote-image=ghcr.io/blackden/olcrtc:latest \
    interface=veth-olcrtc \
    root-dir=disk1/cont/olcrtc/root \
    envlist=ENV_OLCRTC \
    mountlists=MOUNT_OLCRTC \
    name=olcrtc-cnc \
    start-on-boot=yes \
    logging=yes
```

Подождать пока RouterOS дотянет слои (минуты на медленном линке):

```routeros
/container/print
```

Когда `status` станет `stopped` (после extraction):

```routeros
/container/start olcrtc-cnc
```

Через 10–30 секунд:

```routeros
/container/print detail
```

Поле `status=running`.

---

## Шаг 6. Проверка

Лог контейнера (RouterOS пишет в системный лог с topic `container`):

```routeros
/log/print where topics~"container"
```

Войти в контейнер для дебага:

```routeros
/container/shell [find name=olcrtc-cnc]
```

Внутри:

```sh
nc -z 0.0.0.0 8808 && echo "SOCKS5 listening"
ps
```

С хост-роутера или из LAN — `curl --socks5 172.20.0.2:8808 https://ifconfig.me` (с LAN — через ваш DNAT).

---

## Troubleshooting

| Симптом | Причина | Что делать |
|---------|---------|------------|
| `failed to pull` | Нет резолва `ghcr.io` | Проверить `/ip/dns` — DNS-сервер должен быть рабочий и достижимый |
| `not enough space` | Мало места на `disk1` | Проверить `/file/print`; убрать `tmpdir`/`root-dir` на бо́льший раздел |
| `container exited immediately` | Неверные env (carrier/transport не настроены, или KEY не 64 hex) | `log/print` — entrypoint пишет конкретную ошибку валидации |
| `manifest unknown` для arm64 | Workflow не собрал arm64 | Проверить `gh run list -R blackden/olcrtc -w docker` |
| `denied: requested access to the resource is denied` | Образ ещё private | Флипнуть на public, [`ghcr.md`](ghcr.md) |
| Не подключается клиент через SOCKS | SOCKS_HOST=127.0.0.1 | См. шаг 4 — должно быть `0.0.0.0` |

---

## Готовый скрипт

Все шаги одним файлом — [`script/mikrotik/install.rsc`](../../script/mikrotik/install.rsc). Отредактируй переменные вверху и импортни:

```routeros
/import file-name=install.rsc
```

---

## srv на CHR

В принципе работает аналогично, разница только в env:

```routeros
/container/envs/add list=ENV_OLCRTC key=OLCRTC_MODE value=srv
```

И не нужен DNAT с LAN — `srv` устанавливает исходящие соединения к видеоконф-сервису.

---

## Безопасность

- Контейнер с `cap_drop ALL` и `no-new-privileges` (как в нашем `compose.yaml`) на RouterOS **не работает** — `container` package не поддерживает Linux capabilities или security_opt. Доверяете образу так же, как самому RouterOS.
- LAN-клиенты, которые могут резолвить роутер, получат прямой SOCKS5-прокси — фильтруйте DNAT по `src-address-list` если не хотите wide-open
