#if os(macOS)
import SwiftUI

/// Startup splash shown while the Python server is coming up.
struct SplashView: View {
    let state: ServerManager.State
    let onSetPath: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "brain.head.profile")
                .font(.system(size: 64))
                .foregroundStyle(Color.accent)

            switch state {
            case .idle:
                Text("OllamaSearch")
                    .font(.largeTitle.weight(.semibold))

            case .starting:
                Text("Starting server…")
                    .font(.title2)
                ProgressView()

            case .waitingForModel:
                Text("Loading model…")
                    .font(.title2)
                Text("First launch takes 30–60 seconds while gemma4:26b loads into memory.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 340)
                ProgressView()

            case .ready:
                EmptyView()   // caller replaces this view when ready

            case .failed(let msg):
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(.red)
                Text("Could not start server")
                    .font(.title2.weight(.semibold))
                Text(msg)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 340)
                Button("Set Project Path", action: onSetPath)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(40)
        .frame(width: 440, height: 320)
    }
}

#Preview {
    SplashView(state: .waitingForModel, onSetPath: {})
}

#endif
