import SwiftUI

struct DryRunResult {
    let toolName: String
    let simulatedOutput: String
    let wouldModify: [String]    // list of resources that would be modified
    let estimatedDuration: String?
    let riskAssessment: String
}

struct DryRunResultView: View {
    let result: DryRunResult
    var onProceed: () -> Void
    var onCancel: () -> Void

    @State private var showFullOutput = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "eyes.inverse")
                            .font(.system(size: 24))
                            .foregroundColor(.cyan)

                        Text("Dry Run Results")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(.white)
                    }

                    Text(result.toolName)
                        .font(.system(size: 16, design: .monospaced))
                        .foregroundColor(.white.opacity(0.7))
                }

                Divider()
                    .background(Color.white.opacity(0.1))

                // Risk assessment card
                VStack(alignment: .leading, spacing: 12) {
                    Label {
                        Text("Risk Assessment")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                    } icon: {
                        Image(systemName: "shield.checkered")
                            .foregroundColor(.yellow)
                    }

                    Text(result.riskAssessment)
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.8))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.yellow.opacity(0.1))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color.yellow.opacity(0.3), lineWidth: 1)
                )

                // Resources that would be modified
                if !result.wouldModify.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Label {
                            Text("Resources Affected")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.white)
                        } icon: {
                            Image(systemName: "doc.text.magnifyingglass")
                                .foregroundColor(.orange)
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(result.wouldModify, id: \.self) { resource in
                                HStack(spacing: 8) {
                                    Image(systemName: "circle.fill")
                                        .font(.system(size: 6))
                                        .foregroundColor(.orange)

                                    Text(resource)
                                        .font(.system(size: 13, design: .monospaced))
                                        .foregroundColor(.white.opacity(0.8))
                                }
                            }
                        }
                    }
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.orange.opacity(0.1))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(Color.orange.opacity(0.3), lineWidth: 1)
                    )
                }

                // Estimated duration
                if let duration = result.estimatedDuration {
                    HStack(spacing: 12) {
                        Image(systemName: "clock")
                            .font(.system(size: 14))
                            .foregroundColor(.white.opacity(0.6))

                        Text("Estimated Duration:")
                            .font(.system(size: 13))
                            .foregroundColor(.white.opacity(0.6))

                        Text(duration)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white)
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.white.opacity(0.05))
                    )
                }

                // Simulated output
                VStack(alignment: .leading, spacing: 12) {
                    Button(action: { showFullOutput.toggle() }) {
                        HStack {
                            Label {
                                Text("Simulated Output")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(.white)
                            } icon: {
                                Image(systemName: "terminal")
                                    .foregroundColor(.green)
                            }

                            Spacer()

                            Image(systemName: showFullOutput ? "chevron.down" : "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.white.opacity(0.5))
                        }
                    }

                    if showFullOutput {
                        ScrollView {
                            Text(result.simulatedOutput)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundColor(.green.opacity(0.8))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxHeight: 200)
                        .padding(12)
                        .background(Color.black.opacity(0.5))
                        .cornerRadius(8)
                    }
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.green.opacity(0.05))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color.green.opacity(0.2), lineWidth: 1)
                )

                // Action buttons
                HStack(spacing: 16) {
                    Button(action: onCancel) {
                        HStack(spacing: 8) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 16))
                            Text("Cancel")
                                .font(.system(size: 16, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.red.opacity(0.3))
                        )
                    }

                    Button(action: onProceed) {
                        HStack(spacing: 8) {
                            Image(systemName: "play.circle.fill")
                                .font(.system(size: 16))
                            Text("Proceed for Real")
                                .font(.system(size: 16, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(
                                    LinearGradient(
                                        colors: [Color.cyan, Color.blue],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                        )
                    }
                }
                .padding(.top, 8)
            }
            .padding(20)
        }
        .background(Color.black.ignoresSafeArea())
    }
}

#Preview {
    DryRunResultView(
        result: DryRunResult(
            toolName: "db.migrate",
            simulatedOutput: """
                Running migration: 2024_05_21_add_user_preferences

                Would execute:
                - CREATE TABLE user_preferences (
                    id SERIAL PRIMARY KEY,
                    user_id INTEGER REFERENCES users(id),
                    theme VARCHAR(50),
                    notifications BOOLEAN
                  );

                - CREATE INDEX idx_user_preferences_user_id ON user_preferences(user_id);

                Affected rows: 0 (dry run)
                Estimated time: 120ms
                """,
            wouldModify: [
                "Database: main",
                "Table: user_preferences (CREATE)",
                "Index: idx_user_preferences_user_id (CREATE)",
                "Schema version: 42 → 43"
            ],
            estimatedDuration: "~120ms",
            riskAssessment: "Low risk operation. Creates new table without modifying existing data. Reversible via rollback migration."
        ),
        onProceed: { print("Proceeding...") },
        onCancel: { print("Cancelled") }
    )
}
