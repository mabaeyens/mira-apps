import SwiftUI

/// Collapsible panel showing RAG chunks injected from attached documents.
struct RAGPanel: View {
    let chunks: [RAGChunk]
    @State private var isExpanded = true

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(chunks) { chunk in
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "doc.text")
                            .foregroundStyle(Color.appAccent)
                            .font(.caption)
                            .frame(width: 14)
                        VStack(alignment: .leading, spacing: 1) {
                            HStack {
                                Text(chunk.source)
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(Color.appAccent)
                                Spacer()
                                Text(String(format: "%.2f", chunk.score))
                                    .font(.caption2)
                                    .foregroundStyle(Color.textSecondary)
                            }
                            Text(chunk.preview)
                                .font(.caption2)
                                .foregroundStyle(Color.textSecondary)
                                .lineLimit(2)
                        }
                    }
                }
            }
            .padding(.top, 4)
        } label: {
            Label("Document sections used (\(chunks.count))", systemImage: "square.3.layers.3d")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.appAccent)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.appAccent.opacity(0.07))
                .stroke(Color.appAccent.opacity(0.25), lineWidth: 1)
        )
    }
}
