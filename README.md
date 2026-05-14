# Claw 🦀

An iOS companion app for [OpenClaw](https://openclaw.ai) — chat with your AI agents, manage EC2 instances over SSH, monitor health checks, and run custom commands from your phone.

Built because no app like this existed.

---

## Features

- **AI Chat** — full session management, streaming responses, voice input, file/image attachments
- **SSH Key Management** — store private keys securely in iOS Keychain, connect directly to EC2 instances
- **Health Checks** — ping instances on demand or schedule automatic checks (background task, push notification on failure)
- **Custom Commands** — define named shell commands per instance, run them with one tap and see the output
- **Container Monitoring** — live `docker ps` output via SSH
- **Remote Ops Dashboard** — EC2 instances, GitHub Actions, Datadog alerts, incident feed
- **Commandments** — persistent rules injected into every AI session (once per conversation, token-efficient)
- **Agent Monitor** — watch running agents, view live terminal output
- **Memory Browser** — search and manage your OpenClaw memory store
- **Scheduled Tasks** — view and manage cron jobs running on the gateway
- **Live Activities** — agent status on your Lock Screen

---

## Requirements

- iOS 17.0+
- An [OpenClaw](https://openclaw.ai) gateway (self-hosted or managed)
- Xcode 15+

---

## Setup

### 1. Clone

```bash
git clone https://github.com/Drumshadow/claw-ios.git
cd claw-ios
```

### 2. Configure secrets

```bash
cp Claw/Config/Secrets.xcconfig.example Claw/Config/Secrets.xcconfig
```

Edit `Secrets.xcconfig` and fill in your GitHub OAuth client ID (required for GitHub Actions integration). This file is gitignored and never committed.

### 3. Generate the Xcode project

```bash
brew install xcodegen
xcodegen generate
```

### 4. Open and run

```bash
open Claw.xcodeproj
```

Select your target device or simulator and hit Run.

---

## Architecture

- **SwiftUI** — all views
- **`@Observable`** — state management throughout
- **Citadel** — pure Swift SSH library (SwiftNIO-based)
- **iOS Keychain** — all credentials (SSH keys, AWS, Datadog, GitHub tokens)
- **BGTaskScheduler** — background health checks
- **WebSocket** — real-time gateway connection

---

## Contributing

PRs welcome. Open an issue first for anything large.

---

## License

MIT — see [LICENSE](LICENSE).
