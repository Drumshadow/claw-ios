import SwiftUI

// MARK: - VoiceOpsOverlay

/// Modal overlay for voice operations — appears as a sheet over the current view.
///
/// Integrates with VoiceSessionBridge for live agent sends when client+sessionKey
/// are provided. Falls back to a plain transcript callback when omitted.
struct VoiceOpsOverlay: View {
    @Bindable var manager: VoiceOpsManager
    var client: GatewayClient?
    var sessionKey: String?
    /// Called with the transcript if no bridge is configured (compose-mode callback).
    var onTranscript: ((String) -> Void)?
    var onDismiss: () -> Void

    @State private var bridge: VoiceSessionBridge?
    @State private var bridgeStatus: String = ""
    @State private var isBridgeActive: Bool = false
    @State private var pendingConfirmation: VoiceCommandIntent?
    @State private var showConfirmation: Bool = false

    @State private var waveformHeights: [CGFloat] = [0.3, 0.5, 0.8, 0.5, 0.3]
    @State private var waveformTimer: Timer?

    var body: some View {
        ZStack {
            Color.clawBg.opacity(0.97)
                .ignoresSafeArea()
                .onTapGesture {
                    if manager.isRecording { manager.stopRecording() }
                    onDismiss()
                }

            VStack(spacing: 40) {
                Spacer()

                // Mic button + waveform
                VStack(spacing: 32) {
                    ZStack {
                        Circle()
                            .stroke(
                                LinearGradient(
                                    colors: [.clawTeal, .clawAccent],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 4
                            )
                            .frame(width: 120, height: 120)
                            .opacity(manager.isRecording ? 0.7 : 0.3)
                            .animation(.easeInOut(duration: 0.3), value: manager.isRecording)

                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [.clawTeal.opacity(0.3), .clawAccent.opacity(0.3)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 120, height: 120)

                        Image(systemName: overlayIcon)
                            .font(.system(size: 48))
                            .foregroundStyle(.white)
                            .animation(.easeInOut(duration: 0.2), value: overlayIcon)
                    }

                    if manager.isRecording {
                        HStack(spacing: 8) {
                            ForEach(0..<5, id: \.self) { index in
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color.clawTeal)
                                    .frame(width: 6, height: 60 * waveformHeights[index])
                                    .animation(
                                        .easeInOut(duration: 0.3).repeatForever(autoreverses: true),
                                        value: waveformHeights[index]
                                    )
                            }
                        }
                        .frame(height: 60)
                        .onAppear  { startWaveformAnimation() }
                        .onDisappear { stopWaveformAnimation() }
                    }
                }

                Spacer()

                // Transcript + status
                VStack(spacing: 16) {
                    if manager.isRecording {
                        Text(manager.liveTranscript.isEmpty ? "Listening…" : manager.liveTranscript)
                            .font(.title3)
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 80)
                    } else if case .processing = manager.state {
                        Text("Processing…")
                            .font(.title3)
                            .foregroundStyle(.white.opacity(0.7))
                    } else if case .speaking = manager.state {
                        Text("Playing response…")
                            .font(.title3)
                            .foregroundStyle(Color.clawTeal)
                    }

                    if !bridgeStatus.isEmpty && !manager.isRecording {
                        VoiceStatusBar(status: bridgeStatus, isActive: isBridgeActive)
                    }

                    Text(overlayHint)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.4))
                }
                .padding(.bottom, 60)
            }

            // Dismiss indicator
            VStack {
                HStack {
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.title2)
                        .foregroundStyle(.white.opacity(0.3))
                        .padding()
                    Spacer()
                }
                Spacer()
            }
        }
        .gesture(
            DragGesture(minimumDistance: 50, coordinateSpace: .local)
                .onEnded { value in
                    if value.translation.height > 0 {
                        if manager.isRecording { manager.cancelRecording() }
                        onDismiss()
                    }
                }
        )
        .sheet(isPresented: $showConfirmation) {
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
                    }
                )
                .presentationDetents([.large])
                .presentationBackground(Color.clawBg)
            }
        }
        .onAppear {
            setupBridgeAndCallbacks()
            if !manager.hasPermission, case .idle = manager.state {
                Task {
                    await manager.requestPermissions()
                    if manager.hasPermission { manager.startRecording() }
                }
            } else if manager.hasPermission {
                manager.startRecording()
            }
        }
        .onDisappear {
            if manager.isRecording { manager.cancelRecording() }
            stopWaveformAnimation()
        }
    }

    // MARK: - Setup (closure-based, no weak struct references)

    private func setupBridgeAndCallbacks() {
        if let client, let sessionKey {
            let b = VoiceSessionBridge(client: client, sessionKey: sessionKey)

            b.onResponse = { response in
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
            }

            bridge = b
        }

        manager.onTranscriptReady = { transcript in
            if let bridge {
                bridge.processTranscript(transcript)
                isBridgeActive = true
            } else {
                onTranscript?(transcript)
            }
        }
    }

    // MARK: - View helpers

    private var overlayIcon: String {
        switch manager.state {
        case .recording:          return "mic.fill"
        case .speaking:           return "speaker.wave.2.fill"
        case .processing:         return "ellipsis"
        case .confirmationNeeded: return "exclamationmark.triangle.fill"
        default:                  return "mic"
        }
    }

    private var overlayHint: String {
        if manager.isRecording                    { return "Tap anywhere to stop" }
        if case .speaking = manager.state         { return "Listening for response" }
        if bridge != nil                          { return "Connected to session" }
        return ""
    }

    // MARK: - Waveform animation

    private func startWaveformAnimation() {
        waveformTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { _ in
            for i in 0..<5 {
                waveformHeights[i] = CGFloat.random(in: 0.3...1.0)
            }
        }
    }

    private func stopWaveformAnimation() {
        waveformTimer?.invalidate()
        waveformTimer = nil
    }
}

// MARK: - Previews

#Preview("Idle") {
    VoiceOpsOverlay(manager: VoiceOpsManager(), onDismiss: {})
}
