import AVFoundation
import Speech
import Foundation

@Observable
@MainActor
final class VoiceOpsManager {
    enum VoiceState: Equatable {
        case idle
        case requestingPermission
        case ready           // has permission, not recording
        case recording       // actively listening
        case processing      // transcript received, sending to agent
        case speaking        // TTS playing response
        case unavailable(String)
    }

    private(set) var state: VoiceState = .idle
    private(set) var liveTranscript: String = ""     // partial transcript while recording
    private(set) var finalTranscript: String = ""    // confirmed transcript
    private(set) var isSpeaking: Bool = false
    private(set) var hasPermission: Bool = false

    // Called when a finalized transcript is ready to send
    var onTranscriptReady: ((String) -> Void)?
    // Called when the user wants to interrupt current speech
    var onInterrupt: (() -> Void)?

    // Private components
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    private let speechSynthesizer = AVSpeechSynthesizer()

    init() {
        speechSynthesizer.delegate = SpeechSynthesizerDelegate(manager: self)
    }

    var isRecording: Bool {
        if case .recording = state { return true }
        return false
    }

    // MARK: - Permissions

    func requestPermissions() async {
        state = .requestingPermission

        // Request speech recognition permission
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

        // Request microphone permission
        let micStatus = await AVAudioApplication.requestRecordPermission()

        guard micStatus else {
            state = .unavailable("Microphone access not authorized")
            hasPermission = false
            return
        }

        // Check if speech recognizer is available
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

        // Stop any ongoing speech
        if isSpeaking {
            stopSpeaking()
            onInterrupt?()
        }

        // Cancel any existing recording
        if audioEngine.isRunning {
            stopRecording()
        }

        // Configure audio session
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .allowBluetooth])
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

        // Configure audio input
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }

        // Start audio engine
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

        // Wait a moment for final recognition result
        Task {
            try? await Task.sleep(nanoseconds: 200_000_000) // 0.2 seconds

            let transcript = finalTranscript.isEmpty ? liveTranscript : finalTranscript

            if !transcript.isEmpty {
                onTranscriptReady?(transcript)
            }

            liveTranscript = ""
            finalTranscript = ""
            state = .ready
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

    // MARK: - Text-to-Speech

    func speak(_ text: String) {
        // Stop any ongoing speech
        if isSpeaking {
            stopSpeaking()
        }

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = 0.52
        utterance.pitchMultiplier = 0.95
        utterance.volume = 1.0

        // Configure audio session for playback
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            try audioSession.setActive(true)
        } catch {
            print("Audio session configuration failed: \(error)")
        }

        isSpeaking = true
        state = .speaking
        speechSynthesizer.speak(utterance)
    }

    func stopSpeaking() {
        guard isSpeaking else { return }

        speechSynthesizer.stopSpeaking(at: .immediate)
        isSpeaking = false
        state = .ready
    }

    // MARK: - Speech Synthesizer Delegate

    private class SpeechSynthesizerDelegate: NSObject, AVSpeechSynthesizerDelegate {
        weak var manager: VoiceOpsManager?

        init(manager: VoiceOpsManager) {
            self.manager = manager
        }

        func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
            Task { @MainActor in
                self.manager?.isSpeaking = false
                if self.manager?.state == .speaking {
                    self.manager?.state = .ready
                }
            }
        }

        func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
            Task { @MainActor in
                self.manager?.isSpeaking = false
                if self.manager?.state == .speaking {
                    self.manager?.state = .ready
                }
            }
        }
    }
}
