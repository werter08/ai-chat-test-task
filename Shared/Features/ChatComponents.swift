import PhotosUI
import SwiftUI

private struct StagedHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

private struct RevealKey: Hashable {
    let count: Int
    let streaming: Bool
}

struct TypingCursor: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 1.5)
            .fill(Color.accentColor)
            .frame(width: 3, height: 18)
            .phaseAnimator([1.0, 0.15]) { content, phase in
                content.opacity(phase)
            } animation: { _ in
                .easeInOut(duration: 0.5)
            }
            .accessibilityHidden(true)
    }
}

/// Actions offered under the assistant's "photos are unavailable" message.
struct PhotoRecovery {
    let tryAgain: () -> Void
    let sendWithoutPhoto: () -> Void
}

struct MessageBubble: View {
    let message: Message
    let isStreaming: Bool
    let photoRecovery: PhotoRecovery?
    @Environment(Toast.self) private var toast
    @State private var copied = false
    /// True while the reply is being revealed sentence by sentence (only for replies streamed right now).
    @State private var isStaging: Bool
    /// When each unit (sentence / list item / block) became available, as seconds since the reference date.
    @State private var eligible: [Double] = []
    @State private var now = Date.timeIntervalSinceReferenceDate
    /// Natural height of the staged content; the visible frame animates towards it.
    @State private var stagedHeight: CGFloat = 0

    init(message: Message, isStreaming: Bool = false, photoRecovery: PhotoRecovery? = nil) {
        self.message = message
        self.isStreaming = isStreaming
        self.photoRecovery = photoRecovery
        // Stored history appears instantly; only a reply that is streaming right now is revealed gradually.
        _isStaging = State(initialValue: isStreaming)
    }

    private var isUser: Bool { message.role == .user }

    private var shape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            cornerRadii: .init(
                topLeading: Theme.cardRadius,
                bottomLeading: isUser ? Theme.cardRadius : 4,
                bottomTrailing: isUser ? 4 : Theme.cardRadius,
                topTrailing: Theme.cardRadius
            ),
            style: .continuous
        )
    }

    var body: some View {
        HStack(alignment: .top, spacing: Theme.spacing2) {
            if isUser { Spacer(minLength: 48) }
            VStack(alignment: .leading, spacing: 4) {
                bubble
                    .contextMenu {
                        Button(action: copyMessage) { Label("Copy", systemImage: "doc.on.doc") }
                        ShareLink(item: message.content) { Label("Share", systemImage: "square.and.arrow.up") }
                    }
                // Actions sit below the finished reply (never while it is still being written).
                if !isUser && !isStaging {
                    if let photoRecovery {
                        recoveryActions(photoRecovery)
                            .transition(.opacity)
                    } else {
                        copyButton
                            .transition(.opacity)
                    }
                }
            }
            .frame(maxWidth: isUser ? 560 : 680, alignment: isUser ? .trailing : .leading)
            .animation(.easeOut(duration: 0.25), value: isStaging)
            if !isUser { Spacer(minLength: 0) }
        }
    }

    private func recoveryActions(_ recovery: PhotoRecovery) -> some View {
        HStack(spacing: Theme.spacing2) {
            Button("Send without photo", action: recovery.sendWithoutPhoto)
                .buttonStyle(PrimaryButtonStyle())
                .frame(maxWidth: 200)
            Button("Try again", action: recovery.tryAgain)
                .buttonStyle(PrimaryButtonStyle(tinted: true))
                .frame(maxWidth: 130)
        }
        .padding(.top, 4)
    }

    private var copyButton: some View {
        Button(action: copyMessage) {
            HStack(spacing: 5) {
                Image(systemName: copied ? "checkmark.circle.fill" : "doc.on.doc")
                    .contentTransition(.symbolEffect(.replace))
                Text(copied ? "Copied" : "Copy")
            }
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(copied ? Color.green : .secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(copied ? "Copied" : "Copy")
        .sensoryFeedback(.success, trigger: copied) { _, new in new }
    }

    @ViewBuilder
    private var bubble: some View {
        if isUser {
            let hasText = !message.content.isEmpty
            VStack(alignment: .leading, spacing: 8) {
                if !message.attachments.isEmpty {
                    AttachmentGrid(attachments: message.sortedAttachments)
                }
                if hasText {
                    Text(InlineMarkdown.attributed(message.content))
                        .font(.system(size: 16))
                        .lineSpacing(3)
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, message.attachments.isEmpty ? 0 : 6)
                }
            }
            .padding(.horizontal, hasText && message.attachments.isEmpty ? 14 : 6)
            .padding(.vertical, hasText && message.attachments.isEmpty ? 10 : 6)
            .padding(.bottom, hasText && !message.attachments.isEmpty ? 4 : 0)
            .background(Color.accentColor, in: shape)
            .accessibilityElement(children: .contain)
        } else if isStaging {
            stagedBubble
        } else {
            MarkdownView(text: message.content)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(Theme.fill, in: shape)
        }
    }

    /// While being revealed, the bubble's height is measured and *animated*: the full text is laid out at its
    /// natural size, and a clipping frame grows smoothly to it, so new sentences ease in instead of the whole
    /// message jumping a line at a time.
    private var stagedBubble: some View {
        VStack(alignment: .leading, spacing: 6) {
            StagedMarkdownView(
                content: StagedText.prepare(message.content, finished: !isStreaming),
                alphas: StagedText.alphas(eligible: eligible, at: now)
            )
            // The cursor only shows while the network is still writing, so the end of the reply never snaps.
            if isStreaming { TypingCursor() }
        }
        .fixedSize(horizontal: false, vertical: true)
        .background(
            GeometryReader { proxy in
                Color.clear.preference(key: StagedHeightKey.self, value: proxy.size.height)
            }
        )
        .onPreferenceChange(StagedHeightKey.self) { stagedHeight = $0 }
        .frame(height: stagedHeight > 0 ? stagedHeight : nil, alignment: .top)
        .clipped()
        .animation(.smooth(duration: 0.45), value: stagedHeight)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Theme.fill, in: shape)
        .task(id: RevealKey(count: message.content.count, streaming: isStreaming)) { await drive() }
    }

    /// Drives the sentence-by-sentence fade: registers newly available units and ticks the clock until
    /// everything is fully visible; when the reply is finished the bubble switches to normal rendering.
    private func drive() async {
        guard isStaging else { return }
        let content = StagedText.prepare(message.content, finished: !isStreaming)
        let arrival = Date.timeIntervalSinceReferenceDate
        while eligible.count < content.unitCount { eligible.append(arrival) }

        while !Task.isCancelled {
            now = Date.timeIntervalSinceReferenceDate
            let alphas = StagedText.alphas(eligible: eligible, at: now)
            if alphas.allSatisfy({ $0 >= 1 }) {
                if !isStreaming {
                    isStaging = false   // finished: render the full text normally, Copy row appears
                }
                return   // otherwise idle until more text arrives (the task restarts with it)
            }
            try? await Task.sleep(for: .milliseconds(33))
        }
    }

    private func copyMessage() {
        Clipboard.copy(message.content)
        toast.show("Copied to clipboard")
        withAnimation(.snappy) { copied = true }
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            withAnimation(.snappy) { copied = false }
        }
    }
}

/// Floating "go to the latest message" bubble, shown when the reply is ready and part of it is below the fold.
struct GoDownButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.down")
                    .font(.system(size: 13, weight: .bold))
                Text("Go down")
                    .font(.system(size: 14, weight: .semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.accentColor, in: Capsule())
            .shadow(color: .black.opacity(0.25), radius: 8, y: 3)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Go down")
    }
}

/// Photos of a sent message, shown above its text inside the bubble.
struct AttachmentGrid: View {
    let attachments: [Attachment]

    var body: some View {
        if attachments.count == 1, let only = attachments.first {
            photo(only, size: 220)
        } else {
            LazyVGrid(columns: [GridItem(.fixed(108), spacing: 6), GridItem(.fixed(108), spacing: 6)], spacing: 6) {
                ForEach(attachments) { photo($0, size: 108) }
            }
            .frame(width: 222, alignment: .leading)
        }
    }

    private func photo(_ attachment: Attachment, size: CGFloat) -> some View {
        PhotoThumbnail(data: attachment.data, size: size, corner: 12)
            .accessibilityLabel("Attached photo")
            .accessibilityAddTraits(.isImage)
    }
}

/// Centered, display-only line such as "You stopped the response." (with Retry when it is the last item).
struct NoteRow: View {
    let text: String
    let onRetry: (() -> Void)?

    var body: some View {
        HStack(spacing: Theme.spacing2) {
            Image(systemName: "stop.circle")
            Text(text)
            if let onRetry {
                Button("Retry", action: onRetry)
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.accentColor)
                    .fontWeight(.semibold)
            }
        }
        .font(.system(size: 13))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Theme.fill, in: Capsule())
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

struct TypingIndicator: View {
    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(Color.secondary)
                    .frame(width: 8, height: 8)
                    .phaseAnimator([0.4, 1.0]) { content, phase in
                        content.opacity(phase)
                    } animation: { _ in
                        .easeInOut(duration: 0.5).delay(Double(index) * 0.15)
                    }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .background(Theme.fill, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .accessibilityLabel("Assistant is typing")
    }
}

struct ErrorBanner: View {
    let error: ChatAPIError
    let onRetry: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(error.title).font(.subheadline.weight(.semibold))
                Text(error.message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Button("Retry", action: onRetry)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        }
        .padding(12)
        .background(Color.accentColor.opacity(0.10), in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var icon: String {
        switch error {
        case .offline: "wifi.slash"
        case .timeout: "clock.badge.exclamationmark"
        case .insufficientCredits, .rateLimited: "gauge.with.dots.needle.100percent"
        default: "exclamationmark.triangle.fill"
        }
    }
}

/// "Stop generating…" pill shown above the composer while a reply streams.
struct StopPill: View {
    let onStop: () -> Void

    var body: some View {
        Button(action: onStop) {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 2).fill(Color.accentColor).frame(width: 12, height: 12)
                Text("Stop generating…").font(.system(size: 14, weight: .medium))
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, Theme.spacing3)
            .padding(.vertical, 10)
            .background(Theme.fill, in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Stop generating")
    }
}

struct ModeCard: View {
    let mode: ChatMode
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: Theme.spacing2) {
                HStack(spacing: 8) {
                    Image(systemName: mode.symbol)
                        .foregroundStyle(isSelected ? Color.accentColor : .primary)
                    Text(mode.title)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(isSelected ? Color.accentColor : .primary)
                }
                Text(mode.blurb)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Text(mode.cta)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.accentColor : .primary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(Theme.spacing3)
            .frame(maxWidth: .infinity, minHeight: 140, alignment: .topLeading)
            .background(
                isSelected ? Color.accentColor.opacity(0.10) : Theme.fill,
                in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                    .strokeBorder(isSelected ? Color.accentColor.opacity(0.6) : Theme.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(mode.title). \(mode.blurb) \(mode.cta)")
    }
}

/// Empty chat content: greeting + mode cards (general), or the selected mode's intro + quick prompts.
struct EmptyChatContent: View {
    let mode: ChatMode?
    let userName: String
    let onSelectMode: (ChatMode) -> Void
    let onClearMode: () -> Void
    let onPrompt: (String) -> Void

    private var greeting: String {
        let name = userName.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "Hey there 👋" : "Hey \(name) 👋"
    }

    var body: some View {
        ScrollView {
            if let mode {
                modeIntro(mode)
            } else {
                general
            }
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private var general: some View {
        VStack(spacing: Theme.spacing4) {
            VStack(spacing: Theme.spacing2) {
                Text(greeting)
                    .font(.display(32))
                Text("What would you like to do today?")
                    .font(.system(size: 18, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)
            .padding(.top, Theme.spacing4)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: Theme.spacing2)], spacing: Theme.spacing2) {
                ForEach(ChatMode.allCases) { mode in
                    ModeCard(mode: mode, isSelected: false) { onSelectMode(mode) }
                }
            }
        }
        .padding(.horizontal, Theme.spacing3)
        .padding(.bottom, Theme.spacing3)
    }

    private func modeIntro(_ mode: ChatMode) -> some View {
        VStack(alignment: .leading, spacing: Theme.spacing3) {
            Button(action: onClearMode) {
                HStack(spacing: 6) {
                    Text(mode.title)
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                }
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color.accentColor, in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(mode.title) mode. Tap to leave this mode")

            VStack(spacing: Theme.spacing2) {
                Text(mode.introTitle).font(.system(size: 18, weight: .semibold, design: .rounded))
                Text(mode.intro)
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)

            Text("🎯 Quick Prompts")
                .font(.system(size: 15, weight: .semibold))
                .padding(.top, Theme.spacing2)
            VStack(spacing: Theme.spacing2) {
                ForEach(mode.quickPrompts, id: \.self) { prompt in
                    Button { onPrompt(prompt) } label: {
                        HStack(spacing: Theme.spacing2) {
                            Text(prompt)
                                .font(.system(size: 15, weight: .medium))
                                .multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .foregroundStyle(Color.accentColor)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                                .strokeBorder(Color.accentColor.opacity(0.45), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, Theme.spacing3)
        .padding(.bottom, Theme.spacing3)
    }
}

/// How much room the message editor takes: one line (grows to 6), 30% of the screen, or the whole screen.
enum ComposerSize {
    case compact, third, full

    var next: ComposerSize {
        switch self {
        case .compact: .third
        case .third: .full
        case .full: .compact
        }
    }
}

/// Composer from the design kit: rounded input + red rounded-square send/stop button.
/// While focused the field glows; the corner button cycles compact → 30% → full screen → compact.
/// Photos picked for the message appear in a strip *above* the text box; the mic dictates into the box.
struct ComposerView: View {
    @Binding var text: String
    @Binding var size: ComposerSize
    @Binding var images: [DraftImage]
    let isGenerating: Bool
    let availableHeight: CGFloat
    let onSend: () -> Void
    let onStop: () -> Void

    @Environment(SpeechInput.self) private var speech
    @Environment(Toast.self) private var toast
    @FocusState private var focused: Bool
    @State private var pickerItems: [PhotosPickerItem] = []

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !images.isEmpty
    }

    private var photosFull: Bool { images.count >= ImageProcessing.maxPhotosPerMessage }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
    }

    private var placeholder: String { speech.isListening ? "Listening…" : "Ask me anything…" }

    var body: some View {
        VStack(spacing: Theme.spacing2) {
            if !images.isEmpty { attachmentStrip }

            // Compact: tools, field and send button side by side. Expanded (30% / full): editor on top, tools and a
            // full-width send button below.
            if size == .compact {
                HStack(alignment: .bottom, spacing: Theme.spacing2) {
                    photoButton.padding(.bottom, 4)
                    field
                    micButton.padding(.bottom, 4)
                    sendButton(wide: false)
                }
            } else {
                VStack(spacing: Theme.spacing2) {
                    field
                    HStack(spacing: Theme.spacing2) {
                        photoButton
                        micButton
                        sendButton(wide: true)
                    }
                }
            }
        }
        .padding(.horizontal, Theme.spacing3)
        .padding(.vertical, Theme.spacing2)
        .frame(maxHeight: size == .full ? .infinity : nil, alignment: .bottom)
        .background {
            // Full-screen compose blends with the page; otherwise the composer sits on a bar material.
            if size == .full { Color.clear } else { Rectangle().fill(.bar).ignoresSafeArea(edges: .bottom) }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: size)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: images.count)
    }

    // MARK: Photos

    private var attachmentStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.spacing2) {
                ForEach(images) { image in
                    ZStack(alignment: .topTrailing) {
                        PhotoThumbnail(data: image.jpeg, size: 68)
                            .accessibilityLabel("Photo to send")
                            .accessibilityAddTraits(.isImage)
                        Button { images.removeAll { $0.id == image.id } } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 20))
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(.white, Color.black.opacity(0.65))
                        }
                        .buttonStyle(.plain)
                        .offset(x: 6, y: -6)
                        .accessibilityLabel("Remove photo")
                    }
                }
            }
            .padding(.top, 8)
            .padding(.trailing, 8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var photoButton: some View {
        PhotosPicker(
            selection: $pickerItems,
            maxSelectionCount: max(1, ImageProcessing.maxPhotosPerMessage - images.count),
            matching: .images
        ) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 17))
                .foregroundStyle(Color.primary.opacity(0.8))
                .frame(width: 40, height: 40)
                .background(Theme.fill, in: shape)
                .contentShape(shape)
        }
        .buttonStyle(.plain)
        .disabled(photosFull)
        .opacity(photosFull ? 0.4 : 1)
        .accessibilityLabel("Add photo")
        .onChange(of: pickerItems) { loadPickedPhotos() }
    }

    private func loadPickedPhotos() {
        let items = pickerItems
        guard !items.isEmpty else { return }
        pickerItems = []
        Task {
            for item in items {
                guard images.count < ImageProcessing.maxPhotosPerMessage else { break }
                var loaded = (try? await item.loadTransferable(type: PickedPhoto.self))?.data
                if loaded == nil { loaded = try? await item.loadTransferable(type: Data.self) }
                guard let data = loaded else {
                    toast.show("That photo couldn't be loaded.", kind: .warning)
                    continue
                }
                let jpeg = await Task.detached { ImageProcessing.downscaledJPEG(from: data) }.value
                if let jpeg {
                    images.append(DraftImage(jpeg: jpeg))
                } else {
                    toast.show("That photo couldn't be read.", kind: .warning)
                }
            }
        }
    }

    // MARK: Dictation

    private var micButton: some View {
        Button(action: toggleDictation) {
            Image(systemName: speech.isListening ? "mic.fill" : "mic")
                .font(.system(size: 17))
                .foregroundStyle(speech.isListening ? Color.white : Color.primary.opacity(0.8))
                .frame(width: 40, height: 40)
                .background(speech.isListening ? Color.accentColor : Theme.fill, in: shape)
                .symbolEffect(.pulse, isActive: speech.isListening)
                .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(speech.isListening ? "Stop dictation" : "Dictate")
    }

    private func toggleDictation() {
        speech.toggle(
            currentText: text,
            apply: { text = $0 },
            report: { toast.show($0, kind: .warning) }
        )
    }

    // MARK: Field

    private var field: some View {
        ZStack(alignment: .topTrailing) {
            if size == .compact {
                TextField("Ask me anything…", text: $text, prompt: Text(placeholder), axis: .vertical)
                    .lineLimit(1...6)
                    .textFieldStyle(.plain)
                    .font(.system(size: 16))
                    .padding(.leading, 14)
                    .padding(.trailing, 44)
                    .frame(minHeight: Theme.controlHeight)
                    .focused($focused)
                    .onSubmit { if canSend && !isGenerating { onSend() } }
            } else {
                editor
            }
            sizeButton
        }
        .frame(maxHeight: size == .full ? .infinity : nil)
        .background(focused ? Color.accentColor.opacity(0.06) : Theme.fill, in: shape)
        .overlay(shape.strokeBorder(focused || speech.isListening ? Color.accentColor : Theme.border, lineWidth: focused || speech.isListening ? 2 : 1))
        .shadow(color: Color.accentColor.opacity(focused || speech.isListening ? 0.35 : 0), radius: focused || speech.isListening ? 10 : 0)
        .animation(.easeInOut(duration: 0.2), value: focused)
        .animation(.easeInOut(duration: 0.2), value: speech.isListening)
    }

    private var editor: some View {
        ZStack(alignment: .topLeading) {
            if text.isEmpty {
                Text(placeholder)
                    .font(.system(size: 16))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 8)
                    .allowsHitTesting(false)
            }
            TextEditor(text: $text)
                .font(.system(size: 16))
                .scrollContentBackground(.hidden)
                .focused($focused)
        }
        .padding(.leading, 9)
        .padding(.trailing, 44)
        .padding(.vertical, 6)
        .frame(height: size == .third ? max(120, availableHeight * 0.3) : nil)
        .frame(maxHeight: size == .full ? .infinity : nil)
    }

    private var sizeButton: some View {
        Button(action: cycleSize) {
            Image(systemName: size == .full ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(focused ? Color.accentColor : .secondary)
                .frame(width: 34, height: 34)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.top, 7)
        .padding(.trailing, 4)
        .accessibilityLabel(size == .full ? "Collapse input" : "Expand input")
    }

    private func cycleSize() {
        size = size.next
        // The text view is replaced when switching between compact and expanded: give focus back.
        Task {
            try? await Task.sleep(for: .milliseconds(60))
            focused = true
        }
    }

    // MARK: Send / stop

    private func sendButton(wide: Bool) -> some View {
        Button(action: isGenerating ? onStop : onSend) {
            HStack(spacing: Theme.spacing2) {
                Image(systemName: isGenerating ? "stop.fill" : "paperplane.fill")
                    .font(.system(size: 18, weight: .semibold))
                if wide {
                    Text(isGenerating ? "Stop" : "Send")
                        .font(.system(size: 16, weight: .semibold))
                }
            }
            .foregroundStyle(.white)
            .frame(maxWidth: wide ? .infinity : Theme.controlHeight)
            .frame(width: wide ? nil : Theme.controlHeight, height: Theme.controlHeight)
            .background(
                Color.accentColor.opacity(isGenerating || canSend ? 1 : 0.4),
                in: shape
            )
        }
        .buttonStyle(.plain)
        .disabled(!isGenerating && !canSend)
        .accessibilityLabel(isGenerating ? "Stop generating" : "Send message")
    }
}
