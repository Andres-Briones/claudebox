#!/usr/bin/env bash
# Toggle the provider section in ~/.claudebox/env on/off without touching
# the rest of the file (e.g. git identity, EMAIL, future persistent settings).
#
# The provider section is delimited by:
#     # === PROVIDER START ===
#     ...lines...
#     # === PROVIDER END ===
#
# Disabling the section rewrites every non-comment, non-blank line inside
# it as `#__OFF__ <original line>` and renames the START marker to
# `# === PROVIDER START (disabled) ===`. Re-enabling reverses both steps.
# User comments inside the section (lines that already start with `#`) are
# preserved verbatim across toggles.
#
# Usage:
#   toggle-provider.sh            # flip current state
#   Restart any running claudebox slot for the change to take effect.

set -Eeuo pipefail
IFS=$'\n\t'

ENV_FILE="${CLAUDEBOX_HOME:-$HOME/.claudebox}/env"

if [[ ! -f "$ENV_FILE" ]]; then
    printf 'No env file at %s. See examples/env.example.\n' "$ENV_FILE" >&2
    exit 1
fi

if grep -q '^# === PROVIDER START (disabled) ===$' "$ENV_FILE"; then
    state=disabled
elif grep -q '^# === PROVIDER START ===$' "$ENV_FILE"; then
    state=enabled
else
    printf 'No PROVIDER markers found in %s.\n' "$ENV_FILE" >&2
    printf 'Wrap your provider lines with `# === PROVIDER START ===` and\n' >&2
    printf '`# === PROVIDER END ===` (see examples/env.example).\n' >&2
    exit 1
fi

tmp="$(mktemp "${TMPDIR:-/tmp}/claudebox-env.XXXXXX")"
trap 'rm -f "$tmp"' EXIT

if [[ "$state" == enabled ]]; then
    awk '
        /^# === PROVIDER START ===$/ {
            print "# === PROVIDER START (disabled) ==="
            in_block = 1
            next
        }
        /^# === PROVIDER END ===$/ {
            in_block = 0
            print
            next
        }
        in_block && !/^[[:space:]]*#/ && !/^[[:space:]]*$/ {
            print "#__OFF__ " $0
            next
        }
        { print }
    ' "$ENV_FILE" > "$tmp"
    mv "$tmp" "$ENV_FILE"
    trap - EXIT
    printf 'Provider: Anthropic (direct) — provider section disabled.\n'
else
    awk '
        /^# === PROVIDER START \(disabled\) ===$/ {
            print "# === PROVIDER START ==="
            in_block = 1
            next
        }
        /^# === PROVIDER END ===$/ {
            in_block = 0
            print
            next
        }
        in_block && /^#__OFF__ / {
            sub(/^#__OFF__ /, "")
            print
            next
        }
        { print }
    ' "$ENV_FILE" > "$tmp"
    mv "$tmp" "$ENV_FILE"
    trap - EXIT
    printf 'Provider: custom — provider section enabled.\n'
fi

printf 'Restart any running slot to apply.\n'
