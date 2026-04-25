#if os(macOS)
import SwiftUI

struct SplashView: View {
    let state: MacConnectionManager.State
    let onRetry: () -> Void

    private var isConnecting: Bool {
        if case .connecting = state { return true }
        return false
    }

    var body: some View {
        ZStack {
            Color.appBg.ignoresSafeArea()

            RadialGradient(
                colors: [Color.accent.opacity(0.10), .clear],
                center: .center,
                startRadius: 20,
                endRadius: 200
            )
            .blur(radius: 30)

            VStack(spacing: 0) {
                Spacer()

                MiraLogoView(size: 108, animated: isConnecting)

                Spacer().frame(height: 26)

                Text("Mira")
                    .font(.bookerly(size: 36, weight: .semibold))
                    .foregroundStyle(Color.textPrimary)

                Spacer().frame(height: 18)

                stateContent
                    .animation(.easeInOut(duration: 0.35), value: isConnecting)

                Spacer()
            }
            .padding(.horizontal, 48)
        }
        .frame(width: 440, height: 320)
    }

    @ViewBuilder
    private var stateContent: some View {
        switch state {
        case .connecting:
            statusRow("Connecting to server…")

        case .ready:
            EmptyView()

        case .failed(let msg):
            VStack(spacing: 14) {
                Label("Server not available", systemImage: "exclamationmark.triangle")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.red)
                Text(msg)
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 300)
                Button("Retry", action: onRetry)
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

#Preview("Connecting") { SplashView(state: .connecting, onRetry: {}) }
#Preview("Failed")     { SplashView(state: .failed("Server not found at localhost:8000."), onRetry: {}) }
#endif
