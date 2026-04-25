import SwiftUI

// ── Mira brand mark ───────────────────────────────────────────────────────────
//
//  Large 4-pointed star at center; small companion star orbits around it.
//  Orbit uses TimelineView for per-frame position so z-ordering (behind/in
//  front of the big star) is computed correctly each frame.
//
//  Static:   both stars at rest (small star at design position, lower-right).
//  Animated: companion orbits continuously + breathing ambient glow.
//  Intro:    same as animated but orbit begins after a short settle delay.

struct MiraLogoView: View {
    var size:      CGFloat = 80
    var animated:  Bool    = false
    var playIntro: Bool    = false

    private let orbitDuration: Double = 5.0   // seconds per full revolution

    @State private var orbitStart:  Date? = nil
    @State private var glowing:     Bool  = false
    @State private var introPlayed: Bool  = false

    private var bigStarSize:   CGFloat { size * 0.60 }
    private var smallStarSize: CGFloat { bigStarSize * 0.235 }  // matches SVG scale(0.235)
    private var orbitRX:       CGFloat { size * 0.260 }         // horizontal radius
    private var orbitRY:       CGFloat { size * 0.145 }         // vertical radius (compressed → 3-D look)

    var body: some View {
        TimelineView(.animation(minimumInterval: nil, paused: orbitStart == nil)) { tl in
            let elapsed  = orbitStart.map { tl.date.timeIntervalSince($0) } ?? 0
            // natural design position is 35° (lower-right), advance from there
            let deg      = 35.0 + (elapsed / orbitDuration) * 360.0
            let rad      = deg * .pi / 180.0
            let ox       = orbitRX * CGFloat(cos(rad))
            let oy       = orbitRY * CGFloat(sin(rad))
            let inFront  = sin(rad) >= 0   // positive y → lower half → in front

            ZStack {
                // Ambient glow
                Ellipse()
                    .fill(Color.accent.opacity(0.18))
                    .blur(radius: size * 0.20)
                    .scaleEffect(glowing ? 1.4 : 1.0)
                    .frame(width: size * 0.70, height: size * 0.44)

                // Small star — back half (behind big star, slightly dim)
                if !inFront {
                    FourPointStar()
                        .fill(Color.accent.opacity(0.52))
                        .frame(width: smallStarSize, height: smallStarSize)
                        .offset(x: ox, y: oy)
                }

                // Big star
                FourPointStar()
                    .fill(Color.accent)
                    .frame(width: bigStarSize, height: bigStarSize)

                // Small star — front half (in front of big star, full opacity)
                if inFront {
                    FourPointStar()
                        .fill(Color.accent)
                        .frame(width: smallStarSize, height: smallStarSize)
                        .offset(x: ox, y: oy)
                }
            }
        }
        .frame(width: size, height: size)
        .onAppear { handleAppear() }
        .onChange(of: animated) { if animated { beginOrbit() } }
    }

    // ── appear / start logic ──────────────────────────────────────────────────

    private func handleAppear() {
        if playIntro && !introPlayed {
            introPlayed = true
            // brief settle delay so the view is fully laid out before orbiting
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.20) { beginOrbit() }
        } else if animated {
            beginOrbit()
        }
        if animated { startGlow() }
    }

    private func beginOrbit() {
        guard orbitStart == nil else { return }
        orbitStart = Date()
    }

    private func startGlow() {
        withAnimation(.easeInOut(duration: 2.6).repeatForever(autoreverses: true)) {
            glowing = true
        }
    }
}

// ── Four-pointed star shape ───────────────────────────────────────────────────
//
//  Replicates the exact bezier curves from the Concept C SVG (mira_icon_C.svg).
//  The star arms meet at (0,±318) and (±318,0); each quadrant is two cubic
//  segments that create the concave waist between adjacent points.

struct FourPointStar: Shape {
    func path(in rect: CGRect) -> Path {
        let s  = min(rect.width, rect.height)
        let cx = rect.midX
        let cy = rect.midY
        let k  = s / 636.0   // path spans −318…+318 = 636 units total

        func pt(_ x: Double, _ y: Double) -> CGPoint {
            CGPoint(x: cx + CGFloat(x) * k, y: cy + CGFloat(y) * k)
        }

        var p = Path()
        p.move(to: pt(0, -318))
        // top → right
        p.addCurve(to: pt(23, -102),   control1: pt(8, -214),   control2: pt(15, -140))
        p.addCurve(to: pt(102, -23),   control1: pt(33, -56),   control2: pt(56, -33))
        p.addCurve(to: pt(318, 0),     control1: pt(140, -15),  control2: pt(214, -8))
        // right → bottom
        p.addCurve(to: pt(102, 23),    control1: pt(214, 8),    control2: pt(140, 15))
        p.addCurve(to: pt(23, 102),    control1: pt(56, 33),    control2: pt(33, 56))
        p.addCurve(to: pt(0, 318),     control1: pt(15, 140),   control2: pt(8, 214))
        // bottom → left
        p.addCurve(to: pt(-23, 102),   control1: pt(-8, 214),   control2: pt(-15, 140))
        p.addCurve(to: pt(-102, 23),   control1: pt(-33, 56),   control2: pt(-56, 33))
        p.addCurve(to: pt(-318, 0),    control1: pt(-140, 15),  control2: pt(-214, 8))
        // left → top
        p.addCurve(to: pt(-102, -23),  control1: pt(-214, -8),  control2: pt(-140, -15))
        p.addCurve(to: pt(-23, -102),  control1: pt(-56, -33),  control2: pt(-33, -56))
        p.addCurve(to: pt(0, -318),    control1: pt(-15, -140), control2: pt(-8, -214))
        p.closeSubpath()
        return p
    }
}

// ── Previews ──────────────────────────────────────────────────────────────────

#Preview("Static") {
    MiraLogoView(size: 120)
        .padding(40)
        .background(Color.appBg)
}

#Preview("Animated orbit") {
    MiraLogoView(size: 120, animated: true)
        .padding(40)
        .background(Color.appBg)
}

#Preview("Intro") {
    MiraLogoView(size: 120, animated: true, playIntro: true)
        .padding(40)
        .background(Color.appBg)
}
