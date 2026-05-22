import SwiftUI

// Placeholder — Mission Control dashboard (implemented in Stream 2)
struct DashboardTabView: View {
    var body: some View {
        ZStack {
            Color.clawBg.ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: "square.grid.2x2")
                    .font(.system(size: 52))
                    .foregroundStyle(Color.clawMuted.opacity(0.4))
                Text("Mission Control")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(Color.clawTextStrong)
                Text("Metrics, widgets, and infrastructure health — coming soon")
                    .font(.subheadline)
                    .foregroundStyle(Color.clawMuted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
        }
        .navigationTitle("Dashboard")
        .navigationBarTitleDisplayMode(.large)
        .toolbarBackground(Color.clawBgAccent, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }
}
