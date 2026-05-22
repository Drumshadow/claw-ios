import SwiftUI

struct TimelineScrubberView: View {
    @Bindable var store: ReplayStore

    var body: some View {
        VStack(spacing: 8) {
            // Step dots: small circles for each step, colored by role
            // - User steps: clawAccent
            // - Tool steps: clawTeal
            // - Assistant steps: clawMuted
            // Current step: larger, brighter
            stepsTrack

            // Slider for scrubbing
            HStack(spacing: 12) {
                Text("Step \(store.currentIndex + 1)/\(store.steps.count)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(Color.clawMuted)
                    .frame(width: 80, alignment: .leading)

                Slider(
                    value: Binding(
                        get: { store.progress },
                        set: { store.scrubTo(progress: $0) }
                    ),
                    in: 0...1
                )
                .tint(Color.clawAccent)

                // Playback speed picker
                Menu {
                    ForEach([0.5, 1.0, 2.0, 4.0], id: \.self) { speed in
                        Button("\(speed, specifier: "%.1f")×") {
                            store.playbackSpeed = speed
                        }
                    }
                } label: {
                    Text("\(store.playbackSpeed, specifier: "%.1f")×")
                        .font(.caption2)
                        .foregroundStyle(Color.clawAccent)
                        .frame(width: 36, alignment: .trailing)
                }
            }

            // Transport controls
            HStack(spacing: 24) {
                Button { store.jumpToStart() } label: {
                    Image(systemName: "backward.end.fill").font(.caption)
                }
                Button { store.stepBackward() } label: {
                    Image(systemName: "backward.frame.fill").font(.body)
                }
                Button { store.isPlaying ? store.pause() : store.play() } label: {
                    Image(systemName: store.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title3)
                }
                Button { store.stepForward() } label: {
                    Image(systemName: "forward.frame.fill").font(.body)
                }
                Button { store.jumpToEnd() } label: {
                    Image(systemName: "forward.end.fill").font(.caption)
                }
            }
            .tint(Color.clawTextStrong)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.clawBgAccent)
    }

    private var stepsTrack: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(store.steps) { step in
                    Circle()
                        .fill(colorFor(step))
                        .frame(
                            width: step.index == store.currentIndex ? 10 : 6,
                            height: step.index == store.currentIndex ? 10 : 6
                        )
                        .animation(.spring(duration: 0.2), value: store.currentIndex)
                        .onTapGesture { store.scrubTo(index: step.index) }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
        }
    }

    private func colorFor(_ step: ReplayStep) -> Color {
        let isPast = step.index <= store.currentIndex
        if step.isUser { return isPast ? Color.clawAccent : Color.clawAccent.opacity(0.3) }
        if step.isTool { return isPast ? Color.clawTeal : Color.clawTeal.opacity(0.3) }
        return isPast ? Color.clawMuted : Color.clawMuted.opacity(0.3)
    }
}
