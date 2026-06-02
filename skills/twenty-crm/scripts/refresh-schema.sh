#!/usr/bin/env bash
# Re-download OpenAPI specs after a Twenty server upgrade or schema change.
# Usage: bash refresh-schema.sh [instance-name]   # default: configured default instance

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

tw_require jq
tw_require curl

name=$(tw_resolve_instance "${1:-}")
url=$(tw_instance_url "$name")
token=$(tw_resolve_token "$name")

# Read this instance's persisted slim preferences (set at setup time).
slim_full=$(jq -r --arg n "$name" '.instances[$n].slim.full    // false' "$TW_INSTANCES_FILE")
slim_objs=$(jq -r --arg n "$name" '.instances[$n].slim.objects // ""'    "$TW_INSTANCES_FILE")

slim_args=()
[ "$slim_full" = "true" ] && slim_args+=("--full")
[ -n "$slim_objs" ]       && slim_args+=("--objects" "$slim_objs")

specs_dir="$TW_SPECS_DIR/$name"
mkdir -p "$specs_dir"

for kind in core metadata; do
  full="$specs_dir/$kind.full.json"
  slim="$specs_dir/$kind.json"
  tw_fetch_spec "$url/rest/open-api/$kind" "$token" "$full"
  if [ "$kind" = "metadata" ]; then
    bash "$SCRIPT_DIR/slim-spec.sh" "$full" --full > "$slim"
  else
    bash "$SCRIPT_DIR/slim-spec.sh" "$full" ${slim_args[@]+"${slim_args[@]}"} > "$slim"
  fi
  printf '✓ %s: full=%d paths, slim=%d paths\n' \
    "$kind" "$(jq '.paths|length' "$full")" "$(jq '.paths|length' "$slim")"
done

rm -f "$TW_RESTISH_CACHE/twenty-$name-core.cbor" "$TW_RESTISH_CACHE/twenty-$name-meta.cbor"
echo "✓ restish spec cache cleared"
