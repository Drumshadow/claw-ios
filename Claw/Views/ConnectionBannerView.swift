import SwiftUI

// MARK: - ConnectionBannerView

/// A slim banner that overlays the top of the screen to communicate connection state changes.
/// Animates in when reconnecting or disconnected, and animates away on connection.
struct ConnectionBannerView: View {
    let connectionState: ConnectionState
    let onRetry: (() -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            if showBanner {
                bannerContent
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            Spacer()
        }
        .animation(.easeInOut(duration: 0.3), value: connectionState)
        .ignoresSafeArea(edges: .top)
    }

    // MARK: - Visibility logic

    private var showBanner: Bool {
        switch connectionState {
        case .reconnecting, .disconnected, .failed:
            return true
        default:
            return false
        }
    }

    // MARK: - Banner content

    @ViewBuilder
    private var bannerContent: some View {
        switch connectionState {
        case .reconnecting:
            reconnectingBanner
        case .disconnected:
            disconnectedBanner
        case .failed(let reason):
            failedBanner(reason: reason)
        default:
            EmptyView()
        }
    }

    // MARK: - Reconnecting banner (warn)

    private var reconnectingBanner: some View {
        HStack(spacing: 8) {
            ProgressView()
                .progressViewStyle(.circular)
                .scaleEffect(0.75)
                .tint(.black)
            Text("Reconnecting…")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.black)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
        .padding(.top, topPadding + 8)
        .padding(.bottom, 8)
        .background(Color.clawWarn)
    }

    // MARK: - Disconnected banner (accent, tappable)

    private var disconnectedBanner: some View {
        Button(action: { onRetry?() }) {
            HStack(spacing: 8) {
                Image(systemName: "wifi.slash")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                Text("Disconnected — tap to retry")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 16)
            .padding(.top, topPadding + 8)
            .padding(.bottom, 8)
            .background(Color.clawAccent)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Failed banner (danger)

    private func failedBanner(reason: String) -> some View {
        Button(action: { onRetry?() }) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                Text(reason.isEmpty ? "Connection failed — tap to retry" : reason)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 16)
            .padding(.top, topPadding + 8)
            .padding(.bottom, 8)
            .background(Color.clawDanger)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Safe area top inset

    private var topPadding: CGFloat {
        // Pull the safe area inset to sit flush under the status bar
        (UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?
            .windows
            .first { $0.isKeyWindow }?
            .safeAreaInsets.top) ?? 0
    }
}

// MARK: - View modifier convenience

extension View {
    /// Overlays a connection status banner at the top of the view.
    func connectionBanner(state: ConnectionState, onRetry: (() -> Void)? = nil) -> some View {
        self.overlay(alignment: .top) {
            ConnectionBannerView(connectionState: state, onRetry: onRetry)
        }
    }
}
