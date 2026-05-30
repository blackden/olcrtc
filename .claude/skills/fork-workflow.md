---
name: fork-workflow
description: Use whenever working in the blackden/olcrtc fork — pre-commit gates (lint/hadolint/compose-config), secret handling, hook policy, MCP-over-CLI preference, host-network build mandate. Triggers on Edit/Write/Bash in this repo, especially when committing, pushing, opening PRs, editing Dockerfile/compose/workflows, or running mage/docker.
---

# Workflow для blackden/olcrtc

Umbrella для общих правил форка. Узкоспециальные правила — в соседних скиллах:
`[[commit-fork]]` (branch policy + Conventional Commits), `[[docker-hygiene]]`, `[[go-hygiene]]`.

## Источники истины

| Тема | Где искать |
|------|------------|
| Принципы DevOps / Docker / Go / Git | `docs/blackden/principles.md` |
| Issue/PR workflow + MCP | `docs/blackden/github-mcp.md` |
| Архитектура (4-axis, registry pattern) | корневой `CLAUDE.md` |
| Хуки и их код | `.claude/hooks/*.sh` — открыть, если хук блокирует |
| GHCR / релизы | `docs/blackden/ghcr.md` (после Phase B) |
| CHR / RouterOS-деплой | `docs/blackden/mikrotik-chr.md` (после Phase B) |

## Гейты перед коммитом

Только если соответствующие файлы реально затронуты:

| Затронуто | Команда |
|-----------|---------|
| Go (`*.go`, `go.mod`, `go.sum`) | `mage lint` + `mage test` |
| `Dockerfile` | `hadolint Dockerfile` |
| `compose.yaml` | `docker compose config --profiles` (узнать профили) → затем `docker compose --profile <name> config -q` на каждый |
| `.github/workflows/*.yml` | `actionlint <file>` если установлен; иначе ручной review |
| Shell-скрипты | `shellcheck <file>` если установлен |

Если `mage` не установлен — `command -v mage || echo "install: go install github.com/magefile/mage@latest"` и не падать молча на `go test` без расовых флагов; mage обёртка корректнее.

PostToolUse-хук `check-gofmt.sh` уже правит форматирование автоматически — но lint всё равно нужен.

## Ветка + коммит

Полные правила — `[[commit-fork]]` (включая branch table, push policy, Conventional Commits format). Перед коммитом всегда:

```bash
git branch --show-current   # не master!
```

## Хуки и обходы

Запрещены без явного пользовательского разрешения:

- `git commit --no-verify` / `--no-gpg-sign` / `-c commit.gpgsign=false` — блок `block-no-verify.sh`
- `git push --force` на `master` или `blackden/master`
- `git push` в `master` — блок `block-push-master.sh`

Если хук падает — открыть `.claude/hooks/<имя>.sh`, понять причину, починить.

## Секреты

Никогда не выводить содержимое:

- `crypto.key` / `OLCRTC_KEY` / `secrets/olcrtc.key`
- GitHub PAT (`GITHUB_PERSONAL_ACCESS_TOKEN`)
- `~/.claude.json`, `~/.zshenv`, `~/.zshrc`
- `.env`

Безопасные проверки:
- `[ -n "$VAR" ]` — есть ли значение
- `wc -c <file>` — размер
- `sha256sum <file> | cut -c1-12` — стабильный fingerprint (для бинарных ключей лучше чем `head`)

Файлы с секретами: `chmod 600`. Прецедент: PAT уже утекал через `grep ~/.zshrc` — не повторять. `.env` в `.gitignore`; commit'ить только `.env.example`.

## MCP > CLI

Когда MCP-инструмент покрывает задачу — используем его:

| Задача | MCP |
|--------|-----|
| Issue/PR/labels-read на GitHub | `mcp__github__*` |
| Чтение удалённых файлов | `mcp__github__get_file_contents` |

Исключения, где MCP не покрывает: создание labels (`gh api repos/.../labels`), низкоуровневые git, локальный docker.

## Docker build — host network

Build-контейнер использует `--network=host` (commit 587c13e, умышленно). При правках:

- `compose.yaml` build-блок: `build: { context: ., network: host }`
- `.github/workflows/docker.yml`: `docker/build-push-action` → `network: host`
- Локально: `docker build --network=host .` (уже в `mage docker`)

Не убирать без обсуждения.

## Subprocess hygiene

- Submodule `internal/transport/videochannel/gr`: после `git checkout` ветки делать `git submodule update --init --recursive` если submodule-state изменилось
- CI клонирует с `submodules: recursive` — локально надо вручную
