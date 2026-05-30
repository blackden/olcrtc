# GitHub MCP — настройка и workflow с Issues

Этот документ — про то, как мы (ragnar + Claude) подключаем GitHub MCP-сервер к Claude Code и используем GitHub Issues как долговременный список задач blackden-форка.

## Зачем

- **Issues** = постоянный, видимый снаружи реестр того, что мы делаем. Переживает рестарты сессии Claude, виден на github.com, индексируется поиском.
- **TaskCreate** внутри Claude Code = эфемерные подзадачи внутри одной сессии. Короткоживущие, не уходят в репо.
- **MCP-сервер** = мост между ними. Из чата Claude мы можем создавать/закрывать/комментировать issues, не уходя в браузер.

Принцип: **значимое — в Issues**. Внутрисессионные мелочи остаются в TaskCreate. Если работа займёт больше одной сессии или результат хочется явно зафиксировать — заводим issue.

---

## Подключение MCP-сервера

### Шаг 1. Создать GitHub PAT (Personal Access Token)

Рекомендуем **fine-grained token** (новый формат, явные права на конкретные репозитории), а не classic.

1. Открыть https://github.com/settings/personal-access-tokens/new
2. **Token name:** `olcrtc-claude-mcp` (или любое осмысленное)
3. **Expiration:** 90 дней или меньше; ставим напоминалку обновить
4. **Repository access:** Only select repositories → выбрать `blackden/olcrtc`
   - Когда добавим `blackden/olcbox` как субмодуль — добавить и его в список
5. **Permissions → Repository:**
   - Contents: Read and write
   - Issues: Read and write
   - Pull requests: Read and write
   - Metadata: Read-only (включается автоматически)
6. **Permissions → Account:** ничего не трогаем

Сохранить токен в безопасное место. После закрытия страницы он больше не показывается.

### Шаг 2. Положить токен в env

В `~/.zshrc` (или `~/.zshenv`):

```bash
export GITHUB_PERSONAL_ACCESS_TOKEN="ghp_..."
```

Перезагрузить шелл: `source ~/.zshrc`. Проверить: `echo $GITHUB_PERSONAL_ACCESS_TOKEN | head -c 10`.

**Не коммитим** токен ни в `.mcp.json`, ни в `.env`, ни куда-либо в репо.

### Шаг 3. Зарегистрировать MCP-сервер в Claude Code

Используем официальный образ от GitHub — `ghcr.io/github/github-mcp-server`. Команда:

```bash
claude mcp add github \
  -- docker run -i --rm \
  -e GITHUB_PERSONAL_ACCESS_TOKEN \
  ghcr.io/github/github-mcp-server
```

Это добавит сервер в **user-level** конфиг (`~/.claude.json`). Если хочешь чтобы он подцеплялся только в этом проекте — используй `--scope project`, конфиг попадёт в `.mcp.json` рядом с репо. Для одного PAT user-level проще.

### Шаг 4. Проверить

```bash
claude mcp list
```

Должна быть строка вида `github: docker run -i --rm ...`. После рестарта сессии Claude в списке доступных tools появятся `mcp__github__*`.

### Альтернатива: GitHub-hosted remote MCP

Есть и хостимый вариант — `https://api.githubcopilot.com/mcp/`, авторизация через OAuth, не нужен ни PAT, ни Docker:

```bash
claude mcp add github --transport http https://api.githubcopilot.com/mcp/
```

Это удобнее, но привязано к Copilot-подписке и работает не во всех тарифах. PAT-вариант надёжнее как fallback.

---

## Включение Issues на форке

У форков GitHub Issues по умолчанию **выключены**. Включаем:

1. Открыть https://github.com/blackden/olcrtc/settings
2. Прокрутить до раздела «Features»
3. Поставить галку «Issues»

После этого `gh issue list -R blackden/olcrtc` должен не падать с ошибкой.

---

## Issue workflow

### Когда заводим issue

- Работа займёт больше одной сессии Claude
- Результат хочется зафиксировать (отчёт, чеклист, исторический след)
- Есть гипотеза/баг, который надо проверить не сейчас, но позже
- Работа имеет внешнюю важность (security, breaking change)

### Когда НЕ заводим

- Внутри одной сессии: проще TaskCreate
- Однострочный фикс, который сразу коммитим
- Эксперимент, который выбросим

### Формат title

Тот же стиль, что и у коммитов — Conventional Commits-подобный:

- `feat(transport): add room rotation via shared PRF`
- `chore(docker): multi-arch buildx + slim variant`
- `docs(blackden): document MikroTik CHR setup`
- `fix(jitsi): handle JVB session expiry`

Короткие, понятные на одной строке. Подробности — в теле issue.

### Формат тела

Минимум:

```markdown
## Цель
Один абзац: что хотим получить и зачем.

## Подзадачи
- [ ] первая
- [ ] вторая
- [ ] третья

## Критерии готовности
Когда мы считаем эту работу завершённой.

## Заметки
Контекст, ссылки на обсуждения, связанные issues.
```

### Labels (предлагаемая таксономия)

При первом использовании MCP создадим их разом.

**Area (где работа):**
- `area/docker` — Dockerfile, compose, контейнеры
- `area/go` — Go-код в `cmd/`, `pkg/`, `internal/`
- `area/transport` — слой transport
- `area/engine` — слой engine
- `area/auth` — auth providers
- `area/docs` — документация
- `area/ci` — workflows, mage targets
- `area/blackden` — fork-only стафф (этот документ, principles, skills)

**Type (что за работа):**
- `type/feat` — новая фича
- `type/fix` — баг
- `type/refactor` — рефакторинг
- `type/chore` — рутина (deps, configs)
- `type/research` — гипотеза/спайк
- `type/docs` — документация

**Priority:**
- `prio/high` — блокирует другое
- `prio/normal` — обычный поток
- `prio/low` — когда-нибудь

**Status (опционально, если поедем в Projects-board):**
- `status/blocked` — ждём чего-то

### Связь Issue ↔ Commit ↔ PR

В сообщении коммита:

- `refs #N` — связать без закрытия
- `closes #N` / `fixes #N` — закрыть при merge в default branch

Default branch для нас — `blackden/master`, не `master`. То есть `closes` сработает только при PR `blackden/<feature>` → `blackden/master`, что нам и нужно.

---

## Чеклист по этой настройке

- [ ] PAT создан и сохранён в `~/.zshrc`
- [ ] `claude mcp add github` выполнено
- [ ] `claude mcp list` показывает github
- [ ] Issues включены в settings репо
- [ ] Сессия Claude перезапущена, появились `mcp__github__*` tools
- [ ] Создан первый тестовый issue → закрыт
- [ ] Labels по таксономии созданы

---

## Если что-то пошло не так

- `claude mcp list` пусто → `~/.claude.json` не сохранил конфиг, перезапусти `claude` без флагов
- `mcp__github__*` не появляется в tools → перезапусти сессию Claude (в `/mcp` посмотри статус сервера)
- Docker MCP падает с auth error → токен не пробрасывается, проверь `echo $GITHUB_PERSONAL_ACCESS_TOKEN`
- Issues не создаются с правильными правами → fine-grained token не включил «Issues: Read and write» для нужного репо
