# Plan

Goal: the test task in [`TASK.md`](TASK.md) — an AI chat app for iPhone (iOS 18+), built with AI tools in one working day.
How the result is built: [`ARCHITECTURE.md`](ARCHITECTURE.md). How it was verified: [`TESTING.md`](TESTING.md).

## Decisions (made up front)
| Topic | Decision | Why |
|---|---|---|
| UI | SwiftUI | One codebase for iPhone / iPad / Mac |
| Persistence | SwiftData (`Chat` 1—* `Message`, cascade delete) | Native, iOS 17+, autosave |
| Streaming | `URLSession.bytes` → SSE line parser → `AsyncThrowingStream<String>` | No dependencies, cancellable |
| Orchestration | `@Observable ChatEngine`, one task per chat | Generation continues if the user switches chats; Stop = cancel task |
| AI | OpenRouter, free model `baidu/ernie-5.5-flash-preview:free` | Free, OpenAI-compatible API |
| Key | `.env` → `scripts/obfuscate_key.swift` → XOR+salt byte arrays in a generated Swift file | Not plain text in source/binary; app runs without setup. Obfuscation ≠ security (documented) |
| Project | XcodeGen `project.yml`, no packages | Task requirement |
| Mac | Second target `AIChatMac` sharing `Shared/` | Optional extra |

## Steps and status
| # | Step | Status |
|---|---|---|
| 1 | Docs, rules, `.gitignore` | done |
| 2 | Scaffold: `project.yml`, `Build.command`, key obfuscation | done |
| 3 | Networking: SSE parser, error mapping, `OpenRouterClient` (+ tests) | done |
| 4 | Models + `ChatEngine` (send / stop / retry) (+ tests) | done |
| 5 | UI: chat, composer (send/stop), error banner with Retry, empty and loading states | done |
| 6 | macOS target | done (builds; not run by hand) |
| 7 | Design kit applied (accent, onboarding, cards, composer) | done |
| 8 | Modes, drawer sidebar with history/search, custom Settings, personalization | done |
| 9 | Markdown rendering, code blocks with syntax colors, copy / share | done |
| 10 | Reply animation: sentence-by-sentence fade-in, read-from-top scrolling, "Go down" | done |
| 11 | Verification: unit + UI tests, live API tests, screenshots | done |
| 12 | README, docs, redacted AI logs | done (hours: fill in) |
| 13 | Photo attachments (picker, preview above the text box, vision model) | done — tests written, not run |
| 14 | Dictation with Apple Speech (text appears in the box before sending) | done — tests written, not run |
| — | Offline Apple Foundation Models mode | not done (optional) |

## What changed versus the original plan
- **Model id:** the bare id from the provider doc (`baidu/ernie-5.5-flash-preview`) returns 404 ("no endpoints"). The free variant needs the `:free` suffix. Found with a live request before any UI work depended on it.
- **Navigation:** the planned `NavigationSplitView` list was replaced by a chat-first screen: the app opens on an empty chat; history lives in a push-style drawer.
- **Design kit** arrived mid-way and drove the visual language (red accent, 16px cards, 48px controls); login/sign-up/OTP screens from it were deliberately skipped (no accounts in the task).
- **Reply rendering** grew from plain text to a Markdown renderer after a screenshot showed raw `##` and flattened code.
- **Stop** became a first-class state ("You stopped the response." note) after it surfaced as an API error.
- **Testing** grew from unit tests to UI tests with screenshots, because several visual bugs (dark mode not applying, drawer stuck, blank reopened chat, clipped content) were invisible to unit tests.

## States covered
- Empty chat (greeting + mode cards), waiting for first token (typing indicator), streaming (sentence fade-in, Stop pill), stopped (note + Retry), error: no network / timeout / invalid key / limit exhausted (402/429) / model unavailable / server / missing key — all with Retry. After a restart, a chat ending with an unanswered user message also offers Retry.

## Out of scope for now
Photo attachments, Apple Foundation Models offline mode.
