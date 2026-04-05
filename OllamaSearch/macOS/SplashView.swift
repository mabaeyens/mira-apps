#if os(macOS)
import SwiftUI

struct SplashView: View {
    let state: ServerManager.State
    let onSetPath: () -> Void

    private var isLoading: Bool {
        switch state {
        case .starting, .waitingForModel: true
        default: false
        }
    }

    var body: some View {
        ZStack {
            Color.appBg.ignoresSafeArea()

            // Warm radial halo behind the logo
            RadialGradient(
                colors: [Color.accent.opacity(0.10), .clear],
                center: .center,
                startRadius: 20,
                endRadius: 200
            )
            .blur(radius: 30)

            VStack(spacing: 0) {
                Spacer()

                MiraLogoView(size: 108, animated: isLoading)

                Spacer().frame(height: 26)

                Text("Mira")
                    .font(.bookerly(size: 36, weight: .semibold))
                    .foregroundStyle(Color.textPrimary)

                Spacer().frame(height: 18)

                stateContent
                    .animation(.easeInOut(duration: 0.35), value: isLoading)

                Spacer()
            }
            .padding(.horizontal, 48)
        }
        .frame(width: 440, height: 320)
    }

    @ViewBuilder
    private var stateContent: some View {
        switch state {
        case .idle:
            Text("Local AI, always ready.")
                .font(.subheadline)
                .foregroundStyle(Color.textSecondary)

        case .starting:
            statusRow("Starting server…")

        case .waitingForModel:
            VStack(spacing: 10) {
                statusRow("Loading model…")
                Text("First launch takes 30–60 s while the model loads into memory.")
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary.opacity(0.65))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 300)
            }

        case .ready:
            EmptyView()

        case .failed(let msg):
            VStack(spacing: 14) {
                Label("Could not start server", systemImage: "exclamationmark.triangle")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.red)
                Text(msg)
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 300)
                Button("Set Project Path", action: onSetPath)
                    .buttonStyle(.borderedProminent)
                    .tint(Color.accent)
            }
        }
    }

    private func statusRow(_ label: String) -> some View {
        HStack(spacing: 8) {
            ProgressView()
                .tint(Color.accent)
                .scaleEffect(0.8)
            Text(label)
                .font(.subheadline)
                .foregroundStyle(Color.textSecondary)
        }
    }
}

#Preview("Idle")     { SplashView(state: .idle,           onSetPath: {}) }
#Preview("Starting") { SplashView(state: .starting,       onSetPath: {}) }
#Preview("Waiting")  { SplashView(state: .waitingForModel, onSetPath: {}) }
#Preview("Failed")   { SplashView(state: .failed("Server binary not found at ~/MAI/server.py"), onSetPath: {}) }
#endif
