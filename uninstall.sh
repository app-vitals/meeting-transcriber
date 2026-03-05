#!/bin/bash
# LEGACY: Removes the LaunchAgent installed by install.sh.
# For GUI app users, disable auto-start via Settings → Launch at Login instead.
set -euo pipefail

PLIST_NAME="com.meeting-transcriber.plist"
PLIST_PATH="$HOME/Library/LaunchAgents/$PLIST_NAME"

if [ ! -f "$PLIST_PATH" ]; then
  echo "LaunchAgent not installed (no plist at $PLIST_PATH)."
  exit 0
fi

echo "Unloading LaunchAgent..."
launchctl bootout "gui/$(id -u)/com.meeting-transcriber" 2>/dev/null || true

echo "Removing plist..."
rm "$PLIST_PATH"

rm -f "$HOME/.local/bin/mt"

echo ""
echo "meeting-transcriber uninstalled."
