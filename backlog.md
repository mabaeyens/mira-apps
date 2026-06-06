# Backlog

See [CHANGELOG.md](CHANGELOG.md) for recent changes.

## Done

- [2026-06-06] Shipped v0.1.38 to TestFlight — macOS seamless sidebar, sidebar toggle, New Chat at bottom, blank-on-open scroll fix
- [2026-06-06] Fixed blank conversation view on all platforms using `defaultScrollAnchor(.bottom)` (LazyVStack was not rendering bottomAnchor before scrollTo fired)
- [2026-06-06] Replaced NavigationSplitView with HStack(spacing:0) — eliminates 1pt column divider; sidebar and detail share Color.appBg
- [2026-06-06] Added sidebar toggle button (sidebar.left) with 0.25s slide animation
- [2026-06-06] Moved New Chat button to sidebar bottom (macOS), matching iOS layout; added bottom-fade mask
- [2026-06-06] Wired ASC API key into ExportOptions plists — xcodebuild no longer falls back to expiring Apple ID session; real plists gitignored, templates committed
- [2026-06-06] Purged Bookerly font files from entire git history (git filter-repo); force-pushed

## Pending

1. **iPad layout** — verify conversation list and detail pane on iPad-sized simulator
2. **Project conversation count** — badge on project rows; verify accuracy after delete
3. **Vera release** — held; Vera has unresolved issues; do not release until separately confirmed

## Notes

- Color.appAccent is canonical amber — never use Color.accent (SwiftUI redeclaration conflict)
- Message rendering: `renderedMessageText` → `MessageContentView` splits content into segments: prose uses `Markdown(preprocessLatex())` with `.markdownTheme(.app)` (full block-level rendering), fenced code uses `CopyableCodeBlock`, GFM tables use `MarkdownTableBlock` (horizontally scrollable, 160pt columns). Long-press → Copy on assistant bubbles copies the full raw message.
- Only "Sending…" / "Thinking…" shown; blinking cursor provides activity feedback
- reconnectMessages: 103 entries in OllamaSearchApp (iOS), shown during startReconnect()
- sidebarPinned defaults to true — never auto-hides unless user clicks pin icon
- projectsExpanded (@AppStorage) persists projects section collapse state across launches
- ExportOptions-iOS.plist and ExportOptions-macOS.plist are gitignored; copy from *.plist.template and fill in authenticationKeyID, authenticationKeyIssuerID, authenticationKeyPath before first use on a new machine
- macOS sidebar uses HStack(spacing:0) not NavigationSplitView — no column divider API needed; sidebar visibility controlled by @State showSidebar in MacRootView
- LazyVStack + scrollTo race: bottomAnchor is outside the initial viewport, so scrollTo silently fails. Fix: .defaultScrollAnchor(.bottom) on the ScrollView — renders cells from the bottom up on first appearance
- caffeinate: server.py spawns `caffeinate -i -s -w <own_pid>` on startup; exits automatically with server
- App forces `.preferredColorScheme(.dark)` on both platforms — light mode palette exists in Theme.swift but is never shown
- startReconnect() flow: quick 2s probe → if ok, silent; if fail → banner polls startupStatus() every 2s for 90s; 503 = stay on URL (Ollama loading); unreachable = try other saved connections; on success: banner clears, loadConversations() called
- TransparentTitleBar uses NSViewRepresentable + DispatchQueue.main.async to access NSWindow after view is in hierarchy — do not simplify away
- iOS 26+ icon system: universal entry = light default; `luminosity: dark` for dark mode; `luminosity: tinted` for tinted; all three needed
- macOS icon PNGs are not adaptive (no light/dark variants) — expected macOS behavior
