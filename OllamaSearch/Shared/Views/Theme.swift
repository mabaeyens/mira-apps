import SwiftUI

// ── Claude-inspired warm brown palette (Tailwind stone scale) ─────────────────
//
//  stone-900  #1C1917  main window background
//  stone-800  #292524  sidebar background
//  stone-700  #44403C  user bubble background
//  stone-600  #57534E  subtle borders
//  stone-400  #A8A29E  secondary text
//  stone-50   #FAFAF9  primary text
//  amber      #D09268  brand accent

extension Color {
    static let appBg         = Color(hex: 0x1C1917)
    static let sidebarBg     = Color(hex: 0x292524)
    static let userBubbleBg  = Color(hex: 0x44403C)
    static let surfaceBg     = Color(hex: 0x232120)
    static let borderSubtle  = Color(hex: 0x57534E)
    static let accent        = Color(hex: 0xD09268)
    static let textPrimary   = Color(hex: 0xFAFAF9)
    static let textSecondary = Color(hex: 0xA8A29E)

    init(hex: UInt32) {
        self.init(
            red:   Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8)  & 0xFF) / 255,
            blue:  Double( hex        & 0xFF) / 255
        )
    }
}
