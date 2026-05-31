import SwiftUI

/// Collapsible panel showing web pages fetched during this turn.
/// Blue accent — mirrors the "Pages read" panel in the web UI.
struct SourcesPanel: View {
    let fetches: [FetchInfo]
    @State private var isExpanded = true

    var body: some View {
        DisclosureListPanel(
            isExpanded: $isExpanded,
            header: "Pages read (\(fetches.count))",
            headerIcon: "doc.text.magnifyingglass",
            itemIcon: "globe",
            items: fetches,
            vStackSpacing: 4
        ) { fetch in
            Text(fetch.url)
                .font(.caption)
                .foregroundStyle(Color.appAccent)
                .lineLimit(1)
                .truncationMode(.middle)
            Text(fetch.preview)
                .miraMetadataLabel()
        }
    }
}
