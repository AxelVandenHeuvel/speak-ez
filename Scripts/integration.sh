#!/bin/bash
# End-to-end speech test: transcribes the spoken fixture through the real
# Parakeet models and checks the words came through.
# Downloads ~1 GB of models to ~/.cache/fluidaudio on first run.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build
OUTPUT=$(.build/debug/SpeakEz --transcribe Tests/Fixtures/fixture.wav)
echo "$OUTPUT"

for WORD in deploy build production tomorrow; do
    if ! grep -qi "$WORD" <<<"$OUTPUT"; then
        echo "FAIL: transcript is missing '$WORD'" >&2
        exit 1
    fi
done
echo "integration test passed"
