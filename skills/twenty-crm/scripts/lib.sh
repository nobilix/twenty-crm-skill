#!/usr/bin/env bash
# Shared helpers for twenty-crm skill scripts. Source this; never exec.
# Public functions are prefixed `tw_`. Errors go to stderr; exit codes propagate.

set -euo pipefail

# Our own tiny state dir. Holds config.json — a pointer to the ocli profile
# name(s). The token, base URL, and resolved spec are owned by ocli under
# ~/.ocli (see TW_OCLI_* below); we never duplicate them.
# shellcheck disable=SC2034
TW_CONFIG_DIR="${TW_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/twenty-cli}"
# shellcheck disable=SC2034
TW_CONFIG_FILE="$TW_CONFIG_DIR/config.json"

# ocli's standard config home. $HOME honored via os.homedir(). profiles.ini is
# an INI file (one [section] per profile) holding api_base_url + api_bearer_token;
# resolved specs are cached under specs/<profile>.json.
# shellcheck disable=SC2034
TW_OCLI_HOME="$HOME/.ocli"
# shellcheck disable=SC2034
TW_OCLI_INI="$TW_OCLI_HOME/profiles.ini"

# The pinned ocli package — single source of truth for the install/upgrade hint.
# Bump deliberately after re-testing the round-trip (the dep has no git tags).
# shellcheck disable=SC2034
TW_OCLI_PKG="openapi-to-cli@0.1.15"

tw_die() { printf 'twenty-cli: %s\n' "$*" >&2; exit 1; }

tw_require() {
  command -v "$1" >/dev/null 2>&1 || tw_die "missing dependency: $1"
}

# tw_ocli <args...> — run ocli with cwd=$HOME so its config resolves to ~/.ocli.
# ocli (config.ts:resolveConfig) defaults to $PWD/.ocli when neither $PWD/.ocli
# nor ~/.ocli has a profiles.ini yet; from $HOME, $PWD/.ocli IS ~/.ocli, so
# every write lands there regardless of where the script was invoked from.
tw_ocli() { ( cd "$HOME" && ocli "$@" ); }

# tw_config_get <key> — read a top-level scalar from our config.json (empty if
# absent or file missing). Used for: profile, metadata_profile.
tw_config_get() {
  [ -f "$TW_CONFIG_FILE" ] || return 0
  jq -r --arg k "$1" '.[$k] // empty' "$TW_CONFIG_FILE"
}

# tw_ini_get <section> <key> — value of <key> within [<section>] of the ocli
# profiles.ini. ocli writes plain `key=value` lines; the value is preserved
# verbatim (kept intact even if it contains '='). Empty if not found.
tw_ini_get() {
  [ -f "$TW_OCLI_INI" ] || return 0
  awk -v sec="[$1]" -v key="$2" '
    /^\[/        { in_sec = ($0 == sec); next }
    in_sec {
      eq = index($0, "=")
      if (eq > 0) {
        k = substr($0, 1, eq - 1); gsub(/^[ \t]+|[ \t]+$/, "", k)
        if (k == key) { print substr($0, eq + 1); exit }
      }
    }
  ' "$TW_OCLI_INI"
}

# tw_fetch_spec <url> <token> <out-file>
# ocli does NOT send auth when fetching a spec, so we pre-download it ourselves.
# Validates HTTP 200 and that the body is OpenAPI JSON. Atomic via tmp.
tw_fetch_spec() {
  local url="$1" tok="$2" out="$3"
  local tmp; tmp=$(mktemp "${out}.XXXXXX")
  local http
  http=$(curl -sS -o "$tmp" -w '%{http_code}' \
    -H "Authorization: Bearer $tok" "$url") || { rm -f "$tmp"; tw_die "fetch failed: $url"; }
  [ "$http" = "200" ] || { rm -f "$tmp"; tw_die "HTTP $http from $url (token wrong/expired, or bad URL?)"; }
  jq -e '.openapi' "$tmp" >/dev/null 2>&1 \
    || { rm -f "$tmp"; tw_die "not valid OpenAPI JSON: $url"; }
  mv "$tmp" "$out"
}

# tw_add_profile <name> <api-base-url> <spec-url> <token>
# Download <spec-url> and (re)create the ocli profile <name> pointing at
# <api-base-url>, then report the path count. Manages its own temp file.
# Shared by setup.sh and refresh-schema.sh, for both core and metadata profiles.
tw_add_profile() {
  local name="$1" base="$2" spec_url="$3" tok="$4"
  local tmp; tmp="$(mktemp)"
  tw_fetch_spec "$spec_url" "$tok" "$tmp"
  tw_ocli profiles add "$name" \
    --api-base-url "$base" --openapi-spec "$tmp" --api-bearer-token "$tok" >/dev/null
  printf '✓ %s: %s paths\n' "$name" "$(jq '.paths | length' "$tmp")"
  rm -f "$tmp"
}
