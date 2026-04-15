#!/usr/bin/env bash
# Toggle between default Anthropic API and a custom provider.
# When the env file exists, claudebox uses it; when removed, it falls back
# to the default Anthropic API with your ANTHROPIC_API_KEY.
#
# Usage: ./toggle-provider.sh
#        Restart your claudebox container after toggling.

ENV_FILE="${CLAUDEBOX_HOME:-$HOME/.claudebox}/env"

if [[ -f "$ENV_FILE" ]]; then
    mv "$ENV_FILE" "${ENV_FILE}.bak"
    printf 'Provider: Anthropic (direct) — env file disabled\n'
elif [[ -f "${ENV_FILE}.bak" ]]; then
    mv "${ENV_FILE}.bak" "$ENV_FILE"
    printf 'Provider: Custom (env file) — env file enabled\n'
else
    printf 'No env file found at %s or %s.bak\n' "$ENV_FILE" "$ENV_FILE"
    exit 1
fi
printf 'Restart container to apply.\n'
