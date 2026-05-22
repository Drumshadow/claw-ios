import SwiftUI
import UniformTypeIdentifiers
import Social

// MARK: - ShareExtensionUI

/// SwiftUI root for the Claw share extension.
/// Presents a lightweight action picker + session selector, then
/// writes the intake item to the App Group queue and deep-links
/// into the main app.
///
/// The extension avoids importing GatewayClient or making network calls.
/// All delivery happens in the main app via ShareIntakeProcessor.
struct ShareExtensionUI: View {

    // Items extracted from the NSExtensionContext
    @Binding var sharedItems: [PendingShareItem]
    var onCancel: () -> Void
    var onConfirm: ([ShareIntakeItem]) -> Void

    @State private var selectedAction: ShareActionType = .analyze
    @State private var customPrompt: String = ""
    @State private var isLoading = true

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    loadingView
                } else if sharedItems.isEmpty {
                    emptyView
                } else {
                    contentView
                }
            }
            .navigationTitle("Send to Claw")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel", action: onCancel)
                        .foregroundStyle(Color.clawMuted)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Send") { confirmSend() }
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.clawAccent)
                        .disabled(sharedItems.isEmpty)
                }
            }
        }
        .onAppear {
            // Give items a tick to load
            Task {
                try? await Task.sleep(nanoseconds: 200_000_000)
                isLoading = sharedItems.isEmpty
            }
        }
        .onChange(of: sharedItems.isEmpty) { _, isEmpty in
            if !isEmpty { isLoading = false }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Views

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .tint(Color.clawAccent)
            Text("Loading content…")
                .font(.subheadline)
                .foregroundStyle(Color.clawMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.clawBg)
    }

    private var emptyView: some View {
        VStack(spacing: 16) {
            Image(systemName: "questionmark.circle")
                .font(.system(size: 48))
                .foregroundStyle(Color.clawMuted.opacity(0.4))
            Text("Nothing to share")
                .font(.headline)
                .foregroundStyle(Color.clawMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.clawBg)
    }

    private var contentView: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Preview of items
                itemsPreviewSection

                Divider()
                    .background(Color.clawBorder)
                    .padding(.vertical, 16)
                    .padding(.horizontal, 16)

                // Action picker for the first/primary item
                if let primary = sharedItems.first {
                    ShareActionPickerView(
                        contentType: primary.contentType,
                        selectedAction: $selectedAction,
                        customPrompt: $customPrompt
                    )
                    .padding(.horizontal, 16)
                }

                // Routing note
                VStack(alignment: .leading, spacing: 6) {
                    Divider()
                        .background(Color.clawBorder)
                        .padding(.vertical, 16)

                    HStack(spacing: 8) {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.clawTeal)
                        Text("Will be routed to an available session in Claw")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.clawMuted)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 80)
            }
        }
        .background(Color.clawBg.ignoresSafeArea())
        .safeAreaInset(edge: .bottom) {
            sendBar
        }
    }

    private var itemsPreviewSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("\(sharedItems.count) item\(sharedItems.count == 1 ? "" : "s")")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.clawMuted)
                .textCase(.uppercase)
                .tracking(0.5)
                .padding(.horizontal, 16)
                .padding(.top, 16)

            ForEach(sharedItems) { item in
                ShareExtensionItemRow(item: item)
                    .padding(.horizontal, 16)
            }
        }
    }

    private var sendBar: some View {
        Button(action: confirmSend) {
            HStack(spacing: 10) {
                Image(systemName: selectedAction.systemImage)
                    .font(.system(size: 18))
                Text(selectedAction.displayName)
                    .font(.system(size: 16, weight: .bold))
            }
            .foregroundStyle(.black)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(Color.clawTeal)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .disabled(sharedItems.isEmpty)
        .background(Color.clawBg)
    }

    // MARK: - Actions

    private func confirmSend() {
        let intake = sharedItems.map { pending in
            ShareIntakeItem(
                contentType: pending.contentType,
                action: selectedAction,
                routing: .autoSelect,
                customPrompt: selectedAction == .custom ? customPrompt : nil,
                url: pending.url,
                fileName: pending.fileName,
                fileData: pending.data,
                textContent: pending.text
            )
        }
        onConfirm(intake)
    }
}

// MARK: - ShareExtensionItemRow

struct ShareExtensionItemRow: View {
    let item: PendingShareItem

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: item.contentType.systemImage)
                .font(.system(size: 18))
                .foregroundStyle(Color.clawTeal)
                .frame(width: 36, height: 36)
                .background(Color.clawTeal.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 3) {
                Text(item.displayTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.clawTextStrong)
                    .lineLimit(1)

                Text(item.displaySubtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.clawMuted)
                    .lineLimit(1)
            }

            Spacer()

            Text(item.contentType.displayName)
                .font(.system(size: 11))
                .foregroundStyle(Color.clawMuted)
        }
        .padding(10)
        .background(Color.clawBgElevated)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - PendingShareItem

/// Lightweight in-extension model before full intake item is constructed.
struct PendingShareItem: Identifiable {
    let id = UUID()
    let contentType: ShareContentType
    let url: URL?
    let fileName: String?
    let data: Data?
    let text: String?

    var displayTitle: String {
        if let url = url { return url.host ?? url.absoluteString }
        if let name = fileName { return name }
        if let t = text { return String(t.prefix(60)) }
        return contentType.displayName
    }

    var displaySubtitle: String {
        if let url = url { return url.absoluteString }
        if let t = text { return String(t.prefix(80)) }
        return ""
    }
}
