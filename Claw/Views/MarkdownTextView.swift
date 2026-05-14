import SwiftUI
import MarkdownUI

// MARK: - MarkdownTextView

struct MarkdownTextView: View {
    let text: String

    var body: some View {
        Markdown(text)
            .markdownTheme(.claw)
            .markdownTextStyle {
                FontSize(15)
            }
    }
}

// MARK: - Claw theme

extension Theme {
    // Cached as `static let` so the theme builder chain only runs once,
    // not on every MarkdownTextView body re-render.
    static let claw: Theme = {
        Theme()
            .text {
                ForegroundColor(.init(Color.clawText))
            }
            .strong {
                FontWeight(.bold)
            }
            .emphasis {
                FontStyle(.italic)
            }
            .code {
                FontFamilyVariant(.monospaced)
                FontSize(.em(0.9))
                ForegroundColor(.init(Color.clawAccent))
                BackgroundColor(.init(Color.clawCard))
            }
            .link {
                ForegroundColor(.init(Color.clawAccent))
            }
            .heading1 { configuration in
                configuration.label
                    .markdownMargin(top: .em(0.8), bottom: .em(0.3))
                    .markdownTextStyle {
                        FontSize(.em(1.4))
                        FontWeight(.bold)
                        ForegroundColor(.init(Color.clawTextStrong))
                    }
            }
            .heading2 { configuration in
                configuration.label
                    .markdownMargin(top: .em(0.7), bottom: .em(0.3))
                    .markdownTextStyle {
                        FontSize(.em(1.2))
                        FontWeight(.bold)
                        ForegroundColor(.init(Color.clawTextStrong))
                    }
            }
            .heading3 { configuration in
                configuration.label
                    .markdownMargin(top: .em(0.5), bottom: .em(0.2))
                    .markdownTextStyle {
                        FontSize(.em(1.05))
                        FontWeight(.semibold)
                        ForegroundColor(.init(Color.clawTextStrong))
                    }
            }
            .codeBlock { configuration in
                ScrollView(.horizontal, showsIndicators: false) {
                    configuration.label
                        .relativeLineSpacing(.em(0.25))
                        .markdownTextStyle {
                            FontFamilyVariant(.monospaced)
                            FontSize(.em(0.85))
                            ForegroundColor(.init(Color.clawText))
                        }
                        .padding(12)
                }
                .background(Color.clawCard)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.clawBorder, lineWidth: 1)
                )
                .markdownMargin(top: .em(0.5), bottom: .em(0.5))
            }
            .blockquote { configuration in
                HStack(spacing: 0) {
                    Color.clawMuted
                        .frame(width: 3)
                        .clipShape(Capsule())
                    configuration.label
                        .markdownTextStyle {
                            ForegroundColor(.init(Color.clawMuted))
                        }
                        .padding(.leading, 10)
                }
                .fixedSize(horizontal: false, vertical: true)
                .markdownMargin(top: .em(0.3), bottom: .em(0.3))
            }
            .listItem { configuration in
                configuration.label
                    .markdownMargin(top: .em(0.1))
            }
            .bulletedListMarker { _ in
                Text("•")
                    .foregroundStyle(Color.clawMuted)
                    .relativeFrame(minWidth: .em(1.5), alignment: .trailing)
            }
            .numberedListMarker { configuration in
                Text("\(configuration.itemNumber).")
                    .foregroundStyle(Color.clawMuted)
                    .relativeFrame(minWidth: .em(1.5), alignment: .trailing)
            }
    }()
}
