import SwiftUI

// ── Mira brand mark ───────────────────────────────────────────────────────────
//
//  An almond eye with a four-pointed star at its pupil.
//  The eye references "mira" = look (Spanish).
//  The star references Mira Ceti, the pulsating variable star.
//  While loading, the ambient glow breathes — like Mira Ceti varying in brightness.

struct MiraLogoView: View {
    var size: CGFloat = 80
    var animated: Bool = false

    @State private var glowing = false

    private var eyeWidth:    CGFloat { size * 0.94 }
    private var eyeHeight:   CGFloat { size * 0.46 }
    private var strokeWidth: CGFloat { max(1.5, size * 0.032) }
    private var sparkleSize: CGFloat { size * 0.22 }

    var body: some View {
        ZStack {
            // Breathing glow — sized to the eye, not the full frame
            Ellipse()
                .fill(Color.accent.opacity(0.28))
                .blur(radius: size * 0.22)
                .scaleEffect(glowing ? 1.5 : 1.0)
                .frame(width: eyeWidth * 0.75, height: eyeHeight * 2.2)

            // Eye outline
            MiraEyeShape()
                .stroke(
                    Color.accent,
                    style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round)
                )
                .frame(width: eyeWidth, height: eyeHeight)

            // Star pupil — SF Symbol "sparkle" is a clean four-pointed star
            Image(systemName: "sparkle")
                .font(.system(size: sparkleSize, weight: .regular))
                .foregroundStyle(Color.accent)
        }
        .frame(width: size, height: size)
        .onAppear {
            guard animated else { return }
            startPulse()
        }
        .onChange(of: animated) {
            if animated { startPulse() }
        }
    }

    private func startPulse() {
        withAnimation(.easeInOut(duration: 2.6).repeatForever(autoreverses: true)) {
            glowing = true
        }
    }
}

// ── Eye path ──────────────────────────────────────────────────────────────────
//
//  Two quadratic Bézier arcs meeting at the left and right tips.
//  Control points sit at the vertical poles (top and bottom of the bounding rect),
//  which gives a natural almond curve.

struct MiraEyeShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let left   = CGPoint(x: rect.minX, y: rect.midY)
        let right  = CGPoint(x: rect.maxX, y: rect.midY)
        let top    = CGPoint(x: rect.midX, y: rect.minY)
        let bottom = CGPoint(x: rect.midX, y: rect.maxY)
        p.move(to: left)
        p.addQuadCurve(to: right, control: top)
        p.addQuadCurve(to: left,  control: bottom)
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

#Preview("Animated") {
    MiraLogoView(size: 120, animated: true)
        .padding(40)
        .background(Color.appBg)
}
