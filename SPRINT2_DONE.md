# Sprint 2 Complete

## Files Created

| File | Summary |
|------|---------|
| `Claw/Models/Session.swift` | `ClawSession` struct and `AgentStatus` enum (idle/thinking/running) with display helpers |
| `Claw/Models/Message.swift` | `ClawMessage` struct and `MessageRole` enum (user/assistant/system) |
| `Claw/Stores/SessionStore.swift` | `@Observable SessionStore` — loads sessions via `sessions.list`, reacts to `session.created/updated/deleted/agent.status` events |
| `Claw/Stores/MessageStore.swift` | `@Observable MessageStore` — loads messages via `messages.list`, handles `message.created/delta/done` streaming events, sends via `message.send` |
| `Claw/Views/ConnectedView.swift` | Root view post-connection; `AdaptiveSessionsLayout` uses `NavigationSplitView` on iPad and `NavigationStack` on iPhone |
| `Claw/Views/SessionListView.swift` | Session list with status dots, last message preview, unread badge, relative timestamp, pull-to-refresh, and empty state |
| `Claw/Views/ChatThreadView.swift` | Per-session message thread with streaming cursor, auto-scroll, compose bar, send button gating on agent status |
| `Claw/Views/MessageBubbleView.swift` | Single message bubble — right-aligned blue for user, left-aligned gray for assistant, streaming `▌` cursor, formatted timestamp |

## Files Modified

| File | Summary |
|------|---------|
| `Claw/App/AppState.swift` | Added `sessionStore` property, `setupSessionStore`, `startDisconnectWatcher`, `runReconnectLoop` using `ReconnectManager` for automatic reconnect on drop |
| `Claw/App/ClawApp.swift` | Removed Sprint 1 `ConnectedView` stub (replaced by real implementation in `ConnectedView.swift`) |
