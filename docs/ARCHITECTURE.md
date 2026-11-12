# Architecture

Single app codebase in `Shared/`, compiled into an iOS target (`AIChat`) and a macOS target (`AIChatMac`). Swift 5 mode, SwiftUI, SwiftData, Observation. iOS 18 / macOS 15 minimum; no third-party packages.

## Layers
```
Views (Features/)  ──►  ChatEngine (state + orchestration)  ──►  ChatStreaming protocol  ──►  OpenRouterClient ──► network
        │                         │
        └── SwiftData models ◄────┘   (Chat, Message — persistence, autosave)
```
Views never touch `URLSession`; the engine never touches views. The engine takes a `ChatStreaming` so tests (and debug UI tests) can inject a fake backend.

| Folder | Contents |
|---|---|
| `App/` | `AIChatApp` (model container, engine, toast; debug-only launch flags), `DemoData` (DEBUG only) |
| `Models/` | `Chat`, `Message` (+ `MessageRole`: user / assistant / note), `ChatMode`, `UserProfile` |
| `Networking/` | `OpenRouterClient` (streaming POST), `SSEParser`, `ChatAPIError` |
| `Security/` | `KeyVault`, `Secrets.generated.swift` (generated) |
| `Features/` | `ChatEngine`, `RootView`, `DrawerContainer`, `ChatScreen`, `ChatComponents`, `Markdown`, `StagedReveal`, `SidebarView`, `SettingsView`, `OnboardingView`, `Toast`, `Theme`, `ChatStore` |
| `Config/` | `Base.xcconfig` (+ optional gitignored `Local.xcconfig` for signing / bundle id) |
| `scripts/` | key obfuscation, AI-log export |

## Data flow of one message
1. `ChatScreen` → `ChatEngine.send(text, in: chat)`: inserts the user `Message`, sets the chat title from the first message, saves.
2. `generate`: builds the request from the last 30 messages (notes excluded) with a system prompt composed of the base prompt + the chat's mode prompt + the user's name and custom instructions. Starts one `Task` per chat; state (`isGenerating`, `error`) is published per chat id.
3. `OpenRouterClient.stream` → `SSEParser` yields text deltas (reasoning tokens are ignored; mid-stream errors are surfaced). The assistant `Message` is created lazily on the **first** delta, so no empty bubble is ever persisted.
4. Finish: errors map to `ChatAPIError` (all retryable). **Stop** is not an error: the partial reply is kept and a `note` message ("You stopped the response.") is added. `retry` removes trailing notes and a partial reply, then regenerates. `discard` (chat deleted) cancels the task and touches nothing afterwards.

## Reply rendering
- `MarkdownParser` (pure) → blocks: heading, paragraph, fenced code (also unterminated while streaming), lists, quote, table, rule. `InlineMarkdown` handles bold / italic / inline code / links. `SyntaxHighlighter` is a small language-agnostic highlighter (keywords, types, strings, numbers, comments).
- While a reply streams it is revealed **sentence by sentence** (`StagedReveal`): `SentenceSplitter` + `StagedText.prepare` (holds back the unfinished tail) + `StagedText.alphas` (each unit fades 0→1 over 0.5 s; the next starts at 70 %; the gap shrinks when the animation falls > 2 s behind the network). The bubble's natural height is measured and a clipping frame animates to it, so text eases in instead of jumping. Finished/stored replies render instantly with the normal view.

## Scrolling rules
A reopened chat starts at its newest message. When you send, your message is scrolled to the top once and the reply grows beneath it — nothing follows the text, so you read from the top. When the reply is ready and part of it is below the fold, a **Go down** bubble appears. Programmatic scrolling uses the iOS 18 `ScrollPosition` API (anchor-based `scrollTo` stopped part-way).

## Drawer
`DrawerContainer` is a push-style drawer (content slides aside, drawer parallax beneath). Drag offset is a `@GestureState` and the dim layer is never removed mid-drag — removing it cancelled the closing gesture and left the drawer stuck (a regression test covers it). A rightward, mostly horizontal swipe opens it from anywhere; the dim layer ignores safe areas.

## Photos
`Attachment` (`@Model`, `externalStorage` data, cascade-deleted with its `Message`). `PhotosPicker` → `ImageProcessing.downscaledJPEG` (ImageIO, cross-platform, EXIF-aware, 1024 px long side, JPEG 0.7) → `DraftImage`s shown in a strip *above* the text box; `ChatEngine.send(_:images:)` stores them on the user message (max 4; a photo-only message is allowed). `buildRequest` encodes messages that carry pictures in the multi-part format (`text` + `image_url` data URLs); only the 3 most recent photo messages keep their pictures (request size), older ones fall back to their text or a `[photo]` marker. `OpenRouterClient.chooseModel` picks the vision model (`nvidia/nemotron-3.5-super-vl`, `OPENROUTER_VISION_MODEL`) for any request containing a photo, otherwise the text model. Sent messages render the photos above the text inside the bubble. Every request carries `max_tokens` (4096): without it the provider reserves the model's maximum and answers HTTP 402 when the account cannot afford that. If a request that contained photos fails with a quota / rate-limit / availability error (402, 429, 403, 404), `ChatEngine` inserts an assistant message (`photoApology`) instead of an error banner; the bubble then offers *Send without photo* (`retryWithoutPhotos`: the model is told a photo was attached but cannot be seen) and *Try again*. A stream that ends with reasoning but no answer maps to `ChatAPIError.noAnswer`. The picker hands photos over through an image `Transferable` (`PickedPhoto`) with a `Data` fallback (plain `Data` failed on macOS); the Mac target has the photo-library entitlement and usage string.

## Dictation
`SpeechInput` (UI-facing, `@Observable`) drives a `SpeechService`. `AppleSpeechService` uses `SFSpeechRecognizer` + `AVAudioEngine`: asks speech and microphone permission, prefers on-device recognition when `supportsOnDeviceRecognition` (only a limited set of languages; otherwise audio is processed by Apple), reports partial results. Each callback carries the full transcript so far; `SpeechTextMerger` merges it with the text that was in the box when dictation started, so partial results replace each other instead of piling up. Nothing is sent until the user presses Send. Permissions: `NSMicrophoneUsageDescription`, `NSSpeechRecognitionUsageDescription` (both targets) and the sandbox audio-input entitlement on macOS.

## Key handling
`.env` (gitignored) → `scripts/obfuscate_key.swift` XORs the key with a random 32-byte salt and writes `Secrets.generated.swift`; `KeyVault` reveals it at runtime. This keeps the key out of plain-text source and `strings`, but **is not security** — anyone with the binary can recover it, so use a free, limited key. The public repository contains only the empty placeholder file (`git update-index --skip-worktree` keeps the local, real one out of commits). `Build.command` re-runs the script when `.env` holds a real key and keeps the existing file otherwise.

## Platform notes
- iOS 18 minimum, no newer API without a guard. The macOS target is sandboxed with the network-client entitlement.
- Signing / bundle id overrides live in the gitignored `Config/Local.xcconfig`, so `xcodegen generate` never wipes them.

## Known limitations
See the README ("Not done and known bugs"): no photo attachments, no offline mode, simple highlighter, Mac target not exercised by hand, only an iOS 26 simulator available for runs.
