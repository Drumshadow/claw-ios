import SwiftUI
import UIKit

// MARK: - TerminalSessionView
//
// Full-featured live terminal viewer. Features:
//   - ANSI colour rendering via ANSIParser
//   - Auto-scroll with detection when user has scrolled away
//   - Pause/resume with offline buffer
//   - Live search with match count
//   - Timestamps toggle (inline)
//   - "Take Control" mode: guarded text input passthrough
//   - Export log as plain text (share sheet)
//   - Reconnect button on disconnect
//   - Session info sheet

struct TerminalSessionView: View {
    let session: TerminalSession

    @State private var store: TerminalStore
    @State private var searchText: String = ""
    @State private var isSearching: Bool = false
    @State private var showTimestamps: Bool = false
    @State private var showTakeControlAlert: Bool = false
    @State private var showExportSheet: Bool = false
    @State private var exportText: String = ""
    @State private var inputText: String = ""
    @State private var showInfo: Bool = false
    @FocusState private var searchFocused: Bool
    @FocusState private var inputFocused: Bool

    // Injected from environment in non-preview paths
    @Environment(TerminalSessionStore.self) private var sessionStore: TerminalSessionStore?

    init(session: TerminalSession, store: TerminalStore? = nil) {
        self.session = session
        self._store = State(initialValue: store ?? TerminalStore(sessionId: session.id))
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Color(UIColor(hex: 0x0a0c0f)).ignoresSafeArea()

            VStack(spacing: 0) {
                statusBar
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color(UIColor(hex: 0x14161a)))

                Divider()
                    .background(Color.clawBorder)

                terminalContent
            }

            // Take Control input bar
            if store.isTakeControlActive {
                takeControlBar
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            // Search overlay
            if isSearching && !store.isTakeControlActive {
                searchOverlay
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .navigationTitle(session.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.clawBgAccent, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar { toolbarContent }
        .sheet(isPresented: $showInfo) { infoSheet }
        .sheet(isPresented: $showExportSheet) {
            ShareSheet(items: [exportText])
        }
        .alert("Take Control", isPresented: $showTakeControlAlert) {
            Button("Enable", role: .destructive) {
                withAnimation(.spring(response: 0.3)) {
                    store.isTakeControlActive = true
                    inputFocused = true
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You will be able to send keystrokes directly to the remote terminal. Use with caution in production environments.")
        }
        .onChange(of: isSearching) { _, newValue in
            if !newValue { searchText = "" }
        }
        .task {
            if !session.isReplay && !store.isConnected {
                await store.connect()
            } else if session.isReplay {
                await store.loadHistory()
            }
        }
        .onDisappear {
            Task { await sessionStore?.releaseStore(for: session.id) }
        }
    }

    // MARK: - Status bar

    private var statusBar: some View {
        HStack(spacing: 12) {
            // Connection indicator
            HStack(spacing: 5) {
                connectionDot
                Text(statusLabel)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.clawMuted)
            }

            if store.isReconnecting {
                ProgressView()
                    .scaleEffect(0.6)
                    .tint(Color.clawWarn)
            }

            Spacer()

            // Line count
            Text("\(store.buffer.lineCount) ln")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(Color.clawMuted)

            if store.isPaused {
                Label("Paused", systemImage: "pause.circle.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.clawWarn)
                    .labelStyle(.titleAndIcon)
            }

            if store.isTakeControlActive {
                Label("Control", systemImage: "keyboard")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.clawAccent)
                    .labelStyle(.titleAndIcon)
            }

            // Reconnect button when disconnected
            if !store.isConnected && !session.isReplay && !store.hasEnded {
                Button {
                    store.reconnect()
                } label: {
                    Label("Reconnect", systemImage: "arrow.clockwise")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.clawAccent)
                        .labelStyle(.titleAndIcon)
                }
            }
        }
    }

    @ViewBuilder
    private var connectionDot: some View {
        if store.isConnected && !session.isReplay {
            Circle()
                .fill(Color.clawOk)
                .frame(width: 7, height: 7)
                .overlay(
                    Circle()
                        .fill(Color.clawOk.opacity(0.3))
                        .frame(width: 14, height: 14)
                )
        } else if session.isReplay {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 10))
                .foregroundStyle(Color.clawTeal)
        } else {
            Circle()
                .fill(Color.clawDanger)
                .frame(width: 7, height: 7)
        }
    }

    private var statusLabel: String {
        if session.isReplay { return "Replay" }
        if store.hasEnded { return "Ended\(store.exitCode.map { " (\($0))" } ?? "")" }
        if !store.isConnected { return "Disconnected" }
        return "Live"
    }

    // MARK: - Terminal content

    private var terminalContent: some View {
        GeometryReader { geometry in
            let displayLines = searchText.isEmpty
                ? store.buffer.lines
                : store.buffer.search(searchText)

            let combinedText = displayLines.map { line -> String in
                if showTimestamps {
                    let ts = DateFormatter.terminalTime.string(from: line.timestamp)
                    return "\u{1B}[2m\(ts)\u{1B}[0m \(line.raw)"
                }
                return line.raw
            }.joined(separator: "\n")

            let baseFont = UIFont.monospacedSystemFont(ofSize: 12, weight: .regular)
            let baseForeground = UIColor(hex: 0xd4d4d8)
            let attributedText = ANSIParser.parse(combinedText, baseFont: baseFont, baseForeground: baseForeground)

            TerminalTextView(attributedText: attributedText, isPaused: store.isPaused)
                .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .background(Color(UIColor(hex: 0x0a0c0f)))
    }

    // MARK: - Search overlay

    private var searchOverlay: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Color.clawMuted)
                    .font(.system(size: 15))

                TextField("Search output…", text: $searchText)
                    .textFieldStyle(.plain)
                    .foregroundStyle(Color.clawText)
                    .focused($searchFocused)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .font(.system(size: 14, design: .monospaced))

                if !searchText.isEmpty {
                    let count = store.buffer.search(searchText).count
                    Text("\(count)")
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(count > 0 ? Color.clawOk : Color.clawMuted)
                        .monospacedDigit()

                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Color.clawMuted)
                    }
                }
            }
            .padding(14)
            .background(Color.clawBgElevated)
        }
        .cornerRadius(14, corners: [.topLeft, .topRight])
        .shadow(color: Color.black.opacity(0.4), radius: 24, y: -6)
    }

    // MARK: - Take Control input bar

    private var takeControlBar: some View {
        VStack(spacing: 0) {
            Divider().background(Color.clawAccent.opacity(0.3))

            HStack(spacing: 10) {
                Image(systemName: "keyboard")
                    .foregroundStyle(Color.clawAccent)
                    .font(.system(size: 14))

                TextField("Send input…", text: $inputText)
                    .textFieldStyle(.plain)
                    .foregroundStyle(Color.clawText)
                    .focused($inputFocused)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .font(.system(size: 13, design: .monospaced))
                    .onSubmit {
                        let text = inputText + "\n"
                        inputText = ""
                        Task { await store.sendInput(text) }
                    }

                // Ctrl-C button
                Button {
                    Task { await store.sendInterrupt() }
                } label: {
                    Text("^C")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.clawDanger)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.clawDanger.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                }

                // Exit Take Control
                Button {
                    withAnimation(.spring(response: 0.3)) {
                        store.isTakeControlActive = false
                        inputText = ""
                        inputFocused = false
                    }
                } label: {
                    Image(systemName: "xmark")
                        .foregroundStyle(Color.clawMuted)
                        .font(.system(size: 14))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color(UIColor(hex: 0x14161a)))
        }
    }

    // MARK: - Info sheet

    private var infoSheet: some View {
        NavigationStack {
            List {
                Section("Session") {
                    infoRow("ID", value: session.id)
                    infoRow("Title", value: session.title)
                    infoRow("Status", value: session.status.displayLabel)
                }
                if let node = session.nodeName ?? session.nodeId {
                    Section("Runner") {
                        infoRow("Node", value: node)
                    }
                }
                Section("Timing") {
                    infoRow("Started", value: DateFormatter.terminalFull.string(from: session.startedAt))
                    if let ended = session.endedAt {
                        infoRow("Ended", value: DateFormatter.terminalFull.string(from: ended))
                    }
                    if let dur = session.formattedDuration {
                        infoRow("Duration", value: dur)
                    }
                    if let code = session.exitCode {
                        infoRow("Exit Code", value: String(code))
                    }
                }
                Section("Buffer") {
                    infoRow("Lines", value: "\(store.buffer.lineCount) / \(store.buffer.maxLines)")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.clawBg)
            .navigationTitle("Session Info")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.clawBgAccent, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { showInfo = false }
                        .foregroundStyle(Color.clawAccent)
                        .fontWeight(.semibold)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func infoRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(Color.clawMuted)
            Spacer()
            Text(value)
                .foregroundStyle(Color.clawText)
                .font(.system(size: 13, design: .monospaced))
                .multilineTextAlignment(.trailing)
        }
        .listRowBackground(Color.clawCard)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .navigationBarTrailing) {
            // Info
            Button {
                showInfo = true
            } label: {
                Image(systemName: "info.circle")
                    .foregroundStyle(Color.clawMuted)
            }

            // Search toggle
            Button {
                withAnimation(.spring(response: 0.3)) {
                    isSearching.toggle()
                    if isSearching { searchFocused = true }
                    else if store.isTakeControlActive { inputFocused = true }
                }
            } label: {
                Image(systemName: isSearching ? "magnifyingglass.circle.fill" : "magnifyingglass")
                    .foregroundStyle(isSearching ? Color.clawAccent : Color.clawMuted)
            }

            // Timestamps toggle
            Button {
                withAnimation { showTimestamps.toggle() }
            } label: {
                Image(systemName: showTimestamps ? "clock.fill" : "clock")
                    .foregroundStyle(showTimestamps ? Color.clawAccent : Color.clawMuted)
            }

            Menu {
                // Pause / Resume
                if store.isPaused {
                    Button {
                        store.resume()
                    } label: {
                        Label("Resume Streaming", systemImage: "play.fill")
                    }
                } else {
                    Button {
                        store.isPaused = true
                    } label: {
                        Label("Pause Streaming", systemImage: "pause.fill")
                    }
                }

                Divider()

                // Take Control
                if !session.isReplay && store.isConnected {
                    if store.isTakeControlActive {
                        Button(role: .destructive) {
                            withAnimation { store.isTakeControlActive = false }
                        } label: {
                            Label("Exit Control Mode", systemImage: "keyboard.chevron.compact.down")
                        }
                    } else {
                        Button {
                            showTakeControlAlert = true
                        } label: {
                            Label("Take Control", systemImage: "keyboard")
                        }
                    }
                }

                Divider()

                // Export
                Button {
                    exportText = store.exportLog()
                    showExportSheet = true
                } label: {
                    Label("Export Log", systemImage: "square.and.arrow.up")
                }

                // Clear
                Button(role: .destructive) {
                    store.clear()
                } label: {
                    Label("Clear Buffer", systemImage: "trash")
                }

            } label: {
                Image(systemName: "ellipsis.circle")
                    .foregroundStyle(Color.clawMuted)
            }
        }
    }
}

// MARK: - DateFormatter helpers

private extension DateFormatter {
    static let terminalTime: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    static let terminalFull: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .medium
        return f
    }()
}

// MARK: - RoundedCorner helper (corner-selective rounding)

extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}

struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners

    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}

// MARK: - ShareSheet

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - TerminalTextView (enhanced with isPaused indicator)

struct TerminalTextView: UIViewRepresentable {
    let attributedText: NSAttributedString
    var isPaused: Bool = false
    var onTap: (() -> Void)? = nil

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.backgroundColor = .clear
        textView.isEditable = false
        textView.isSelectable = true
        textView.dataDetectorTypes = []
        textView.textContainerInset = UIEdgeInsets(top: 8, left: 12, bottom: 80, right: 12)
        textView.font = UIFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.textColor = UIColor(hex: 0xd4d4d8)
        textView.isScrollEnabled = true
        textView.alwaysBounceVertical = true
        textView.delegate = context.coordinator
        if onTap != nil {
            let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap))
            textView.addGestureRecognizer(tap)
        }
        return textView
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        let shouldScroll = !isPaused && context.coordinator.shouldAutoScroll(uiView)
        uiView.attributedText = attributedText
        if shouldScroll {
            DispatchQueue.main.async {
                context.coordinator.scrollToBottom(uiView)
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(onTap: onTap) }

    class Coordinator: NSObject, UITextViewDelegate {
        var onTap: (() -> Void)?
        init(onTap: (() -> Void)?) { self.onTap = onTap }

        func shouldAutoScroll(_ textView: UITextView) -> Bool {
            let offset = textView.contentOffset.y
            let contentHeight = textView.contentSize.height
            let frameHeight = textView.frame.size.height
            let bottomOffset = contentHeight - frameHeight
            if bottomOffset <= 0 { return true }
            return offset >= bottomOffset - 120
        }

        func scrollToBottom(_ textView: UITextView) {
            let contentHeight = textView.contentSize.height
            let frameHeight = textView.frame.size.height
            if contentHeight > frameHeight {
                textView.setContentOffset(
                    CGPoint(x: 0, y: contentHeight - frameHeight),
                    animated: false
                )
            }
        }

        @objc func handleTap() { onTap?() }
        func textViewDidChangeSelection(_ textView: UITextView) {}
    }
}

// MARK: - Previews

#Preview("Live Terminal") {
    NavigationStack {
        TerminalSessionView(
            session: TerminalSession.sampleSessions[0],
            store: TerminalStore.preview()
        )
    }
    .preferredColorScheme(.dark)
}

#Preview("Replay Terminal") {
    NavigationStack {
        TerminalSessionView(
            session: TerminalSession.sampleSessions[2],
            store: TerminalStore.preview()
        )
    }
    .preferredColorScheme(.dark)
}
