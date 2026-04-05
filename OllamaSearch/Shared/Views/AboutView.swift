import SwiftUI

struct AboutView: View {
    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            MiraLogoView(size: 80)

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
                    "The app runs AI models entirely on your own device, keeping your conversations " +
                    "private and independent of any cloud service or internet connection. " +
                    "Together they capture the spirit of the project: a quiet, local intelligence " +
                    "that looks with you, always on your side."
                )
                .font(.subheadline)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .frame(maxWidth: 360)
            }

            Spacer().frame(height: 28)

            Text("© Miguel Angel Baeyens 2026")
                .font(.caption)
                .foregroundStyle(Color.textSecondary.opacity(0.6))

            Spacer()
        }
        .padding(.horizontal, 40)
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.appBg)
    }
}

#Preview {
    AboutView()
        .frame(width: 480, height: 420)
}
