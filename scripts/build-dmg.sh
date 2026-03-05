#!/bin/bash
# build-dmg.sh — Build, sign, notarize, and package Meeting Transcriber as a DMG.
#
# Usage:
#   ./scripts/build-dmg.sh [--version 1.2.3]
#
# Required env vars for signing + notarization (set in CI via GitHub Actions secrets,
# or export locally before running):
#
#   SIGNING_IDENTITY   — Full name of your Developer ID cert, e.g.:
#                        "Developer ID Application: Your Name (TEAMID)"
#   TEAM_ID            — Your 10-character Apple Developer Team ID
#   NOTARY_APPLE_ID    — Apple ID email used for App Store Connect / notarytool
#   NOTARY_APP_PASSWORD — App-specific password generated at appleid.apple.com
#
# If SIGNING_IDENTITY is not set the script builds and packages the DMG unsigned
# (useful for local development / testing the bundle layout).
#
# Prerequisites (install once):
#   brew install create-dmg
#   brew install sox whisper-cpp        # runtime deps bundled separately by the user
#   Xcode Command Line Tools: xcode-select --install
#   Bun: curl -fsSL https://bun.sh/install | bash

set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
APP_NAME="MeetingTranscriber"
BUNDLE_ID="ai.openclaw.MeetingTranscriberApp"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="$REPO_DIR/build"
APP_PATH="$BUILD_DIR/$APP_NAME.app"

# Parse --version flag
VERSION="1.0.0"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --version) VERSION="$2"; shift 2 ;;
    *) echo "Unknown arg: $1"; exit 1 ;;
  esac
done

DMG_PATH="$BUILD_DIR/$APP_NAME-$VERSION.dmg"

SIGNING_IDENTITY="${SIGNING_IDENTITY:-}"
TEAM_ID="${TEAM_ID:-}"
NOTARY_APPLE_ID="${NOTARY_APPLE_ID:-}"
NOTARY_APP_PASSWORD="${NOTARY_APP_PASSWORD:-}"

echo "=== Building $APP_NAME $VERSION ==="
echo "    Repo:    $REPO_DIR"
echo "    Output:  $DMG_PATH"
echo "    Signing: ${SIGNING_IDENTITY:-<unsigned>}"
echo ""

# ---------------------------------------------------------------------------
# Step 1: Clean build directory
# ---------------------------------------------------------------------------
echo "--- Step 1: Clean build dir ---"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# ---------------------------------------------------------------------------
# Step 2: Build Bun engine binary + Swift helpers
# ---------------------------------------------------------------------------
echo "--- Step 2: Build Bun engine + Swift helpers ---"
cd "$REPO_DIR"
bun install --frozen-lockfile

# Compile Swift helpers
swiftc src/mic-check.swift -framework CoreAudio -o src/mic-check
swiftc src/rec-status.swift -framework Cocoa -o src/rec-status
swiftc src/system-audio-capture.swift \
    -framework ScreenCaptureKit -framework CoreMedia \
    -o src/system-audio-capture

# Compile standalone Bun binary (macOS grants TCC permissions to this binary directly)
bun build --compile src/index.ts --outfile meeting-transcriber

# ---------------------------------------------------------------------------
# Step 3: Build Swift menu bar app
# ---------------------------------------------------------------------------
echo "--- Step 3: Build Swift menu bar app ---"
cd "$REPO_DIR/MeetingTranscriberApp"
swift build -c release
SWIFT_BIN="$REPO_DIR/MeetingTranscriberApp/.build/release/MeetingTranscriberApp"

# ---------------------------------------------------------------------------
# Step 4: Assemble .app bundle
# ---------------------------------------------------------------------------
# Bundle layout:
#   MeetingTranscriber.app/
#     Contents/
#       Info.plist
#       PkgInfo
#       MacOS/
#         MeetingTranscriberApp      ← Swift menu bar app (main executable)
#         meeting-transcriber        ← Bun engine (found by ProcessManager via sibling lookup)
#         src/
#           mic-check                ← CoreAudio helper (found via process.cwd()/src/)
#           rec-status               ← Menu-bar REC indicator
#           system-audio-capture     ← ScreenCaptureKit audio capture
#       Resources/
#         mt                         ← CLI wrapper (symlink target for ~/.local/bin/mt)
#         install-cli-command.sh     ← Invoked by "Install mt CLI" menu item
#         uninstall-cli-command.sh   ← Invoked by "Remove mt CLI" menu item
# ---------------------------------------------------------------------------
echo "--- Step 4: Assemble .app bundle ---"

CONTENTS="$APP_PATH/Contents"
MACOS_DIR="$CONTENTS/MacOS"
SRC_DIR="$MACOS_DIR/src"
RESOURCES_DIR="$CONTENTS/Resources"

mkdir -p "$MACOS_DIR" "$SRC_DIR" "$RESOURCES_DIR"

# Info.plist (top-level, read by macOS — not the one embedded in the binary)
cp "$REPO_DIR/MeetingTranscriberApp/Sources/MeetingTranscriberApp/Info.plist" \
   "$CONTENTS/Info.plist"

# Stamp the release version into the bundle's Info.plist
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $VERSION" "$CONTENTS/Info.plist"

# PkgInfo — required by macOS for a valid .app bundle
printf 'APPL????' > "$CONTENTS/PkgInfo"

# Main executable
cp "$SWIFT_BIN" "$MACOS_DIR/MeetingTranscriberApp"

# Bun engine (sits alongside the Swift executable so ProcessManager's sibling
# directory walk finds it at depth 0)
cp "$REPO_DIR/meeting-transcriber" "$MACOS_DIR/meeting-transcriber"

# Swift helpers (placed in src/ so process.cwd()+"/src/..." resolves correctly
# when the engine's working directory is set to Contents/MacOS/ — see ProcessManager)
cp "$REPO_DIR/src/mic-check"              "$SRC_DIR/mic-check"
cp "$REPO_DIR/src/rec-status"             "$SRC_DIR/rec-status"
cp "$REPO_DIR/src/system-audio-capture"   "$SRC_DIR/system-audio-capture"

# CLI scripts (Resources/ so the mt symlink target survives app reinstalls cleanly)
cp "$SCRIPT_DIR/mt"                         "$RESOURCES_DIR/mt"
cp "$SCRIPT_DIR/install-cli-command.sh"     "$RESOURCES_DIR/install-cli-command.sh"
cp "$SCRIPT_DIR/uninstall-cli-command.sh"   "$RESOURCES_DIR/uninstall-cli-command.sh"
chmod +x "$RESOURCES_DIR/mt" \
         "$RESOURCES_DIR/install-cli-command.sh" \
         "$RESOURCES_DIR/uninstall-cli-command.sh"

echo "    Bundle created at $APP_PATH"

# ---------------------------------------------------------------------------
# Step 5: Code sign (requires SIGNING_IDENTITY)
# ---------------------------------------------------------------------------
if [ -n "$SIGNING_IDENTITY" ]; then
  echo "--- Step 5: Code sign ---"
  ENTITLEMENTS="$REPO_DIR/MeetingTranscriber.entitlements"

  # Sign leaf binaries first (inside-out order required by codesign)
  for helper in mic-check rec-status system-audio-capture; do
    echo "    Signing src/$helper"
    codesign --force --options runtime \
      --sign "$SIGNING_IDENTITY" \
      "$SRC_DIR/$helper"
  done

  # Bun engine needs entitlements for JIT / unsigned executable memory
  echo "    Signing meeting-transcriber (with entitlements)"
  codesign --force --options runtime \
    --entitlements "$ENTITLEMENTS" \
    --sign "$SIGNING_IDENTITY" \
    "$MACOS_DIR/meeting-transcriber"

  # Main Swift app — sign last (bundle-level, validates all Contents/)
  echo "    Signing .app bundle"
  codesign --force --options runtime \
    --entitlements "$ENTITLEMENTS" \
    --sign "$SIGNING_IDENTITY" \
    "$APP_PATH"

  # Verify
  echo "    Verifying signature"
  codesign --verify --deep --strict --verbose=2 "$APP_PATH"
  spctl --assess --type exec --verbose "$APP_PATH" || true  # may fail before notarization
else
  echo "--- Step 5: Code sign (SKIPPED — SIGNING_IDENTITY not set) ---"
fi

# ---------------------------------------------------------------------------
# Step 6: Create DMG
# ---------------------------------------------------------------------------
echo "--- Step 6: Create DMG ---"

# create-dmg writes a temp DMG first; clean up any leftover from prior runs
rm -f "$DMG_PATH"

# Icon placement: app on left, Applications alias on right
create-dmg \
  --volname "$APP_NAME" \
  --window-pos 200 120 \
  --window-size 600 380 \
  --icon-size 100 \
  --icon "$APP_NAME.app" 155 185 \
  --hide-extension "$APP_NAME.app" \
  --app-drop-link 445 185 \
  --text-size 14 \
  "$DMG_PATH" \
  "$BUILD_DIR/"

echo "    DMG created at $DMG_PATH"

# ---------------------------------------------------------------------------
# Step 7: Sign the DMG (required before notarization)
# ---------------------------------------------------------------------------
if [ -n "$SIGNING_IDENTITY" ]; then
  echo "--- Step 7: Sign DMG ---"
  codesign --force --sign "$SIGNING_IDENTITY" "$DMG_PATH"
else
  echo "--- Step 7: Sign DMG (SKIPPED) ---"
fi

# ---------------------------------------------------------------------------
# Step 8: Notarize + Staple (requires Apple Developer credentials)
# ---------------------------------------------------------------------------
if [ -n "$SIGNING_IDENTITY" ] && [ -n "$NOTARY_APPLE_ID" ] && \
   [ -n "$NOTARY_APP_PASSWORD" ] && [ -n "$TEAM_ID" ]; then

  echo "--- Step 8: Notarize ---"
  echo "    Submitting $DMG_PATH to Apple notary service (this may take a few minutes)..."

  xcrun notarytool submit "$DMG_PATH" \
    --apple-id "$NOTARY_APPLE_ID" \
    --password "$NOTARY_APP_PASSWORD" \
    --team-id "$TEAM_ID" \
    --wait

  echo "--- Step 9: Staple notarization ticket ---"
  xcrun stapler staple "$DMG_PATH"

  echo "    Verifying staple"
  xcrun stapler validate "$DMG_PATH"

  echo "    Notarization complete — DMG works offline (ticket stapled)"
else
  echo "--- Step 8: Notarize (SKIPPED — credentials not set) ---"
  echo "    To notarize, set: SIGNING_IDENTITY, TEAM_ID, NOTARY_APPLE_ID, NOTARY_APP_PASSWORD"
fi

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------
echo ""
echo "=== Build complete ==="
echo "    $DMG_PATH"
du -sh "$DMG_PATH"
