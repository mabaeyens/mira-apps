import Foundation
import Highlightr
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Shared, off-main syntax highlighter for code blocks.
///
/// Constructing a `Highlightr` builds a whole JavaScriptCore context and loads
/// highlight.js — measured at ~20 ms (see `scratchpad/hlbench`, Phase 0). The old
/// `HighlightedCodeView` did exactly that (`let h = Highlightr()`) inside a
/// `@MainActor` `.task`, on *every* appearance. Because a `LazyVStack` destroys
/// off-screen cells, scrolling re-ran it constantly on the main thread — ~26 ms per
/// block, serialized — which froze the main thread and blanked the message list
/// until the work finished (or a scroll forced a fresh layout pass).
///
/// Here one instance per theme is reused (so the ~20 ms construction is paid once),
/// highlighting runs on this actor's executor rather than the main thread, and
/// results are cached in `HighlightCache` so a re-appearance is instant. The actor
/// serializes access to the `Highlightr` instances, which own a JSContext that is
/// not safe to touch from two threads at once.
actor CodeHighlighter {
    static let shared = CodeHighlighter()

    private var light: Highlightr?
    private var dark: Highlightr?

    /// `lang` must already be a highlight.js canonical name (see
    /// `HighlightedCodeView.languageMap`). Returns nil when the engine cannot
    /// highlight it, so callers keep their plain-text fallback.
    func highlight(code: String, lang: String, dark isDark: Bool) -> AttributedString? {
        guard let engine = instance(dark: isDark),
              let ns = engine.highlight(code, as: lang)
        else { return nil }

        // Strip the theme's block background so the code sits on the app's own
        // surface colour, exactly as the old computeHighlighted() did.
        let mutable = NSMutableAttributedString(attributedString: ns)
        mutable.removeAttribute(.backgroundColor,
                                range: NSRange(location: 0, length: mutable.length))
        #if os(macOS)
        return try? AttributedString(mutable, including: \.appKit)
        #else
        return try? AttributedString(mutable, including: \.uiKit)
        #endif
    }

    private func instance(dark isDark: Bool) -> Highlightr? {
        if isDark {
            if dark == nil { dark = make(theme: "atom-one-dark") }
            return dark
        } else {
            if light == nil { light = make(theme: "atom-one-light") }
            return light
        }
    }

    private func make(theme: String) -> Highlightr? {
        let h = Highlightr()
        h?.setTheme(to: theme)
        #if os(macOS)
        h?.theme.setCodeFont(NSFont(name: "Menlo", size: 16)
            ?? NSFont.monospacedSystemFont(ofSize: 16, weight: .regular))
        #else
        h?.theme.setCodeFont(UIFont(name: "Menlo", size: 16)
            ?? UIFont.monospacedSystemFont(ofSize: 16, weight: .regular))
        #endif
        return h
    }
}

/// Main-thread result cache, read synchronously during `body` so a recycled cell
/// that was highlighted before renders instantly, with no plain-text flash. Bounded
/// LRU; only ever touched from the main actor, so it needs no locking.
@MainActor
final class HighlightCache {
    static let shared = HighlightCache()

    struct Key: Hashable {
        let code: String
        let lang: String
        let dark: Bool
    }

    private var store: [Key: AttributedString] = [:]
    private var order: [Key] = []
    private let limit = 256

    func get(_ key: Key) -> AttributedString? { store[key] }

    func set(_ key: Key, _ value: AttributedString) {
        if store[key] == nil { order.append(key) }
        store[key] = value
        while order.count > limit {
            store[order.removeFirst()] = nil
        }
    }
}
