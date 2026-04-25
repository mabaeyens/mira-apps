import SwiftUI

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss

    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
          VStack(spacing: 0) {
            Spacer()

            MiraLogoView(size: 80, playIntro: true)

            Spacer().frame(height: 20)

            Text("Mira")
                .font(.bookerly(size: 28, weight: .semibold))
                .foregroundStyle(Color.textPrimary)

            Text("Version \(version)")
                .font(.subheadline)
                .foregroundStyle(Color.textSecondary)
                .padding(.top, 4)

            Spacer().frame(height: 28)

            VStack(spacing: 12) {
                Text(
                    "The name Mira is the Spanish imperative of mirar \u{2014} \u{201C}look\u{201D} \u{2014} " +
                    "and the name of one of the oldest variable stars observed by astronomers, " +
                    "a red giant whose brightness pulses on a 332-day cycle. " +
                    "Inference runs entirely on your Mac \u{2014} the phone is simply a window into it \u{2014} " +
                    "so your conversations stay private and never touch an external server. " +
                    "Together they capture the spirit of the project: a quiet, local intelligence " +
                    "that looks with you, always on your side."
                )
                .font(.subheadline)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .frame(maxWidth: 360)
            }

            Spacer()
          }
          .padding(.horizontal, 40)
          .padding(.vertical, 24)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
          .background(Color.appBg)

          Button {
              dismiss()
          } label: {
              Image(systemName: "xmark.circle.fill")
                  .font(.system(size: 28))
                  .symbolRenderingMode(.hierarchical)
                  .foregroundStyle(Color.textSecondary)
          }
          .buttonStyle(.plain)
          .padding(16)
        }
        .background(Color.appBg)
    }
}

#Preview {
    AboutView()
        .frame(width: 480, height: 420)
}
