---
name: commit-fork
description: Use before any git commit in this fork. Enforces Conventional Commits style, the no-LLM-slop rule from the upstream PR template, and the branch policy (master stays clean for upstream syncs).
---

# Commit hygiene (blackden fork)

This is a fork of openlibrecommunity/olcrtc. Special rules apply.

## Before committing — orient

Full policy: `Read docs/blackden/principles.md` section "Git & commits".

## Branch check (do this FIRST)

```bash
git branch --show-current
```

- **`master`** — DO NOT COMMIT. Upstream mirror, only `git merge upstream/master` allowed.
- **`blackden/master`** — long-lived integration. Avoid direct commits; prefer PR from `blackden/<feature>`.
- **`blackden/<anything>`** — short-lived working branches. Commit freely.

If on `master` and about to commit: stop, switch to or create a `blackden/*` branch first.

## Commit message format

Conventional Commits, English:

```
<type>(<scope>): <short summary, <72 chars>

<optional body, wrapped to 72 chars, explains *why* not *what*>
```

**Types:** `feat`, `fix`, `docs`, `chore`, `refactor`, `test`, `ci`, `build`, `perf`.

**Scope examples:** `cnc`, `srv`, `transport`, `engine`, `auth`, `docs`, `blackden`, `docker`, `compose`.

**Examples from this project's history:**
- `fix(cnc): use host network mode for build container`
- `docs: add Russian walkthrough explaining project from scratch`
- `fix(jitsi): add RTCP keepalive to prevent JVB session expiry`

## NEVER include in commit messages

These are upstream PR-template rules ("No LLM slop"). The hook doesn't block them — discipline does.

- `🤖 Generated with Claude Code` or any "generated with X" line
- `Co-Authored-By: Claude <...>` or any Claude/LLM trailer
- Emoji in the title
- Verbose "I did X then Y then Z" narratives — keep summaries factual

## Files NOT to commit

- `.env`, `*.key`, `key.hex` — secrets, ever
- `CLAUDE.md` — already in upstream `.gitignore`
- `build/`, `dist/` — artifacts
- `.DS_Store`, IDE configs unless project-owned

## What to verify before commit

- [ ] On a `blackden/*` branch (not `master`)
- [ ] `git diff --staged` reviewed
- [ ] `mage lint` green (for Go changes)
- [ ] `mage test` green (for Go changes)
- [ ] No secrets in diff
- [ ] Conventional Commits message
- [ ] No LLM/Claude trailer

## Push policy

- Push to `origin blackden/*` freely
- Never `git push --force` to `master` or `blackden/master`
- Never push to `master` at all — it's just `upstream/master` mirrored

The hook `block-push-master` blocks pushes to master automatically.
