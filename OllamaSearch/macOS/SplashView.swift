#if os(macOS)
import SwiftUI
import AppKit

/// Apply title-bar styling to the view's window, idempotently and outside the
/// current layout pass.
///
/// Both callers below mutate the SAME window, and they are mounted in opposite
/// branches of an `if showMain` that animates over 0.3s. SwiftUI keeps both
/// branches alive during that transition, so the two would fight over
/// `styleMask` (one inserting `.fullSizeContentView`, the other removing it)
/// while the hosting view was mid-layout. Changing `styleMask` forces the window
/// to re-lay out its content view, which is what produced:
///
///   It's not legal to call -layoutSubtreeIfNeeded on a view which is already
///   being laid out.
///
/// Two things keep that from happening. Every property is compared before it is
/// written, so a no-op transition performs no layout at all; and the work is
/// scheduled with `RunLoop.main.perform`, which runs at the top of a run-loop
/// iteration rather than `DispatchQueue.main.async`, whose blocks AppKit can
/// drain *inside* an active layout transaction.
private func applyTitleBar(to view: NSView, transparent: Bool) {
    RunLoop.main.perform(inModes: [.default]) {
        guard let w = view.window else { return }

        if w.titlebarAppearsTransparent != transparent {
            w.titlebarAppearsTransparent = transparent
        }
        if w.titleVisibility != .hidden {
            w.titleVisibility = .hidden
        }
        if transparent != w.styleMask.contains(.fullSizeContentView) {
            if transparent {
                w.styleMask.insert(.fullSizeContentView)
            } else {
                w.styleMask.remove(.fullSizeContentView)
            }
        }
        let bg = NSColor(Color.appBg)
        if w.backgroundColor != bg {
            w.backgroundColor = bg
        }
    }
}

// Makes the window title bar transparent so the content fills edge-to-edge.
private struct TransparentTitleBar: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        applyTitleBar(to: view, transparent: true)
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

// Resets the window to a normal (opaque) title bar — content sits below it, so a
// floating panel can't be overlapped by the titlebar region. Counterpart to
// TransparentTitleBar, which the splash applies to the shared window first.
struct NormalTitleBar: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        applyTitleBar(to: view, transparent: false)
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

struct SplashView: View {
    let state: MacConnectionManager.State
    let onRetry: () -> Void
    /// Called with the token the user pasted in the `.needsToken` state.
    var onSubmitToken: (String) -> Void = { _ in }

    @State private var tokenEntry = ""

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
                    .font(.brandTitle)
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

        case .needsToken:
            VStack(spacing: 12) {
                Label("Access token needed", systemImage: "key")
                    .font(.subheadline.weight(.medium))
                Text("The server is running but rejected this app. Paste the token from ~/.local/share/mira/token — it is stored in your keychain, so this is asked once.")
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 320)
                SecureField("Access token", text: $tokenEntry)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 320)
                    .onSubmit { onSubmitToken(tokenEntry) }
                Button("Connect") { onSubmitToken(tokenEntry) }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.accent)
                    .disabled(tokenEntry.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

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
#Preview("Needs token") { SplashView(state: .needsToken, onRetry: {}) }
#endif
