import SwiftUI

// MARK: - Claw design tokens (mirrors OpenClaw control-ui CSS variables)

extension Color {

    // Backgrounds
    static let clawBg          = Color(clawHex: 0x0e1015)
    static let clawBgAccent    = Color(clawHex: 0x13151b)
    static let clawBgElevated  = Color(clawHex: 0x191c24)
    static let clawBgHover     = Color(clawHex: 0x1f2330)
    static let clawCard        = Color(clawHex: 0x161920)

    // Text
    static let clawText        = Color(clawHex: 0xd4d4d8)
    static let clawTextStrong  = Color(clawHex: 0xf4f4f5)
    static let clawMuted       = Color(clawHex: 0x838387)

    // Borders
    static let clawBorder      = Color(clawHex: 0x1e2028)
    static let clawBorderStrong = Color(clawHex: 0x2e3040)

    // Accent (#ff5c5c coral-red)
    static let clawAccent      = Color(clawHex: 0xff5c5c)
    static let clawAccentSubtle = Color(red: 1, green: 0.361, blue: 0.361).opacity(0.1)
    static let clawAccentGlow   = Color(red: 1, green: 0.361, blue: 0.361).opacity(0.2)

    // Accent 2 (teal)
    static let clawTeal        = Color(clawHex: 0x14b8a6)

    // Status
    static let clawOk          = Color(clawHex: 0x22c55e)
    static let clawWarn        = Color(clawHex: 0xf59e0b)
    static let clawDanger      = Color(clawHex: 0xef4444)

    private init(clawHex hex: UInt32) {
        self.init(
            .sRGB,
            red:   Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8)  & 0xFF) / 255,
            blue:  Double( hex        & 0xFF) / 255,
            opacity: 1
        )
    }
}

// MARK: - View modifier: apply Claw dark chrome

extension View {
    func clawBackground() -> some View {
        self.background(Color.clawBg.ignoresSafeArea())
    }
}
