#if os(iOS)
import SwiftUI

/// Shown on iPhone portrait when no conversation is selected.
/// Full-screen dark canvas with Mira logo, a prompt label, and the input bar at the bottom.
struct WelcomeView: View {
    @Bindable var vm: ChatViewModel
    var onMenu: () -> Void
    var onSettings: (() -> Void)? = nil
    var isReachable: Bool = true
    var connectionIcon: String = "wifi"

    var body: some View {
        VStack(spacing: 0) {
            // ── Top buttons ────────────────────────────────────────────────
            HStack {
                circleButton(icon: "line.3.horizontal", action: onMenu)
                Spacer()
                if let onSettings {
                    circleButton(
                        icon: connectionIcon,
                        color: isReachable ? Color.appAccent : .orange,
                        action: onSettings
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)

            // ── Centered logo + prompt ─────────────────────────────────────
            Spacer()
            VStack(spacing: 18) {
                MiraLogoView(size: 68)
                Text("What can I help with?")
                    .font(.bookerly(size: 26, weight: .light))
                    .foregroundStyle(Color.textPrimary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            Spacer()

            // ── Input bar ──────────────────────────────────────────────────
            InputBar(vm: vm)
        }
        .background(Color.appBg.ignoresSafeArea())
    }

    private func circleButton(icon: String, color: Color = Color.textPrimary, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(color)
                .frame(width: 38, height: 38)
                .background(Color(uiColor: .systemFill), in: Circle())
        }
        .buttonStyle(.plain)
    }
}
#endif
