import SwiftUI

struct IncidentListView: View {
    @Environment(WatchBridge.self) private var bridge

    var ongoingIncidents: [WatchBridge.WatchIncidentItem] {
        bridge.incidents.filter(\.isOngoing)
    }

    var resolvedIncidents: [WatchBridge.WatchIncidentItem] {
        bridge.incidents.filter { !$0.isOngoing }
    }

    var body: some View {
        if bridge.incidents.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "checkmark.shield.fill")
                    .font(.title2)
                    .foregroundColor(.green)
                Text("No incidents")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle("Incidents")
        } else {
            List {
                if !ongoingIncidents.isEmpty {
                    Section("ONGOING") {
                        ForEach(ongoingIncidents) { incident in
                            NavigationLink {
                                IncidentSummaryView(incident: incident)
                            } label: {
                                IncidentRowView(incident: incident)
                            }
                            .listRowBackground(Color.red.opacity(0.08))
                        }
                    }
                }

                if !resolvedIncidents.isEmpty {
                    Section("RESOLVED") {
                        ForEach(resolvedIncidents) { incident in
                            NavigationLink {
                                IncidentSummaryView(incident: incident)
                            } label: {
                                IncidentRowView(incident: incident)
                            }
                            .listRowBackground(Color.clear)
                        }
                    }
                }
            }
            .listStyle(.carousel)
            .navigationTitle("Incidents")
        }
    }
}

struct IncidentRowView: View {
    let incident: WatchBridge.WatchIncidentItem

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(incident.isOngoing ? incident.severityColor : Color.gray)
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 2) {
                Text(incident.title)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)

                HStack(spacing: 4) {
                    Text(incident.environment.uppercased())
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.gray)
                    if incident.actionRequired {
                        Image(systemName: "hand.point.right.fill")
                            .font(.system(size: 8))
                            .foregroundColor(.yellow)
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }
}

// severityColor is defined as a computed property in WatchBridge.WatchIncidentItem
