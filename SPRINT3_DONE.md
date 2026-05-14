# Sprint 3 — Done

## Files Created

### Push
- `Claw/Push/PushManager.swift` — `@Observable @MainActor` push manager: APNs registration, hex token storage in Keychain, `push.apns.register` gateway call, background wake/presence, local notification scheduling
- `Claw/Push/NotificationDelegate.swift` — `UNUserNotificationCenterDelegate`: foreground banner presentation, tap → `claw.notification.tapped` notification with `sessionKey`

### App
- `Claw/App/AppDelegate.swift` — `UIApplicationDelegate`: APNs token delivery to `PushManager`, silent push → `handleBackgroundWake`, sets `NotificationDelegate` as `UNUserNotificationCenter` delegate

### Stores
- `Claw/Stores/GatewayStore.swift` — `@Observable @MainActor` store: `add`, `remove`, `setDefault`, persists to `UserDefaults` via `GatewayConfig.saveAll`

### Views
- `Claw/Views/ConnectionBannerView.swift` — Slim overlay banner: yellow spinner for `.reconnecting`, red tappable for `.disconnected`/`.failed`; `connectionBanner(state:onRetry:)` view modifier
- `Claw/Views/MarkdownTextView.swift` — `AttributedString(markdown:)`-based renderer with fenced code block pre-processing; falls back to plain `Text`
- `Claw/Views/SettingsView.swift` — Settings sheet with Gateways list (add/delete/set-default), Current Connection status, Device ID copy, Danger Zone reset-pairing

### Fastlane
- `fastlane/Appfile`
- `fastlane/Gymfile`
- `fastlane/Fastfile`

### Entitlements
- `Claw/Claw.entitlements` — APNs `development` environment

## Files Modified

- `Claw/Protocol/GatewayMethods.swift` — Added `.reconnecting` case to `ConnectionState` with `isReconnecting` computed property and `displayDescription`
- `Claw/Models/GatewayConfig.swift` — Added `loadAll()`, `saveAll(_:)`, `setDefault(_:)` static helpers
- `Claw/App/AppState.swift` — Reconnect loop now transitions through `.reconnecting` instead of `.connecting` when re-attempting after disconnect
- `Claw/App/ClawApp.swift` — Added `@UIApplicationDelegateAdaptor(AppDelegate.self)`, `@State private var gatewayStore`, `@State private var pushManager`, environment injections, push auth on `.connected`, `.reconnecting` case in `RootView`
- `Claw/Views/ConnectedView.swift` — Settings gear toolbar button + `SettingsView` sheet; `connectionBanner` overlay via modifier
- `Claw/Views/MessageBubbleView.swift` — Assistant messages now rendered with `MarkdownTextView` instead of plain `Text`
- `project.yml` — Added `UIBackgroundModes: [remote-notification]`, entitlements reference
