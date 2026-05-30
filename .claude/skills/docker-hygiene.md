---
name: docker-hygiene
description: Use when editing Dockerfile, compose.yaml, docker-compose*.yml, .dockerignore, or anything related to container packaging/runtime. Reminds the operational hygiene checklist and points to the full principles doc.
---

# Docker hygiene checklist

When touching Docker/Compose files, verify these before declaring work done.

## Before editing — orient

If non-obvious: `Read docs/blackden/principles.md` section "Docker & Compose hygiene". It's the canonical source. This skill is a checklist; the doc has the reasoning.

## Dockerfile checklist

- Multi-stage build, build deps stay in build layer
- Base image pinned with explicit tag (`alpine:3.22`, not `:latest`)
- Non-root `USER` at the end (system account: `adduser -S`)
- BuildKit cache mounts for package managers (`--mount=type=cache,target=/go/pkg/mod`)
- Go: `CGO_ENABLED=0`, `-trimpath -ldflags="-s -w"` for production
- `HEALTHCHECK` measures *functional* health, or is explicitly labelled liveness-only

## Compose checklist

- No `version:` field (deprecated)
- One `compose.yaml` with `profiles:` instead of multiple files (where it makes sense)
- Each service has:
  - `security_opt: [no-new-privileges:true]`
  - `cap_drop: [ALL]` (only add back what's strictly needed)
  - `read_only: true` + `tmpfs: [/tmp]` (or other writable paths)
  - `pids_limit:`, `mem_limit:`, `cpus:`
  - `logging:` with `max-size` and `max-file`
  - `init: true` for single-process containers
  - `restart: unless-stopped` (not `always`)
- Secrets via `secrets:`, never raw env vars for sensitive material
- 10+ env vars → move to `env_file:`

## `.dockerignore` checklist

- Excludes: `.git/`, `.github/`, `.claude/`, `.remember/`, `docs/`, `*.md`, build artifacts, secrets
- Doesn't accidentally exclude `script/` or anything COPY-needed

## Verification

After editing, run mentally (and trust the hooks to verify):

- `docker compose -f compose.yaml config -q` — syntax valid
- `hadolint Dockerfile` — no warnings (or `# hadolint ignore=` with reason)
- If multi-arch claim: `docker buildx build --platform linux/amd64,linux/arm64 .` succeeds

## When in doubt

The principles doc has the *why* behind each rule. If a constraint seems wrong for the current case, read the why first — there may be a reason. If there genuinely isn't, the rule can be overridden with an explicit comment.
