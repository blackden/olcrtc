#!/bin/sh
# PreToolUse hook on Bash: block git commands that bypass hooks or signing.
# Fixing the underlying problem is always preferred over bypassing the check.
set -eu

input=$(cat)
cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null || true)

if printf '%s' "$cmd" | grep -Eq '(--no-verify|--no-gpg-sign|-c[[:space:]]+commit\.gpgsign=false)'; then
    printf 'BLOCKED: --no-verify / --no-gpg-sign bypass pre-commit hooks or signing.\n' >&2
    printf 'Fix the underlying issue (failing hook, missing key) instead of skipping it.\n' >&2
    exit 2
fi

exit 0
