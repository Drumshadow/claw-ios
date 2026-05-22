import AVFoundation
import Speech
import Foundation

// MARK: - VoiceOpsManager

/// Manages the full voice operations cycle: permission → recording (speech recognition)
/// → command intent parsing → TTS response playback.
///
/// Integration:
/// - Set `onTranscriptReady` to receive finalized transcripts and handle routing.
///   For session-aware integration, use VoiceSessionBridge which sets this automatically.
/// - Set `onInterrupt` to handle cases where the user interrupts ongoing TTS.
/// - Wrap in VoiceOpsOverlay/VoiceDrivingModeView for full UI.
@Observable
@MainActor
final class VoiceOpsManager {

    // MARK: - VoiceState

    enum VoiceState: Equatable {
        case idle
        case requestingPermission
        case ready               // has permission, not recording
        case recording           // actively listening
        case processing          // transcript received, sending to agent
        case speaking            // TTS playing response
        case confirmationNeeded  // waiting for user to confirm risky command
        case unavailable(String)

        var isIdle: Bool {
            if case .idle = self { return true }
            return false
        }
    }

    // MARK: - Observable state

    private(set) var state: VoiceState = .idle
    private(set) var liveTranscript: String = ""     // partial transcript while recording
    private(set) var finalTranscript: String = ""    // confirmed transcript
    private(set) var isSpeaking: Bool = false
    private(set) var hasPermission: Bool = false
    private(set) var pendingConfirmationIntent: VoiceCommandIntent?

    // MARK: - Callbacks

    /// Called when a finalized transcript is ready to route to an agent.
    /// The VoiceSessionBridge uses this to perform the actual message send.
    var onTranscriptReady: ((String) -> Void)?

    /// Called when the user interrupts TTS playback by starting a new recording.
    var onInterrupt: (() -> Void)?

    /// Called when a risky command intent is identified and needs confirmation.
    /// View layer presents VoiceConfirmationView in response.
    var onConfirmationRequired: ((VoiceCommandIntent) -> Void)?

    // MARK: - Private components

    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    private let speechSynthesizer = AVSpeechSynthesizer()

    // MARK: - Init

    init() {
        speechSynthesizer.delegate = SpeechSynthesizerDelegate(manager: self)
    }

    // MARK: - Computed

    var isRecording: Bool {
        if case .recording = state { return true }
        return false
    }

    var isActive: Bool {
        switch state {
        case .idle, .unavailable: return false
        default: return true
        }
    }

    // MARK: - Permissions

    func requestPermissions() async {
        state = .requestingPermission

        let speechStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }

        guard speechStatus == .authorized else {
            state = .unavailable("Speech recognition not authorized")
            hasPermission = false
            return
        }

        let micStatus = await AVAudioApplication.requestRecordPermission()

        guard micStatus else {
            state = .unavailable("Microphone access not authorized")
            hasPermission = false
            return
        }

        guard speechRecognizer?.isAvailable == true else {
            state = .unavailable("Speech recognition unavailable")
            hasPermission = false
            return
        }

        hasPermission = true
        state = .ready
    }

    // MARK: - Recording

    func startRecording() {
        guard hasPermission else {
            Task { await requestPermissions() }
            return
        }

        // Interrupt ongoing TTS playback
        if isSpeaking {
            stopSpeaking()
            onInterrupt?()
        }

        // Cancel any existing recording session
        if audioEngine.isRunning {
            stopRecording()
        }

        // Configure audio session
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(
                .playAndRecord,
                mode: .measurement,
                options: [.defaultToSpeaker, .allowBluetooth])
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            state = .unavailable("Audio session configuration failed: \(error.localizedDescription)")
            return
        }

        // Create recognition request
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else {
            state = .unavailable("Unable to create recognition request")
            return
        }

        recognitionRequest.shouldReportPartialResults = true
        recognitionRequest.requiresOnDeviceRecognition = false

        // Start recognition task
        recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self = self else { return }
            Task { @MainActor in
                if let result = result {
                    self.liveTranscript = result.bestTranscription.formattedString
                    if result.isFinal {
                        self.finalTranscript = result.bestTranscription.formattedString
                    }
                }
                if error != nil {
                    self.stopRecording()
                }
            }
        }

        // Configure audio tap
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
            state = .recording
            liveTranscript = ""
            finalTranscript = ""
        } catch {
            state = .unavailable("Audio engine failed to start: \(error.localizedDescription)")
        }
    }

    func stopRecording() {
        guard isRecording else { return }

        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()

        state = .processing

        // Allow a brief window for the final recognition result to arrive
        Task {
            try? await Task.sleep(nanoseconds: 250_000_000) // 0.25s

            let transcript = finalTranscript.isEmpty ? liveTranscript : finalTranscript

            if !transcript.isEmpty {
                // Perform lightweight intent pre-parse to check if it's a confirm/cancel
                // shortcut when confirmation is pending
                let parsed = VoiceCommandParser.parse(transcript)
                if case .confirmationNeeded = state, parsed.category == .confirm || parsed.category == .cancel {
                    // Pass through to transcript handler for bridge to handle
                }
                onTranscriptReady?(transcript)
            }

            liveTranscript = ""
            finalTranscript = ""
            if case .processing = state {
                state = .ready
            }
        }
    }

    func cancelRecording() {
        guard isRecording else { return }

        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()

        liveTranscript = ""
        finalTranscript = ""
        state = .ready
    }

    // MARK: - Confirmation state management

    func enterConfirmationPending(for intent: VoiceCommandIntent) {
        pendingConfirmationIntent = intent
        state = .confirmationNeeded
    }

    func exitConfirmationPending() {
        pendingConfirmationIntent = nil
        if case .confirmationNeeded = state {
            state = .processing
        }
    }

    // MARK: - Text-to-Speech

    func speak(_ text: String) {
        guard !text.isEmpty else { return }

        if isSpeaking { stopSpeaking() }

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = 0.52
        utterance.pitchMultiplier = 0.95
        utterance.volume = 1.0

        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            try audioSession.setActive(true)
        } catch {
            // Non-fatal — TTS will still attempt playback
        }

        isSpeaking = true
        state = .speaking
        speechSynthesizer.speak(utterance)
    }

    func stopSpeaking() {
        guard isSpeaking else { return }
        speechSynthesizer.stopSpeaking(at: .immediate)
        isSpeaking = false
        if case .speaking = state { state = .ready }
    }

    // MARK: - Speech Synthesizer Delegate (private bridge class)

    private final class SpeechSynthesizerDelegate: NSObject, AVSpeechSynthesizerDelegate {
        weak var manager: VoiceOpsManager?
        init(manager: VoiceOpsManager) { self.manager = manager }

        func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
            Task { @MainActor in
                self.manager?.isSpeaking = false
                if case .speaking = self.manager?.state { self.manager?.state = .ready }
            }
        }

        func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
            Task { @MainActor in
                self.manager?.isSpeaking = false
                if case .speaking = self.manager?.state { self.manager?.state = .ready }
            }
        }
    }
}
