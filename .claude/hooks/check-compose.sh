#!/bin/sh
# PostToolUse hook: on Edit/Write of a compose file, validate its syntax.
# Skips silently if docker is not installed.
set -eu

input=$(cat)
file=$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty' 2>/dev/null || true)

case "$file" in
    *compose.yaml|*compose.yml|*docker-compose*.yml|*docker-compose*.yaml) ;;
    *) exit 0 ;;
esac

[ -f "$file" ] || exit 0
command -v docker >/dev/null 2>&1 || exit 0

if ! out=$(docker compose -f "$file" config -q 2>&1); then
    printf 'docker compose: %s is invalid:\n%s\n' "$file" "$out" >&2
    exit 2
fi

exit 0
