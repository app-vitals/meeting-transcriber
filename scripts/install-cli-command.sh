#!/bin/bash
# install-cli-command.sh — Symlink ~/.local/bin/mt to the mt wrapper inside
# the MeetingTranscriber.app bundle.
#
# Called automatically by "Install mt CLI" in the app's menu bar menu.
# Can also be run directly from the terminal.
#
# After install, `mt list`, `mt watch`, etc. are available in your PATH.

set -euo pipefail

# Locate the app bundle — prefer ~/Applications, fall back to /Applications
if [ -d "$HOME/Applications/MeetingTranscriber.app" ]; then
  APP_PATH="$HOME/Applications/MeetingTranscriber.app"
elif [ -d "/Applications/MeetingTranscriber.app" ]; then
  APP_PATH="/Applications/MeetingTranscriber.app"
else
  echo "Error: MeetingTranscriber.app not found in ~/Applications or /Applications." >&2
  echo "Install it first by opening the DMG and dragging the app to Applications." >&2
  exit 1
fi

MT_WRAPPER="$APP_PATH/Contents/Resources/mt"

if [ ! -f "$MT_WRAPPER" ]; then
  echo "Error: mt wrapper not found inside the app bundle at:" >&2
  echo "  $MT_WRAPPER" >&2
  echo "Try reinstalling MeetingTranscriber from the latest DMG." >&2
  exit 1
fi

chmod +x "$MT_WRAPPER"

mkdir -p "$HOME/.local/bin"
ln -sf "$MT_WRAPPER" "$HOME/.local/bin/mt"

echo "Installed: ~/.local/bin/mt → $MT_WRAPPER"

if ! echo "$PATH" | tr ':' '\n' | grep -qx "$HOME/.local/bin"; then
  echo ""
  echo "Note: ~/.local/bin is not in your PATH."
  echo "Add this line to your shell profile (~/.zshrc or ~/.bash_profile):"
  echo "  export PATH=\"\$HOME/.local/bin:\$PATH\""
fi
