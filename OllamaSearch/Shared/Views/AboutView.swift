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

            MiraLogoView(size: 120, playIntro: true)

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
                    "The name Mira is the Spanish imperative of mirar (\u{201C}look!\u{201D}), " +
                    "the Latin word for \u{201C}wonder\u{201D} and the name of one of the oldest variable double stars " +
                    "observed by astronomers, a red giant whose brightness pulses on a 332-day cycle.\n\n" +
                    "With Mira, inference runs entirely on your Mac \u{2014} this app is simply a window into it \u{2014} " +
                    "so your conversations stay private and never touch an external server.\n\n" +
                    "Mira captures the spirit of the project: a quiet, local intelligence " +
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
