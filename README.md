# AI Chat — test task

A ChatGPT-style chat app for iPhone (iOS 18+), with a macOS target. SwiftUI + SwiftData, streaming replies from OpenRouter.

## Run it
Double-click **`Build.command`** in Finder. It embeds the API key (if `.env` has one), runs `xcodegen generate`, builds for the iOS Simulator, then installs and launches the app. Requires Xcode and `brew install xcodegen`.

The submitted archive already contains the obfuscated key in `Shared/Security/Secrets.generated.swift`, so the app works right after the build with no setup. (The public GitHub repo only has an empty placeholder there, on purpose.)

Optional, for running on a real device: copy `Config/Local.xcconfig.example` to `Config/Local.xcconfig` (gitignored) and set your own bundle id / signing team; it survives `xcodegen generate`.

To use your own key: copy `.env.example` to `.env`, set `OPENROUTER_API_KEY`, run `Build.command`.

## Time
<HOURS> h — **fill in the real number before sending.** For reference: the task file arrived at 12:54, the first commit was 13:02.

## Tools
- Claude Code (model: Claude Sonnet 5.5) for planning, code, tests and review.
- Xcode 26.6, XcodeGen, GitHub CLI.

## AI in the app
OpenRouter (`/api/v1/chat/completions`, `stream: true`), model `baidu/ernie-5.5-flash-preview:free`. The bare id `baidu/ernie-5.5-flash-preview` has no endpoints and returns 404; the `:free` suffix is required. It is a reasoning model, so it streams `reasoning` tokens first; the app ignores them and shows a typing indicator until the answer starts.

The key is XOR-ed with a random salt by `scripts/obfuscate_key.swift` and stored as byte arrays, so it is not a plain string in the source or binary. This is obfuscation, not security: anyone with the binary can recover the key. Use a free, limited key.

## What works
- Composer: glows while focused; a corner button cycles the editor size compact → 30% of the screen → full screen (send button moves below the editor, full width). Reopened chats open at their newest message.
- Replies appear sentence by sentence: each sentence (list item, heading, block) fades in from 0 to 1, and the next one starts when the previous reaches 70%. The unfinished tail is held back until complete; if the network is far ahead the animation speeds up to catch up. The bubble's height is animated (no line-by-line jumps) and the Copy button appears below the message once it is finished. The view does not follow the text: when you send, your message scrolls to the top and the reply grows beneath it, so you read from the top; when the reply is ready, a floating **Go down** bubble jumps to the end.
- Streaming replies as they are generated; **Stop** keeps the partial reply and adds a "You stopped the response." note (with Retry) — it is not treated as an error.
- Replies are rendered as Markdown: headings, lists, quotes, tables, inline code, and code blocks with syntax colors and a Copy button. Long-pressing a message shows Copy and Share (there is no permanent Share button; message text is not selectable so the long-press menu is reliable). Copy actions show a checkmark and a "Copied to clipboard" toast.
- Opens straight into an empty chat with a greeting and mode cards. Modes (Writing, Creative, Conversation, Personal, Developer) change the system prompt and offer quick prompts.
- Multiple chats: a push-style drawer (menu icon or a rightward swipe from anywhere; interactive, spring-animated, dim layer covers the safe areas) with search, a **New chat** button and your history (swipe to delete); history persists across restarts (SwiftData). Quick prompts are bordered, tappable bubbles.
- Settings (sidebar footer, a custom-designed page): your name, custom instructions added to every chat, System/Light/Dark theme, delete all chats, Help and Privacy pages.
- States: empty list, empty chat (greeting + starter prompts), typing indicator, and errors with **Retry** — no network, timeout, invalid key, limit reached (402/429), model unavailable, server error, missing key. After a restart, a chat ending in an unanswered message also offers Retry.
- Light and dark themes; design kit applied (red accent, 16px cards, 48px controls, onboarding on first launch).
- iOS 18 minimum (no newer APIs used), macOS 15 target `AIChatMac` sharing the same code.
- Dependencies: none (Swift Package Manager only, no packages needed).

## Not done / known issues
- Photo attachments and offline Apple Foundation Models mode (optional items) — not implemented.
- Onboarding uses SF Symbols instead of the robot illustrations from the design kit (no exported assets); Urbanist font not bundled (system font used).
- Login/sign-up/OTP, the Pro banner, Notifications, Security and Logout from the design kit are intentionally skipped (no accounts or backend in the task).
- Only an iOS 26.5 simulator was available for testing; iOS 18 is covered by API choice, not by a run on an iOS 18 runtime.
- Syntax highlighting is a lightweight, language-agnostic highlighter (keywords, types, strings, numbers, comments), not a full grammar; no images or nested block quotes in Markdown.
- The free model can be rate limited (429); the app shows the error with Retry.
- Context sent to the model is capped to the last 30 messages.
- The macOS target builds, but I did not run or visually check it.

## How it was verified
- 38 unit tests (plus 2 opt-in live tests, skipped by default) and 2 UI tests (`xcodebuild test`): SSE parser, error mapping, key round-trip, and `ChatEngine` with a mock backend (send, stream, failure leaves no empty bubble, retry after failure and after mid-stream error, stop keeps partial, blank input ignored, context cap). One of these caught a real bug (Retry did nothing after a mid-stream error).
- Opt-in live tests against the real API: `TEST_RUNNER_RUN_LIVE_TESTS=1 xcodebuild test ...` — streamed a real reply; an invalid key maps to "unauthorized".
- `Build.command` run end to end (generate, build, install, launch); iOS and macOS targets both build.
- Checked that the built `.app` contains no plain-text key.
- UI tests (`UITests/`) tap through home, a mode, the sidebar and Settings and assert that switching to Dark really turns the Settings page and home dark (background brightness is sampled), and that a seeded Markdown reply renders (no raw `##`) and Copy flips to "Copied". The seed uses debug-only launch args (`-uiTestInMemory -uiTestSeedMarkdown`, in-memory store, not compiled into Release). The toast itself is checked in a screenshot only. Sending a real message through the UI was not automated.

## Docs
`docs/TASK.md` (task), `docs/PLAN.md` (plan), `CLAUDE.md` (agent rules), `ai-logs/` (AI session logs, secrets redacted).
