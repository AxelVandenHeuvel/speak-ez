#!/bin/bash
# Runs the SpeakEzKit unit tests.
#
# With a full Xcode toolchain (CI, most contributor machines) plain
# `swift test` works. With Command Line Tools only, Testing.framework lives
# outside the default search paths and we have to point at it explicitly.
set -euo pipefail
cd "$(dirname "$0")/.."

if xcode-select -p 2>/dev/null | grep -qv CommandLineTools; then
    exec swift test "$@"
fi

FRAMEWORKS=/Library/Developer/CommandLineTools/Library/Developer/Frameworks
INTEROP_LIB=/Library/Developer/CommandLineTools/Library/Developer/usr/lib

exec swift test --disable-xctest \
    -Xswiftc -F -Xswiftc "$FRAMEWORKS" \
    -Xlinker -F -Xlinker "$FRAMEWORKS" \
    -Xlinker -rpath -Xlinker "$FRAMEWORKS" \
    -Xlinker -rpath -Xlinker "$INTEROP_LIB" \
    "$@"
