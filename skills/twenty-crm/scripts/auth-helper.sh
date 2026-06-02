#!/usr/bin/env bash
# Restish external-tool auth helper. Invoked by restish per request.
# Reads (and discards) a request JSON on stdin, outputs JSON injecting Authorization.
# Configured in restish apis.json: "commandline": "<skill>/scripts/auth-helper.sh <name>"

set -euo pipefail
exec </dev/null     # restish pipes the request body in; we don't need it. Drain explicitly.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

[ $# -eq 1 ] || tw_die "auth-helper: instance name required"

token=$(tw_resolve_token "$1")
[ -n "$token" ] || tw_die "auth-helper: empty token for '$1'"

jq -nc --arg t "Bearer $token" '{headers: {authorization: [$t]}}'
