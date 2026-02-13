#!/bin/bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
PLIST_NAME="com.meeting-transcriber.plist"
PLIST_PATH="$HOME/Library/LaunchAgents/$PLIST_NAME"
LOG_PATH="$HOME/Library/Logs/meeting-transcriber.log"

# Check prerequisites
missing=()
for cmd in bun sox whisper-cli terminal-notifier; do
  command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd")
done

# BlackHole check: brew list won't work if installed via pkg, so check for the audio device
if ! system_profiler SPAudioDataType 2>/dev/null | grep -q "BlackHole"; then
  missing+=("blackhole-2ch")
fi

if [ ${#missing[@]} -gt 0 ]; then
  echo "Missing prerequisites: ${missing[*]}"
  echo "Install with: brew install ${missing[*]}"
  exit 1
fi

echo "Installing dependencies..."
cd "$REPO_DIR"
bun install

echo "Building..."
bun run build

DOMAIN="gui/$(id -u)"

# Uninstall existing agent if present
"$REPO_DIR/uninstall.sh"

echo "Writing LaunchAgent plist..."
mkdir -p "$HOME/Library/LaunchAgents"
cat > "$PLIST_PATH" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>com.meeting-transcriber</string>
  <key>ProgramArguments</key>
  <array>
    <string>$REPO_DIR/meeting-transcriber</string>
  </array>
  <key>EnvironmentVariables</key>
  <dict>
    <key>PATH</key>
    <string>/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
  </dict>
  <key>WorkingDirectory</key>
  <string>$REPO_DIR</string>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <false/>
  <key>StandardOutPath</key>
  <string>$LOG_PATH</string>
  <key>StandardErrorPath</key>
  <string>$LOG_PATH</string>
</dict>
</plist>
EOF

echo "Loading LaunchAgent..."
launchctl bootstrap "$DOMAIN" "$PLIST_PATH"

echo ""

# Symlink binary to ~/.local/bin as 'mt'
mkdir -p "$HOME/.local/bin"
ln -sf "$REPO_DIR/meeting-transcriber" "$HOME/.local/bin/mt"
echo "Symlinked to ~/.local/bin/mt"

if ! echo "$PATH" | tr ':' '\n' | grep -qx "$HOME/.local/bin"; then
  echo "Note: ~/.local/bin is not in your PATH. Add it with:"
  echo "  export PATH=\"\$HOME/.local/bin:\$PATH\""
fi

echo ""
echo "meeting-transcriber installed and started."
echo "Logs: $LOG_PATH"
echo "To uninstall: ./uninstall.sh"
