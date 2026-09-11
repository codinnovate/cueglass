# Cueglass

A native **macOS** AI interview assistant (codebase target still named Smarty). Cueglass listens to your mic, optionally reads the screen via OCR, and generates spoken-style answers into a floating overlay with best-effort screen-sharing exclusion.

No accounts, no backend, no analytics. Pick an AI provider in Settings, paste its API key (Keychain only), and go.

## Features

- **Multiple AI providers** — OpenAI, Claude (Anthropic), Gemini (Google), or DeepSeek for answers; switch anytime in Settings → API. Each provider keeps its own key and model list, so switching doesn't lose the others.
- **Whisper / Stream modes** — tap-to-record + Send, or Listen with pause detection
- **Floating overlay** with best-effort blind mode (`sharingType = .none`)
- **Region capture and answer** — press Control–Option–S, drag over a question, and release to send the cropped screenshot; Escape cancels
- **Screen OCR** and **typed ask** with optional **image attachments** (multimodal on OpenAI, Claude, and Gemini; DeepSeek is text-only)
- **Role brief** — set the job title, field, company, and notes for the role you're interviewing for; answers are framed for that field (non-technical roles drop code, algorithms, and Big-O)
- **Session presets** — interview focus, answer length, preferred coding language
- **Key terms** panel and Markdown transcript export
- Global shortcuts for overlay, pause, and start

## Requirements

- Apple Silicon Mac (recommended)
- macOS 14.0+
- Xcode 16+
- An API key for at least one provider: [OpenAI](https://platform.openai.com/api-keys), [Anthropic](https://console.anthropic.com/settings/keys), [Google AI Studio (Gemini)](https://aistudio.google.com/apikey), or [DeepSeek](https://platform.deepseek.com/api_keys)
- An OpenAI API key specifically if you want voice input (Whisper/Stream modes) — speech-to-text always uses OpenAI regardless of which provider you pick for answers

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

5. **Settings → API** → pick a provider (OpenAI, Claude, Gemini, or DeepSeek), paste its API key → **Save**. Each provider's key is stored in **Keychain only**, under its own entry — never commit `.env` or key files (see `.gitignore`). Voice input (Whisper/Stream) needs an OpenAI key specifically, even if you answer with a different provider.

6. Grant Microphone / Speech / Screen Recording when prompted.

## Privacy

- Screenshots and attachment frames are processed in memory (not written as a capture archive)
- Each provider's API key lives in its own Keychain entry
- Settings, history, and window frame use UserDefaults
- Only traffic to your selected AI provider (and OpenAI, for voice input) leaves the machine
- Region screenshots are sent to your selected provider for visual answering (OpenAI, Claude, and Gemini support this; DeepSeek is text-only), with optional OCR; typed drafts and pending attachments remain separate
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
| ⌃⌥S | Capture region and answer — global; drag then release, Escape cancels |
| ⌘⇧S | Start session (Stream) — app must be frontmost |
| ⌘⇧H | Show / hide overlay — global |
| ⌘⇧P | Pause / resume — global |

Region capture works without starting a listening session. Configure the API key and grant Screen
Recording access using **Settings → General → Permissions** before using it; the shortcut does not open permission prompts. Select an area at
least 8 × 8 points on one display. A drag crossing displays is clipped to its starting display.
Wait for an existing answer to finish, or resume a paused session, before selecting another question.
If another app owns ⌃⌥S, use **Capture Region and Answer** in the menu bar, or free the shortcut and restart.

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
Speech/         Mic capture + OpenAI STT / pause detection
OpenAI/         AIProviderClienting protocol + OpenAI Responses API client (text + multimodal + STT)
AIProviders/    AIClientRouter, plus Claude / Gemini / DeepSeek clients
PromptBuilder/  Context store, summarization, prompt assembly
Services/       Keychain (per-provider keys), settings, permissions, hotkeys, login item
Models/         Shared types (settings, AIProvider, attachments, messages)
```

Answer generation is provider-agnostic: `InterviewSessionManager` and `ContextSummarizer` depend on
`AIProviderClienting`, and `AIClientRouter` dispatches each request to the client for the currently
selected `AIProvider`. Speech-to-text is the one exception — it always goes through `OpenAIClient`
directly, since none of the other three vendors offer an equivalent transcription API today.

MVVM: views bind to `@Observable` managers; capture / OCR / OpenAI run in actors.

## Secrets

See `.env.example`. **No provider API key should ever be committed.** Enter each key in Settings → API so it is stored in Keychain (one entry per provider). `.gitignore` already excludes `.env`, key files, and Xcode user state (`xcuserdata/`, `*.xcuserstate`).

## Build / test

```bash
xcodegen generate
xcodebuild -scheme Smarty -destination 'platform=macOS' -configuration Debug build
xcodebuild test -scheme Smarty -destination 'platform=macOS'
```
