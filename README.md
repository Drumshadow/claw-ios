# Claw

Claw is a native SwiftUI iOS app that serves as an operator chat client for [OpenClaw](https://openclaw.ai) — the self-hosted AI agent platform. It connects to one or more OpenClaw gateway nodes over a WebSocket, lists running agent sessions in real time, lets operators send messages and watch agent output stream in, and delivers push notifications via APNs when new messages arrive while the app is backgrounded.

---

## Prerequisites

- **Xcode 16** or later (Swift 5.9+ required)
- **[xcodegen](https://github.com/yoichiro-shimizu/XcodeGen)** to generate the `.xcodeproj` from `project.yml`
  ```
  brew install xcodegen
  ```
- A running **OpenClaw gateway** (v3+ protocol) accessible over the network

---

## How to Build

```bash
# 1. Clone the repo and enter the iOS app directory
cd claw-ios

# 2. Generate the Xcode project
xcodegen generate

# 3. Open in Xcode
open Claw.xcodeproj

# 4. Select your Development Team
#    Xcode → Targets → Claw → Signing & Capabilities → Team

# 5. Select your target device or simulator and press Run (⌘R)
```

For a release/TestFlight build using Fastlane:
```bash
bundle exec fastlane beta
```

---

## How to Pair with a Gateway

1. Launch Claw on your device.
2. On the **Gateways** screen, either:
   - Tap a gateway discovered automatically on your local network via Bonjour, or
   - Tap **+** to enter a host and port manually.
3. Claw connects and, if this is the first time, enters **Pairing** mode showing your Device ID.
4. Approve the device on the gateway:
   ```
   openclaw devices approve <device-id-prefix>
   ```
5. Claw detects approval automatically (polling every 3 seconds) and transitions to the **Sessions** view.

---

## Project Structure

```
Claw/
├── App/
│   ├── AppDelegate.swift        UIApplicationDelegate — APNs token + silent push
│   ├── AppState.swift           @Observable root state, connect/disconnect/reconnect logic
│   └── ClawApp.swift            @main SwiftUI App, scene setup, environment injection
│
├── Auth/
│   ├── DeviceIdentity.swift     Actor managing Ed25519 key pair + device token persistence
│   ├── KeychainStore.swift      Thin wrapper over Security.framework
│   └── PairingCoordinator.swift Polling loop for device approval
│
├── Discovery/
│   └── GatewayDiscovery.swift   Bonjour browser for _openclaw._tcp. services
│
├── Models/
│   ├── GatewayConfig.swift      Gateway host/port config + multi-gateway UserDefaults helpers
│   ├── Message.swift            ClawMessage, MessageRole
│   └── Session.swift            ClawSession, AgentStatus
│
├── Protocol/
│   ├── GatewayFrames.swift      Wire frame types: RequestFrame, ResponseFrame, EventFrame, JSONValue
│   └── GatewayMethods.swift     Method name constants, ConnectionState enum
│
├── Push/
│   ├── NotificationDelegate.swift  UNUserNotificationCenterDelegate — foreground banners + tap routing
│   └── PushManager.swift           APNs registration, gateway token registration, local notifications
│
├── Stores/
│   ├── GatewayStore.swift       @Observable list of saved gateways
│   ├── MessageStore.swift       Per-session message loading, streaming, and sending
│   └── SessionStore.swift       Real-time session list with gateway event subscription
│
├── Transport/
│   ├── GatewayClient.swift      Actor managing a single WebSocket connection + handshake
│   ├── ReconnectManager.swift   Exponential backoff reconnection actor
│   └── RequestRouter.swift      In-flight request tracking via async continuations
│
└── Views/
    ├── ChatThreadView.swift      Message thread with streaming output and compose bar
    ├── ConnectedView.swift       Root connected layout (iPad split / iPhone stack)
    ├── ConnectionBannerView.swift Slim overlay banner for reconnecting/disconnected states
    ├── GatewaySetupView.swift    Gateway discovery + manual entry
    ├── MarkdownTextView.swift    AttributedString-based markdown renderer
    ├── MessageBubbleView.swift   Chat bubble with markdown support for assistant messages
    ├── PairingView.swift         Waiting-for-approval UI with device ID display
    ├── SessionListView.swift     Scrollable session list with agent status dots
    └── SettingsView.swift        Gateway management, connection info, device ID, danger zone
```
