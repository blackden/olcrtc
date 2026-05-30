---
name: go-hygiene
description: Use when editing any *.go file in the olcrtc codebase. Reminds the strict golangci-lint expectations, error wrapping discipline, the registry-pattern architecture, and the backbone-stability rule.
---

# Go hygiene checklist

The full ruleset is `.golangci.yml` (~90 linters enabled). This skill summarizes the gotchas.

## Before editing — orient

If non-obvious: `Read docs/blackden/principles.md` section "Go". For architecture orientation use `CLAUDE.md` (top-level).

## Errors

- Always wrap with `%w`: `fmt.Errorf("doing X: %w", err)`. Without `%w`, `errors.Is/As` break downstream.
- No `errors.New("...")` inline (forbidden by `err113`). Use sentinel errors at package level:
  ```go
  var ErrFoo = errors.New("foo") //nolint:gochecknoglobals // sentinel error
  ```
- No `panic(err)` in library code. In `main` or init — OK, but log first.

## Globals & init

- `gochecknoglobals` is on. Every package-level variable needs `//nolint:gochecknoglobals // <one-line reason>`.
- `gochecknoinits` is on. Registry pattern (`engine.Register(...)` in `init()`) is the standard exception — same nolint.

## Logging

- `fmt.Print*` is forbidden (`forbidigo`). Use `internal/logger`. In tests use `t.Log`, not `fmt.Println`.

## Architecture — where to add things

olcrtc has four orthogonal axes: `mode × auth.provider × engine × transport`. Each is a separate package, plugged in via `Register()`.

- **New transport** → `internal/transport/<name>/`, register in `init()`
- **New engine (SFU protocol)** → `internal/engine/<name>/`, register in `init()`
- **New auth provider** → `internal/auth/<name>/`, register via `internal/engine/builtin`
- **New YAML field** → `internal/config` + `internal/app/session` validation/defaults + `docs/*.md`

## Don't touch lightly

Backbone packages — changing these breaks wire compatibility between client/server:

- `internal/crypto` (XChaCha20-Poly1305)
- `internal/muxconn` (encrypted byte pipe)
- `internal/handshake` (`CLIENT_HELLO/SERVER_WELCOME`)
- `internal/control` (`CONTROL_PING/PONG`)

If you must — bump a protocol version, don't silently change.

## Public API

`pkg/olcrtc` and `pkg/olcrtc/tunnel` are *public surface*. The `Carrier` field is a back-compat alias for `Auth` — preserve patterns like this.

## Before commit

- `mage test` green
- `mage lint` green
- No real-provider e2e runs unless deliberately testing a provider (burns API quota)
- `//nolint:` only with a one-line reason; never bare

## Red flag

If you find yourself adding `//nolint` to silence the linter, ask first: is this the right design? `//nolint` is the last resort, not the first.
