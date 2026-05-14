import SwiftUI

// MARK: - PairingView

struct PairingView: View {
    let deviceID: String

    @Environment(AppState.self) private var appState
    @State private var coordinator: PairingCoordinator?
    @State private var showCopiedFeedback = false
    @State private var elapsedSeconds = 0
    @State private var clockTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            ZStack {
                Color.clawBg.ignoresSafeArea()

                VStack(spacing: 0) {
                    Spacer()

                    // Icon
                    ZStack {
                        Circle()
                            .fill(Color.clawAccentSubtle)
                            .frame(width: 100, height: 100)
                        Circle()
                            .stroke(Color.clawAccent.opacity(0.3), lineWidth: 1)
                            .frame(width: 100, height: 100)
                        Image(systemName: "key.horizontal.fill")
                            .font(.system(size: 42))
                            .foregroundStyle(Color.clawAccent)
                            .symbolEffect(.pulse, isActive: true)
                    }
                    .padding(.bottom, 28)

                    // Title
                    Text("Waiting for Approval")
                        .font(.title.bold())
                        .foregroundStyle(Color.clawTextStrong)
                        .multilineTextAlignment(.center)

                    Text("Your device needs to be approved on the gateway before it can connect.")
                        .font(.subheadline)
                        .foregroundStyle(Color.clawMuted)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                        .padding(.top, 10)

                    Spacer().frame(height: 36)

                    // Device ID display
                    VStack(spacing: 12) {
                        Text("Device ID")
                            .font(.caption)
                            .foregroundStyle(Color.clawMuted)
                            .textCase(.uppercase)
                            .tracking(0.5)

                        Text(deviceID)
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(Color.clawTextStrong)
                            .lineLimit(2)
                            .minimumScaleFactor(0.7)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 20)

                        Button {
                            UIPasteboard.general.string = deviceID
                            withAnimation { showCopiedFeedback = true }
                            Task {
                                try? await Task.sleep(nanoseconds: 2_000_000_000)
                                await MainActor.run {
                                    withAnimation { showCopiedFeedback = false }
                                }
                            }
                        } label: {
                            Label(
                                showCopiedFeedback ? "Copied!" : "Copy Device ID",
                                systemImage: showCopiedFeedback ? "checkmark" : "doc.on.doc"
                            )
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(showCopiedFeedback ? Color.clawOk : Color.clawAccent)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(
                                Capsule().fill(
                                    (showCopiedFeedback ? Color.clawOk : Color.clawAccent)
                                        .opacity(0.12)
                                )
                            )
                            .overlay(
                                Capsule().strokeBorder(
                                    (showCopiedFeedback ? Color.clawOk : Color.clawAccent)
                                        .opacity(0.4),
                                    lineWidth: 1
                                )
                            )
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 20)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.clawCard)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Color.clawBorder, lineWidth: 1)
                    )
                    .padding(.horizontal, 24)

                    Spacer().frame(height: 28)

                    // CLI hint
                    VStack(spacing: 8) {
                        Text("Approve from the gateway:")
                            .font(.caption)
                            .foregroundStyle(Color.clawMuted)

                        Text("openclaw devices approve \(shortDeviceID)")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(Color.clawText)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color.clawBgElevated)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .strokeBorder(Color.clawBorder, lineWidth: 1)
                            )
                    }

                    Spacer().frame(height: 24)

                    // Polling indicator
                    HStack(spacing: 8) {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .scaleEffect(0.75)
                            .tint(Color.clawAccent)
                        Text("Checking every 3 seconds… (\(elapsedSeconds)s)")
                            .font(.caption)
                            .foregroundStyle(Color.clawMuted)
                    }

                    Spacer()

                    // Cancel button
                    Button {
                        coordinator?.cancel()
                        Task { await appState.disconnect() }
                    } label: {
                        Label("Cancel Pairing", systemImage: "xmark.circle")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .foregroundStyle(Color.clawDanger)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(Color.clawDanger.opacity(0.1))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(Color.clawDanger.opacity(0.4), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 32)
                }
            }
            .navigationTitle("Pairing")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.clawBgAccent, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .onAppear {
            startPairingCoordinator()
            startClock()
        }
        .onDisappear {
            clockTask?.cancel()
            clockTask = nil
        }
        .onChange(of: coordinator?.state) { _, newState in
            handleStateChange(newState)
        }
    }

    // MARK: - Helpers

    private var shortDeviceID: String {
        String(deviceID.prefix(12))
    }

    private func startPairingCoordinator() {
        guard let config = appState.selectedConfig else { return }
        let c = PairingCoordinator(config: config)
        coordinator = c
        c.startPairing()
    }

    private func startClock() {
        clockTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                await MainActor.run { elapsedSeconds += 1 }
            }
        }
    }

    private func handleStateChange(_ state: PairingState?) {
        guard let state else { return }
        switch state {
        case .approved:
            // Re-connect now that we're approved
            guard let config = appState.selectedConfig else { return }
            Task {
                await appState.connect(to: config)
            }
        case .failed(let reason):
            Task { await appState.setConnectionState(.failed(reason)) }
        default:
            break
        }
    }
}
