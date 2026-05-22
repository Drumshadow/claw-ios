import SwiftUI

// MARK: - VoiceConfirmationView

/// Full-screen confirmation prompt for caution/danger voice commands.
/// Shown when VoiceSessionBridge detects a risky intent and requires
/// explicit user confirmation before executing.
///
/// UX: Large, readable text for eyes-busy/driving contexts.
/// - Danger: requires spoken or manual confirmation
/// - Caution: single tap confirms
struct VoiceConfirmationView: View {
    let intent: VoiceCommandIntent
    var onConfirm: () -> Void
    var onCancel: () -> Void

    @State private var showContent = false
    @State private var borderPulse: CGFloat = 1.0

    var body: some View {
        ZStack {
            // Background — tinted by risk
            riskBackgroundColor
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // Risk badge
                HStack(spacing: 8) {
                    Image(systemName: riskIcon)
                        .font(.system(size: 20, weight: .bold))
                    Text(intent.risk.displayName.uppercased())
                        .font(.system(size: 14, weight: .black, design: .monospaced))
                        .tracking(3)
                }
                .foregroundStyle(riskAccentColor)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(riskAccentColor.opacity(0.15))
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(riskAccentColor.opacity(0.4), lineWidth: 1.5)
                        .scaleEffect(borderPulse)
                        .opacity(2 - borderPulse)
                        .animation(
                            .easeOut(duration: 1.4).repeatForever(autoreverses: false),
                            value: borderPulse
                        )
                )
                .onAppear { borderPulse = 1.15 }
                .padding(.bottom, 32)

                // Command preview
                VStack(spacing: 16) {
                    Text("Confirm command?")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(.white)

                    // Original transcript
                    Text(""\(intent.rawTranscript)"")
                        .font(.title3)
                        .foregroundStyle(.white.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                        .frame(maxWidth: .infinity)

                    // Confirmation prompt (more specific)
                    if let prompt = intent.confirmationPrompt,
                       prompt != intent.rawTranscript {
                        Divider()
                            .background(Color.white.opacity(0.15))
                            .padding(.horizontal, 40)

                        Text(prompt)
                            .font(.body)
                            .foregroundStyle(riskAccentColor)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }
                }
                .padding(.bottom, 48)

                // Action buttons — large for hand-busy UX
                VStack(spacing: 16) {
                    Button(action: onConfirm) {
                        HStack(spacing: 12) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 22))
                            Text(intent.confirmButtonLabel)
                                .font(.system(size: 20, weight: .bold))
                        }
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 64)
                        .background(riskAccentColor)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                    }
                    .padding(.horizontal, 32)

                    Button(action: onCancel) {
                        HStack(spacing: 10) {
                            Image(systemName: "xmark.circle")
                                .font(.system(size: 20))
                            Text("Cancel")
                                .font(.system(size: 18, weight: .semibold))
                        }
                        .foregroundStyle(.white.opacity(0.7))
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(Color.white.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .padding(.horizontal, 32)
                }

                // Voice hint
                Text("Or say "yes" to confirm, "cancel" to abort")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.4))
                    .multilineTextAlignment(.center)
                    .padding(.top, 20)
                    .padding(.horizontal, 40)

                Spacer()
            }
        }
        .opacity(showContent ? 1 : 0)
        .scaleEffect(showContent ? 1 : 0.92)
        .animation(.spring(response: 0.35, dampingFraction: 0.78), value: showContent)
        .onAppear { showContent = true }
    }

    // MARK: - Theme helpers

    private var riskBackgroundColor: Color {
        switch intent.risk {
        case .safe:    return Color.clawBg
        case .caution: return Color(red: 0.12, green: 0.10, blue: 0.03)
        case .danger:  return Color(red: 0.14, green: 0.04, blue: 0.04)
        }
    }

    private var riskAccentColor: Color {
        switch intent.risk {
        case .safe:    return .clawTeal
        case .caution: return .clawWarn
        case .danger:  return .clawDanger
        }
    }

    private var riskIcon: String {
        switch intent.risk {
        case .safe:    return "checkmark.shield.fill"
        case .caution: return "exclamationmark.triangle.fill"
        case .danger:  return "flame.fill"
        }
    }
}

// MARK: - VoiceStatusBar

/// Compact inline status bar shown below voice controls.
/// Displays current bridge status and pulsing indicator while active.
struct VoiceStatusBar: View {
    let status: String
    let isActive: Bool

    @State private var dotOpacity: Double = 1.0

    var body: some View {
        HStack(spacing: 8) {
            if isActive {
                Circle()
                    .fill(Color.clawTeal)
                    .frame(width: 7, height: 7)
                    .opacity(dotOpacity)
                    .animation(
                        .easeInOut(duration: 0.7).repeatForever(autoreverses: true),
                        value: dotOpacity
                    )
                    .onAppear { dotOpacity = 0.25 }
            }

            Text(status)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(isActive ? Color.clawTeal : Color.clawMuted.opacity(0.6))
                .lineLimit(1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(Color.clawBgAccent.opacity(0.8))
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(isActive ? Color.clawTeal.opacity(0.3) : Color.clear, lineWidth: 1)
        )
    }
}

// MARK: - Previews

#Preview("Danger") {
    let intent = VoiceCommandIntent(
        category: .deploy,
        risk: .danger,
        rawTranscript: "deploy to production",
        normalizedMessage: "deploy to production",
        confirmationPrompt: "Deploy to production now?",
        confirmButtonLabel: "Deploy",
        executionHint: "Deploying…",
        extractedKeywords: ["deploy"]
    )
    VoiceConfirmationView(intent: intent, onConfirm: {}, onCancel: {})
}

#Preview("Caution") {
    let intent = VoiceCommandIntent(
        category: .restart,
        risk: .caution,
        rawTranscript: "restart the API server",
        normalizedMessage: "restart the API server",
        confirmationPrompt: "Restart the API server?",
        confirmButtonLabel: "Restart",
        executionHint: "Restarting…",
        extractedKeywords: ["restart"]
    )
    VoiceConfirmationView(intent: intent, onConfirm: {}, onCancel: {})
}

#Preview("Status Bar") {
    VStack(spacing: 16) {
        VoiceStatusBar(status: "Waiting for agent…", isActive: true)
        VoiceStatusBar(status: "Done", isActive: false)
    }
    .padding()
    .background(Color.clawBg)
}
