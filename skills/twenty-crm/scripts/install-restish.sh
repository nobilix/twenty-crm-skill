#!/usr/bin/env bash
# Install Restish if missing. Idempotent.

set -euo pipefail

if command -v restish >/dev/null 2>&1; then
  echo "restish already installed: $(restish --version)"
  exit 0
fi

if command -v brew >/dev/null 2>&1; then
  echo "→ installing via Homebrew tap..."
  brew install danielgtaylor/restish/restish
elif command -v go >/dev/null 2>&1; then
  echo "→ installing via 'go install'..."
  go install github.com/rest-sh/restish@latest
  echo "Make sure \$(go env GOPATH)/bin is on your PATH."
else
  cat >&2 <<EOF
Cannot auto-install restish: neither brew nor go found.
Install one of them, or download a binary from:
  https://github.com/rest-sh/restish/releases
EOF
  exit 1
fi

restish --version
