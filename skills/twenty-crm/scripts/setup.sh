#!/usr/bin/env bash
# Configure a Twenty CRM instance for the skill.
#
# Interactive (default):
#   bash setup.sh
#
# Non-interactive (agent-friendly):
#   bash setup.sh --non-interactive \
#     --name <instance-name> \
#     --url  <https://twenty-server> \
#     --token-from {keychain|env|file} \
#     [--token <key>]                                     # required for keychain/file
#                                                         # when no entry exists yet
#     [--keychain-account <a>] [--keychain-service <s>]   # default: twenty-<name> / api
#     [--env-name <VAR>]                                  # default: TWENTY_<NAME>_KEY
#     [--token-file <path>]                               # default: $TW_CONFIG_DIR/tokens/<name>
#     [--set-default]                                     # mark as default instance
#     [--full]                                            # don't slim core paths
#     [--objects o1,o2,...]                               # custom slim object set
#
# Effects:
#   1. Validates token by fetching <url>/rest/open-api/core
#   2. Stores full + slim core/metadata specs under $TW_CONFIG_DIR/specs/<name>/
#   3. Persists token via the chosen source (keychain create / file write)
#   4. Records instance + slim config in $TW_INSTANCES_FILE
#   5. Updates restish apis.json: twenty-<name>-{core,meta}

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

tw_require jq
tw_require curl

INTERACTIVE=1
name="" url="" token_from="" token=""
kc_account="" kc_service="" env_name="" token_file=""
set_default=0 slim_full=0 slim_objects=""

while [ $# -gt 0 ]; do
  case "$1" in
    --non-interactive)    INTERACTIVE=0 ;;
    --name)               name="$2"; shift ;;
    --url)                url="$2"; shift ;;
    --token-from)         token_from="$2"; shift ;;
    --token)              token="$2"; shift ;;
    --keychain-account)   kc_account="$2"; shift ;;
    --keychain-service)   kc_service="$2"; shift ;;
    --env-name)           env_name="$2"; shift ;;
    --token-file)         token_file="$2"; shift ;;
    --set-default)        set_default=1 ;;
    --full)               slim_full=1 ;;
    --objects)            slim_objects="$2"; shift ;;
    -h|--help)            sed -n '2,28p' "$0"; exit 0 ;;
    *) tw_die "unknown flag: $1" ;;
  esac
  shift
done

ask() {
  local _var=$1 _prompt=$2 _default="${3:-}" _answer
  if [ -n "$_default" ]; then read -r -p "$_prompt [$_default]: " _answer; _answer="${_answer:-$_default}"
  else                        read -r -p "$_prompt: " _answer
  fi
  printf -v "$_var" '%s' "$_answer"
}
ask_secret() {
  local _var=$1 _prompt=$2 _answer
  read -r -s -p "$_prompt: " _answer; echo
  printf -v "$_var" '%s' "$_answer"
}

if [ "$INTERACTIVE" -eq 1 ]; then
  echo "── Twenty CRM skill setup ──"
  [ -z "$name" ]  && ask name  "Instance name (short, lowercase, no spaces)" "myco"
  [ -z "$url" ]   && ask url   "Twenty URL — the address you open Twenty at (self-hosted: https://crm.your-company.com — cloud: https://your-workspace.twenty.com)"
  [ -z "$token" ] && ask_secret token "API key (Settings → APIs & Webhooks → + Create key)"
  if [ -z "$token_from" ]; then
    echo "Token storage:"
    echo "  1) keychain  — macOS Keychain (recommended on Mac)"
    echo "  2) file      — \$TW_CONFIG_DIR/tokens/<name> with chmod 600"
    echo "  3) env       — read from environment variable"
    choice=""
    ask choice "Pick 1/2/3" "1"
    case "$choice" in
      1) token_from="keychain" ;;
      2) token_from="file" ;;
      3) token_from="env" ;;
      *) tw_die "invalid choice: $choice" ;;
    esac
  fi
fi

[ -n "$name" ]       || tw_die "missing --name"
[ -n "$url" ]        || tw_die "missing --url"
[ -n "$token_from" ] || tw_die "missing --token-from"
[[ "$name" =~ ^[a-z0-9-]+$ ]] || tw_die "name must match [a-z0-9-]+: $name"
url="${url%/}"
case "$token_from" in keychain|env|file) ;; *) tw_die "--token-from must be keychain|env|file";; esac

# Source-specific defaults derived from $name.
[ -z "$kc_account" ] && kc_account="twenty-$name"
[ -z "$kc_service" ] && kc_service="api"
[ -z "$env_name" ]   && env_name="TWENTY_$(echo "$name" | tr '[:lower:]-' '[:upper:]_')_KEY"
[ -z "$token_file" ] && token_file="$TW_CONFIG_DIR/tokens/$name"

# If --token wasn't passed, fall back to whatever the chosen source already holds.
if [ -z "$token" ]; then
  case "$token_from" in
    env)
      [ -n "${!env_name:-}" ] || tw_die "env var '$env_name' is empty; export it or pass --token"
      token="${!env_name}" ;;
    keychain)
      [ "$(uname -s)" = "Darwin" ] || tw_die "keychain only on macOS"
      token=$(security find-generic-password -a "$kc_account" -s "$kc_service" -w 2>/dev/null) \
        || tw_die "no token provided and no existing keychain entry (account=$kc_account service=$kc_service)"
      ;;
    file)
      [ -r "$token_file" ] || tw_die "no token provided and file not readable: $token_file"
      token=$(tr -d '\r\n' < "$token_file") ;;
  esac
fi

# Validate against server, save full spec, generate slim spec.
echo "→ validating token against $url ..."
specs_dir="$TW_SPECS_DIR/$name"
mkdir -p "$specs_dir"
core_full="$specs_dir/core.full.json"
core_spec="$specs_dir/core.json"
meta_full="$specs_dir/metadata.full.json"
meta_spec="$specs_dir/metadata.json"

tw_fetch_spec "$url/rest/open-api/core"     "$token" "$core_full"
tw_fetch_spec "$url/rest/open-api/metadata" "$token" "$meta_full"

slim_args=()
[ "$slim_full" -eq 1 ]    && slim_args+=("--full")
[ -n "$slim_objects" ]    && slim_args+=("--objects" "$slim_objects")
bash "$SCRIPT_DIR/slim-spec.sh" "$core_full" ${slim_args[@]+"${slim_args[@]}"} > "$core_spec"
bash "$SCRIPT_DIR/slim-spec.sh" "$meta_full" --full > "$meta_spec"

echo "✓ token valid; core: $(jq '.paths|length' "$core_spec")/$(jq '.paths|length' "$core_full") paths (slim/full), metadata: $(jq '.paths|length' "$meta_spec") paths"

# Persist token.
case "$token_from" in
  keychain)
    [ "$(uname -s)" = "Darwin" ] || tw_die "keychain only on macOS"
    security add-generic-password -U -a "$kc_account" -s "$kc_service" -w "$token" \
      || tw_die "failed to write keychain entry"
    echo "✓ token stored in macOS Keychain (account=$kc_account service=$kc_service)" ;;
  file)
    umask 077
    mkdir -p "$(dirname "$token_file")"
    printf '%s' "$token" > "$token_file"
    echo "✓ token written to $token_file (mode 600)" ;;
  env)
    echo "✓ env mode: ensure '$env_name' is exported in your shell" ;;
esac

# Build instance entry. Persist slim config so refresh-schema.sh can honor it.
mkdir -p "$TW_CONFIG_DIR"
[ -f "$TW_INSTANCES_FILE" ] || echo '{"instances":{}}' > "$TW_INSTANCES_FILE"

case "$token_from" in
  keychain) src_json=$(jq -n --arg a "$kc_account" --arg s "$kc_service" '{type:"keychain", account:$a, service:$s}') ;;
  env)      src_json=$(jq -n --arg n "$env_name"   '{type:"env",      name:$n}') ;;
  file)     src_json=$(jq -n --arg p "$token_file" '{type:"file",     path:$p}') ;;
esac
slim_json=$(jq -n --argjson full "$slim_full" --arg objs "$slim_objects" \
  '{full: ($full == 1), objects: (if $objs == "" then null else $objs end)}')

existing_default=$(tw_default_instance 2>/dev/null || echo "")
become_default=$([ -z "$existing_default" ] || [ "$set_default" -eq 1 ] && echo true || echo false)

# shellcheck disable=SC2016  # $n, $u, $src, $slim, $set_default are jq variables, not shell
tw_jq_inplace "$TW_INSTANCES_FILE" \
  --arg n "$name" --arg u "$url" \
  --argjson src  "$src_json" \
  --argjson slim "$slim_json" \
  --argjson set_default "$become_default" \
  '.instances[$n] = {base_url: $u, token_source: $src, slim: $slim}
   | if $set_default then .default = $n else . end'

[ "$become_default" = "true" ] && echo "✓ default instance: $name"

# Update restish apis.json.
mkdir -p "$(dirname "$TW_RESTISH_APIS")"
[ -f "$TW_RESTISH_APIS" ] || echo '{}' > "$TW_RESTISH_APIS"

helper="$SCRIPT_DIR/auth-helper.sh"
build_api() {  # build_api <base-url> <spec-file>
  jq -n --arg base "$1" --arg spec "$2" --arg cmd "$helper $name" \
    '{base: $base, spec_files: [$spec],
      profiles: {default: {auth: {name: "external-tool", params: {commandline: $cmd}}}}}'
}
core_api=$(build_api "$url/rest"          "$core_spec")
meta_api=$(build_api "$url/rest/metadata" "$meta_spec")

# shellcheck disable=SC2016  # $core, $meta, $cn, $mn are jq variables, not shell
tw_jq_inplace "$TW_RESTISH_APIS" \
  --argjson core "$core_api" --argjson meta "$meta_api" \
  --arg cn "twenty-$name-core" --arg mn "twenty-$name-meta" \
  '.[$cn] = $core | .[$mn] = $meta'
echo "✓ restish APIs registered: twenty-$name-core, twenty-$name-meta"

# Drop any stale parsed-spec cache so a changed URL or re-downloaded spec takes
# effect immediately (Restish otherwise serves the previous registration).
rm -f "$TW_RESTISH_CACHE/twenty-$name-core.cbor" "$TW_RESTISH_CACHE/twenty-$name-meta.cbor"

cat <<EOF

✓ Setup complete — '$name' is connected.

Now just ask your agent in plain language, e.g.:
  • "How many people are in my CRM?"
  • "Find the most recently added company."
  • "List my open opportunities in the PROPOSAL stage."
EOF
