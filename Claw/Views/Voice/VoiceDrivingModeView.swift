import SwiftUI

// MARK: - VoiceDrivingModeView

/// Full-screen immersive driving/hands-busy voice operations mode.
///
/// Wires VoiceOpsManager + VoiceSessionBridge together:
/// - Push-to-talk (hold) → speech recognition → command intent → bridge send
/// - Dangerous commands → VoiceConfirmationView full-screen cover
/// - Agent response → TTS via VoiceOpsManager.speak()
///
/// Requires `client` and `sessionKey` for live message routing.
/// Falls back to echo-only mode if client/sessionKey are nil (preview/test).
struct VoiceDrivingModeView: View {
    @Bindable var manager: VoiceOpsManager
    var client: GatewayClient?
    var sessionKey: String?
    var onDismiss: () -> Void

    // Bridge created lazily when client+sessionKey are available
    @State private var bridge: VoiceSessionBridge?
    @State private var bridgeStatus: String = ""
    @State private var isBridgeActive: Bool = false

    // Confirmation
    @State private var pendingConfirmation: VoiceCommandIntent?
    @State private var showConfirmation: Bool = false

    // Response display
    @State private var lastResponse: String = ""
    @State private var pulseScale: CGFloat = 1.0

    var body: some View {
        ZStack {
            Color.clawBg.ignoresSafeArea()

            VStack(spacing: 0) {
                // Status header
                VStack(spacing: 8) {
                    Text(statusText)
                        .font(.system(size: 32, weight: .bold))
                        .foregroundStyle(.white)
                    Text(stateDescription)
                        .font(.title3)
                        .foregroundStyle(.white.opacity(0.7))
                }
                .padding(.top, 60)
                .frame(maxWidth: .infinity)

                Spacer()

                // Last response display
                if !lastResponse.isEmpty && !manager.isRecording {
                    ScrollView {
                        Text(lastResponse)
                            .font(.title2)
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.leading)
                            .padding(.horizontal, 40)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 300)
                    .padding(.bottom, 40)
                }

                // Live transcript while recording
                if manager.isRecording && !manager.liveTranscript.isEmpty {
                    VStack(spacing: 12) {
                        Text("You said:")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.5))
                            .textCase(.uppercase)
                        Text(manager.liveTranscript)
                            .font(.title2)
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                    }
                    .frame(maxHeight: 200)
                    .padding(.bottom, 40)
                }

                Spacer()

                // Bridge status bar
                if !bridgeStatus.isEmpty {
                    VoiceStatusBar(status: bridgeStatus, isActive: isBridgeActive)
                        .padding(.bottom, 20)
                }

                // Giant PTT button
                ZStack {
                    if manager.isRecording {
                        Circle()
                            .stroke(Color.clawDanger, lineWidth: 6)
                            .frame(width: 160, height: 160)
                            .scaleEffect(pulseScale)
                            .opacity(2.0 - pulseScale)
                            .animation(
                                .easeOut(duration: 1.5).repeatForever(autoreverses: false),
                                value: pulseScale
                            )
                            .onAppear { pulseScale = 1.5 }
                            .onDisappear { pulseScale = 1.0 }
                    }

                    Button(action: {}) {
                        ZStack {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: buttonGradientColors,
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 160, height: 160)
                            Image(systemName: buttonIcon)
                                .font(.system(size: 64))
                                .foregroundStyle(.white)
                        }
                        .scaleEffect(manager.isRecording ? 1.1 : 1.0)
                        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: manager.isRecording)
                    }
                    .simultaneousGesture(
                        LongPressGesture(minimumDuration: 0.1)
                            .simultaneously(with: DragGesture(minimumDistance: 0))
                            .onChanged { _ in
                                if !manager.isRecording && canRecord {
                                    manager.startRecording()
                                }
                            }
                            .onEnded { _ in
                                if manager.isRecording {
                                    manager.stopRecording()
                                }
                            }
                    )
                    .disabled(!canInteract)
                }
                .padding(.bottom, 20)

                Text(holdInstruction)
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.6))
                    .padding(.bottom, 40)

                Spacer()
            }

            // Footer row
            VStack {
                Spacer()
                HStack {
                    if sessionKey != nil {
                        HStack(spacing: 6) {
                            Image(systemName: "dot.radiowaves.left.and.right")
                                .font(.caption)
                            Text("Live")
                                .font(.caption.weight(.medium))
                        }
                        .foregroundStyle(Color.clawTeal)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.clawTeal.opacity(0.12))
                        .clipShape(Capsule())
                        .padding(.leading, 24)
                    }
                    Spacer()
                    Button(action: onDismiss) {
                        HStack(spacing: 8) {
                            Image(systemName: "xmark.circle.fill")
                            Text("Exit Driving Mode")
                        }
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.white.opacity(0.1))
                        .clipShape(Capsule())
                    }
                    .padding(.trailing, 24)
                }
                .padding(.bottom, 24)
            }
        }
        .fullScreenCover(isPresented: $showConfirmation) {
            if let intent = pendingConfirmation {
                VoiceConfirmationView(
                    intent: intent,
                    onConfirm: {
                        showConfirmation = false
                        pendingConfirmation = nil
                        bridge?.confirmPendingIntent()
                        manager.exitConfirmationPending()
                    },
                    onCancel: {
                        showConfirmation = false
                        pendingConfirmation = nil
                        bridge?.cancelPendingIntent()
                        manager.exitConfirmationPending()
                        manager.speak("Cancelled.")
                    }
                )
            }
        }
        .onAppear {
            setupBridgeAndCallbacks()
            if !manager.hasPermission, case .idle = manager.state {
                Task { await manager.requestPermissions() }
            }
        }
    }

    // MARK: - Setup (closures, not a delegate class, to avoid struct weak-ref issues)

    private func setupBridgeAndCallbacks() {
        if let client, let sessionKey {
            let b = VoiceSessionBridge(client: client, sessionKey: sessionKey)

            b.onResponse = { response in
                lastResponse = response
                isBridgeActive = false
                manager.speak(response)
            }

            b.onConfirmationRequired = { intent in
                pendingConfirmation = intent
                manager.enterConfirmationPending(for: intent)
                if let prompt = intent.confirmationPrompt {
                    manager.speak(prompt)
                }
                showConfirmation = true
            }

            b.onStatusChange = { status in
                bridgeStatus = status
                isBridgeActive = (
                    status != "Done" &&
                    status != "Cancelled" &&
                    !status.hasPrefix("Send failed")
                )
            }

            b.onError = { _ in
                isBridgeActive = false
                manager.speak("Sorry, something went wrong.")
            }

            bridge = b
        }

        manager.onTranscriptReady = { transcript in
            if let bridge {
                bridge.processTranscript(transcript)
                isBridgeActive = true
            } else {
                // Echo fallback
                lastResponse = "Received: \(transcript)"
                manager.speak("Echo: \(transcript)")
            }
        }
    }

    // MARK: - State helpers

    private var statusText: String {
        switch manager.state {
        case .idle, .requestingPermission: return "Drive Safe"
        case .ready:                       return "Ready"
        case .recording:                   return "Listening"
        case .processing:                  return "Thinking"
        case .speaking:                    return "Speaking"
        case .confirmationNeeded:          return "Confirm?"
        case .unavailable:                 return "Unavailable"
        }
    }

    private var stateDescription: String {
        switch manager.state {
        case .idle, .ready:          return "Hold the button to speak"
        case .requestingPermission:  return "Setting up voice…"
        case .recording:             return "Release when done"
        case .processing:            return bridgeStatus.isEmpty ? "Processing…" : bridgeStatus
        case .speaking:              return "Playing response"
        case .confirmationNeeded:    return "Say 'yes' or tap Confirm"
        case .unavailable(let r):    return r
        }
    }

    private var buttonIcon: String {
        switch manager.state {
        case .recording:          return "waveform"
        case .speaking:           return "speaker.wave.3.fill"
        case .processing:         return "ellipsis"
        case .confirmationNeeded: return "exclamationmark.triangle.fill"
        default:                  return "mic.fill"
        }
    }

    private var buttonGradientColors: [Color] {
        switch manager.state {
        case .recording:          return [.clawDanger, .clawDanger.opacity(0.7)]
        case .speaking:           return [.clawTeal, .clawTeal.opacity(0.7)]
        case .processing:         return [.clawAccent, .clawAccent.opacity(0.7)]
        case .confirmationNeeded: return [.clawWarn, .clawWarn.opacity(0.7)]
        default:                  return [.clawTeal, .clawAccent]
        }
    }

    private var holdInstruction: String {
        if manager.isRecording               { return "Release to send" }
        if case .speaking = manager.state    { return "Tap mic to interrupt" }
        if canRecord                         { return "Hold to speak" }
        return ""
    }

    private var canRecord: Bool {
        if case .ready = manager.state { return manager.hasPermission }
        return false
    }

    private var canInteract: Bool {
        switch manager.state {
        case .idle, .ready, .recording: return manager.hasPermission || manager.isRecording
        case .speaking:                 return true
        default:                        return false
        }
    }
}

// MARK: - Previews

#Preview("Ready") {
    VoiceDrivingModeView(manager: VoiceOpsManager(), onDismiss: {})
        .onAppear {
            Task { await VoiceOpsManager().requestPermissions() }
        }
}
