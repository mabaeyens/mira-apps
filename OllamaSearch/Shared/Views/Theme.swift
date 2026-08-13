import SwiftUI
import MarkdownUI

// ── Color helpers ──────────────────────────────────────────────────────────────

extension Color {
    // `Color(light:dark:)` used below is NOT a SwiftUI API, whatever this
    // comment used to claim. It comes from **MarkdownUI**
    // (Sources/MarkdownUI/Utility/Color+RGBA.swift), which is why this file
    // imports MarkdownUI even though only the theme at the bottom renders
    // markdown. The whole palette therefore depends on a rendering library's
    // public utility extension. It builds a proper dynamic NSColor/UIColor, so
    // it behaves correctly; the risk is that it disappears in a MarkdownUI
    // release and takes every colour in the app with it.
    //
    // Verified 2026-07-26: `swiftc` refuses `Color(light:dark:)` with only
    // SwiftUI imported, at the app's own macOS 15 deployment target.

    init(hex: UInt32) {
        self.init(
            red:   Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8)  & 0xFF) / 255,
            blue:  Double( hex        & 0xFF) / 255
        )
    }
}

// ── Adaptive palette ───────────────────────────────────────────────────────────
//
//  Dark mode  — Tailwind stone scale (warm brown)
//  Light mode — Claude-inspired warm cream/beige
//
//  Dark                Light
//  stone-900 #1C1917   #FAF9F7  warm off-white    — main bg
//  stone-800 #292524   #F0EDE8  warm light gray   — sidebar
//  stone-700 #44403C   #E8E3DC  warm beige        — user bubble
//  stone-600 #57534E   #D5D0CA  warm light border — borders
//  stone-400 #A8A29E   #78716C  warm mid gray     — secondary text
//  stone-50  #FAFAF9   #1C1917  near-black        — primary text
//  input bg  #232120   #FFFFFF  white             — surface
//  accent    #D09268   #C07A4F  slightly deeper   — brand amber

extension Color {
    static let appBg = Color(
        light: Color(hex: 0xFAF9F7),
        dark:  Color(hex: 0x1C1917)
    )
    static let sidebarBg = Color(
        light: Color(hex: 0xF0EDE8),
        dark:  Color(hex: 0x292524)
    )
    static let userBubbleBg = Color(
        light: Color(hex: 0xE0D8CE),
        dark:  Color(hex: 0x44403C)
    )
    static let surfaceBg = Color(
        light: Color(hex: 0xFFFFFF),
        dark:  Color(hex: 0x232120)
    )
    static let borderSubtle = Color(
        light: Color(hex: 0xD5D0CA),
        dark:  Color(hex: 0x57534E)
    )
    /// Warm amber — same hue in both modes, slightly deeper in light for contrast.
    ///
    /// The `AccentColor` asset holds these same two values, so `Color.accent`
    /// and `Color.appAccent` resolve identically today and the ~35 uses of the
    /// former are not a visual bug. They are one colour defined twice: edit one
    /// and they diverge.
    static let appAccent = Color(
        light: Color(hex: 0xC07A4F),
        dark:  Color(hex: 0xD09268)
    )

    /// Accent for body-size text, notably markdown links.
    ///
    /// The brand amber is a tint, chosen against the icon and the dark page. As
    /// text on the light page it measures **3.25:1**, below the 4.5 that normal
    /// text needs, so links were the one place light mode failed outright. This
    /// is the same hue (22.8°) and saturation with the value dropped 0.753 to
    /// 0.625: 4.52 on the page, 4.76 on a card. Dark mode already cleared it at
    /// 6.66 and is unchanged, so the brand colour itself is untouched.
    ///
    /// Measured by `notes/mira-palette-contrast.py` in mira-core.
    static let linkAccent = Color(
        light: Color(hex: 0x9F6542),
        dark:  Color(hex: 0xD09268)
    )
    static let textPrimary = Color(
        light: Color(hex: 0x1C1917),
        dark:  Color(hex: 0xFAFAF9)
    )
    static let textSecondary = Color(
        light: Color(hex: 0x78716C),
        dark:  Color(hex: 0xA8A29E)
    )
    static let splashCenter = Color(
        light: Color(hex: 0xF0EDE8),
        dark:  Color(hex: 0x272220)
    )
}

// ── App font ──────────────────────────────────────────────────────────────────

extension Font {
    static func brand(size: CGFloat, weight: Weight = .regular) -> Font {
        .custom("Lora", size: size).weight(weight)
    }

    /// Brand title — app name display / splash screens. Fixed size, no Dynamic Type.
    static let brandTitle: Font = .brand(size: 36, weight: .semibold)

    /// Icon sizing — apply via .font() on Image(systemName:) to decouple icons from surrounding text.
    static let iconSmall:   Font = .system(size: 13, weight: .regular)
    /// Between small and medium: the compose bar's own controls, which sit in a
    /// 28pt tap target and would crowd it at 17.
    static let iconCompact: Font = .system(size: 16, weight: .regular)
    static let iconMedium:  Font = .system(size: 17, weight: .regular)
    static let iconLarge:   Font = .system(size: 22, weight: .regular)
    static let iconXL:      Font = .system(size: 28, weight: .regular)

    /// Body size used in chat bubbles, streaming text, and the input field.
    /// iOS uses .body (Dynamic Type, 17pt at default) so SwiftUI–UIKit font
    /// bridging is consistent across Text, TextField(axis:.vertical)/UITextView,
    /// and MarkdownUI. macOS uses a fixed 16pt (macOS .body is 13pt, too small).
    #if os(iOS)
    static let chatBody: Font = .body
    static let sidebarTitle: Font = .subheadline
    static let sidebarSubtitle: Font = .caption
    static let sidebarMeta: Font = .caption2.weight(.medium)
    #else
    static let chatBody: Font = .system(size: 16)
    // macOS system semantic sizes are small. Measured 2026-07-26 on macOS 15:
    // body 13, callout 12, subheadline 11, footnote 10, caption 10, caption2 10.
    // (An older comment here said caption was 11; it is 10.) Fixed sizes keep
    // the sidebar proportionate to the 16pt chat body.
    static let sidebarTitle: Font = .system(size: 14)
    static let sidebarSubtitle: Font = .system(size: 12)
    static let sidebarMeta: Font = .system(size: 11, weight: .medium)
    #endif

    // ── Roles ─────────────────────────────────────────────────────────────────
    //
    // Named by what the text IS, not what size it is, so a value can move in one
    // place instead of across nine files. Every value below is exactly what the
    // literal it replaces used, on both platforms: this is a rename, not a
    // restyle.
    //
    // Two roles that share a value today are still two roles. `bannerLabel` and
    // `pillLabel` are both 13; keeping them separate is the whole point, since
    // moving one later should not drag the other with it.
    //
    // KNOWN ISSUE, deliberately not changed here. On iOS these fixed sizes are
    // exactly the Dynamic Type defaults (11 = caption2, 12 = caption,
    // 13 = footnote, 15 = subheadline, 17 = body), so they render identically
    // at the default text size and then refuse to grow, while the neighbouring
    // `.caption` and `.subheadline` uses do grow. A Larger Text user sees a
    // layout come apart. Switching these to semantic fonts on iOS is a one-line
    // change per role now that the roles exist, but it changes behaviour and is
    // Miguel's call, so it is written up rather than done.

    /// Primary text of a list or sheet row: sidebar entries, option rows.
    static let rowTitle: Font = .system(size: 15, weight: .medium)

    /// Row title on denser surfaces, currently the model picker's 340pt sheet.
    static let rowTitleDense: Font = .system(size: 14, weight: .medium)

    /// Uppercase section label above a group of rows ("MODELS", "NOT AVAILABLE").
    static let sectionHeader: Font = .system(size: 11, weight: .medium)

    /// Text inside an inline banner across the top of the chat.
    static let bannerLabel: Font = .system(size: 13)

    /// Text inside a capsule control, currently the model pill.
    static let pillLabel: Font = .system(size: 13)

    /// Token counters and other figures that must not reflow as digits change.
    static let monoStatus: Font = .system(size: 13, weight: .medium, design: .monospaced)
    static let monoStatusSmall: Font = .system(size: 11, weight: .medium, design: .monospaced)
    /// Monospaced detail inside a row, e.g. a search snippet.
    static let monoDetail: Font = .system(size: 12, design: .monospaced)
}

// ── Corner radii ──────────────────────────────────────────────────────────────
//
// Same rule as the type roles above: named by what the shape IS, so a value can
// move in one place instead of across nine files. Every value here is exactly
// what the literal it replaced used — a rename, not a restyle.
//
// Only values used more than twice earned a name. `3` (one attachment
// progress bar), `6` (two code-block corners) and `18` (the user message
// bubble) stay as literals on purpose: a shape used once or twice does not
// need a role, and inventing one to satisfy a grep is ceremony, not a scale.
enum Radius {
    /// Inline pill sitting in a line of text — 2pt vertical padding.
    /// Token counters, the "copied" confirmation chip.
    static let badge: CGFloat = 4

    /// The workhorse. Anything small and filled: toolbar buttons, inner
    /// panels, model-picker rows, code blocks.
    static let control: CGFloat = 8

    /// An editable surface: the iOS search field, the memory text editors.
    static let field: CGFloat = 10

    /// A row on a dense surface — currently the model picker's 340pt sheet,
    /// the same surface `Font.rowTitleDense` exists for.
    ///
    /// NOTE: this is a row, and `card` (12) is also a row. They do the same
    /// job at different radii, which is drift, not intent. Merging them would
    /// change how the picker looks, so it is named honestly and left alone —
    /// see `specs/type-scale.md`, which forbids restyling under a rename.
    static let cardDense: CGFloat = 10

    /// The macOS sidebar's clipped corner. One use, but it is load-bearing
    /// geometry rather than decoration: the sidebar sits inset with an even
    /// 10pt margin and this radius is what makes that read as deliberate.
    static let sidebarClip: CGFloat = 10

    /// A padded card, a list row, or an image thumbnail: the connection form,
    /// About rows, conversation rows, attachment previews.
    static let card: CGFloat = 12

    /// The compose surface and the attachment tiles in its sheet.
    static let compose: CGFloat = 14
}

// ── Markdown theme ────────────────────────────────────────────────────────────

extension MarkdownUI.Theme {
    /// App-wide Markdown theme: system body font, adaptive warm palette.
    static let app: Self = .gitHub
        .text {
            #if os(macOS)
            FontSize(16)
            #endif
            ForegroundColor(Color.textPrimary)
        }
        .link {
            ForegroundColor(Color.linkAccent)
        }
        .code {
            FontFamily(.custom("Menlo"))
            FontSize(.em(0.875))
            BackgroundColor(Color.userBubbleBg)
            ForegroundColor(Color.textPrimary)
        }
        .codeBlock { cfg in
            CopyableCodeBlock(
                language: cfg.language,
                content: cfg.content
            )
        }
}
