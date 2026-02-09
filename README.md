# Local STT

Local speech-to-text for macOS. Runs entirely on-device using [WhisperKit](https://github.com/argmaxinc/WhisperKit) (CoreML/Metal). No cloud, no API keys, no data leaves your Mac.

Sits in the menubar. Hold a key — speak — release — get text.

## Requirements

- macOS 14+, Apple Silicon
- Xcode 16+ (to build)
- Microphone permission
- Accessibility permission (for global hotkey)

## Build & Run

```bash
swift build
swift run LocalSTT
```

The first launch downloads the Whisper model (~140 MB for Base). Subsequent launches use the cached model.

## Usage

### Hotkey (Right Option)

| Gesture | Action |
|---|---|
| **Hold** (≥ 0.3s) | Start recording. Release to transcribe. |
| **Single tap** | Copy result to clipboard + dismiss |
| **Double tap** | Dismiss without copying |

### Menubar

- **Left-click** the mic icon — toggle the popover (shows status / result)
- **Right-click** — context menu:
  - **Translate to English** — translate any language to English instead of transcribing
  - **Model** — switch Whisper model:
    | Model | Size | Speed | Accuracy |
    |---|---|---|---|
    | Tiny | ~75 MB | Fastest | Lower |
    | Base | ~140 MB | Fast | Good (default) |
    | Small | ~460 MB | Medium | Better |
    | Large v3 | ~3 GB | Slower | Best |
  - **Quit**

### Result popover

After transcription, the popover shows:
- Transcribed text (selectable)
- Detected language and word count
- **Copy** button (Cmd+C)
- **Dismiss** button (Esc)

The popover auto-sizes to fit the text, up to 1/3 of screen height.

## Build DMG

```bash
./scripts/build-dmg.sh
# Output: dist/LocalSTT-0.1.0.dmg

# With code signing:
CODESIGN_IDENTITY="Developer ID Application: ..." VERSION=1.0.0 ./scripts/build-dmg.sh
```

## Create GitHub Release

```bash
gh release create v0.1.0 dist/LocalSTT-0.1.0.dmg --title "v0.1.0"
```

## Project structure

```
Sources/
  App/            # AppDelegate, AppCoordinator
  Core/           # AudioRecorder, TranscriptionEngine, HotkeyMonitor, StateManager
  UI/             # StatusBarController, PopoverContentView
  Utilities/      # Constants, PermissionManager
Package.swift
docs/
  PRD.md
  ARCHITECTURE.md
```
