import SwiftUI

// MARK: - TopologyGraphView
//
// Interactive infrastructure topology graph with:
//  • Canvas-drawn edges (bezier curves, health-colored)
//  • Positioned SwiftUI node chips (tap for detail)
//  • Pinch-to-zoom + drag-to-pan with inertia accumulation
//  • Filter bar (kind + health)
//  • Minimap overlay (bottom-right)
//  • Incident & deployment highlights

struct TopologyGraphView: View {
    let graph: InfraGraph

    // Zoom / pan state
    @State private var scale: CGFloat = 0.85
    @State private var lastScale: CGFloat = 0.85
    @State private var panOffset: CGSize = .zero
    @State private var lastPanOffset: CGSize = .zero

    // Filters
    @State private var selectedKinds: Set<InfraNodeKind> = []
    @State private var selectedHealth: InfraHealth? = nil

    // Selection
    @State private var selectedNode: InfraNode? = nil
    @State private var showNodeDetail: Bool = false

    // Layout
    @State private var canvasSize: CGSize = .zero

    private let nodeWidth: CGFloat  = 86
    private let nodeHeight: CGFloat = 64

    // MARK: - Computed

    private var filteredNodes: [InfraNode] {
        graph.nodes.filter { node in
            let kindOK   = selectedKinds.isEmpty || selectedKinds.contains(node.kind)
            let healthOK = selectedHealth == nil  || node.health == selectedHealth
            return kindOK && healthOK
        }
    }

    private var filteredNodeIDs: Set<String> {
        Set(filteredNodes.map(\.id))
    }

    private var filteredEdges: [InfraEdge] {
        graph.validEdges.filter {
            filteredNodeIDs.contains($0.fromNodeId) && filteredNodeIDs.contains($0.toNodeId)
        }
    }

    private var activeIncidentNodeIDs: Set<String> {
        Set(graph.activeIncidents.flatMap(\.affectedNodeIds))
    }

    private var activeDeployNodeIDs: Set<String> {
        Set(graph.deployments.filter { $0.status == .running }.flatMap(\.affectedNodeIds))
    }

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.clawBg.ignoresSafeArea()

            // Graph canvas
            graphCanvas
                .ignoresSafeArea(edges: .bottom)

            VStack(spacing: 0) {
                filterBar
                Spacer()
                HStack(alignment: .bottom) {
                    legendOverlay
                    Spacer()
                    minimapOverlay
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
            }
        }
        .navigationTitle("Topology")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.clawBgAccent, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                resetButton
            }
        }
        .sheet(isPresented: $showNodeDetail) {
            if let node = selectedNode {
                InfraNodeDetailView(node: node, graph: graph)
            }
        }
    }

    // MARK: - Graph canvas

    private var graphCanvas: some View {
        GeometryReader { geo in
            ZStack {
                // Edge canvas (drawn behind nodes)
                Canvas { ctx, size in
                    drawEdges(ctx: ctx, size: size)
                }
                .allowsHitTesting(false)

                // Node chips (interactive)
                ForEach(filteredNodes) { node in
                    nodeChip(node: node, canvasSize: geo.size)
                        .position(
                            x: node.posX * geo.size.width,
                            y: node.posY * geo.size.height
                        )
                        .onTapGesture {
                            selectedNode = node
                            showNodeDetail = true
                        }
                }
            }
            .scaleEffect(scale, anchor: .center)
            .offset(panOffset)
            .gesture(
                SimultaneousGesture(magnifyGesture, panGesture)
            )
            .onAppear { canvasSize = geo.size }
            .onChange(of: geo.size) { _, s in canvasSize = s }
        }
    }

    // MARK: - Node chip view

    @ViewBuilder
    private func nodeChip(node: InfraNode, canvasSize: CGSize) -> some View {
        let isIncident  = activeIncidentNodeIDs.contains(node.id)
        let isDeploying = activeDeployNodeIDs.contains(node.id)
        let isSelected  = selectedNode?.id == node.id

        VStack(spacing: 3) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.clawCard)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(
                                isSelected  ? Color.clawAccent :
                                isIncident  ? node.health.color.opacity(0.8) :
                                isDeploying ? Color.clawWarn.opacity(0.8) :
                                              Color.clawBorder,
                                lineWidth: isSelected || isIncident || isDeploying ? 1.5 : 1
                            )
                    )

                VStack(spacing: 4) {
                    Image(systemName: node.kind.systemImage)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(node.kind.accentColor)

                    if let cpu = node.cpuPercent {
                        miniGauge(value: cpu / 100, color: gaugeColor(cpu / 100))
                    } else if let mem = node.memPercent {
                        miniGauge(value: mem / 100, color: .clawTeal)
                    } else if let depth = node.queueDepth {
                        Text("\(compactNumber(depth))")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundStyle(Color.clawMuted)
                    }
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 4)

                // Health dot
                Circle()
                    .fill(node.health.color)
                    .frame(width: 7, height: 7)
                    .overlay(
                        Circle().strokeBorder(Color.clawCard, lineWidth: 1.5)
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(4)

                // Incident badge
                if isIncident && node.incidentCount > 0 {
                    Text("\(node.incidentCount)")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(
                            Capsule().fill(Color.clawDanger)
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .padding(3)
                }

                // Deploy pulse ring
                if isDeploying {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.clawWarn.opacity(0.4), lineWidth: 3)
                }
            }
            .frame(width: nodeWidth, height: nodeHeight - 16)

            Text(node.label)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(Color.clawText)
                .lineLimit(1)
                .frame(width: nodeWidth)
        }
        .frame(width: nodeWidth, height: nodeHeight)
    }

    // MARK: - Edge drawing

    private func drawEdges(ctx: GraphicsContext, size: CGSize) {
        for edge in filteredEdges {
            guard let fromNode = graph.nodeMap[edge.fromNodeId],
                  let toNode   = graph.nodeMap[edge.toNodeId] else { continue }

            let from = CGPoint(x: fromNode.posX * size.width, y: fromNode.posY * size.height)
            let to   = CGPoint(x: toNode.posX   * size.width, y: toNode.posY   * size.height)

            // Control point for a subtle curve
            let mid = CGPoint(x: (from.x + to.x) / 2, y: (from.y + to.y) / 2)
            let ctrl = CGPoint(
                x: mid.x + (to.y - from.y) * 0.15,
                y: mid.y - (to.x - from.x) * 0.15
            )

            var path = Path()
            path.move(to: from)
            path.addQuadCurve(to: to, control: ctrl)

            let edgeColor = edge.health.color
            let lineWidth: CGFloat = edge.health == .ok ? 1.0 : 1.5
            let dash: [CGFloat]   = edge.kind == .monitors ? [4, 3] :
                                    edge.kind == .controls  ? [6, 2] : []

            ctx.stroke(
                path,
                with: .color(edgeColor.opacity(edge.health == .ok ? 0.35 : 0.75)),
                style: StrokeStyle(lineWidth: lineWidth, dash: dash)
            )

            // Arrowhead at destination
            drawArrow(ctx: ctx, from: ctrl, to: to, color: edgeColor.opacity(0.6))
        }
    }

    private func drawArrow(ctx: GraphicsContext, from: CGPoint, to: CGPoint, color: Color) {
        let angle = atan2(to.y - from.y, to.x - from.x)
        let arrowLen: CGFloat = 7
        let arrowAngle: CGFloat = .pi / 6

        let left  = CGPoint(
            x: to.x - arrowLen * cos(angle - arrowAngle),
            y: to.y - arrowLen * sin(angle - arrowAngle)
        )
        let right = CGPoint(
            x: to.x - arrowLen * cos(angle + arrowAngle),
            y: to.y - arrowLen * sin(angle + arrowAngle)
        )

        var arrow = Path()
        arrow.move(to: to)
        arrow.addLine(to: left)
        arrow.move(to: to)
        arrow.addLine(to: right)

        ctx.stroke(arrow, with: .color(color), lineWidth: 1.2)
    }

    // MARK: - Minimap

    private var minimapOverlay: some View {
        let mapSize = CGSize(width: 110, height: 80)

        return ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.clawBgElevated.opacity(0.95))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.clawBorder, lineWidth: 1)
                )

            // Mini-canvas for dots
            Canvas { ctx, size in
                for node in filteredNodes {
                    let x = node.posX * size.width
                    let y = node.posY * size.height
                    let rect = CGRect(x: x - 3, y: y - 3, width: 6, height: 6)
                    let path = Path(roundedRect: rect, cornerRadius: 2)
                    ctx.fill(path, with: .color(node.health.color.opacity(0.85)))
                }
                // Viewport indicator
                let vpW = size.width  / scale
                let vpH = size.height / scale
                let vpX = size.width  / 2 - panOffset.width  / scale - vpW / 2
                let vpY = size.height / 2 - panOffset.height / scale - vpH / 2
                let vpRect = CGRect(x: vpX, y: vpY, width: vpW, height: vpH)
                    .intersection(CGRect(origin: .zero, size: size))
                var vp = Path(roundedRect: vpRect.isEmpty ? CGRect(origin: .zero, size: size) : vpRect, cornerRadius: 2)
                ctx.stroke(vp, with: .color(Color.clawAccent.opacity(0.5)), lineWidth: 1)
            }
            .padding(6)
        }
        .frame(width: mapSize.width, height: mapSize.height)
    }

    // MARK: - Legend

    private var legendOverlay: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach([InfraHealth.ok, .degraded, .down], id: \.rawValue) { h in
                HStack(spacing: 5) {
                    Circle()
                        .fill(h.color)
                        .frame(width: 6, height: 6)
                    Text(h.label)
                        .font(.system(size: 10))
                        .foregroundStyle(Color.clawMuted)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.clawBgElevated.opacity(0.9))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.clawBorder, lineWidth: 1)
                )
        )
    }

    // MARK: - Filter bar

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                // Health filter
                ForEach([InfraHealth.degraded, .down], id: \.rawValue) { h in
                    filterPill(
                        label: h.label,
                        icon: h.systemImage,
                        color: h.color,
                        active: selectedHealth == h
                    ) {
                        selectedHealth = selectedHealth == h ? nil : h
                    }
                }

                Divider()
                    .frame(height: 18)
                    .background(Color.clawBorderStrong)

                // Kind filter — show a subset of key kinds
                ForEach([InfraNodeKind.kubernetes, .ec2, .rds, .queue, .datadogAlert, .agent], id: \.id) { k in
                    filterPill(
                        label: k.label,
                        icon: k.systemImage,
                        color: k.accentColor,
                        active: selectedKinds.contains(k)
                    ) {
                        if selectedKinds.contains(k) {
                            selectedKinds.remove(k)
                        } else {
                            selectedKinds.insert(k)
                        }
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(Color.clawBgAccent.opacity(0.95))
        .overlay(alignment: .bottom) {
            Divider().background(Color.clawBorder)
        }
    }

    private func filterPill(label: String, icon: String, color: Color, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                Text(label)
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(active ? color : Color.clawMuted)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(active ? color.opacity(0.15) : Color.clawBgElevated)
                    .overlay(
                        Capsule()
                            .strokeBorder(active ? color.opacity(0.4) : Color.clawBorder, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Reset button

    private var resetButton: some View {
        Button {
            withAnimation(.spring(response: 0.4)) {
                scale = 0.85
                lastScale = 0.85
                panOffset = .zero
                lastPanOffset = .zero
                selectedKinds = []
                selectedHealth = nil
            }
        } label: {
            Image(systemName: "arrow.counterclockwise")
                .font(.system(size: 14, weight: .medium))
        }
        .tint(Color.clawAccent)
    }

    // MARK: - Gestures

    private var magnifyGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                scale = max(0.25, min(4.0, lastScale * value))
            }
            .onEnded { _ in
                lastScale = scale
            }
    }

    private var panGesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                panOffset = CGSize(
                    width:  lastPanOffset.width  + value.translation.width,
                    height: lastPanOffset.height + value.translation.height
                )
            }
            .onEnded { _ in
                lastPanOffset = panOffset
            }
    }

    // MARK: - Helpers

    private func gaugeColor(_ fraction: Double) -> Color {
        fraction > 0.85 ? .clawDanger : fraction > 0.65 ? .clawWarn : .clawOk
    }

    private func miniGauge(value: Double, color: Color) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(Color.clawBorder)
                    .frame(height: 3)
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(color)
                    .frame(width: max(2, geo.size.width * CGFloat(value)), height: 3)
            }
        }
        .frame(height: 3)
        .padding(.horizontal, 6)
    }

    private func compactNumber(_ n: Int) -> String {
        if n >= 1000 { return "\(n / 1000)k" }
        return "\(n)"
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        TopologyGraphView(graph: .preview)
    }
    .preferredColorScheme(.dark)
}
