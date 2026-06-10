# Contributing to Cueglass

Cueglass is a local-only macOS app. No accounts, no backend PRs.

## Setup

```bash
brew install xcodegen
xcodegen generate
open Smarty.xcodeproj
```

Sign with your Apple Development team so Screen Recording TCC persists.

## Guidelines

- Keep API keys out of the repo — Keychain via Settings only
- Prefer Swift 6 concurrency (`actor`, `@Observable`) matching existing managers
- Add unit tests under `SmartyTests/Unit` for pure logic; fakes live in `SmartyTests/Fakes`
- Do not add authentication, analytics, or cloud sync

## Architecture

See the Architecture section in `README.md`. MVVM with `@Observable` session/overlay managers; capture, OCR, and OpenAI run off the main actor.
