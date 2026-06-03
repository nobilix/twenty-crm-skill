#!/usr/bin/env bash
# Re-download the OpenAPI spec(s) after a Twenty upgrade or schema change
# (new custom object/field). Arg-free: reads the configured profile and reuses
# the URL + token already stored in ~/.ocli.
#
#   bash refresh-schema.sh
#
# Re-running `ocli profiles add` re-resolves the spec and overwrites the cached
# copy at ~/.ocli/specs/<profile>.json.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

tw_require ocli
tw_require jq
tw_require curl

profile="$(tw_config_get profile)"
[ -n "$profile" ] || tw_die "not configured — run setup.sh first"
meta_profile="$(tw_config_get metadata_profile)"

base="$(tw_ini_get "$profile" api_base_url)"     # <url>/rest
token="$(tw_ini_get "$profile" api_bearer_token)"
[ -n "$base" ]  || tw_die "no api_base_url for profile '$profile' in $TW_OCLI_INI"
[ -n "$token" ] || tw_die "no api_bearer_token for profile '$profile' in $TW_OCLI_INI"

umask 077
tw_add_profile "$profile" "$base" "$base/open-api/core" "$token"

if [ -n "$meta_profile" ]; then
  tw_add_profile "$meta_profile" "$base/metadata" "$base/open-api/metadata" "$token"
  tw_ocli use "$profile" >/dev/null   # leave the core profile active
fi

chmod 600 "$TW_OCLI_INI" 2>/dev/null || true
echo "✓ schema refreshed"
