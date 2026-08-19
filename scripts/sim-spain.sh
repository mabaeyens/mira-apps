#!/bin/bash
#
# sim-spain.sh — configure the dedicated Mira screenshot/RAG simulator.
#
# Idempotent: re-run any time the sim drifts or after an "Erase All Content".
# Sets English UI + Spanish keyboard + Spain region, turns off hardware-keyboard
# passthrough (so the on-screen keyboard appears), then reboots the device and
# opens Simulator.
#
# No iCloud needed: add documents to Mira by dragging a PDF/.txt/.html onto the
# Simulator window -> "Save to Files" -> On My iPhone -> attach via the paperclip.

set -euo pipefail

# Dedicated device: iPhone 17 Pro Max (iOS 26.5)
UDID="3CA476E0-A034-4D39-96BA-9C3F5F232ABB"

echo "==> Booting $UDID (ignore 'already booted')"
xcrun simctl boot "$UDID" 2>/dev/null || true

echo "==> Applying locale: English UI, Spain region"
xcrun simctl spawn "$UDID" defaults write .GlobalPreferences AppleLocale -string "en_US@rg=eszzzz"
xcrun simctl spawn "$UDID" defaults write .GlobalPreferences AppleLanguages -array "en-US" "es-ES"

echo "==> Setting Spanish (Spain) as the active on-screen keyboard"
# AppleLanguages alone does NOT switch the keyboard — AppleKeyboards must be set
# explicitly, first entry = active. Without this the on-screen keyboard stays English.
xcrun simctl spawn "$UDID" defaults write .GlobalPreferences AppleKeyboards -array \
  "es_ES@sw=QWERTY-Spanish;hw=Automatic" \
  "en_US@sw=QWERTY;hw=Automatic" \
  "emoji@sw=Emoji"

echo "==> Disabling hardware-keyboard passthrough (shows on-screen keyboard)"
defaults write com.apple.iphonesimulator ConnectHardwareKeyboard -bool false

echo "==> Restarting device so settings take effect"
xcrun simctl shutdown "$UDID"
xcrun simctl boot "$UDID"

echo "==> Opening Simulator"
open -a Simulator

echo "==> Done. Region=Spain, language=English, Spanish keyboard available via the globe key."
