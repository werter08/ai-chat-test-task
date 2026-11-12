#!/bin/bash
# Double-click in Finder: generates the Xcode project with XcodeGen, builds for the iOS Simulator,
# then installs and launches the app. No manual terminal commands needed.
cd "$(dirname "$0")" || exit 1
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

pause() { echo; read -n 1 -s -r -p "Press any key to close..."; echo; }
fail() { echo; echo "ERROR: $1"; pause; exit 1; }

echo "== AI Chat: build for iOS Simulator =="

command -v xcodegen >/dev/null 2>&1 || fail "xcodegen not found. Install it with: brew install xcodegen"
command -v xcodebuild >/dev/null 2>&1 || fail "xcodebuild not found. Install Xcode and run: sudo xcode-select -s /Applications/Xcode.app"

echo "-- Embedding API key (if .env has one)"
swift scripts/obfuscate_key.swift .env Shared/Security/Secrets.generated.swift || fail "key obfuscation failed"

echo "-- xcodegen generate"
xcodegen generate || fail "xcodegen generate failed"

# Pick a simulator: prefer an already booted iPhone, otherwise the first available iPhone.
DEVICE_LINE=$(xcrun simctl list devices available | grep -E "iPhone .*\(Booted\)" | head -1)
[ -z "$DEVICE_LINE" ] && DEVICE_LINE=$(xcrun simctl list devices available | grep -E "iPhone [0-9]" | head -1)
UDID=$(echo "$DEVICE_LINE" | grep -Eo '[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}')
[ -z "$UDID" ] && fail "No iPhone simulator found. Install an iOS Simulator runtime in Xcode > Settings > Components."

echo "-- xcodebuild (simulator $UDID)"
xcodebuild -project AIChat.xcodeproj -scheme AIChat \
    -destination "id=$UDID" -derivedDataPath build \
    CODE_SIGNING_ALLOWED=NO -quiet build || fail "build failed (see output above)"

APP="build/Build/Products/Debug-iphonesimulator/AIChat.app"
[ -d "$APP" ] || fail "built app not found at $APP"

echo "-- Installing and launching"
xcrun simctl boot "$UDID" 2>/dev/null
open -a Simulator
xcrun simctl bootstatus "$UDID" -b >/dev/null 2>&1
BUNDLE_ID=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Info.plist")
xcrun simctl install "$UDID" "$APP" && xcrun simctl launch "$UDID" "$BUNDLE_ID" \
    || echo "Built OK, but could not launch automatically. Run it from the Simulator."

echo
echo "Done. App: $APP"
pause
