#!/usr/bin/env bash
# Preflight: is the twenty-crm skill ready to use?
# Exit 0 with STATUS=ready and useful metadata on stdout. Otherwise prints a
# structured report on stderr explaining the two setup paths (user vs agent).

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

errors=()
command -v node >/dev/null 2>&1 || errors+=("missing dependency: node (Node.js ≥18 — https://nodejs.org)")
command -v ocli >/dev/null 2>&1 || errors+=("missing dependency: ocli (install: npm i -g $TW_OCLI_PKG)")
command -v jq   >/dev/null 2>&1 || errors+=("missing dependency: jq (install: brew install jq)")
command -v curl >/dev/null 2>&1 || errors+=("missing dependency: curl")

profile=""
if [ ${#errors[@]} -eq 0 ]; then
  if [ ! -f "$TW_CONFIG_FILE" ]; then
    errors+=("not configured (no $TW_CONFIG_FILE)")
  else
    jq -e . "$TW_CONFIG_FILE" >/dev/null 2>&1 || errors+=("$TW_CONFIG_FILE is not valid JSON")
    profile="$(tw_config_get profile)"
    [ -n "$profile" ] || errors+=("config file has no 'profile': $TW_CONFIG_FILE")
  fi
fi

# Does `ocli` resolve our profile FROM HERE (the agent's cwd)? This mirrors what
# a bare `ocli <cmd>` will see, so it catches a $PWD/.ocli that shadows ~/.ocli.
# Capture first, then match via here-string — piping `ocli` into `grep -q` under
# `set -o pipefail` can SIGPIPE ocli (grep -q exits on the first match before
# draining), spuriously failing the check once there is >1 profile.
if [ ${#errors[@]} -eq 0 ]; then
  visible="$(ocli profiles list 2>/dev/null || true)"
  if ! grep -qx "$profile" <<<"$visible"; then
    global="$(tw_ocli profiles list 2>/dev/null || true)"
    if grep -qx "$profile" <<<"$global"; then
      errors+=("profile '$profile' exists in ~/.ocli but is hidden by a local $PWD/.ocli — remove it or run the skill from another directory")
    else
      errors+=("ocli profile '$profile' not found — (re)run setup.sh")
    fi
  fi
fi

if [ ${#errors[@]} -eq 0 ]; then
  base="$(tw_ini_get "$profile" api_base_url)"; base="${base%/rest}"
  metadata="$(tw_config_get metadata_profile)"
  printf 'STATUS=ready\nPROFILE=%s\nURL=%s\n' "$profile" "$base"
  [ -n "$metadata" ] && printf 'METADATA=%s\n' "$metadata"
  # The user's local timezone + current local time. Twenty stores datetimes in
  # UTC and renders them in the user's zone, so the agent must read a wall-clock
  # date ("10am", "tomorrow") in this zone and convert to UTC before writing it.
  tz="$(node -p 'Intl.DateTimeFormat().resolvedOptions().timeZone' 2>/dev/null || true)"
  printf 'TZ=%s\nNOW=%s\n' "${tz:-unknown}" "$(date +%Y-%m-%dT%H:%M:%S%z)"
  # A local .ocli in the working dir is a latent hazard even when it happens to
  # carry our profile — surface it without failing.
  [ -e "$PWD/.ocli" ] && echo "WARN=a local $PWD/.ocli is present and overrides ~/.ocli for commands run here" >&2
  exit 0
fi

guide="$(cd "$SCRIPT_DIR/.." && pwd)/references/setup-guide.md"
{
  echo 'STATUS=not_ready'
  for e in "${errors[@]}"; do echo "ERROR=$e"; done
  cat <<EOF

This skill isn't configured yet. Recommend the user run setup in their own
terminal — the API key is typed as hidden input, so it never enters the chat:

    bash $SCRIPT_DIR/setup.sh

It asks for two things: the URL they open Twenty at (cloud:
https://your-workspace.twenty.com, self-hosted: https://crm.your-company.com —
not api.twenty.com; setup appends /rest) and an API key (Settings → APIs &
Webhooks → Create API Key → copy, shown once).

Full step-by-step: $guide
EOF
} >&2
exit 1
