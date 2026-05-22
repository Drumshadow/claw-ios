import SwiftUI

struct IncidentDetailView: View {
    let incident: Incident
    @Environment(BackgroundAgentStore.self) private var store
    @State private var showResolveDialog: Bool = false
    @State private var resolutionText: String = ""

    var body: some View {
        List {
            // Header card
            Section {
                headerCard
                    .listRowBackground(Color.clawCard)
                    .listRowInsets(EdgeInsets())
            }

            // Timeline
            Section("Timeline") {
                ForEach(incident.timeline) { entry in
                    IncidentTimelineEntryRow(entry: entry)
                        .listRowBackground(Color.clawCard)
                }
                if incident.timeline.isEmpty {
                    Text("No timeline entries recorded.")
                        .font(.caption)
                        .foregroundStyle(Color.clawMuted)
                        .listRowBackground(Color.clawCard)
                }
            }

            // Tags
            if !incident.tags.isEmpty {
                Section("Tags") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(incident.tags, id: \.self) { tag in
                                Text(tag)
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(Color.clawTeal)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(Color.clawTeal.opacity(0.1))
                                    .clipShape(Capsule())
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                    }
                    .listRowBackground(Color.clawCard)
                    .listRowInsets(EdgeInsets())
                }
            }

            // Actions
            if incident.status.isActive {
                Section("Actions") {
                    if incident.status == .open {
                        Button {
                            Task { await store.acknowledgeIncident(incident.id) }
                        } label: {
                            Label("Acknowledge", systemImage: "eye")
                                .foregroundStyle(Color.clawTeal)
                        }
                        .listRowBackground(Color.clawCard)
                    }

                    Button {
                        showResolveDialog = true
                    } label: {
                        Label("Mark Resolved", systemImage: "checkmark.circle")
                            .foregroundStyle(Color.clawOk)
                    }
                    .listRowBackground(Color.clawCard)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.clawBg)
        .navigationTitle(incident.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.clawBgAccent, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .sheet(isPresented: $showResolveDialog) {
            resolveSheet
        }
    }

    // MARK: - Header

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: incident.severity.systemImage)
                    .foregroundStyle(Color(hex: incident.severity.colorHex))
                Text(incident.severity.displayName.uppercased())
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color(hex: incident.severity.colorHex))
                Spacer()
                Text(incident.status.displayName)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(incident.status.isActive ? Color.clawWarn : Color.clawMuted)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background((incident.status.isActive ? Color.clawWarn : Color.clawMuted).opacity(0.12))
                    .clipShape(Capsule())
            }

            Text(incident.description)
                .font(.system(size: 13))
                .foregroundStyle(Color.clawText)

            HStack(spacing: 16) {
                Label(incident.createdAt, format: .dateTime.month().day().hour().minute())
                    .font(.caption2)
                    .foregroundStyle(Color.clawMuted)
                if let resolved = incident.resolvedAt {
                    Label("Resolved " + resolved.formatted(.relative(presentation: .named)))
                        .font(.caption2)
                        .foregroundStyle(Color.clawOk.opacity(0.8))
                }
            }
        }
        .padding(16)
    }

    // MARK: - Resolve Sheet

    private var resolveSheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("Describe the resolution:")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.clawTextStrong)
                TextEditor(text: $resolutionText)
                    .frame(minHeight: 100)
                    .padding(8)
                    .background(Color.clawBgElevated)
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(Color.clawBorder, lineWidth: 1)
                    )
                    .foregroundStyle(Color.clawText)
                Spacer()
            }
            .padding(20)
            .background(Color.clawBg.ignoresSafeArea())
            .navigationTitle("Resolve Incident")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.clawBgAccent, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { showResolveDialog = false }.tint(Color.clawMuted)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Resolve") {
                        Task {
                            await store.resolveIncident(incident.id, resolution: resolutionText)
                            showResolveDialog = false
                        }
                    }
                    .tint(Color.clawOk)
                    .fontWeight(.semibold)
                    .disabled(resolutionText.isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - IncidentTimelineEntryRow

struct IncidentTimelineEntryRow: View {
    let entry: IncidentTimelineEntry

    private var iconName: String {
        switch entry.kind {
        case .triggered:        return "exclamationmark.triangle.fill"
        case .acknowledged:     return "eye"
        case .agentStarted:     return "cpu"
        case .proposalCreated:  return "lightbulb"
        case .proposalApproved: return "checkmark.circle"
        case .actionTaken:      return "wrench"
        case .resolved:         return "checkmark.circle.fill"
        case .escalated:        return "arrow.up.circle"
        case .comment:          return "bubble.left"
        }
    }

    private var iconColor: Color {
        switch entry.kind {
        case .triggered:    return .clawDanger
        case .resolved:     return .clawOk
        case .escalated:    return .clawWarn
        default:            return .clawTeal
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: iconName)
                .font(.system(size: 13))
                .foregroundStyle(iconColor)
                .frame(width: 20)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.message)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.clawText)
                Text(entry.timestamp, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(Color.clawMuted)
            }
        }
        .padding(.vertical, 4)
    }
}
