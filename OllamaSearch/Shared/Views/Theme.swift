import SwiftUI
import MarkdownUI

// ── Color helpers ──────────────────────────────────────────────────────────────

extension Color {
    // Color(light:dark:) is provided by SwiftUI since macOS 14 / iOS 17.
    // No custom init needed — the system version is used directly below.

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
        light: Color(hex: 0xE8E3DC),
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
    static let appAccent = Color(
        light: Color(hex: 0xC07A4F),
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
}

// ── App font ──────────────────────────────────────────────────────────────────
//
// Uses Bookerly if installed (download .ttf files, double-click to install via
// macOS Font Book). Falls back to the system default if not found.

extension Font {
    static func bookerly(size: CGFloat, weight: Weight = .regular) -> Font {
        .custom("Bookerly", size: size).weight(weight)
    }

    /// Body size used in chat bubbles and streaming text.
    /// Fixed size on both platforms so it stays in sync with the Markdown
    /// theme's FontSize(17) / FontSize(16), which are also absolute.
    #if os(iOS)
    static let chatBody: Font = .system(size: 17)
    #else
    static let chatBody: Font = .system(size: 16)
    #endif
}

// ── Markdown theme ────────────────────────────────────────────────────────────

extension MarkdownUI.Theme {
    /// App-wide Markdown theme: system body font, adaptive warm palette.
    static let app: Self = .gitHub
        .text {
            #if os(iOS)
            FontSize(17)
            #else
            FontSize(16)
            #endif
            ForegroundColor(Color.textPrimary)
        }
        .link {
            ForegroundColor(Color.accent)
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
                content: cfg.content,
                label: AnyView(cfg.label)
            )
        }
}
