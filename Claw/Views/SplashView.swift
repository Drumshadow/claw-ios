import SwiftUI

// MARK: - SplashView

struct SplashView: View {
    @State private var bounce: Bool = false
    @State private var scale: Double = 0.7

    var body: some View {
        ZStack {
            // Sea foam green → sea foam blue gradient background
            LinearGradient(
                colors: [
                    Color(red: 0.29, green: 0.87, blue: 0.78),
                    Color(red: 0.20, green: 0.67, blue: 0.90)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            CrabMascot()
                .frame(width: 180, height: 180)
                .scaleEffect(scale)
                .offset(y: bounce ? -12 : 0)
                .onAppear {
                    withAnimation(.easeOut(duration: 0.45)) { scale = 1.0 }
                    withAnimation(
                        .easeInOut(duration: 0.55)
                        .repeatForever(autoreverses: true)
                        .delay(0.45)
                    ) { bounce = true }
                }
        }
    }
}

// MARK: - CrabMascot

struct CrabMascot: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let cx = w / 2
            let r = w * 0.42

            ZStack {
                // Body
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color(red: 0.96, green: 0.35, blue: 0.30),
                                     Color(red: 0.78, green: 0.18, blue: 0.14)],
                            center: .init(x: 0.4, y: 0.35),
                            startRadius: 0,
                            endRadius: w * 0.5
                        )
                    )
                    .frame(width: r * 2, height: r * 2)
                    .position(x: cx, y: h * 0.50)

                // Left claw
                Ellipse()
                    .fill(Color(red: 0.84, green: 0.22, blue: 0.18))
                    .frame(width: w * 0.18, height: w * 0.16)
                    .position(x: cx - r + w * 0.01, y: h * 0.50)

                // Right claw
                Ellipse()
                    .fill(Color(red: 0.84, green: 0.22, blue: 0.18))
                    .frame(width: w * 0.18, height: w * 0.16)
                    .position(x: cx + r - w * 0.01, y: h * 0.50)

                // Left leg
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(red: 0.78, green: 0.18, blue: 0.14))
                    .frame(width: w * 0.08, height: w * 0.15)
                    .position(x: cx - w * 0.10, y: h * 0.50 + r + w * 0.06)

                // Right leg
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(red: 0.78, green: 0.18, blue: 0.14))
                    .frame(width: w * 0.08, height: w * 0.15)
                    .position(x: cx + w * 0.10, y: h * 0.50 + r + w * 0.06)

                // Left antenna
                Path { path in
                    path.move(to: CGPoint(x: cx - w * 0.10, y: h * 0.50 - r))
                    path.addQuadCurve(
                        to: CGPoint(x: cx - w * 0.22, y: h * 0.50 - r - w * 0.18),
                        control: CGPoint(x: cx - w * 0.20, y: h * 0.50 - r - w * 0.05)
                    )
                }
                .stroke(Color(red: 0.96, green: 0.45, blue: 0.42), style: StrokeStyle(lineWidth: w * 0.04, lineCap: .round))

                // Right antenna
                Path { path in
                    path.move(to: CGPoint(x: cx + w * 0.10, y: h * 0.50 - r))
                    path.addQuadCurve(
                        to: CGPoint(x: cx + w * 0.22, y: h * 0.50 - r - w * 0.18),
                        control: CGPoint(x: cx + w * 0.20, y: h * 0.50 - r - w * 0.05)
                    )
                }
                .stroke(Color(red: 0.96, green: 0.45, blue: 0.42), style: StrokeStyle(lineWidth: w * 0.04, lineCap: .round))

                // Left eye (white + teal pupil)
                Circle()
                    .fill(Color.black)
                    .frame(width: w * 0.14, height: w * 0.14)
                    .position(x: cx - w * 0.13, y: h * 0.50 - w * 0.04)
                Circle()
                    .fill(Color(red: 0.20, green: 0.87, blue: 0.80))
                    .frame(width: w * 0.06, height: w * 0.06)
                    .position(x: cx - w * 0.11, y: h * 0.50 - w * 0.06)

                // Right eye (white + teal pupil)
                Circle()
                    .fill(Color.black)
                    .frame(width: w * 0.14, height: w * 0.14)
                    .position(x: cx + w * 0.13, y: h * 0.50 - w * 0.04)
                Circle()
                    .fill(Color(red: 0.20, green: 0.87, blue: 0.80))
                    .frame(width: w * 0.06, height: w * 0.06)
                    .position(x: cx + w * 0.15, y: h * 0.50 - w * 0.06)
            }
        }
    }
}
