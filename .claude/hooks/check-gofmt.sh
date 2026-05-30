#!/bin/sh
# PostToolUse hook: on Edit/Write of *.go, ensure gofmt is happy.
# Exits 2 to push the diagnostic into Claude's context if formatting differs.
set -eu

input=$(cat)
file=$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty' 2>/dev/null || true)

case "$file" in
    *.go) ;;
    *) exit 0 ;;
esac

[ -f "$file" ] || exit 0
command -v gofmt >/dev/null 2>&1 || exit 0

out=$(gofmt -l "$file" 2>&1 || true)
if [ -n "$out" ]; then
    printf 'gofmt: %s is not formatted.\nRun: gofmt -w %s\n' "$file" "$file" >&2
    exit 2
fi

exit 0
