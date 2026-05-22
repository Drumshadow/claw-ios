import SwiftUI

struct RiskBadge: View {
    let risk: RiskLevel
    @State private var isPulsing = false

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(Color(hex: risk.color))
                .frame(width: 8, height: 8)
                .opacity(risk == .critical && isPulsing ? 0.6 : 1.0)

            Text(risk.displayLabel.uppercased())
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundColor(.white)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(Color(hex: risk.color))
                .opacity(0.9)
        )
        .overlay(
            Capsule()
                .strokeBorder(Color.white.opacity(0.3), lineWidth: 1)
        )
        .shadow(color: Color(hex: risk.color).opacity(0.3), radius: 4, x: 0, y: 2)
        .onAppear {
            if risk == .critical {
                withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                    isPulsing = true
                }
            }
        }
    }
}

// Helper extension for hex color support
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

#Preview {
    VStack(spacing: 16) {
        RiskBadge(risk: .info)
        RiskBadge(risk: .caution)
        RiskBadge(risk: .danger)
        RiskBadge(risk: .critical)
    }
    .padding()
    .background(Color.black)
}
