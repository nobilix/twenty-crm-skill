#!/usr/bin/env bash
# Connect a Twenty CRM instance to the skill via ocli.
#
# Interactive (default):
#   bash setup.sh
#
# Non-interactive (agent-friendly):
#   bash setup.sh --non-interactive --url <https://your-twenty> --token <api-key>
#
# Options:
#   --with-metadata    Also create the metadata profile (schema admin; rarely needed).
#   -h | --help        Show this header.
#
# Effects:
#   1. Downloads <url>/rest/open-api/core with the token (also validates it).
#   2. Creates an ocli profile (default name `twenty`) in ~/.ocli, holding the
#      base URL, bearer token, and a resolved-spec cache. Hardened to 0600/0700.
#   3. Records the profile name in ~/.config/twenty-cli/config.json.
#   4. With --with-metadata, repeats for <url>/rest/metadata as `<name>-meta`.
#
# ocli owns the token, URL, and spec cache (~/.ocli). We keep only a pointer.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

tw_require ocli
tw_require jq
tw_require curl

INTERACTIVE=1
url="" token="" with_metadata=0

while [ $# -gt 0 ]; do
  case "$1" in
    --non-interactive) INTERACTIVE=0 ;;
    --url)             url="$2"; shift ;;
    --token)           token="$2"; shift ;;
    --with-metadata)   with_metadata=1 ;;
    -h|--help)         sed -n '2,20p' "$0"; exit 0 ;;
    *) tw_die "unknown flag: $1" ;;
  esac
  shift
done

ask() {
  local _var=$1 _prompt=$2 _answer
  read -r -p "$_prompt: " _answer
  printf -v "$_var" '%s' "$_answer"
}
ask_secret() {
  local _var=$1 _prompt=$2 _answer
  read -r -s -p "$_prompt: " _answer; echo
  printf -v "$_var" '%s' "$_answer"
}

if [ "$INTERACTIVE" -eq 1 ]; then
  echo "── Twenty CRM skill setup ──"
  [ -n "$url" ]   || ask url "Twenty URL — the address you open Twenty at (self-hosted: https://crm.your-company.com — cloud: https://your-workspace.twenty.com)"
  [ -n "$token" ] || ask_secret token "API key (Settings → APIs & Webhooks → + Create key)"
fi

[ -n "$url" ]   || tw_die "missing --url"
[ -n "$token" ] || tw_die "missing --token"
url="${url%/}"

# Pick the profile name: reuse the one we already recorded (idempotent re-setup),
# else `twenty`; if some other ocli tool already owns `twenty`, fall back.
profile="$(tw_config_get profile)"
if [ -z "$profile" ]; then
  profile="twenty"
  # Capture the list once, then match via here-string (see preflight.sh: piping
  # into `grep -q` under pipefail can SIGPIPE ocli once there is >1 profile).
  taken="$(tw_ocli profiles list 2>/dev/null || true)"
  if grep -qx "$profile" <<<"$taken"; then
    profile="twenty-crm"; i=2
    while grep -qx "$profile" <<<"$taken"; do
      profile="twenty-$i"; i=$((i + 1))
    done
  fi
fi
meta_profile="${profile}-meta"

# Files in ~/.ocli are born 0600/0700 under this umask (chmod below is a fallback
# for a pre-existing world/group-readable profiles.ini).
umask 077
mkdir -p "$TW_OCLI_HOME"

echo "→ validating token against $url ..."
tw_add_profile "$profile" "$url/rest" "$url/rest/open-api/core" "$token"

if [ "$with_metadata" -eq 1 ]; then
  tw_add_profile "$meta_profile" "$url/rest/metadata" "$url/rest/open-api/metadata" "$token"
  tw_ocli use "$profile" >/dev/null   # leave the core profile active
fi

chmod 600 "$TW_OCLI_INI" 2>/dev/null || true

# Record the pointer. ocli owns the token/URL/spec; we only remember the name(s).
mkdir -p "$TW_CONFIG_DIR"
if [ "$with_metadata" -eq 1 ]; then
  jq -n --arg p "$profile" --arg m "$meta_profile" \
    '{profile: $p, metadata_profile: $m}' > "$TW_CONFIG_FILE"
else
  jq -n --arg p "$profile" '{profile: $p}' > "$TW_CONFIG_FILE"
fi

cat <<EOF

✓ Setup complete — '$profile' is connected.

Now just ask your agent in plain language, e.g.:
  • "How many people are in my CRM?"
  • "Find the most recently added company."
  • "List my open opportunities in the PROPOSAL stage."
EOF
