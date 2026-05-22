import SwiftUI

struct VoiceOpsButton: View {
    @Bindable var manager: VoiceOpsManager
    var onTranscript: (String) -> Void

    @State private var isPressed = false
    @State private var pulseScale: CGFloat = 1.0

    var body: some View {
        ZStack {
            // Pulsing circle while recording
            if manager.isRecording {
                Circle()
                    .fill(Color.clawDanger.opacity(0.3))
                    .frame(width: 44, height: 44)
                    .scaleEffect(pulseScale)
                    .animation(
                        .easeInOut(duration: 1.0)
                        .repeatForever(autoreverses: true),
                        value: pulseScale
                    )
                    .onAppear {
                        pulseScale = 1.3
                    }
                    .onDisappear {
                        pulseScale = 1.0
                    }
            }

            // Pulsing effect while speaking
            if case .speaking = manager.state {
                Circle()
                    .fill(Color.clawTeal.opacity(0.2))
                    .frame(width: 44, height: 44)
                    .scaleEffect(pulseScale)
                    .animation(
                        .easeInOut(duration: 0.8)
                        .repeatForever(autoreverses: true),
                        value: pulseScale
                    )
                    .onAppear {
                        pulseScale = 1.15
                    }
                    .onDisappear {
                        pulseScale = 1.0
                    }
            }

            // Button content
            Button(action: {}) {
                iconForState
                    .font(.system(size: 20))
                    .foregroundStyle(colorForState)
                    .frame(width: 44, height: 44)
                    .background(backgroundForState)
                    .clipShape(Circle())
                    .scaleEffect(isPressed ? 0.9 : (manager.isRecording ? 1.2 : 1.0))
                    .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isPressed)
                    .animation(.spring(response: 0.3, dampingFraction: 0.6), value: manager.isRecording)
            }
            .disabled(!canInteract)
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 0.1)
                    .simultaneously(with: DragGesture(minimumDistance: 0))
                    .onChanged { _ in
                        if !isPressed && canInteract {
                            isPressed = true
                            startRecording()
                        }
                    }
                    .onEnded { _ in
                        if isPressed {
                            isPressed = false
                            endRecording()
                        }
                    }
            )
        }
        .onAppear {
            // Set up transcript callback
            if manager.onTranscriptReady == nil {
                manager.onTranscriptReady = { transcript in
                    onTranscript(transcript)
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

    private var iconForState: Image {
        switch manager.state {
        case .idle, .requestingPermission, .ready, .processing, .confirmationNeeded:
            return Image(systemName: "mic.fill")
        case .recording:
            return Image(systemName: "waveform")
        case .speaking:
            return Image(systemName: "speaker.wave.2.fill")
        case .unavailable:
            return Image(systemName: "mic.slash.fill")
        }
    }

    private var colorForState: Color {
        switch manager.state {
        case .idle, .requestingPermission, .ready, .processing, .confirmationNeeded:
            return .clawMuted
        case .recording:
            return .clawDanger
        case .speaking:
            return .clawTeal
        case .unavailable:
            return Color.clawMuted.opacity(0.4)
        }
    }

    private var backgroundForState: Color {
        switch manager.state {
        case .recording:
            return Color.clawDanger.opacity(0.15)
        case .confirmationNeeded:
            return Color.clawWarn.opacity(0.15)
        case .speaking:
            return Color.clawTeal.opacity(0.15)
        default:
            return Color.clawMuted.opacity(0.1)
        }
    }

    private var canInteract: Bool {
        switch manager.state {
        case .idle, .ready:
            return manager.hasPermission
        case .recording:
            return true
        case .unavailable, .requestingPermission, .processing, .confirmationNeeded, .speaking:
            return false
        }
    }

    private func startRecording() {
        manager.startRecording()
    }

    private func endRecording() {
        if manager.isRecording {
            manager.stopRecording()
        }
    }
}

#Preview("Idle") {
    VoiceOpsButton(
        manager: VoiceOpsManager(),
        onTranscript: { _ in }
    )
    .padding()
}

#Preview("Recording") {
    let manager = VoiceOpsManager()
    VoiceOpsButton(
        manager: manager,
        onTranscript: { _ in }
    )
    .padding()
    .onAppear {
        Task {
            await manager.requestPermissions()
            manager.startRecording()
        }
    }
}
