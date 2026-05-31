#if os(macOS)
import SwiftUI
import AppKit

// Makes the window title bar transparent so the content fills edge-to-edge.
private struct TransparentTitleBar: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let w = view.window else { return }
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.styleMask.insert(.fullSizeContentView)
            w.backgroundColor = NSColor(Color.appBg)
        }
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

struct SplashView: View {
    let state: MacConnectionManager.State
    let onRetry: () -> Void

    private var isConnecting: Bool {
        if case .connecting = state { return true }
        return false
    }

    private var connectingMessage: String {
        if case .connecting(let msg) = state { return msg }
        return "Connecting to server…"
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
        .background(TransparentTitleBar())
    }

    @ViewBuilder
    private var stateContent: some View {
        switch state {
        case .connecting:
            statusRow(connectingMessage)

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

#Preview("Connecting") { SplashView(state: .connecting("Connecting to server…"), onRetry: {}) }
#Preview("Starting")   { SplashView(state: .connecting("Starting Ollama…"), onRetry: {}) }
#Preview("Failed")     { SplashView(state: .failed("Server not found at localhost:8000."), onRetry: {}) }
#endif
