You are a Claude Code implementation agent working on the native Swift iOS app "Claw" in this worktree.

Context:
- Repo is an XcodeGen SwiftUI iOS 17 project for OpenClaw/OpenCode-style autonomous AI agents.
- Treat this as a production iOS codebase. Think principal iOS engineer + SRE power-user.
- Existing app has WebSocket gateway, pairing/auth, sessions/chat, push, Dynamic Island, memory/skills/cron/nodes, remote ops hooks, and several partial/bones features.
- This worktree has a copy of current WIP from main. Do not assume placeholder files are final.

Global implementation rules:
1. Fully implement your assigned feature stream end-to-end as much as possible in this repo.
2. Prefer SwiftUI, async/await, @Observable, actors, protocol-oriented design, and modular feature boundaries.
3. Reuse existing theme/colors (`ClawTheme`) and existing gateway/client/store patterns.
4. Do not delete unrelated work. Avoid broad rewrites outside your stream unless necessary.
5. Add/extend data models, stores, views, and gateway method/event constants where needed.
6. If backend API is missing, create clean client-side abstractions, mock/preview fallbacks, typed method/event names, and comments documenting expected gateway contracts.
7. Keep UI native, dense, fast, dark, operational, and trustworthy. Avoid generic chatbot aesthetics.
8. Add meaningful sample/preview data where live backend is unavailable.
9. Update README or add a short architecture note if you introduce major systems.
10. Attempt lightweight validation that is possible on this host. If Xcode is unavailable, at least run grep/static sanity checks and report that build requires macOS/Xcode.
11. Commit your work to the worktree branch with a clear commit message.
12. At the end, print: branch name, files changed, what was implemented, known backend expectations, validation performed, and merge notes.

No direct user notification route is available in this webchat context. Do NOT use openclaw message send. Just print your completion summary to stdout.

ASSIGNED STREAM: Live Terminal Streaming + Visual Runbooks

Implement the next evolution for:
1. LIVE TERMINAL STREAMING
2. VISUAL RUNBOOKS

Terminal requirements:
- True live terminal session mirroring UI, not just static logs.
- ANSI color support, streaming cursor, realtime updates, pause/resume, search, copy commands, timestamps, collapsible sections, export/share logs.
- Safe large-output handling: incremental parsing, bounded buffers, virtualization-friendly rendering.
- Reconnect-aware terminal store and typed gateway contracts for terminal stream subscribe/input/control.
- UI for terminal session list/detail and a route from Ops tab.
- Optional "Take Control" mode with guarded input passthrough.
- Replay previous terminal session history when backend data is available; preview/mock fallback now.

Runbook requirements:
- Reusable runbook engine with typed models for runbook definition, steps, risk, approvals, checkpoints, retries, rollback.
- YAML/JSON-like definitions via Codable structs; sample definitions for restart API, rollback deployment, investigate unhealthy container.
- SwiftUI visual stepper: status, logs per step, dry-run, approvals, FaceID/TouchID gate for dangerous steps via existing/new BiometricGuard.
- Execution modes: manual, semi-autonomous, fully autonomous.
- Gateway API expectations documented as typed methods/events.
- Integrate into Ops tab. Ops tab should no longer be placeholder.

Be ambitious but keep it compilable and cohesive. Commit changes on this worktree branch.