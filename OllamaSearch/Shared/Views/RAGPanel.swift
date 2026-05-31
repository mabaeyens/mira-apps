import SwiftUI

/// Collapsible panel showing RAG chunks injected from attached documents.
struct RAGPanel: View {
    let chunks: [RAGChunk]
    @State private var isExpanded = true

    var body: some View {
        DisclosureListPanel(
            isExpanded: $isExpanded,
            header: "Document sections used (\(chunks.count))",
            headerIcon: "square.3.layers.3d",
            itemIcon: "doc.text",
            items: chunks,
            vStackSpacing: 6
        ) { chunk in
            HStack {
                Text(chunk.source)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.appAccent)
                Spacer()
                Text(String(format: "%.2f", chunk.score))
                    .miraMetadataLabel()
                    .lineLimit(1)
            }
            Text(chunk.preview)
                .miraMetadataLabel()
        }
    }
}
