import SwiftUI

struct VoiceOpsOverlay: View {
    @Bindable var manager: VoiceOpsManager
    var onDismiss: () -> Void

    @State private var waveformHeights: [CGFloat] = [0.3, 0.5, 0.8, 0.5, 0.3]
    @State private var waveformTimer: Timer?

    var body: some View {
        ZStack {
            // Dark background overlay
            Color.clawBg.opacity(0.95)
                .ignoresSafeArea()
                .onTapGesture {
                    if manager.isRecording {
                        manager.stopRecording()
                    }
                    onDismiss()
                }

            VStack(spacing: 40) {
                Spacer()

                // Central recording button with waveform
                VStack(spacing: 32) {
                    // Large circular button
                    ZStack {
                        // Outer pulsing ring
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
                            .opacity(manager.isRecording ? 0.6 : 0.3)

                        // Filled circle with gradient
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [.clawTeal.opacity(0.3), .clawAccent.opacity(0.3)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 120, height: 120)

                        // Microphone icon
                        Image(systemName: manager.isRecording ? "mic.fill" : "mic")
                            .font(.system(size: 48))
                            .foregroundStyle(.white)
                    }

                    // Waveform visualization
                    if manager.isRecording {
                        HStack(spacing: 8) {
                            ForEach(0..<5, id: \.self) { index in
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color.clawTeal)
                                    .frame(width: 6, height: 60 * waveformHeights[index])
                                    .animation(
                                        .easeInOut(duration: 0.3)
                                        .repeatForever(autoreverses: true),
                                        value: waveformHeights[index]
                                    )
                            }
                        }
                        .frame(height: 60)
                        .onAppear {
                            startWaveformAnimation()
                        }
                        .onDisappear {
                            stopWaveformAnimation()
                        }
                    }
                }

                Spacer()

                // Live transcript
                VStack(spacing: 16) {
                    if manager.isRecording {
                        Text(manager.liveTranscript.isEmpty ? "Listening..." : manager.liveTranscript)
                            .font(.title3)
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 100)
                    } else if case .processing = manager.state {
                        Text("Processing...")
                            .font(.title3)
                            .foregroundStyle(.white.opacity(0.7))
                    }

                    // Hint text
                    Text(manager.isRecording ? "Tap anywhere to stop" : "")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.5))
                }
                .padding(.bottom, 60)
            }

            // Swipe down to cancel gesture indicator
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
                        // Swipe down to cancel
                        if manager.isRecording {
                            manager.cancelRecording()
                        }
                        onDismiss()
                    }
                }
        )
    }

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

#Preview("Recording") {
    let manager = VoiceOpsManager()
    VoiceOpsOverlay(
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

#Preview("Idle") {
    VoiceOpsOverlay(
        manager: VoiceOpsManager(),
        onDismiss: {}
    )
}
