# Cueglass

A native **macOS** AI interview assistant (codebase target still named Smarty). Cueglass listens to your mic, optionally reads the screen via OCR, and generates spoken-style answers into a floating overlay with best-effort screen-sharing exclusion.

No accounts, no backend, no analytics. Pick an AI provider in Settings, paste its API key (Keychain only), and go.

## Features

- **Multiple AI providers** — OpenAI, Claude (Anthropic), Gemini (Google), or DeepSeek for answers; switch anytime in Settings → API. Each provider keeps its own key and model list, so switching doesn't lose the others.
- **Whisper / Stream modes** — tap-to-record + Send, or Listen with pause detection
- **Command List tab** — view every global shortcut from the overlay
- **Floating overlay** with best-effort blind mode (`sharingType = .none`)
- **Full-screen overlay** — enable **Settings → Overlay → Overlay over high-level windows** for full-screen and borderless apps that permit other apps to run. Managed single-app kiosk and assessment modes may stop Cueglass, block its launch, and disable screen capture; the overlay cannot override those restrictions.
- **Direct screen solve** — press Control–Option–S to send the full screenshot directly to OpenAI vision (no Apple OCR)
- **OpenAI region commands** — answer, transcribe-and-copy, or copy-image-and-answer from one selected crop without Apple OCR
- **Screen OCR** and **typed ask** with optional **image attachments** (multimodal on OpenAI, Claude, and Gemini; DeepSeek is text-only)
- **Interview field** — pick the kind of interview (overlay **Set role**, or Settings → Prompt), with an optional extra prompt. **AI Training & Annotation** includes Senior AI trainer, Video Annotation Expert, and Generalist. Answers follow that field instead of assuming software engineering. The session keeps prior Q&A so follow-ups stay consistent.
- **Session presets** — interview focus, answer length, preferred coding language
- **Key terms** panel and Markdown transcript export
- Global shortcuts for overlay, pause, and start

## Requirements

- Apple Silicon Mac (recommended)
- macOS 14.0+
- Xcode 16+
- An API key for at least one provider: [OpenAI](https://platform.openai.com/api-keys), [Anthropic](https://console.anthropic.com/settings/keys), [Google AI Studio (Gemini)](https://aistudio.google.com/apikey), or [DeepSeek](https://platform.deepseek.com/api_keys)
- For voice input (Whisper/Stream modes): an OpenAI key, or a Gemini key with Gemini selected as the answer provider — Claude and DeepSeek have no speech-to-text

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

5. **Settings → API** → pick a provider (OpenAI, Claude, Gemini, or DeepSeek), paste its API key → **Save**. Each provider's key is stored in **Keychain only**, under its own entry — never commit `.env` or key files (see `.gitignore`). Voice input (Whisper/Stream) uses Gemini when it's selected and has a saved key, otherwise it falls back to OpenAI.

6. Grant Microphone / Speech / Screen Recording when prompted.

To keep Cueglass running independently of Xcode or Terminal, copy the signed `.app` to Applications and open it from Finder. **Settings → General → Launch at login** can start it when you sign in, but does not override another app's single-app restrictions.

## Privacy

- Screenshots and attachment frames are processed in memory (not written as a capture archive)
- Each provider's API key lives in its own Keychain entry
- Settings, history, and window frame use UserDefaults
- Only traffic to your selected AI provider (and OpenAI, unless Gemini is handling voice input) leaves the machine
- Explicit full-screen and region commands send their captured image directly to OpenAI. Passive Stream screen context may still use local Apple OCR; typed drafts and pending attachments remain separate.
- No authentication / cloud account for Cueglass itself

Blind mode requests exclusion for the selection panels and answer overlay before they appear.
Apple documents [`NSWindow.SharingType`](https://developer.apple.com/documentation/appkit/nswindow/sharingtype-swift.enum)
as a legacy setting: recording apps may still capture these windows. This feature cannot guarantee
invisibility in Google Meet, Zoom, Teams, TestGorilla, or other recording/assessment platforms.
Cursor movements, macOS permission indicators, the menu bar, and changes in other apps may remain visible.
Verify the remote viewer’s output for your exact app, browser, macOS version, and sharing mode.

## Shortcuts

| Shortcut | Action |
|----------|--------|
| ⌃⌥S | Solve the full screen directly with OpenAI vision |
| ⌃⌥A | Send a selected region to OpenAI for an answer |
| ⌃⌥C | Transcribe a selected region, copy its text, and answer it with OpenAI |
| ⌃⌥R | Copy a selected region image and answer it with OpenAI |
| ⌘⇧S | Start session (Stream) — app must be frontmost |
| ⌘⇧H | Show / hide overlay — global |
| ⌘⇧P | Pause / resume — global |

Region capture works without starting a listening session. Configure the OpenAI API key and grant Screen
Recording access using **Settings → General → Permissions** before using it; the shortcut does not open permission prompts. Select an area at
least 8 × 8 points on one display. A drag crossing displays is clipped to its starting display.
Wait for an existing answer to finish, or resume a paused session, before selecting another question.
If another app owns a shortcut, use its matching menu-bar command, or free the shortcut and restart.

## Menu bar

Cueglass opens directly into its floating overlay, with no separate main window. Closing the overlay
hides it while the app stays running. Press **⌘⇧H** or reopen the app to bring the same overlay back.

Cueglass has no Dock icon (`LSUIElement`). The menu bar item (the `<Cue/>` wordmark) toggles the
overlay, opens Settings, starts/stops a session, and quits. Hide it under **Settings → General → Menu Bar**;
the shortcut and reopening the app still work when it is hidden. Blind mode does not hide the menu bar itself.

The overlay’s gear icon and menu bar open Settings on demand. Open **Settings → General → Permissions**
for microphone and screen-recording setup; Settings and Permissions never open automatically at startup.

## Architecture

```
App/            SwiftUI entry + DI (AppEnvironment)
Views/          Permissions, ask field, role editing, history
Overlay/        Non-activating NSPanel + glass UI
Settings/       Provider/API, capture, overlay, prompt presets, general
Managers/       InterviewSessionManager, OverlayManager
ScreenCapture/  ScreenCaptureKit frames (in-memory)
OCR/            Vision text extraction
Speech/         Mic capture + OpenAI/Gemini STT / pause detection
OpenAI/         AIProviderClienting + SpeechTranscribing protocols; OpenAI Responses API client (text + multimodal + STT)
AIProviders/    AIClientRouter, plus Claude / Gemini (also does STT) / DeepSeek clients
PromptBuilder/  Context store, summarization, prompt assembly
Services/       Keychain (per-provider keys), settings, permissions, hotkeys, login item
Models/         Shared types (settings, AIProvider, attachments, messages)
```

Answer generation is provider-agnostic: `InterviewSessionManager` and `ContextSummarizer` depend on
`AIProviderClienting`, and `AIClientRouter` dispatches each request to the client for the currently
selected `AIProvider`. Speech-to-text goes through `OpenAIClient` or `GeminiClient` directly
(both implement `SpeechTranscribing`), selected per-session based on the answer provider;
Claude and DeepSeek offer no transcription API today.

MVVM: views bind to `@Observable` managers; capture / OCR / OpenAI run in actors.

## Secrets

See `.env.example`. **No provider API key should ever be committed.** Enter each key in Settings → API so it is stored in Keychain (one entry per provider). `.gitignore` already excludes `.env`, key files, and Xcode user state (`xcuserdata/`, `*.xcuserstate`).

## Build / test

```bash
xcodegen generate
xcodebuild -scheme Smarty -destination 'platform=macOS' -configuration Debug build
xcodebuild test -scheme Smarty -destination 'platform=macOS'
```
