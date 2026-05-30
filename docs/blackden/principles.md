# Принципы работы (blackden-fork)

Живой документ. Описывает правила, по которым мы (ragnar + Claude) работаем в этом форке olcrtc. Дополняется по мере столкновений с новыми темами.

Документ читают:

- человек — глазами, когда нужно вспомнить «как правильно»;
- Claude — через skills (`.claude/skills/*.md`), которые срабатывают на соответствующих действиях и подтягивают нужный раздел в контекст.

Принципы — *не догма*. Любое правило можно нарушить, если есть осознанная причина. Но нарушение — явное, с комментарием в коде или PR, а не молчаливое.

---

## Содержание

- [Docker & Compose hygiene](#docker--compose-hygiene)
- [Go](#go)
- [Git & commits](#git--commits)
- [Что НЕ делать](#что-не-делать)

---

## Docker & Compose hygiene

### Образы

- **Multi-stage build** обязателен. Build-зависимости (`git`, тулчейн, заголовки) не должны попасть в runtime-слой.
- **Pinned base images** с явными тэгами. Не `alpine:latest` — `alpine:3.22`. По возможности — digest (`alpine:3.22@sha256:...`), но это можно делать постепенно.
- **Non-root runtime user** обязателен. `USER` директива в конце Dockerfile, не `root`. Создавать через `adduser -S` (system account, без shell, без пароля).
- **BuildKit cache mounts** для пакетных менеджеров: `--mount=type=cache,target=/go/pkg/mod`, `--mount=type=cache,target=/root/.cache/go-build`. Ускоряет повторные сборки на порядок.
- **`CGO_ENABLED=0`** для Go-бинарей, если cgo не нужен. Получается статический бинарь, можно ужимать в `scratch`/`distroless`. Сейчас оставляем alpine из-за ffmpeg.
- **`-trimpath -ldflags="-s -w"`** для production-сборок. Убирает пути сборки и debug-символы.
- **Multi-arch:** `docker buildx build --platform linux/amd64,linux/arm64`. Один и тот же образ должен работать на ноутбуке, на сервере и на MikroTik CHR.
- **`HEALTHCHECK`** должен проверять *функциональное* здоровье, а не только наличие процесса. `pidof <binary>` — это liveness, не health. Лучше: `nc -z` на сокете, HTTP-пинг, проверка свежести lock-файла.

### Compose-файлы

- **`version:` устарел.** Не пишем его. Compose сам понимает схему.
- **Один `compose.yaml`** с `profiles: [server, client]`, а не два отдельных файла. Запуск: `docker compose --profile server up`.
- **`name:`** в верхнем уровне — фиксирует имя проекта, чтобы оно не зависело от имени директории.
- **Security flags для каждого сервиса:**
  ```yaml
  security_opt:
    - no-new-privileges:true
  cap_drop:
    - ALL
  read_only: true        # rootfs только на чтение
  tmpfs:                 # под /tmp нужны записываемые места
    - /tmp
  pids_limit: 256
  mem_limit: 256m
  cpus: "1.0"
  ```
- **Логирование с ротацией.** Без этого `journalctl`/`/var/lib/docker` забивается за неделю:
  ```yaml
  logging:
    driver: json-file
    options:
      max-size: "10m"
      max-file: "3"
  ```
- **Секреты через `secrets:`**, не через env vars. Env vars видны в `docker inspect`, в логах, в `ps -ef`. Секрет монтируется как файл с правами 0400.
- **`env_file:`** когда переменных больше десятка. Список из 30 `OLCRTC_*` в самом compose-файле читать невозможно — вынести в `.env.example` рядом, реальный `.env` в `.gitignore`.
- **`init: true`** для контейнеров с одним процессом, чтобы PID 1 корректно ловил сигналы и собирал зомби.
- **`restart: unless-stopped`** для долгоживущих сервисов. Не `always` — `always` стартует даже после `docker stop`.

### `.dockerignore`

- **Выкидываем всё, что не нужно для сборки:** `.git/`, `.github/`, `.claude/`, `.remember/`, `docs/`, `*.md`, тесты (`*_test.go` оставляем, иначе пакет не соберётся, но можно выкинуть `internal/e2e/` если он не вкомпилируется), build-артефакты (`build/`, `dist/`, `*.exe`).
- Это и про скорость (контекст меньше → передача в Docker daemon быстрее), и про утечки (не уходит `.env`, `.git/`, `.claude/settings.json`).

### Healthcheck — что считать «здоровым»

Liveness (`pidof`) и readiness/health — разные вещи. Принцип:

- **`cnc` режим:** SOCKS-порт слушается → клиент жив. `nc -z 127.0.0.1 ${SOCKS_PORT}`. Этого мало для «комната работает», но достаточно как сигнал «процесс не повис».
- **`srv` режим:** в идеале — runtime сам пишет timestamp последнего успешного control-pong в файл `/var/lib/olcrtc/last_pong`, healthcheck смотрит что файл свежее N секунд. Реализация требует правки Go-кода — пока остаётся todo.
- **Никогда:** `curl https://...` к внешнему сервису как healthcheck. Это не про *наше* здоровье, это про чужое.

### Чеклист перед коммитом Docker-изменений

- [ ] Dockerfile: multi-stage, non-root, pinned base, cache mounts
- [ ] Compose: security_opt + cap_drop + read_only + tmpfs + limits + logging
- [ ] Secrets через `secrets:`, не env vars
- [ ] `env_file:` вместо длинного списка переменных
- [ ] Healthcheck измеряет функциональное здоровье или явно помечен «liveness only»
- [ ] `.dockerignore` не пускает в context лишнее
- [ ] `docker compose -f compose.yaml config -q` проходит без ошибок
- [ ] `hadolint Dockerfile` — без warnings (или явные `# hadolint ignore=...`)
- [ ] Multi-arch собирается: `docker buildx build --platform linux/amd64,linux/arm64`

---

## Go

Основной свод правил — в `.golangci.yml` (включено ~90 линтеров, строгий набор). Skill `go-hygiene` напоминает ключевые моменты при правке `*.go`. Здесь — то, что либо линтер не ловит, либо легко забыть.

### Ошибки

- **Wrap всегда:** `fmt.Errorf("doing X: %w", err)`. Без `%w` — теряем chain, `errors.Is/As` не работают.
- **`errors.New("…")` на лету запрещён** (`err113`). Sentinel-ошибки — в package-level переменных (`var ErrFoo = errors.New("foo")`), со `//nolint:gochecknoglobals // sentinel error` если глобал нельзя избежать.
- **Никаких `panic(err)`** в библиотечном коде. В `main`/инициализации — допустимо, но логируем причину.

### Архитектура

- olcrtc слоистый: `mode × auth.provider × engine × transport`. Каждый слой — отдельный пакет в `internal/`.
- **Новый transport / engine / auth — отдельная папка**, регистрируется через `Register(name, factory)` в `init()`. Не трогаем ядро.
- `internal/crypto`, `internal/muxconn`, `internal/handshake`, `internal/control` — backbone. Изменения тут ломают совместимость между клиентом и сервером. Поднимать версию протокола, не тихо менять.
- Публичные API — только в `pkg/olcrtc` и `pkg/olcrtc/tunnel`. Обратная совместимость соблюдается (поле `Carrier` сохранено как алиас для `Auth` именно по этой причине).

### Глобалы и init

- `gochecknoglobals` запрещён. Каждое исключение помечается `//nolint:gochecknoglobals // <одна строка причины>`. Без причины — `nolintlint` ругается.
- `gochecknoinits` тоже запрещён. Регистрация в `init()` — единственное общепринятое исключение, помечаем тем же образом.

### Логирование и печать

- `forbidigo` блокирует `fmt.Print*` и `print*`. Использовать `internal/logger` (или `slog`, если когда-нибудь переедем).
- В тестах допустимо `t.Log`, не `fmt.Println`.

### Тесты

- `go test -race -count=1 ./...` должен проходить локально перед коммитом.
- Real-provider e2e (`-olcrtc.real-e2e`) **не запускаем casually** — жжёт квоту у настоящих сервисов. Только когда явно проверяем работу с провайдером.
- Каждая новая фича — unit-тест минимум. Integration-тест — желательно, если затрагивает несколько слоёв.

### Прогон линтера

- Перед коммитом: `mage lint`. Если что-то ругается — фиксим, не суём `//nolint`. `nolint` — последнее средство, всегда с причиной.

### Чеклист перед коммитом Go-изменений

- [ ] `mage test` зелёный
- [ ] `mage lint` зелёный
- [ ] Новые глобалы / init — обоснованы и помечены `//nolint`
- [ ] Новый transport/engine/auth — через `Register()`, не через правку ядра
- [ ] Backbone (`crypto`, `muxconn`, `handshake`, `control`) не трогали без явной причины
- [ ] Публичный API в `pkg/` не сломал обратную совместимость

---

## Git & commits

### Ветки

- **`master`** — зеркало `upstream/master`. **Мы туда не коммитим**. Только `git merge upstream/master` при синке.
- **`blackden/master`** — наша долгоживущая интеграционная ветка. От неё ответвляются рабочие.
- **`blackden/<имя-фичи>`** — короткоживущие рабочие ветки. Сливаются в `blackden/master` после ревью.
- Upstream-синк: `git checkout master && git pull upstream master && git push origin master && git checkout blackden/master && git merge master`.

### Коммиты

- **Conventional Commits**, английский: `type(scope): message`.
- Типы: `feat`, `fix`, `docs`, `chore`, `refactor`, `test`, `ci`, `build`, `perf`.
- Scope — пакет/область: `feat(transport): …`, `fix(cnc): …`, `docs(blackden): …`.
- Заголовок до 72 символов, описывает *что и зачем*, не *какие файлы*.
- Тело (если нужно) — wrapped 72 символа, описывает мотивацию.
- **Никаких** `Generated with Claude Code`, `Co-Authored-By: Claude…`, эмодзи в заголовке. PR-template проекта явно запрещает «LLM slop». Это правило апстрима, мы его соблюдаем.

### Что НЕ коммитим

- `.env`, `*.key`, `key.hex` — никогда. Даже если случайно сгенерилось — в `.gitignore` и `git rm --cached`.
- `CLAUDE.md` — уже в `.gitignore` апстрима. Локальный файл, не наш артефакт.
- `build/`, `dist/`, артефакты сборки.
- `.DS_Store`, `Thumbs.db`, IDE-конфиги (`.vscode/`, `.idea/`) — если не часть проекта.

### Чеклист перед коммитом

- [ ] `git diff --staged` глазами просмотрен
- [ ] Сообщение в Conventional Commits
- [ ] Никаких упоминаний LLM/Claude/«generated by»
- [ ] Ветка — `blackden/*`, не `master`
- [ ] Секреты не уехали (особенно ключи)

---

## Что НЕ делать

Жирные нет-нет. Если ловлю себя на этом — стоп, переосмыслить:

- **`git push --force` в `master` или `blackden/master`.** В свои короткие ветки — можно (если ещё не пошли в PR). В долгоживущие — никогда.
- **`git commit --no-verify`.** Обходит pre-commit-хуки. Если хук ругается — фиксим причину, не глушим хук. Хук `block-no-verify.sh` это блокирует автоматически.
- **`mage lint` skipping.** Если ругается — фиксим. Не `//nolint`.
- **Коммит секретов.** Любых. Хук пока не ловит, дисциплина.
- **Изменение backbone-протокола без bump версии.** `crypto`, `muxconn`, `handshake`, `control` — тихо не трогаем.
- **Real e2e «на всякий случай».** Жжёт квоту. Только когда есть конкретная гипотеза для проверки.
- **Добавление новой зависимости без обоснования.** `go.mod` растёт — supply chain risk растёт. Каждая новая зависимость — спросить «можно ли без неё».
