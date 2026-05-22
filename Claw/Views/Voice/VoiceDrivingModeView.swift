import SwiftUI

struct VoiceDrivingModeView: View {
    @Bindable var manager: VoiceOpsManager
    var onDismiss: () -> Void

    @State private var lastResponse: String = ""
    @State private var pulseScale: CGFloat = 1.0

    var body: some View {
        ZStack {
            // Full screen dark background
            Color.clawBg
                .ignoresSafeArea()

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

                // Giant central push-to-talk button
                ZStack {
                    // Pulsing outer ring
                    if manager.isRecording {
                        Circle()
                            .stroke(Color.clawDanger, lineWidth: 6)
                            .frame(width: 160, height: 160)
                            .scaleEffect(pulseScale)
                            .opacity(2.0 - pulseScale)
                            .animation(
                                .easeOut(duration: 1.5)
                                .repeatForever(autoreverses: false),
                                value: pulseScale
                            )
                            .onAppear {
                                pulseScale = 1.5
                            }
                            .onDisappear {
                                pulseScale = 1.0
                            }
                    }

                    // Main button
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
                    .disabled(!canRecord && !manager.isRecording)
                }
                .padding(.bottom, 60)

                // Hold instruction
                Text(holdInstruction)
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.6))
                    .padding(.bottom, 40)

                Spacer()
            }

            // Exit button
            VStack {
                Spacer()
                HStack {
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
                    .padding(.bottom, 24)
                }
            }
        }
        .onAppear {
            // Set up callbacks
            if manager.onTranscriptReady == nil {
                manager.onTranscriptReady = { transcript in
                    // In real integration, this would send to agent
                    // For now, just echo back
                    lastResponse = "Received: \(transcript)"
                }
            }

            // Request permissions if needed
            if !manager.hasPermission, case .idle = manager.state {
                Task {
                    await manager.requestPermissions()
                }
            }
        }
    }

    private var statusText: String {
        switch manager.state {
        case .idle, .requestingPermission:
            return "Drive Safe"
        case .ready:
            return "Ready"
        case .recording:
            return "Listening"
        case .processing:
            return "Thinking"
        case .speaking:
            return "Speaking"
        case .unavailable:
            return "Unavailable"
        }
    }

    private var stateDescription: String {
        switch manager.state {
        case .idle, .ready:
            return "Hold the button to speak"
        case .requestingPermission:
            return "Setting up voice..."
        case .recording:
            return "Release when done"
        case .processing:
            return "Processing your request..."
        case .speaking:
            return "Playing response"
        case .unavailable(let reason):
            return reason
        }
    }

    private var buttonIcon: String {
        switch manager.state {
        case .recording:
            return "waveform"
        case .speaking:
            return "speaker.wave.3.fill"
        case .processing:
            return "ellipsis"
        default:
            return "mic.fill"
        }
    }

    private var buttonGradientColors: [Color] {
        switch manager.state {
        case .recording:
            return [.clawDanger, .clawDanger.opacity(0.7)]
        case .speaking:
            return [.clawTeal, .clawTeal.opacity(0.7)]
        case .processing:
            return [.clawAccent, .clawAccent.opacity(0.7)]
        default:
            return [.clawTeal, .clawAccent]
        }
    }

    private var holdInstruction: String {
        if manager.isRecording {
            return "Release to send"
        } else if canRecord {
            return "Hold to speak"
        } else {
            return ""
        }
    }

    private var canRecord: Bool {
        switch manager.state {
        case .ready:
            return manager.hasPermission
        default:
            return false
        }
    }
}

#Preview("Ready") {
    let manager = VoiceOpsManager()
    VoiceDrivingModeView(
        manager: manager,
        onDismiss: {}
    )
    .onAppear {
        Task {
            await manager.requestPermissions()
        }
    }
}

#Preview("Recording") {
    let manager = VoiceOpsManager()
    VoiceDrivingModeView(
        manager: manager,
        onDismiss: {}
    )
    .onAppear {
        Task {
            await manager.requestPermissions()
            manager.startRecording()
        }
    }
}
