#!/bin/sh
# PreToolUse hook on Bash: block any 'git push' targeting master.
# master is reserved as a mirror of upstream. Work happens on blackden/* branches.
set -eu

input=$(cat)
cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null || true)

if printf '%s' "$cmd" | grep -Eq 'git[[:space:]]+push([[:space:]]+[^[:space:]]+)*[[:space:]]+(origin[[:space:]]+)?(master|HEAD:master)([[:space:]]|$)'; then
    printf 'BLOCKED: pushing to master is forbidden.\n' >&2
    printf 'master is reserved as a mirror of upstream/master.\n' >&2
    printf 'Push to a blackden/* branch instead.\n' >&2
    exit 2
fi

exit 0
