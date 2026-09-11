# Region capture validation

Use **Control–Option–S**, drag on one display, and release to answer. Escape or right-click cancels.
Configure the OpenAI key and macOS Screen Recording permission in Settings → General → Permissions first. The shortcut checks permission
without opening system permission UI. Screenshots are held in memory and sent to OpenAI.

## Automated coverage

Validated on September 10, 2026 with macOS 26.1 and Xcode 26.3: **83 tests passed, zero failures**.
`xcodebuild test -scheme Smarty -destination 'platform=macOS' -configuration Debug
-derivedDataPath /private/tmp/Smarty-region-derived CODE_SIGNING_ALLOWED=NO` built the app and ran the
suite. The run includes a window-server hit test confirming the selection panel receives the first click.
This unsigned test build does not validate Screen Recording permission persistence for a signed release.

- Global-to-display coordinate conversion, displays above/left of the primary display, reverse drags,
  clipping, tiny selections, invalid rectangles, and 1×/2× pixel alignment.
- Selection panel creation, Escape cleanup, duplicate activation, display-change cancellation, and
  completing a drag only after removing all temporary panels.
- Region image submission with absent/successful/failed OCR; preserving pending attachments; no microphone
  startup; setup preflight without prompting; busy/paused rejection; cancellation and stop during capture;
  capture failure and API failure recovery.

## Manual acceptance checks

On a signed development build, check a text question and a diagram, native Retina and external displays,
full-screen apps, a drag crossing the display edge, Escape, first-click handling when another app is
frontmost, cursor/focus restoration, and an app already using the shortcut. Confirm the screenshot contains
only the chosen region, without Smarty's panels or a cursor, and that the underlying app receives no drag.
The screenshot shortcut must not write a capture file, change the clipboard, or open Settings.

## Screen-sharing verification — pending

Window exclusion is best effort. A `.none` sharing value is not evidence that a remote viewer cannot
see the window. For each setup below, record macOS/app/browser versions, sharing mode, and results from
a separate viewer or recording. Do not infer support in one application from another application's result.

| Setup | Whole-display share | Window share | Status |
| --- | --- | --- | --- |
| Google Meet in Chrome | Pending | Pending | Unverified |
| Zoom | Pending | Pending | Unverified |
| Microsoft Teams | Pending | Pending | Unverified |
| TestGorilla practice setup | Pending where available | Pending where available | Unverified |
| Other recording/assessment apps | Per-app check required | Per-app check required | Unverified |

Inspect activation, selection outline, mouse movement, cancellation, progress, answer display, and errors,
with blind mode both enabled and disabled. Menu bar contents and OS permission indicators may remain
visible. No recorder-specific invisibility guarantee is made; holding shortcut modifiers does not hide
other applications' actions.

Apple's documentation describes [`NSWindow.SharingType`](https://developer.apple.com/documentation/appkit/nswindow/sharingtype-swift.enum)
as a legacy setting. Selection panels and the answer overlay request exclusion before display, while
Smarty's own ScreenCaptureKit request explicitly excludes Smarty itself.
