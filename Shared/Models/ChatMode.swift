import Foundation

/// A conversation "tab": changes the system prompt and the starter prompts. `nil` mode = general chat.
enum ChatMode: String, CaseIterable, Identifiable {
    case writing, creative, conversation, personal, developer

    var id: String { rawValue }

    var title: String {
        switch self {
        case .writing: "Writing"
        case .creative: "Creative"
        case .conversation: "Conversation"
        case .personal: "Personal"
        case .developer: "Developer"
        }
    }

    var symbol: String {
        switch self {
        case .writing: "pencil.line"
        case .creative: "paintpalette"
        case .conversation: "bubble.left.and.bubble.right"
        case .personal: "person.crop.circle"
        case .developer: "chevron.left.forwardslash.chevron.right"
        }
    }

    var blurb: String {
        switch self {
        case .writing: "Craft emails, blog posts, product descriptions, and more."
        case .creative: "Brainstorm ideas, write stories, poems, or captions."
        case .conversation: "Chat casually, learn something new, or practice a language."
        case .personal: "Get reminders, routines, journaling prompts or life advice."
        case .developer: "Generate code, debug, or explain technical concepts."
        }
    }

    var cta: String {
        switch self {
        case .writing: "Start Writing"
        case .creative: "Get Creative"
        case .conversation: "Let's Talk"
        case .personal: "Personal Assistant"
        case .developer: "Dev Tools"
        }
    }

    var introTitle: String {
        switch self {
        case .writing: "Writing Mode ✍️"
        case .creative: "Creative Mode 🎨"
        case .conversation: "Conversation Mode 💬"
        case .personal: "Personal Mode 🌱"
        case .developer: "Developer Mode 🛠️"
        }
    }

    var intro: String {
        switch self {
        case .writing: "Welcome to your writing desk. I can draft and polish emails, posts, descriptions and more.\n\nWhat would you like to write today?"
        case .creative: "Welcome to your creative space. I can help you write stories, brainstorm ideas, come up with captions, names, quotes, poetry — or anything fun and imaginative.\n\nWhat would you like to create today?"
        case .conversation: "Let's chat. Ask me anything, learn something new, or practice a language with me.\n\nWhat's on your mind?"
        case .personal: "I can help with routines, reminders, journaling prompts and everyday advice.\n\nWhat would you like to work on?"
        case .developer: "I can write and explain code, help debug, and break down technical concepts.\n\nWhat are you building?"
        }
    }

    var quickPrompts: [String] {
        switch self {
        case .writing: ["Write a professional email asking for a deadline extension", "Draft a product description for a leather backpack", "Rewrite this to sound friendlier: \"Send me the report.\"", "Outline a blog post about remote work"]
        case .creative: ["Write a short story", "Give me name ideas for a brand", "Generate Instagram captions", "Brainstorm YouTube video topics", "Write a love poem"]
        case .conversation: ["Teach me something surprising", "Let's practice Spanish at a beginner level", "Explain how HTTPS works in simple words", "Ask me an interesting question"]
        case .personal: ["Plan a simple morning routine for me", "Give me 5 journaling prompts", "Help me build a weekly study schedule", "How can I sleep better?"]
        case .developer: ["Explain async/await in Swift", "Write a function that debounces calls", "What is the difference between a struct and a class?", "Review this code for bugs"]
        }
    }

    var systemPrompt: String {
        switch self {
        case .writing: "Mode: writing assistant. Produce polished, ready-to-use text and offer to adjust tone or length."
        case .creative: "Mode: creative partner. Be imaginative, offer multiple options, and ask if the user wants another style."
        case .conversation: "Mode: friendly conversation partner. Keep a natural, warm tone; for language practice, gently correct mistakes."
        case .personal: "Mode: personal assistant. Give practical, kind, actionable advice. You are not a doctor or lawyer; suggest professionals for serious matters."
        case .developer: "Mode: software engineering assistant. Give correct, idiomatic code with brief explanations; state assumptions."
        }
    }
}
