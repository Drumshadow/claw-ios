import UIKit

extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1.0) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }

    func lighter(by percentage: CGFloat = 0.2) -> UIColor {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return UIColor(hue: h, saturation: s, brightness: min(b * (1 + percentage), 1.0), alpha: a)
    }
}

struct ANSIParser {
    // ANSI color palette mapped to Claw theme
    private static let ansiColors: [UIColor] = [
        UIColor(hex: 0x1e2028), // Black
        UIColor(hex: 0xef4444), // Red
        UIColor(hex: 0x22c55e), // Green
        UIColor(hex: 0xf59e0b), // Yellow
        UIColor(hex: 0x3b82f6), // Blue
        UIColor(hex: 0xa855f7), // Magenta
        UIColor(hex: 0x14b8a6), // Cyan
        UIColor(hex: 0xd4d4d8), // White
    ]

    private static let ansiBrightColors: [UIColor] = [
        UIColor(hex: 0x1e2028).lighter(by: 0.2), // Bright Black
        UIColor(hex: 0xef4444).lighter(by: 0.2), // Bright Red
        UIColor(hex: 0x22c55e).lighter(by: 0.2), // Bright Green
        UIColor(hex: 0xf59e0b).lighter(by: 0.2), // Bright Yellow
        UIColor(hex: 0x3b82f6).lighter(by: 0.2), // Bright Blue
        UIColor(hex: 0xa855f7).lighter(by: 0.2), // Bright Magenta
        UIColor(hex: 0x14b8a6).lighter(by: 0.2), // Bright Cyan
        UIColor(hex: 0xd4d4d8).lighter(by: 0.2), // Bright White
    ]

    // 256-color palette (xterm colors)
    private static let xterm256Colors: [UIColor] = {
        var colors: [UIColor] = []

        // First 16 colors (standard + bright)
        colors.append(contentsOf: ansiColors)
        colors.append(contentsOf: ansiBrightColors)

        // 216 colors (6x6x6 cube)
        for r in 0..<6 {
            for g in 0..<6 {
                for b in 0..<6 {
                    let red = r == 0 ? 0 : 55 + r * 40
                    let green = g == 0 ? 0 : 55 + g * 40
                    let blue = b == 0 ? 0 : 55 + b * 40
                    colors.append(UIColor(
                        red: CGFloat(red) / 255,
                        green: CGFloat(green) / 255,
                        blue: CGFloat(blue) / 255,
                        alpha: 1.0
                    ))
                }
            }
        }

        // 24 grayscale colors
        for i in 0..<24 {
            let gray = 8 + i * 10
            colors.append(UIColor(
                red: CGFloat(gray) / 255,
                green: CGFloat(gray) / 255,
                blue: CGFloat(gray) / 255,
                alpha: 1.0
            ))
        }

        return colors
    }()

    static func parse(_ raw: String, baseFont: UIFont, baseForeground: UIColor) -> NSAttributedString {
        let result = NSMutableAttributedString()

        var currentForeground = baseForeground
        var currentBackground: UIColor?
        var isBold = false
        var isDim = false
        var isItalic = false
        var isUnderline = false

        // Split on ESC character
        let parts = raw.split(separator: "\u{1B}", omittingEmptySubsequences: false)

        for (index, part) in parts.enumerated() {
            let partStr = String(part)

            if index == 0 && !raw.hasPrefix("\u{1B}") {
                // First part with no escape sequence
                appendText(partStr, to: result, font: baseFont, foreground: currentForeground,
                          background: currentBackground, bold: isBold, dim: isDim,
                          italic: isItalic, underline: isUnderline)
                continue
            }

            // Check for ANSI escape sequences
            if partStr.hasPrefix("[") {
                // CSI sequence
                if let endIndex = partStr.firstIndex(where: { $0.isLetter }) {
                    let code = partStr[partStr.index(after: partStr.startIndex)..<endIndex]
                    let command = partStr[endIndex]
                    let remainder = String(partStr[partStr.index(after: endIndex)...])

                    // Parse SGR (Select Graphic Rendition) codes
                    if command == "m" {
                        let codes = code.split(separator: ";").compactMap { Int($0) }

                        for i in 0..<codes.count {
                            let code = codes[i]

                            switch code {
                            case 0: // Reset
                                currentForeground = baseForeground
                                currentBackground = nil
                                isBold = false
                                isDim = false
                                isItalic = false
                                isUnderline = false
                            case 1: // Bold
                                isBold = true
                            case 2: // Dim
                                isDim = true
                            case 3: // Italic
                                isItalic = true
                            case 4: // Underline
                                isUnderline = true
                            case 22: // Normal intensity
                                isBold = false
                                isDim = false
                            case 23: // Not italic
                                isItalic = false
                            case 24: // Not underlined
                                isUnderline = false
                            case 30...37: // Standard foreground colors
                                currentForeground = ansiColors[code - 30]
                            case 38: // Extended foreground color
                                if i + 1 < codes.count {
                                    if codes[i + 1] == 5 && i + 2 < codes.count {
                                        // 256-color mode
                                        let colorIndex = codes[i + 2]
                                        if colorIndex < xterm256Colors.count {
                                            currentForeground = xterm256Colors[colorIndex]
                                        }
                                    } else if codes[i + 1] == 2 && i + 4 < codes.count {
                                        // RGB mode
                                        let r = codes[i + 2]
                                        let g = codes[i + 3]
                                        let b = codes[i + 4]
                                        currentForeground = UIColor(
                                            red: CGFloat(r) / 255,
                                            green: CGFloat(g) / 255,
                                            blue: CGFloat(b) / 255,
                                            alpha: 1.0
                                        )
                                    }
                                }
                            case 39: // Default foreground
                                currentForeground = baseForeground
                            case 40...47: // Standard background colors
                                currentBackground = ansiColors[code - 40]
                            case 48: // Extended background color
                                if i + 1 < codes.count {
                                    if codes[i + 1] == 5 && i + 2 < codes.count {
                                        // 256-color mode
                                        let colorIndex = codes[i + 2]
                                        if colorIndex < xterm256Colors.count {
                                            currentBackground = xterm256Colors[colorIndex]
                                        }
                                    } else if codes[i + 1] == 2 && i + 4 < codes.count {
                                        // RGB mode
                                        let r = codes[i + 2]
                                        let g = codes[i + 3]
                                        let b = codes[i + 4]
                                        currentBackground = UIColor(
                                            red: CGFloat(r) / 255,
                                            green: CGFloat(g) / 255,
                                            blue: CGFloat(b) / 255,
                                            alpha: 1.0
                                        )
                                    }
                                }
                            case 49: // Default background
                                currentBackground = nil
                            case 90...97: // Bright foreground colors
                                currentForeground = ansiBrightColors[code - 90]
                            case 100...107: // Bright background colors
                                currentBackground = ansiBrightColors[code - 100]
                            default:
                                break
                            }
                        }
                    }
                    // Ignore cursor movement and screen clear codes (A, B, C, D, H, J, K, etc.)

                    appendText(remainder, to: result, font: baseFont, foreground: currentForeground,
                              background: currentBackground, bold: isBold, dim: isDim,
                              italic: isItalic, underline: isUnderline)
                } else {
                    // Malformed escape sequence, just append as-is
                    appendText(partStr, to: result, font: baseFont, foreground: currentForeground,
                              background: currentBackground, bold: isBold, dim: isDim,
                              italic: isItalic, underline: isUnderline)
                }
            } else {
                // Not a CSI sequence, might be other escape codes - just skip and append remainder
                if let letterIndex = partStr.firstIndex(where: { $0.isLetter || $0 == "(" || $0 == ")" }) {
                    let remainder = String(partStr[partStr.index(after: letterIndex)...])
                    appendText(remainder, to: result, font: baseFont, foreground: currentForeground,
                              background: currentBackground, bold: isBold, dim: isDim,
                              italic: isItalic, underline: isUnderline)
                }
            }
        }

        return result
    }

    private static func appendText(_ text: String, to attributedString: NSMutableAttributedString,
                                   font: UIFont, foreground: UIColor, background: UIColor?,
                                   bold: Bool, dim: Bool, italic: Bool, underline: Bool) {
        guard !text.isEmpty else { return }

        var attributes: [NSAttributedString.Key: Any] = [:]

        // Font with traits
        var traits: UIFontDescriptor.SymbolicTraits = []
        if bold {
            traits.insert(.traitBold)
        }
        if italic {
            traits.insert(.traitItalic)
        }

        let finalFont: UIFont
        if !traits.isEmpty, let descriptor = font.fontDescriptor.withSymbolicTraits(traits) {
            finalFont = UIFont(descriptor: descriptor, size: font.pointSize)
        } else {
            finalFont = font
        }
        attributes[.font] = finalFont

        // Foreground color
        var finalForeground = foreground
        if dim {
            finalForeground = foreground.withAlphaComponent(0.5)
        }
        attributes[.foregroundColor] = finalForeground

        // Background color
        if let background = background {
            attributes[.backgroundColor] = background
        }

        // Underline
        if underline {
            attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
        }

        let attrString = NSAttributedString(string: text, attributes: attributes)
        attributedString.append(attrString)
    }
}
