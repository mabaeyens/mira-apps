import SwiftUI

/// Generic collapsible panel: DisclosureGroup + accent header + rounded background.
/// Callers supply the items and a @ViewBuilder for each row's inner content.
struct DisclosureListPanel<Item: Identifiable, RowContent: View>: View {
    @Binding var isExpanded: Bool
    let header: String
    let headerIcon: String
    let itemIcon: String
    let items: [Item]
    var vStackSpacing: CGFloat = 6
    @ViewBuilder let rowContent: (Item) -> RowContent

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: vStackSpacing) {
                ForEach(items) { item in
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: itemIcon)
                            .foregroundStyle(Color.appAccent)
                            .font(.caption)
                            .frame(width: 14)
                        VStack(alignment: .leading, spacing: 1) {
                            rowContent(item)
                        }
                    }
                }
            }
            .padding(.top, 4)
        } label: {
            Label(header, systemImage: headerIcon)
                .font(.caption.weight(.medium))
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
