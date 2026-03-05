#!/bin/bash
# uninstall-cli-command.sh — Remove the ~/.local/bin/mt symlink.
#
# Called automatically by "Remove mt CLI" in the app's menu bar menu.
# Can also be run directly from the terminal.

set -euo pipefail

MT_LINK="$HOME/.local/bin/mt"

if [ -L "$MT_LINK" ]; then
  rm "$MT_LINK"
  echo "Removed: $MT_LINK"
elif [ -f "$MT_LINK" ]; then
  echo "Warning: $MT_LINK is not a symlink — not removing." >&2
  echo "Delete it manually if you want to uninstall." >&2
  exit 1
else
  echo "Nothing to remove: $MT_LINK does not exist."
fi
