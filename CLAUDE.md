# speakEZ

Fully-local macOS dictation menu-bar app (open-source Wispr Flow alternative).
Product name is "speakEZ" (repo: speak-ez); internal Swift target names stay SpeakEz/SpeakEzKit.
Native Swift, Apple Silicon only, macOS 14+.

## Build and test

- This machine has only Command Line Tools, no Xcode. Never use xcodebuild.
- Build the app bundle: `./Scripts/bundle.sh` (produces `build/speakEZ.app`).
- Run unit tests: `./Scripts/test.sh` (never plain `swift test`: CLT needs explicit Testing.framework paths, the script provides them).
- Tests cover SpeakEzKit only and need no models, ML, or permissions.

## Architecture

- `Sources/SpeakEzKit/`: pure logic (refinement rules, vocabulary correction, dictation state machine). No AppKit or ML imports allowed here; everything must stay unit-testable.
- `Sources/SpeakEz/`: the app. Hotkey capture (CGEventTap), audio (AVAudioEngine), transcription (FluidAudio Parakeet v3), text insertion (pasteboard + synthetic Cmd+V), overlay, settings.
- STT dependency is pinned exact (`FluidAudio 0.12.4`, pre-1.0 API churn); bump deliberately.

## Conventions

- The app needs Microphone + Input Monitoring + Accessibility permissions; ad-hoc signed dev builds can lose TCC grants on rebuild (re-grant in System Settings if the hotkey stops working).
- Model downloads land in `~/Library/Application Support/FluidAudio/Models/`.
- AI refinement uses Apple's on-device Foundation Models framework (macOS 26+, Apple Intelligence), not MLX: this machine has no Xcode, and MLX needs the Metal shader compiler that only ships with Xcode. The `TextRefiner` protocol in SpeakEzKit is the seam where an MLX/llama.cpp backend could be added.
