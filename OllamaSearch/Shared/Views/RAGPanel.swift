import SwiftUI

/// Collapsible panel showing RAG chunks injected from attached documents.
/// Green accent — mirrors the "Document sections used" panel in the web UI.
struct RAGPanel: View {
    let chunks: [RAGChunk]
    @State private var isExpanded = true

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(chunks) { chunk in
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "doc.text")
                            .foregroundStyle(.green)
                            .font(.caption)
                            .frame(width: 14)
                        VStack(alignment: .leading, spacing: 1) {
                            HStack {
                                Text(chunk.source)
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(.green)
                                Spacer()
                                Text(String(format: "%.2f", chunk.score))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Text(chunk.preview)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                }
            }
            .padding(.top, 4)
        } label: {
            Label("Document sections used (\(chunks.count))", systemImage: "square.3.layers.3d")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.green)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.green.opacity(0.07))
                .stroke(Color.green.opacity(0.25), lineWidth: 1)
        )
    }
}
