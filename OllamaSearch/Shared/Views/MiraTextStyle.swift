import SwiftUI

// ── Reusable text style modifiers ─────────────────────────────────────────────
//
// Use ViewModifier structs (not Text extensions) so they compose with SwiftUI's
// type system and can be applied to any View (Text, Label, etc.).
// Layout modifiers (padding, frame, kerning) stay at the call site.

struct MiraSecondaryCaption: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(Font.sidebarMeta)
            .foregroundStyle(Color.textSecondary)
            .lineLimit(1)
    }
}

struct MiraMetadataLabel: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.caption2)
            .foregroundStyle(Color.textSecondary)
            .lineLimit(2)
    }
}

struct MiraTimestamp: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(Font.sidebarSubtitle)
            .foregroundStyle(Color.textSecondary)
    }
}

extension View {
    func miraSecondaryCaption() -> some View { modifier(MiraSecondaryCaption()) }
    func miraMetadataLabel() -> some View { modifier(MiraMetadataLabel()) }
    func miraTimestamp() -> some View { modifier(MiraTimestamp()) }
}
