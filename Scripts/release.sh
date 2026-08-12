#!/bin/bash
# Builds a distributable zip of SpeakEz.app.
#
# With a "Developer ID Application" identity installed this signs properly
# and (with NOTARY_PROFILE set to a notarytool keychain profile) notarizes.
# Without one it produces an ad-hoc signed zip: fine for personal use and
# for people who build from source; Gatekeeper will warn anyone else.
set -euo pipefail
cd "$(dirname "$0")/.."

./Scripts/bundle.sh release

VERSION=$(defaults read "$(pwd)/build/speakEZ.app/Contents/Info" CFBundleShortVersionString)
ZIP="build/speakEZ-${VERSION}.zip"

IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null | awk -F'"' '/Developer ID Application/ {print $2; exit}')
if [[ -n "${IDENTITY}" ]]; then
    echo "Signing with: ${IDENTITY}"
    codesign --force --options runtime --timestamp \
        --entitlements Resources/speakEZ.entitlements \
        --sign "${IDENTITY}" build/speakEZ.app
fi

ditto -c -k --keepParent build/speakEZ.app "$ZIP"

if [[ -n "${IDENTITY}" && -n "${NOTARY_PROFILE:-}" ]]; then
    xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple build/speakEZ.app
    ditto -c -k --keepParent build/speakEZ.app "$ZIP"
fi

echo "Release artifact: $ZIP"
