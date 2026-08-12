#!/bin/bash
# Builds speakEZ.app from the SwiftPM package. No Xcode required.
# Usage: Scripts/bundle.sh [debug|release]
set -euo pipefail
cd "$(dirname "$0")/.."

CONF="${1:-release}"
VERSION="0.1.1"

swift build -c "$CONF" --arch arm64
BIN_PATH=$(swift build -c "$CONF" --arch arm64 --show-bin-path)

APP="build/speakEZ.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_PATH/SpeakEz" "$APP/Contents/MacOS/speakEZ"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleIdentifier</key>
	<string>dev.speakez.SpeakEz</string>
	<key>CFBundleName</key>
	<string>speakEZ</string>
	<key>CFBundleDisplayName</key>
	<string>speakEZ</string>
	<key>CFBundleExecutable</key>
	<string>speakEZ</string>
	<key>CFBundleIconFile</key>
	<string>AppIcon</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>${VERSION}</string>
	<key>CFBundleVersion</key>
	<string>${VERSION}</string>
	<key>LSMinimumSystemVersion</key>
	<string>14.0</string>
	<key>LSUIElement</key>
	<true/>
	<key>NSMicrophoneUsageDescription</key>
	<string>speakEZ records your voice while the trigger key is held so it can transcribe it into text. Audio never leaves this Mac.</string>
	<key>NSHumanReadableCopyright</key>
	<string>MIT licensed open source software.</string>
</dict>
</plist>
PLIST

# Sign with a stable identity so macOS keeps the permission grants across
# rebuilds. Preference order: the local self-signed dev cert, a real Apple
# identity, then ad-hoc (which resets permissions on every rebuild).
find_identity() {
    security find-identity -v -p codesigning 2>/dev/null \
        | awk -F'"' -v pattern="$1" '$2 ~ pattern {print $2; exit}'
}
IDENTITY=$(find_identity "speakEZ Dev")
[[ -n "$IDENTITY" ]] || IDENTITY=$(find_identity "Apple Development")

if [[ -n "${IDENTITY}" ]]; then
    echo "Signing with: ${IDENTITY}"
    codesign --force --sign "${IDENTITY}" "$APP"
else
    echo "No stable identity found; using ad-hoc signature."
    echo "Note: macOS may re-ask for permissions after each rebuild."
    codesign --force --sign - "$APP"
fi

echo "Built $APP"
