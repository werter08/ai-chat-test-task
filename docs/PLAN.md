# Plan

Goal: the test task in `TASK.md` — an AI chat app for iPhone (iOS 18+), built with AI tools in one working day.

## Decisions
| Topic | Decision | Why |
|---|---|---|
| UI | SwiftUI, `NavigationSplitView` | One codebase: iPhone stack, iPad/Mac split view |
| Persistence | SwiftData (`Chat` 1—* `Message`, cascade delete) | Native, iOS 17+, autosave |
| Streaming | `URLSession.bytes` → SSE line parser → `AsyncThrowingStream<String>` | No dependencies, cancellable |
| Orchestration | `@Observable ChatEngine`, one task per chat | Generation continues if user switches chats; Stop = cancel task |
| AI | OpenRouter, free model `baidu/ernie-5.5-flash-preview:free` | Free, OpenAI-compatible API |
| Key | `.env` → `scripts/obfuscate_key.swift` → XOR+salt byte arrays in generated Swift file | Not plain text in repo/binary strings; app runs without setup. Obfuscation ≠ security (documented) |
| Project | XcodeGen `project.yml`, no packages | Task requirement |
| Mac | Second target `AIChatMac` sharing `Shared/` | Optional extra |

## Steps
1. Docs, rules, `.gitignore`.
2. Scaffold: `project.yml`, `Build.command`, key obfuscation script.
3. Networking: SSE parser, error mapping, `OpenRouterClient` (+ unit tests).
4. Models + `ChatEngine` (send / stop / retry) (+ unit tests with mock client).
5. UI: chat list, chat view, composer (send/stop), error banner with Retry, empty and loading states.
6. macOS target.
7. Verify on simulator, README, export `ai-logs/`.

## States to cover
- Empty list, empty chat (with suggestion prompts), waiting for first token (typing indicator), streaming, stopped (partial kept), error: no network / timeout / invalid key / limit exhausted (402/429) / model unavailable / server / missing key — all with Retry. After a restart, a chat ending with an unanswered user message also offers Retry.

## Out of scope for now
Photo attachments, Apple Foundation Models offline mode.
