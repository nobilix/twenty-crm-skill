#!/usr/bin/env bash
# Shared helpers for twenty-crm skill scripts. Source this; never exec.
# Public functions are prefixed `tw_`. Errors go to stderr; exit codes propagate.

set -euo pipefail

# These variables are consumed by sibling scripts that source this file.
# shellcheck disable=SC2034
TW_CONFIG_DIR="${TW_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/twenty-cli}"
# shellcheck disable=SC2034
TW_INSTANCES_FILE="$TW_CONFIG_DIR/instances.json"
# shellcheck disable=SC2034
TW_SPECS_DIR="$TW_CONFIG_DIR/specs"

if [ "$(uname -s)" = "Darwin" ]; then
  # shellcheck disable=SC2034
  TW_RESTISH_APIS="$HOME/Library/Application Support/restish/apis.json"
  # shellcheck disable=SC2034
  TW_RESTISH_CACHE="$HOME/Library/Caches/restish"
else
  # shellcheck disable=SC2034
  TW_RESTISH_APIS="${XDG_CONFIG_HOME:-$HOME/.config}/restish/apis.json"
  # shellcheck disable=SC2034
  TW_RESTISH_CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/restish"
fi

tw_die() { printf 'twenty-cli: %s\n' "$*" >&2; exit 1; }

tw_require() {
  command -v "$1" >/dev/null 2>&1 || tw_die "missing dependency: $1"
}

tw_list_instances() {
  [ -f "$TW_INSTANCES_FILE" ] || return 0
  jq -r '.instances // {} | keys[]' "$TW_INSTANCES_FILE"
}

tw_default_instance() {
  [ -f "$TW_INSTANCES_FILE" ] || return 1
  jq -er '.default // empty' "$TW_INSTANCES_FILE"
}

tw_resolve_instance() {
  local name="${1:-}"
  if [ -z "$name" ]; then
    name="$(tw_default_instance)" || tw_die "no default instance and none specified"
  fi
  jq -e --arg n "$name" '.instances[$n] // empty' "$TW_INSTANCES_FILE" >/dev/null 2>&1 \
    || tw_die "unknown instance: $name"
  printf '%s' "$name"
}

tw_instance_url() {
  jq -er --arg n "$1" '.instances[$n].base_url' "$TW_INSTANCES_FILE"
}

# Resolve token for an instance. Order: $TWENTY_API_KEY > instance.token_source > error.
# One jq read collects all needed fields to keep the per-request cost low.
tw_resolve_token() {
  local name="$1"

  if [ -n "${TWENTY_API_KEY:-}" ]; then
    printf '%s' "$TWENTY_API_KEY"
    return
  fi

  local src
  src=$(jq -er --arg n "$name" \
    '.instances[$n].token_source
     | [.type, (.account // .name // .path // ""), (.service // "")]
     | @tsv' "$TW_INSTANCES_FILE") \
    || tw_die "instance '$name' has no token_source configured"

  local type a b
  IFS=$'\t' read -r type a b <<<"$src"

  case "$type" in
    keychain)
      [ "$(uname -s)" = "Darwin" ] || tw_die "keychain token_source only supported on macOS"
      security find-generic-password -a "$a" -s "$b" -w 2>/dev/null \
        || tw_die "keychain entry not found (account=$a service=$b)"
      ;;
    env)
      [ -n "${!a:-}" ] || tw_die "env var '$a' is empty"
      printf '%s' "${!a}"
      ;;
    file)
      local path="${a/#\~/$HOME}"
      [ -r "$path" ] || tw_die "token file not readable: $path"
      tr -d '\r\n' < "$path"
      ;;
    *)
      tw_die "unsupported token_source.type: $type"
      ;;
  esac
}

# tw_fetch_spec <url> <token> <out-file>
# Validates HTTP 200 and that the body is OpenAPI JSON. Atomic via tmp.
tw_fetch_spec() {
  local url="$1" tok="$2" out="$3"
  local tmp; tmp=$(mktemp "${out}.XXXXXX")
  local http
  http=$(curl -sS -o "$tmp" -w '%{http_code}' \
    -H "Authorization: Bearer $tok" "$url") || { rm -f "$tmp"; tw_die "fetch failed: $url"; }
  [ "$http" = "200" ] || { rm -f "$tmp"; tw_die "HTTP $http from $url"; }
  jq -e '.openapi' "$tmp" >/dev/null \
    || { rm -f "$tmp"; tw_die "not valid OpenAPI: $url"; }
  mv "$tmp" "$out"
}

# tw_jq_inplace <file> <jq-args...>   — atomic in-place jq edit on the same volume.
tw_jq_inplace() {
  local f="$1"; shift
  local tmp; tmp=$(mktemp "${f}.XXXXXX")
  jq "$@" "$f" > "$tmp" && mv "$tmp" "$f"
}
