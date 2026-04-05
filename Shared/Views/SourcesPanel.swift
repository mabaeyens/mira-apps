import SwiftUI

/// Collapsible panel showing web pages fetched during this turn.
/// Blue accent — mirrors the "Pages read" panel in the web UI.
struct SourcesPanel: View {
    let fetches: [FetchInfo]
    @State private var isExpanded = true

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(fetches) { fetch in
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "globe")
                            .foregroundStyle(.blue)
                            .font(.caption)
                            .frame(width: 14)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(fetch.url)
                                .font(.caption)
                                .foregroundStyle(.blue)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Text(fetch.preview)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                }
            }
            .padding(.top, 4)
        } label: {
            Label("Pages read (\(fetches.count))", systemImage: "doc.text.magnifyingglass")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.blue)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.blue.opacity(0.07))
                .stroke(Color.blue.opacity(0.25), lineWidth: 1)
        )
    }
}
