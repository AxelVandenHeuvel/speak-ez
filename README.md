# speakEZ

A free, open-source, fully-local dictation app for macOS.
Hold a key, speak, release, and clean text appears wherever your cursor is.

Think Wispr Flow, but free, open source, and nothing ever leaves your Mac.

## Features

- Hold-to-talk dictation into any app, up to 5 minutes per recording.
- Default trigger: **hold Right Option**. Held alone it never fires a macOS or app shortcut, so it collides with none of your existing keybinds; if you press another key while holding it, the hold cancels and your shortcut goes through untouched. Right Command, Right Control, and fn (globe) are available in the menu.
- Three trigger modes: **Hold to Talk** (push-to-talk), **Tap to Toggle** (tap to start, tap to stop), or **Hold or Tap** (a quick tap toggles, a long hold behaves like push-to-talk).
- Add vocabulary straight from the menu bar ("Add Vocabulary Term…"), no file editing needed.
- On-device speech-to-text with NVIDIA Parakeet v3 running on the Apple Neural Engine via [FluidAudio](https://github.com/FluidInference/FluidAudio).
- Long recordings are transcribed in the background while you are still speaking, so the text appears about a second after you release the key even after minutes of talking.
- Three refinement levels, switchable from the menu bar:
  - **Off**: the raw transcript, untouched.
  - **Basic**: instant rule-based cleanup: strips "um"/"uh", collapses stutters ("the the"), fixes the punctuation seams, applies your vocabulary.
  - **AI**: Basic plus a polish pass by Apple's on-device foundation model (needs macOS 26 with Apple Intelligence; falls back to Basic elsewhere). No extra download, nothing leaves the machine.
- Custom vocabulary: teach it your jargon ("tmux", "herdr", project names) with optional sound-alike aliases ("tea mux"), stored as human-editable JSON.
- Floating recording indicator with live mic levels while the trigger key is held; Esc cancels.
- No accounts, no telemetry, no network use after the one-time model download (~1 GB).

## Requirements

- Apple Silicon Mac, macOS 14 or later (AI refinement needs macOS 26).
- To build from source: Xcode Command Line Tools are enough, no Xcode needed.

## Install

```sh
curl -fsSL https://raw.githubusercontent.com/AxelVandenHeuvel/speak-ez/main/install.sh | sh
```

This builds speakEZ from source on your machine (~2 minutes; needs the Xcode Command Line Tools, and offers to install them if missing) and puts it in /Applications.
Because the app is built locally there are no Gatekeeper warnings and you are not trusting a prebuilt binary.

Or build manually:

```sh
git clone https://github.com/AxelVandenHeuvel/speak-ez.git && cd speak-ez
./Scripts/bundle.sh
open build/speakEZ.app
```

On first launch, grant the three permissions the app asks for (Microphone, Input Monitoring, Accessibility), then use the menu's "Relaunch speakEZ" button so macOS applies them, and let the speech model download (~1 GB, one time).
If you switch the trigger to fn (globe), also set System Settings -> Keyboard -> "Press globe key" to "Do Nothing" so it stops opening the emoji picker.

## Develop

```sh
./Scripts/test.sh          # unit tests (no models or permissions needed)
./Scripts/integration.sh   # full speech pipeline against the real models
```

## License

MIT. See LICENSE and NOTICE for bundled model and library attributions.
