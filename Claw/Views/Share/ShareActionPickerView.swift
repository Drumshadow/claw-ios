import SwiftUI

// MARK: - ShareActionPickerView

/// Grid of available agent actions for a given content type.
/// Used in both the in-app intake flow and the share extension UI.
struct ShareActionPickerView: View {
    let contentType: ShareContentType
    @Binding var selectedAction: ShareActionType
    @Binding var customPrompt: String

    private var recommendedActions: [ShareActionType] {
        ShareActionType.recommended(for: contentType)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("What should Claw do?")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.clawMuted)
                .textCase(.uppercase)
                .tracking(0.5)

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 10),
                    GridItem(.flexible(), spacing: 10)
                ],
                spacing: 10
            ) {
                ForEach(recommendedActions) { action in
                    ActionTile(
                        action: action,
                        isSelected: selectedAction == action,
                        onTap: { selectedAction = action }
                    )
                }
            }

            // Custom prompt input (shown when .custom is selected)
            if selectedAction == .custom {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Custom instruction")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.clawMuted)

                    TextField("Enter your prompt…", text: $customPrompt, axis: .vertical)
                        .font(.system(size: 14))
                        .foregroundStyle(Color.clawText)
                        .tint(Color.clawAccent)
                        .padding(10)
                        .background(Color.clawBgHover)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(Color.clawBorderStrong, lineWidth: 1)
                        )
                        .lineLimit(3...8)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
                .animation(.easeInOut(duration: 0.2), value: selectedAction)
            }
        }
    }
}

// MARK: - ActionTile

private struct ActionTile: View {
    let action: ShareActionType
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: action.systemImage)
                        .font(.system(size: 18))
                        .foregroundStyle(isSelected ? .black : tileAccentColor)
                    Spacer()
                    if action.riskLevel == .danger {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(isSelected ? .black.opacity(0.7) : Color.clawDanger.opacity(0.8))
                    } else if action.riskLevel == .caution {
                        Image(systemName: "exclamationmark.circle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(isSelected ? .black.opacity(0.7) : Color.clawWarn.opacity(0.8))
                    }
                }

                Text(action.displayName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isSelected ? .black : Color.clawTextStrong)

                Text(action.description)
                    .font(.system(size: 11))
                    .foregroundStyle(isSelected ? .black.opacity(0.7) : Color.clawMuted)
                    .lineLimit(2)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? tileAccentColor : Color.clawBgElevated)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(
                        isSelected ? tileAccentColor : Color.clawBorderStrong,
                        lineWidth: isSelected ? 0 : 1
                    )
            )
        }
        .buttonStyle(.plain)
        .scaleEffect(isSelected ? 0.97 : 1.0)
        .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isSelected)
    }

    private var tileAccentColor: Color {
        switch action.riskLevel {
        case .safe:    return .clawTeal
        case .caution: return .clawWarn
        case .danger:  return .clawDanger
        }
    }
}

// MARK: - Preview

#Preview {
    @Previewable @State var action: ShareActionType = .diagnose
    @Previewable @State var prompt = ""

    ShareActionPickerView(
        contentType: .logs,
        selectedAction: $action,
        customPrompt: $prompt
    )
    .padding()
    .background(Color.clawBg)
}
