import AVFoundation
import Observation
import OSLog
import Speech

// Speech-to-text input (Apple Speech framework). Dictated text is placed into the message box *before* sending.

/// Combines what was already in the text box with the running transcript of the current dictation.
enum SpeechTextMerger {
    nonisolated static func merge(base: String, transcript: String) -> String {
        let spoken = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !spoken.isEmpty else { return base }
        guard !base.trimmingCharacters(in: .whitespaces).isEmpty else { return spoken }
        let separator = (base.last?.isWhitespace == true) ? "" : " "
        return base + separator + spoken
    }
}

enum SpeechError: LocalizedError, Equatable {
    case speechDenied
    case microphoneDenied
    case unavailable(String)

    var errorDescription: String? { message }

    var message: String {
        switch self {
        case .speechDenied: "Speech recognition is off. Allow it for this app in the system Settings."
        case .microphoneDenied: "Microphone access is off. Allow it for this app in the system Settings."
        case .unavailable(let detail): detail
        }
    }
}

/// Abstraction over the recognizer so the UI can be tested with a fake (see `-uiTestFakeSpeech`).
@MainActor
protocol SpeechService: AnyObject {
    /// Asks for permission if needed, then starts listening. `onText` receives the *full* transcript so far
    /// (each call replaces the previous one); `onEnd` fires when listening stops on its own — with a short
    /// user-facing reason when it stopped because of a problem (nil = a normal end).
    func start(onText: @escaping @MainActor (String) -> Void, onEnd: @escaping @MainActor (String?) -> Void) async throws
    func stop()
}

// MARK: - Apple Speech implementation

@MainActor
final class AppleSpeechService: SpeechService {
    private let audioEngine = AVAudioEngine()
    private let log = Logger(subsystem: "app.aichat", category: "speech")
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var isRunning = false
    private var heardSomething = false
    /// Distinguishes recognition tasks, so a late callback from a cancelled one is ignored.
    private var generation = 0

    func start(onText: @escaping @MainActor (String) -> Void, onEnd: @escaping @MainActor (String?) -> Void) async throws {
        guard !isRunning else { return }
        try await requestPermissions()

        // The device language first; on-device models cover only a limited set of languages, so fall back to English.
        let recognizer = [Locale.current, Locale(identifier: "en-US")]
            .compactMap { SFSpeechRecognizer(locale: $0) }
            .first { $0.isAvailable }
        guard let recognizer else {
            throw SpeechError.unavailable("Speech recognition isn't available for your language right now.")
        }
        heardSomething = false
        // Prefer fully on-device recognition (private, works offline) where the language supports it; if that
        // fails before anything was recognised (e.g. the model is not downloaded) it is retried through Apple's servers.
        let onDevice = recognizer.supportsOnDeviceRecognition
        log.info("start: locale=\(recognizer.locale.identifier, privacy: .public) onDevice=\(onDevice, privacy: .public)")
        try beginSession(recognizer: recognizer, onDevice: onDevice, mayFallBack: onDevice, onText: onText, onEnd: onEnd)
    }

    func stop() {
        guard isRunning else { return }
        teardown()
    }

    private func beginSession(
        recognizer: SFSpeechRecognizer,
        onDevice: Bool,
        mayFallBack: Bool,
        onText: @escaping @MainActor (String) -> Void,
        onEnd: @escaping @MainActor (String?) -> Void
    ) throws {
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = onDevice

        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: .duckOthers)
        try session.setActive(true, options: .notifyOthersOnDeactivation)
        #endif

        let input = audioEngine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw SpeechError.unavailable("No microphone input is available.")
        }
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }
        audioEngine.prepare()
        do { try audioEngine.start() } catch {
            input.removeTap(onBus: 0)
            throw SpeechError.unavailable("The microphone could not be started.")
        }

        generation += 1
        let mine = generation
        self.request = request
        isRunning = true
        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            let transcript = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal ?? false
            let nsError = error as NSError?
            Task { @MainActor [weak self] in
                guard let self, self.isRunning, self.generation == mine else { return }   // stopped / superseded
                if let transcript, !transcript.isEmpty {
                    self.heardSomething = true
                    onText(transcript)
                }
                if let nsError {
                    self.log.error("recognition error: \(nsError.domain, privacy: .public) \(nsError.code, privacy: .public) heard=\(self.heardSomething, privacy: .public) onDevice=\(onDevice, privacy: .public)")
                    if mayFallBack, !self.heardSomething {
                        // The on-device model failed before recognising anything: retry once through Apple's servers.
                        self.teardown()
                        do {
                            try self.beginSession(recognizer: recognizer, onDevice: false, mayFallBack: false, onText: onText, onEnd: onEnd)
                        } catch {
                            onEnd("Dictation could not be started.")
                        }
                        return
                    }
                    self.teardown()
                    onEnd(Self.userMessage(for: nsError, heardSomething: self.heardSomething))
                } else if isFinal {
                    self.teardown()
                    onEnd(nil)
                }
            }
        }
    }

    /// Maps a recognition error to a short message; nil means "a normal end, nothing to report".
    nonisolated static func userMessage(for error: NSError, heardSomething: Bool) -> String? {
        switch (error.domain, error.code) {
        case ("kAFAssistantErrorDomain", 1110):
            // "No speech detected": the session timed out. Normal if something was dictated before.
            return heardSomething ? nil : "I didn't hear anything. Check the microphone and try again."
        case ("kAFAssistantErrorDomain", 216), ("kLSRErrorDomain", 301):
            return nil   // cancelled
        case ("kLSRErrorDomain", 300):
            // Apple's recognizer failed to initialise (on-device and server attempts alike) before any audio was
            // processed. Observed on the iOS Simulator, which has no working speech engine.
            return "Speech recognition isn't working here (error 300). It usually doesn't work in the iOS Simulator — try a real iPhone or the Mac app."
        case ("kAFAssistantErrorDomain", 1101), ("kAFAssistantErrorDomain", 1107):
            return "Dictation is turned off on this device (Settings → Keyboard → Enable Dictation)."
        default:
            return "Dictation stopped (\(error.domain) \(error.code))."
        }
    }

    private func teardown() {
        isRunning = false
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
    }

    private func requestPermissions() async throws {
        let speech = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        guard speech == .authorized else { throw SpeechError.speechDenied }

        #if os(iOS)
        let microphone = await AVAudioApplication.requestRecordPermission()
        #else
        let microphone = await AVCaptureDevice.requestAccess(for: .audio)
        #endif
        guard microphone else { throw SpeechError.microphoneDenied }
    }
}

// MARK: - Controller used by the UI

@MainActor
@Observable
final class SpeechInput {
    private(set) var isListening = false
    @ObservationIgnored private let service: SpeechService
    @ObservationIgnored private var base = ""
    @ObservationIgnored private var starting = false

    init(service: SpeechService? = nil) {
        self.service = service ?? AppleSpeechService()
    }

    /// Starts dictation into the text box (keeping what is already typed), or stops it.
    /// `apply` receives the merged text for the box; `report` receives a user-facing problem message.
    func toggle(currentText: String, apply: @escaping @MainActor (String) -> Void, report: @escaping @MainActor (String) -> Void) {
        if isListening {
            stop()
            return
        }
        guard !starting else { return }
        starting = true
        base = currentText
        Task {
            defer { starting = false }
            do {
                try await service.start(
                    onText: { [weak self] transcript in
                        guard let self else { return }
                        apply(SpeechTextMerger.merge(base: self.base, transcript: transcript))
                    },
                    onEnd: { [weak self] reason in
                        self?.isListening = false
                        if let reason { report(reason) }
                    }
                )
                isListening = true
            } catch let error as SpeechError {
                report(error.message)
            } catch {
                report("Dictation could not be started.")
            }
        }
    }

    func stop() {
        guard isListening else { return }
        service.stop()
        isListening = false
    }
}
