#!/usr/bin/env bash
# Preflight: is the twenty-crm skill ready to use?
# Exit 0 with STATUS=ready and useful metadata. Otherwise prints a structured
# report on stderr explaining the two setup paths (user vs agent driven).

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

errors=()
command -v jq      >/dev/null 2>&1 || errors+=("missing dependency: jq (install: brew install jq)")
command -v restish >/dev/null 2>&1 || errors+=("missing dependency: restish (run: bash $SCRIPT_DIR/install-restish.sh)")
command -v curl    >/dev/null 2>&1 || errors+=("missing dependency: curl")

if [ -f "$TW_INSTANCES_FILE" ]; then
  jq -e . "$TW_INSTANCES_FILE" >/dev/null 2>&1 || errors+=("$TW_INSTANCES_FILE is not valid JSON")
  [ -n "$(tw_list_instances)" ] || errors+=("config file exists but has no instances: $TW_INSTANCES_FILE")
else
  errors+=("not configured (no $TW_INSTANCES_FILE)")
fi

if [ ${#errors[@]} -eq 0 ]; then
  printf 'STATUS=ready\nDEFAULT=%s\nINSTANCES=%s\n' \
    "$(tw_default_instance 2>/dev/null || echo "")" \
    "$(tw_list_instances | paste -sd, -)"
  # Per-instance base URLs so the agent can build UI links without re-reading config.
  jq -r '.instances | to_entries[] | "URL_\(.key)=\(.value.base_url)"' "$TW_INSTANCES_FILE"
  exit 0
fi

guide="$(cd "$SCRIPT_DIR/.." && pwd)/references/setup-guide.md"
{
  echo 'STATUS=not_ready'
  for e in "${errors[@]}"; do echo "ERROR=$e"; done
  cat <<EOF

This skill is not yet configured. You need three things:

  1. Base URL — the address you open Twenty at. Self-hosted: https://crm.your-company.com.
     Twenty Cloud: https://api.twenty.com. (setup appends /rest automatically)
  2. API key — in Twenty: Settings → APIs & Webhooks → Create API Key →
     name it → Save → Copy (shown only once).
  3. Token storage — keychain (macOS) | file (Linux/WSL) | env (CI).

Full step-by-step: $guide

Two ways to run it:

(A) User-driven, in your terminal (recommended — your API key never enters chat):
    bash $SCRIPT_DIR/setup.sh

(B) Agent-driven (only if the user handed you the URL + key):
    bash $SCRIPT_DIR/setup.sh --non-interactive --name <name> --url <url> \\
      --token-from {keychain|env|file} [source-specific flags] [--token <key>]
EOF
} >&2
exit 1
