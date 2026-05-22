import SwiftUI

// MARK: - KnowledgeGraphView
//
// A node-link knowledge graph visualization for memory timeline events.
// Approximates a force-directed layout using stored positions
// (positions are stable between renders for the same set of events).
//
// Nodes: MemoryTimelineEvent (colored by category)
// Edges: EventRelationship (labeled with kind)
// Interaction: tap node for details, pinch-to-zoom (future), pan

struct KnowledgeGraphView: View {
    let snapshot: KnowledgeGraphSnapshot

    @State private var selectedEventId: String? = nil
    @State private var layoutPositions: [String: CGPoint] = [:]
    @State private var dragOffset: CGSize = .zero
    @State private var panOffset: CGSize = .zero
    @State private var scale: CGFloat = 1.0

    private let nodeRadius: CGFloat = 22
    private let canvasSize: CGSize = CGSize(width: 600, height: 600)

    var body: some View {
        ZStack(alignment: .bottom) {
            // Graph canvas
            ScrollView([.horizontal, .vertical]) {
                graphCanvas
                    .frame(width: canvasSize.width, height: canvasSize.height)
            }
            .background(Color.clawBg)

            // Legend
            if !snapshot.events.isEmpty {
                legend
                    .padding(.bottom, 12)
            }
        }
        .navigationTitle("Knowledge Graph")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.clawBgAccent, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .onAppear { computeLayout() }
        .onChange(of: snapshot.events.count) { _, _ in computeLayout() }
    }

    // MARK: - Graph Canvas

    private var graphCanvas: some View {
        ZStack {
            // Edges
            Canvas { ctx, size in
                for rel in snapshot.relationships {
                    guard let fromPos = layoutPositions[rel.fromEventId],
                          let toPos = layoutPositions[rel.toEventId] else { continue }
                    var path = Path()
                    path.move(to: fromPos)
                    path.addLine(to: toPos)
                    ctx.stroke(
                        path,
                        with: .color(edgeColor(for: rel.kind).opacity(0.4)),
                        lineWidth: 1.5
                    )
                }
            }
            .frame(width: canvasSize.width, height: canvasSize.height)

            // Nodes
            ForEach(snapshot.events) { event in
                if let pos = layoutPositions[event.id] {
                    nodeView(for: event)
                        .position(pos)
                        .onTapGesture {
                            withAnimation(.spring(duration: 0.2)) {
                                selectedEventId = selectedEventId == event.id ? nil : event.id
                            }
                        }
                }
            }

            // Selected event detail popup
            if let id = selectedEventId,
               let event = snapshot.events.first(where: { $0.id == id }),
               let pos = layoutPositions[id] {
                eventPopup(for: event)
                    .position(x: min(max(pos.x, 120), canvasSize.width - 120),
                              y: pos.y > canvasSize.height / 2 ? pos.y - 90 : pos.y + 80)
            }
        }
    }

    // MARK: - Node View

    private func nodeView(for event: MemoryTimelineEvent) -> some View {
        let isSelected = selectedEventId == event.id
        let degree = snapshot.degree(of: event.id)
        let radius = nodeRadius + CGFloat(min(degree, 4)) * 3

        return ZStack {
            // Pulse for selected
            if isSelected {
                Circle()
                    .stroke(Color(hex: event.category.colorHex).opacity(0.4), lineWidth: 2)
                    .frame(width: radius * 2 + 12, height: radius * 2 + 12)
            }

            // Node circle
            Circle()
                .fill(Color(hex: event.category.colorHex).opacity(0.2))
                .overlay(
                    Circle()
                        .stroke(Color(hex: event.category.colorHex).opacity(isSelected ? 0.9 : 0.5), lineWidth: isSelected ? 2 : 1)
                )
                .frame(width: radius * 2, height: radius * 2)

            // Icon
            Image(systemName: event.category.systemImage)
                .font(.system(size: 12))
                .foregroundStyle(Color(hex: event.category.colorHex))
        }
        .scaleEffect(isSelected ? 1.2 : 1.0)
        .animation(.spring(duration: 0.2), value: isSelected)
    }

    // MARK: - Event Popup

    private func eventPopup(for event: MemoryTimelineEvent) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: event.category.systemImage)
                    .font(.caption2)
                    .foregroundStyle(Color(hex: event.category.colorHex))
                Text(event.category.displayName)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color(hex: event.category.colorHex))
            }
            Text(event.title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.clawTextStrong)
                .lineLimit(2)
            Text(event.timestamp, style: .relative)
                .font(.caption2)
                .foregroundStyle(Color.clawMuted)
        }
        .padding(10)
        .background(Color.clawBgElevated)
        .cornerRadius(10)
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.clawBorderStrong, lineWidth: 1))
        .frame(width: 200)
        .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)
    }

    // MARK: - Legend

    private var legend: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(usedCategories, id: \.self) { cat in
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color(hex: cat.colorHex).opacity(0.6))
                            .frame(width: 8, height: 8)
                        Text(cat.displayName)
                            .font(.caption2)
                            .foregroundStyle(Color.clawMuted)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .background(Color.clawBgAccent.opacity(0.9))
    }

    private var usedCategories: [EventCategory] {
        Array(Set(snapshot.events.map { $0.category })).sorted { $0.rawValue < $1.rawValue }
    }

    // MARK: - Layout

    // Approximate circle layout; events with more relationships get center placement.
    private func computeLayout() {
        guard !snapshot.events.isEmpty else { return }
        let center = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
        let n = snapshot.events.count

        var positions: [String: CGPoint] = [:]

        if n == 1 {
            positions[snapshot.events[0].id] = center
        } else {
            // Sort by degree (highest first) for center placement
            let sorted = snapshot.events.sorted { snapshot.degree(of: $0.id) > snapshot.degree(of: $1.id) }

            // High-degree nodes near center, low-degree on outer ring
            let innerRadius: CGFloat = 120
            let outerRadius: CGFloat = 220
            let split = max(1, n / 3)

            for (i, event) in sorted.enumerated() {
                let radius: CGFloat = i < split ? innerRadius : outerRadius
                let ringCount = i < split ? split : (n - split)
                let ringIndex = i < split ? i : (i - split)
                let angle = (2.0 * .pi / Double(ringCount)) * Double(ringIndex) - .pi / 2
                let x = center.x + radius * CGFloat(cos(angle))
                let y = center.y + radius * CGFloat(sin(angle))
                positions[event.id] = CGPoint(x: x, y: y)
            }
        }

        withAnimation(.spring(duration: 0.4)) {
            layoutPositions = positions
        }
    }

    // MARK: - Edge Color

    private func edgeColor(for kind: EventRelationship.RelationshipKind) -> Color {
        switch kind {
        case .caused:   return .clawDanger
        case .resolved: return .clawOk
        case .related:  return .clawMuted
        case .precedes: return .clawTeal
        case .spawned:  return .clawAccent
        }
    }
}
