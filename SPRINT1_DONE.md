# Sprint 1 — Complete

All files created under `claw-ios/`.

## Files

| Path | Summary |
|------|---------|
| `project.yml` | XcodeGen config: iOS 17 target, bundle ID `ai.claw.app`, Swift 5.9, Bonjour entitlements in Info.plist |
| `Claw/Models/GatewayConfig.swift` | `GatewayConfig` struct — Codable, Identifiable, Hashable; computes `wsURL` and `displayAddress` |
| `Claw/Protocol/GatewayFrames.swift` | All wire types: `RequestFrame`, `ResponseFrame`, `EventFrame`, `GatewayEvent`, `ConnectChallengePayload`, `HelloOkPayload`, `ConnectParams`, `JSONValue` recursive enum, `AnyEncodable` type-eraser |
| `Claw/Protocol/GatewayMethods.swift` | String constants for all gateway method and event names; `ConnectionState` enum with display helpers |
| `Claw/Auth/KeychainStore.swift` | Generic Keychain read/write/delete/exists using `kSecClassGenericPassword`, service `ai.claw.app` |
| `Claw/Auth/DeviceIdentity.swift` | Actor — generates/loads `Curve25519.Signing.PrivateKey` from Keychain; device ID = SHA-256 of public key hex; signs `nonce+ts`; persists per-gateway device tokens |
| `Claw/Auth/PairingCoordinator.swift` | `@Observable` — runs connect→poll loop at 3-second intervals until gateway approves the device |
| `Claw/Transport/RequestRouter.swift` | Actor — tracks in-flight requests by UUID, vends `CheckedContinuation`s, resolves/rejects/cancels-all |
| `Claw/Transport/ReconnectManager.swift` | Actor — exponential backoff with jitter (configurable initial, max, multiplier, jitter fraction); `waitAndShouldReconnect()` async helper |
| `Claw/Transport/GatewayClient.swift` | Actor — full WebSocket lifecycle: connect, `connect.challenge` handshake, `hello-ok` parse, normal receive loop, `send<T>()` with continuation routing, `events()` AsyncStream, 15-second ping loop, disconnect with cleanup |
| `Claw/Discovery/GatewayDiscovery.swift` | `@Observable NSObject` — `NetServiceBrowser` browses `_openclaw._tcp.`, resolves host/port, publishes `[DiscoveredGateway]`; stable UUID from service name hash |
| `Claw/App/AppState.swift` | `@Observable` — owns `GatewayClient?`, `selectedConfig`, `connectionState`; persists config to UserDefaults; `connect(to:)` / `disconnect()` async methods |
| `Claw/App/ClawApp.swift` | `@main` entry point; `RootView` routes between `GatewaySetupView`, `ConnectingView`, `PairingView`, and `ConnectedView` based on `connectionState` |
| `Claw/Views/GatewaySetupView.swift` | NavigationStack list of Bonjour-discovered gateways + last-used gateway; "Add manually" sheet (`ManualGatewayEntryView`) with host/port/name fields and validation |
| `Claw/Views/PairingView.swift` | Shows device ID with copy button, CLI approval hint, live elapsed-second counter, 3-second poll via `PairingCoordinator`; Cancel disconnects and returns to setup |
