#!/bin/bash
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

echo ""
echo "meeting-transcriber uninstalled."
