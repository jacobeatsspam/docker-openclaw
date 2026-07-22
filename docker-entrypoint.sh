#!/usr/bin/env bash
set -euo pipefail

OPENCLAW_HOME="${OPENCLAW_HOME:-${HOME}/.openclaw}"
CONFIG_PATH="${OPENCLAW_CONFIG_PATH:-${OPENCLAW_HOME}/openclaw.json}"

mkdir -p "${OPENCLAW_HOME}" "$(dirname "${CONFIG_PATH}")"

tmpfile="$(mktemp)"
cleanup() {
  rm -f "$tmpfile"
}
trap cleanup EXIT

if [[ -f "$CONFIG_PATH" ]]; then
  jq '
    .plugins |= (. // {})
    | .plugins.entries |= (. // {})
    | .plugins.entries.diffs |= (. // {})
    | .plugins.entries.diffs |= if has("enabled") then . else . + { enabled: true } end
    | .plugins.entries.lobster |= (. // {})
    | .plugins.entries.lobster |= if has("enabled") then . else . + { enabled: true } end
    | .plugins.entries["google-meet"] |= (. // {})
    | .plugins.entries["google-meet"] |= if has("enabled") then . else . + { enabled: true } end
  ' "$CONFIG_PATH" > "$tmpfile"
else
  jq -n '{
    plugins: {
      entries: {
        diffs: { enabled: true },
        lobster: { enabled: true },
        "google-meet": { enabled: true }
      }
    }
  }' > "$tmpfile"
fi

mv "$tmpfile" "$CONFIG_PATH"

exec "$@"
