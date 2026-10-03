#!/usr/bin/env bash
set -euo pipefail

# run-install.sh
# Simple wrapper that calls the main installer in a nearby folder

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MAIN_UNINSTALL="$SCRIPT_DIR/main/uninstall.sh"

if [ -x "$MAIN_UNINSTALL" ]; then
  echo "Running main uninstaller: $MAIN_UNINSTALL"
  exec sudo "$MAIN_UNINSTALL" "$@"
else
  echo "ERROR: main uninstaller not found at $MAIN_UNINSTALL" >&2
  exit 1
fi
