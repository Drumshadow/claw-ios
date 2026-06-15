import SwiftUI
import UserNotifications

@main
struct ClawApp: App {

    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    @State private var appState = AppState()
    @State private var discovery = GatewayDiscovery()
    @State private var gatewayStore = GatewayStore()
    @State private var pushManager = PushManager()
    @State private var router = NavigationRouter()
    @State private var shareProcessor = ShareIntakeProcessor()
    @State private var showSplash: Bool = true

    var body: some Scene {
        WindowGroup {
            ZStack {
                RootView()
                    .environment(appState)
                    .environment(discovery)
                    .environment(gatewayStore)
                    .environment(pushManager)
                    .environment(router)
                    .preferredColorScheme(.dark)
                    .onOpenURL { url in
                        handleDeepLink(url: url)
                    }
                    .onAppear {
                        appDelegate.pushManager = pushManager
                        discovery.startDiscovery()
                    }
                    .onDisappear {
                        discovery.stopDiscovery()
                    }
                    .onChange(of: appState.connectionState) { _, newState in
                        if case .connected = newState {
                            Task { @MainActor in
                                pushManager.gatewayClient = appState.activeClient
                                let granted = await pushManager.requestAuthorization()
                                if granted {
                                    pushManager.registerForRemoteNotifications()
                                }
                                if pushManager.apnsToken != nil {
                                    await pushManager.registerWithGateway()
                                }
                            }
                            // Deliver any share items queued while offline — but NOT while the
                            // review sheet is open, or the drain could send an item the user is
                            // still editing (which would then be re-sent as a new finalItem).
                            if let client = appState.activeClient, !router.showShareIntake {
                                shareProcessor.process(client: client, sessionStore: nil)
                            }
                        }
                        if case .disconnected = newState {
                            pushManager.gatewayClient = nil
                        }
                    }
                    .onReceive(NotificationCenter.default.publisher(for: Notification.Name("claw.intent.newSession"))) { _ in
                        NotificationCenter.default.post(name: Notification.Name("claw.ui.showNewSession"), object: nil)
                    }
                    .onReceive(NotificationCenter.default.publisher(for: Notification.Name("claw.intent.sendMessage"))) { notification in
                        guard let message = notification.userInfo?["message"] as? String else { return }
                        NotificationCenter.default.post(
                            name: Notification.Name("claw.ui.prefillMessage"),
                            object: nil,
                            userInfo: ["message": message]
                        )
                    }

                if showSplash {
                    SplashView()
                        .transition(.opacity)
                        .zIndex(1)
                        .task {
                            try? await Task.sleep(nanoseconds: 1_600_000_000)
                            withAnimation(.easeOut(duration: 0.4)) { showSplash = false }
                        }
                }
            }
            .preferredColorScheme(.dark)
            // Share intake sheet — presented when the app opens via claw://share
            .sheet(isPresented: Binding(
                get: { router.showShareIntake && !router.pendingShareItems.isEmpty },
                set: { if !$0 { router.showShareIntake = false } }
            )) {
                if let firstItem = router.pendingShareItems.first {
                    ShareIntakeView(
                        item: firstItem,
                        onSend: { finalItem in
                            guard let client = appState.activeClient else { return false }
                            return await shareProcessor.deliver(finalItem, client: client, sessionStore: nil)
                        },
                        onDelivered: { _ in
                            // Advance to the next shared item, or close when done.
                            if !router.pendingShareItems.isEmpty {
                                router.pendingShareItems.removeFirst()
                            }
                            if router.pendingShareItems.isEmpty {
                                router.showShareIntake = false
                                // Flush anything still queued (e.g. an item sent while briefly
                                // offline) now that the sheet is closed and the drain is allowed.
                                if let client = appState.activeClient {
                                    shareProcessor.process(client: client, sessionStore: nil)
                                }
                            }
                        },
                        onDismiss: {
                            // Cancel = discard the shares the user backed out of, so the drain
                            // doesn't later deliver them anyway.
                            for shareItem in router.pendingShareItems {
                                ShareIntakeQueue.shared.remove(id: shareItem.id)
                            }
                            router.showShareIntake = false
                            router.pendingShareItems.removeAll()
                        }
                    )
                    .presentationBackground(Color.clawBg)
                    // Force an explicit choice: a swipe-dismiss would bypass both Cancel
                    // (which discards) and Send, leaving the item queued for the drain to
                    // deliver later — i.e. silently sending a share the user backed out of.
                    .interactiveDismissDisabled()
                }
            }
        }
    }
}

// MARK: - RootView

struct RootView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        Group {
            switch appState.connectionState {
            case .disconnected, .failed:
                GatewaySetupView()
            case .connecting:
                ConnectingView()
            case .connected, .reconnecting:
                ConnectedView()
            case .pairing(let deviceID):
                PairingView(deviceID: deviceID)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: appState.connectionState)
    }
}

// MARK: - ConnectingView

struct ConnectingView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        ZStack {
            Color.clawBg.ignoresSafeArea()

            VStack(spacing: 20) {
                Image("AppLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 92, height: 92)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .shadow(color: Color.clawAccent.opacity(0.24), radius: 18, y: 10)

                ProgressView()
                    .progressViewStyle(.circular)
                    .scaleEffect(1.1)
                    .tint(Color.clawAccent)
                Text("Connecting…")
                    .font(.headline)
                    .foregroundStyle(Color.clawMuted)
                Button("Cancel") {
                    Task { await appState.disconnect() }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .foregroundStyle(Color.clawText)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.clawCard)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.clawBorder, lineWidth: 1)
                )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// NOTE: ConnectedView is defined in Claw/Views/ConnectedView.swift

// MARK: - DeepLink handling (extension on ClawApp)

extension ClawApp {
    @MainActor
    func handleDeepLink(url: URL) {
        guard url.scheme?.lowercased() == "claw" else { return }

        switch url.host?.lowercased() {
        case "share":
            // claw://share?pending=1  ← posted by share extension
            router.presentPendingShares()

        case "session":
            // claw://session/<sessionKey>  ← future: deep link to a specific session
            // NavigationRouter doesn't yet have a direct navigate-to-session API;
            // this is a placeholder for when AdaptiveSessionsLayout supports it.
            break

        default:
            break
        }
    }
}
