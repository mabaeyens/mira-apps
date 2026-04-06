import SwiftUI

// ── Mira brand mark ───────────────────────────────────────────────────────────
//
//  Static:   orbit ring + 4-pointed star, no animation.
//  Animated: breathing glow (idle loading state).
//  Intro:    one-shot sequence — eye open → blink → star grows → tilt to orbit.
//            Runs once on appear (splash screen, About sheet).

struct MiraLogoView: View {
    var size:      CGFloat = 80
    var animated:  Bool    = false   // idle breathing glow
    var playIntro: Bool    = false   // one-shot intro animation

    // ── animation state ──────────────────────────────────────────────────────
    @State private var spread:        CGFloat = 1.0   // 0 = closed, 1 = open
    @State private var orbitTilt:     Double  = 0.0   // 0° = eye, −32° = orbit
    @State private var starScale:     CGFloat = 0.0
    @State private var backOpacity:   Double  = 0.70  // symmetric eye → dim orbit back
    @State private var frontOpacity:  Double  = 0.80  // symmetric eye → bright orbit front
    @State private var shadowOpacity: Double  = 0.0   // hidden during eye phase
    @State private var glowing:       Bool    = false
    @State private var introPlayed:   Bool    = false

    // ── geometry ─────────────────────────────────────────────────────────────
    private var sw:        CGFloat { max(1.5, size * 0.035) }   // stroke width
    private var arcWidth:  CGFloat { size * 0.88 }
    private var arcHeight: CGFloat { size * 0.44 }

    var body: some View {
        ZStack {
            // Breathing ambient glow
            Ellipse()
                .fill(Color.accent.opacity(0.22))
                .blur(radius: size * 0.18)
                .scaleEffect(glowing ? 1.45 : 1.0)
                .frame(width: arcWidth * 0.80, height: arcHeight * 2.0)

            // Back arc — lower half, recedes behind star
            MiraArcShape(spread: spread, isUpper: false)
                .stroke(Color.accent, style: StrokeStyle(lineWidth: sw, lineCap: .round))
                .opacity(backOpacity)
                .frame(width: arcWidth, height: arcHeight)

            // 4-pointed star — grows in step 3
            Image(systemName: "sparkle")
                .font(.system(size: size * 0.50, weight: .regular))
                .foregroundStyle(Color.accent)
                .scaleEffect(starScale)

            // Shadow cast by orbit on star surface (offset toward light, i.e. upward)
            MiraArcShape(spread: spread, isUpper: true)
                .stroke(Color.black,
                        style: StrokeStyle(lineWidth: sw * 2.1, lineCap: .round))
                .blur(radius: size * 0.012)
                .opacity(shadowOpacity)
                .offset(y: -size * 0.044)
                .frame(width: arcWidth, height: arcHeight)

            // Front arc — upper half, passes in front of star
            MiraArcShape(spread: spread, isUpper: true)
                .stroke(Color.accent, style: StrokeStyle(lineWidth: sw, lineCap: .round))
                .opacity(frontOpacity)
                .frame(width: arcWidth, height: arcHeight)
        }
        .rotationEffect(.degrees(orbitTilt))
        .frame(width: size, height: size)
        .onAppear { handleAppear() }
        .onChange(of: animated)  { if animated && !playIntro { startPulse() } }
        .onChange(of: playIntro) { if playIntro && !introPlayed { runIntro() } }
    }

    // ── appear logic ─────────────────────────────────────────────────────────

    private func handleAppear() {
        if playIntro && !introPlayed {
            introPlayed = true
            runIntro()
        } else {
            jumpToOrbit()
            if animated { startPulse() }
        }
    }

    /// Instantly place into final orbit state (no animation).
    private func jumpToOrbit() {
        spread        = 1.0
        orbitTilt     = -32
        starScale     = 1.0
        backOpacity   = 0.18
        frontOpacity  = 0.92
        shadowOpacity = 0.92
    }

    // ── one-shot intro ────────────────────────────────────────────────────────
    //
    //  0.0 s  — eye open, star hidden
    //  0.45 s — eye blinks shut   (spread 1 → 0)
    //  0.85 s — eye opens, star grows (spread 0 → 1, starScale 0 → 1)
    //  1.70 s — tilt to orbit, opacities shift, shadow appears
    //  2.55 s — pulse starts (if animated)

    private func runIntro() {
        // Step 1 — blink shut
        withAnimation(.easeIn(duration: 0.28).delay(0.45)) {
            spread = 0.0
        }
        // Step 2 — open with star
        withAnimation(.spring(response: 0.65, dampingFraction: 0.68).delay(0.85)) {
            spread    = 1.0
            starScale = 1.0
        }
        // Step 3 — tilt to orbit, shift opacities
        withAnimation(.easeInOut(duration: 0.70).delay(1.70)) {
            orbitTilt     = -32
            backOpacity   = 0.18
            frontOpacity  = 0.92
            shadowOpacity = 0.92
        }
        // Step 4 — start idle pulse
        if animated {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.55) { startPulse() }
        }
    }

    private func startPulse() {
        withAnimation(.easeInOut(duration: 2.6).repeatForever(autoreverses: true)) {
            glowing = true
        }
    }
}

// ── Arc shape ─────────────────────────────────────────────────────────────────
//
//  Draws one half (upper or lower) of the eye / orbit ring.
//  `spread` scales the arc height: 0 = flat line, 1 = full curve.

struct MiraArcShape: Shape {
    var spread:  CGFloat
    var isUpper: Bool

    var animatableData: CGFloat {
        get { spread }
        set { spread = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let left    = CGPoint(x: rect.minX, y: rect.midY)
        let right   = CGPoint(x: rect.maxX, y: rect.midY)
        let dy      = rect.height * 0.5 * spread
        let control = CGPoint(
            x: rect.midX,
            y: isUpper ? rect.midY - dy : rect.midY + dy
        )
        p.move(to: left)
        p.addQuadCurve(to: right, control: control)
        return p
    }
}

// ── Previews ──────────────────────────────────────────────────────────────────

#Preview("Static orbit") {
    MiraLogoView(size: 120)
        .padding(40)
        .background(Color.appBg)
}

#Preview("Animated pulse") {
    MiraLogoView(size: 120, animated: true)
        .padding(40)
        .background(Color.appBg)
}

#Preview("Intro") {
    MiraLogoView(size: 120, animated: true, playIntro: true)
        .padding(40)
        .background(Color.appBg)
}
