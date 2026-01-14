# Cueglass

A native **macOS** AI interview assistant (codebase target still named Smarty). Cueglass listens to your mic, optionally reads the screen via OCR, and generates spoken-style answers into a floating overlay that stays out of most screen shares.

No accounts, no backend, no analytics. Paste an OpenAI API key in Settings (Keychain only) and go.

## Features

- **Whisper / Stream modes** — tap-to-record + Send, or Listen with pause detection
- **Floating overlay** with blind mode (`sharingType = .none`) for most meeting apps
- **Screen OCR** and **typed ask** with optional **image attachments** (multimodal)
- **Session presets** — interview focus, answer length, preferred coding language
- **Key terms** panel and Markdown transcript export
- Global shortcuts for overlay, pause, and start

## Requirements

- Apple Silicon Mac (recommended)
- macOS 14.0+
- Xcode 16+
- OpenAI API key

## Setup

1. Open or regenerate the project:
   ```bash
   brew install xcodegen   # once
   xcodegen generate
   open Smarty.xcodeproj
   ```

2. Select the **Smarty** scheme → **My Mac**.

3. Signing (required for Screen Recording):
   - Xcode → **Signing & Capabilities** → your **Team** (Apple Development).
   - Avoid ad-hoc / “Sign to Run Locally” — TCC will not stick across rebuilds.

4. Run (⌘R).

5. **Settings → API** → paste your OpenAI API key → **Save**. The key is stored in **Keychain only** — never commit `.env` or key files (see `.gitignore`).

6. Grant Microphone / Speech / Screen Recording when prompted.

## Privacy

- Screenshots and attachment frames are processed in memory (not written as a capture archive)
- API key lives in Keychain
- Settings, history, and window frame use UserDefaults
- Only OpenAI API traffic leaves the machine
- No authentication / cloud account for Cueglass itself

## Shortcuts

| Shortcut | Action |
|----------|--------|
| ⌘⇧S | Start session (Stream) |
| ⌘⇧H | Show / hide overlay |
| ⌘⇧P | Pause / resume |

## Architecture

```
App/            SwiftUI entry + DI (AppEnvironment)
Views/          Main window, permissions, ask field, history
Overlay/        Non-activating NSPanel + glass UI
Settings/       API, capture, overlay, prompt presets, general
Managers/       InterviewSessionManager, OverlayManager
ScreenCapture/  ScreenCaptureKit frames (in-memory)
OCR/            Vision text extraction
Speech/         Mic capture + OpenAI STT / pause detection
OpenAI/         Responses API (text + multimodal images)
PromptBuilder/  Context store, summarization, prompt assembly
Services/       Keychain, settings, permissions, hotkeys, login item
Models/         Shared types (settings, attachments, messages)
```

MVVM: views bind to `@Observable` managers; capture / OCR / OpenAI run in actors.

## Secrets

See `.env.example`. **`OPENAI_API_KEY` must never be committed.** Enter the key in Settings so it is stored in Keychain. `.gitignore` already excludes `.env`, key files, and Xcode user state (`xcuserdata/`, `*.xcuserstate`).

## Build / test

```bash
xcodegen generate
xcodebuild -scheme Smarty -destination 'platform=macOS' -configuration Debug build
xcodebuild test -scheme Smarty -destination 'platform=macOS'
```
