#!/bin/sh
# speakEZ installer: builds from source and installs to /Applications.
#   curl -fsSL https://raw.githubusercontent.com/AxelVandenHeuvel/speak-ez/main/install.sh | sh
#
# Building locally means no Gatekeeper warnings and no trust required in
# prebuilt binaries: the ~2 minute compile is the price of that.
set -eu

REPO="https://github.com/AxelVandenHeuvel/speak-ez.git"
APP_NAME="speakEZ.app"

if [ "$(uname -s)" != "Darwin" ] || [ "$(uname -m)" != "arm64" ]; then
    echo "speakEZ needs an Apple Silicon Mac." >&2
    exit 1
fi

if ! xcode-select -p >/dev/null 2>&1; then
    echo "The Xcode Command Line Tools are required to build speakEZ."
    echo "Starting their installer now; rerun this script when it finishes."
    xcode-select --install
    exit 1
fi

WORKDIR=$(mktemp -d /tmp/speakez-install.XXXXXX)
trap 'rm -rf "$WORKDIR"' EXIT

echo "==> Cloning speak-ez"
git clone --quiet --depth 1 "$REPO" "$WORKDIR/speak-ez"

echo "==> Building (first build downloads dependencies, ~2 minutes)"
cd "$WORKDIR/speak-ez"
./Scripts/bundle.sh release

echo "==> Installing to /Applications"
rm -rf "/Applications/$APP_NAME"
mv "build/$APP_NAME" "/Applications/$APP_NAME"

open "/Applications/$APP_NAME"

cat <<'DONE'

speakEZ is installed and running (waveform icon in the menu bar).

Next steps:
  1. Approve the Microphone, Input Monitoring, and Accessibility prompts.
  2. In the menu bar dropdown, click "Relaunch speakEZ" so the grants apply.
  3. Wait for "Speech model: ready" (a ~1 GB one-time download), then
     hold Right Option anywhere, speak, and release.

Everything runs on your Mac; nothing is ever uploaded.
DONE
