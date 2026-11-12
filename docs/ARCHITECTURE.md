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

## Key handling
`.env` (gitignored) → `scripts/obfuscate_key.swift` XORs the key with a random 32-byte salt and writes `Secrets.generated.swift`; `KeyVault` reveals it at runtime. This keeps the key out of plain-text source and `strings`, but **is not security** — anyone with the binary can recover it, so use a free, limited key. The public repository contains only the empty placeholder file (`git update-index --skip-worktree` keeps the local, real one out of commits). `Build.command` re-runs the script when `.env` holds a real key and keeps the existing file otherwise.

## Platform notes
- iOS 18 minimum, no newer API without a guard. The macOS target is sandboxed with the network-client entitlement.
- Signing / bundle id overrides live in the gitignored `Config/Local.xcconfig`, so `xcodegen generate` never wipes them.

## Known limitations
See the README ("Not done and known bugs"): no photo attachments, no offline mode, simple highlighter, Mac target not exercised by hand, only an iOS 26 simulator available for runs.
