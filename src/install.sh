#!/usr/bin/env bash
set -euo pipefail

# run-install.sh
# Simple wrapper that calls the main installer with sudo

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MAIN_INSTALL="$SCRIPT_DIR/main/install.sh"

: "${CF_API_TOKEN:?CF_API_TOKEN must be set before install}"

if [ -f "$MAIN_INSTALL" ]; then
  echo "Running main installer with sudo: $MAIN_INSTALL"
  exec sudo --preserve-env bash "$MAIN_INSTALL" "$@"
else
  echo "ERROR: main installer not found at $MAIN_INSTALL" >&2
  exit 1
fi
