# Testing

## What exists
- **Unit tests** (`Tests/`): SSE parser, error mapping, key obfuscation round-trip, `ChatEngine` with a scripted mock backend (send, stream, failure leaves no empty bubble, retry after failure and after a mid-stream error, Stop before the first token / after partial text — with and without a quiet stream end, notes never sent to the model, discard while generating, context cap), system prompt composition, chat modes, Markdown parser, sentence splitter, staged-reveal units and timing.
- **UI tests** (`UITests/`, XCUITest on the simulator): walkthrough of home → mode → drawer → Settings → appearance; dark mode actually applies (samples the page background brightness); drawer dim reaches the safe areas and closes on tap; the drawer opens repeatedly after every way of closing; a reopened chat shows its bottom content immediately; Markdown reply renders (no raw `##`) and Copy flips to "Copied"; composer cycles compact → 30 % → full screen with the Send button below the editor; the reply is typed out progressively, stays at the top, shows **Go down** only when ready, and tapping it reaches Copy; Stop mid-stream shows a note and no error; Share only on long press.
- **Live API tests** (opt-in): `TEST_RUNNER_RUN_LIVE_TESTS=1 xcodebuild test …` — a real streamed reply, and an invalid key maps to "unauthorized".

## Added last, written but NOT run (time)
- `Tests/PhotoSpeechTests.swift`: transcript merging, `SpeechInput` with a scripted service, request encoding (plain and multi-part), vision-model choice, image downscaling, engine behaviour with photos (photo-only message, ≤ 4 photos, only the last 3 photo messages carry pictures, cascade delete), and an opt-in live vision test. The whole project including these targets compiles; they have not been executed.
- UI tests still to add/run: dictation fills the box before sending (`-uiTestFakeSpeech`), a seeded photo previews above the text box and above the message text once sent (`-uiTestSeedPhoto`), removing a photo. `testComposerExpandsToThirdThenFullScreen` was adjusted for the new row (tools next to Send) but not re-run.
- Run once (not the full suite): `testPhotoQuotaFullShowsApologyAndAllowsSendingWithoutPhoto` (debug switch `-uiTestPhotoQuota` makes photo requests fail with HTTP 402) — passes; screenshots checked.
- Verified by hand: a command-line program compiled from the app's own networking sources sent a real photo through `OpenRouterClient` (vision model, `max_tokens`, SSE parsing) and got a correct description; the earlier failure was reproduced with a raw request (HTTP 402: the request reserved 131072 tokens).
- Dictation in the iOS Simulator: a temporary UI probe with the real recognizer showed `kLSRErrorDomain 300` on both the on-device and the server attempt (permissions granted, ~0.3 s after start) — an environment limit, not recorded in the test suite. The app logs it (`subsystem app.aichat`, category `speech`) and reports it to the user.
- Verified by hand (earlier): the vision model answers correctly to a request with an image (direct API call), and the composer layout (photo strip above the text box, photo and mic buttons) in a simulator screenshot. Not verified: real speech recognition, tapping the system photo picker.

## Running
```
xcodegen generate
xcodebuild test -project AIChat.xcodeproj -scheme AIChat \
  -destination 'platform=iOS Simulator,name=iPhone 17' CODE_SIGNING_ALLOWED=NO
# screenshots from the UI tests as PNG files:
TEST_RUNNER_SHOT_DIR=/some/dir xcodebuild test …
```
Unit tests can also run on macOS through a temporary Swift package that symlinks `Shared/` and `Tests/` (used when Xcode's build service was stuck).

## Debug-only test hooks
Compiled only in Debug builds (`#if DEBUG`): launch arguments `-uiTestInMemory` (in-memory store, user data untouched), `-uiTestSeedMarkdown` (a demo chat with a rich Markdown reply), `-uiTestFakeStream` (a simulated backend: a silent pause, then the sample reply in small chunks) — they let UI tests exercise typing, Stop and Markdown without the network.

## Bugs the tests caught (kept as regression tests)
| Bug | Found by |
|---|---|
| Retry did nothing after a mid-stream error (deleted reply stayed in `chat.messages`) | unit test |
| Stop before the first token surfaced as "Unexpected response" (quiet stream end treated as failure) | unit + UI test |
| Deleting a chat while it generated could touch a deleted chat | unit test |
| Appearance switch looked selected but the UI stayed light (a launch argument overrode the saved value; my first test passed without checking colour) | screenshot → brightness assertion |
| Settings sheet did not follow the theme | UI test; Settings became a pushed page |
| Reopened chat was blank until dragged (lazy stack + scroll race) | UI test |
| Drawer opened once then never again (closing drag removed its own gesture host) | UI regression test |
| Appearance tiles tappable only on icon/text | UI test taps the tile edge |
| Reply end hidden under the composer / snapping layout | screenshots, then assertions |
| Go down scrolled only part-way | UI test → `ScrollPosition` API |

## What was not automated
Sending a real message through the UI against the live API (the live API is covered at client level); the macOS app was type-checked and built, not run by hand; feel of animation timing (checked in still frames and numbers, not in motion); only an iOS 26 simulator was available, so iOS 18 is covered by API choice, not by a run.
