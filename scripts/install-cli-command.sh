#!/bin/bash
# install-cli-command.sh — Symlink ~/.local/bin/mt to the mt wrapper inside
# the MeetingTranscriber.app bundle.
#
# Called automatically by "Install mt CLI" in the app's menu bar menu.
# Can also be run directly from the terminal.
#
# After install, `mt list`, `mt watch`, etc. are available in your PATH.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# When invoked from within the app bundle, $0 is already inside Contents/Resources/
# so mt lives right next to this script. Fall back to known install locations for
# standalone (terminal) use.
if [ -f "$SCRIPT_DIR/mt" ]; then
  MT_WRAPPER="$SCRIPT_DIR/mt"
elif [ -d "$HOME/Applications/MeetingTranscriber.app" ]; then
  MT_WRAPPER="$HOME/Applications/MeetingTranscriber.app/Contents/Resources/mt"
elif [ -d "/Applications/MeetingTranscriber.app" ]; then
  MT_WRAPPER="/Applications/MeetingTranscriber.app/Contents/Resources/mt"
else
  echo "Error: MeetingTranscriber.app not found in ~/Applications or /Applications." >&2
  echo "Install it first by opening the DMG and dragging the app to Applications." >&2
  exit 1
fi

if [ ! -f "$MT_WRAPPER" ]; then
  echo "Error: mt wrapper not found at:" >&2
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
