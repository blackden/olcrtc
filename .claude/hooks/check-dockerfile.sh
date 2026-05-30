#!/bin/sh
# PostToolUse hook: on Edit/Write of a Dockerfile, run hadolint.
# Skips silently if hadolint is not installed.
set -eu

input=$(cat)
file=$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty' 2>/dev/null || true)

case "$file" in
    *Dockerfile|*Dockerfile.*|*.Dockerfile) ;;
    *) exit 0 ;;
esac

[ -f "$file" ] || exit 0
command -v hadolint >/dev/null 2>&1 || exit 0

if ! out=$(hadolint "$file" 2>&1); then
    printf 'hadolint: %s has warnings:\n%s\n' "$file" "$out" >&2
    exit 2
fi

exit 0
