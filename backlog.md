# Backlog

See [CHANGELOG.md](CHANGELOG.md) for recent changes.

## Pending

1. **iPad layout** — verify conversation list and detail pane on iPad-sized simulator
2. **Project conversation count** — badge on project rows; verify accuracy after delete

## Notes

- Color.appAccent is canonical amber — never use Color.accent (SwiftUI redeclaration conflict)
- Message rendering: `renderedMessageText` → `MessageContentView` splits content into segments: prose uses `Markdown(preprocessLatex())` with `.markdownTheme(.app)` (full block-level rendering), fenced code uses `CopyableCodeBlock`, GFM tables use `MarkdownTableBlock` (horizontally scrollable, 160pt columns). Long-press → Copy on assistant bubbles copies the full raw message.
- Only "Sending…" / "Thinking…" shown; blinking cursor provides activity feedback
- reconnectMessages: 103 entries in OllamaSearchApp (iOS), shown during startReconnect()
- sidebarPinned defaults to true — never auto-hides unless user clicks pin icon
- projectsExpanded (@AppStorage) persists projects section collapse state across launches
- caffeinate: server.py spawns `caffeinate -i -s -w <own_pid>` on startup; exits automatically with server
- App forces `.preferredColorScheme(.dark)` on both platforms — light mode palette exists in Theme.swift but is never shown
- startReconnect() flow: quick 2s probe → if ok, silent; if fail → banner polls startupStatus() every 2s for 90s; 503 = stay on URL (Ollama loading); unreachable = try other saved connections; on success: banner clears, loadConversations() called
- TransparentTitleBar uses NSViewRepresentable + DispatchQueue.main.async to access NSWindow after view is in hierarchy — do not simplify away
- iOS 26+ icon system: universal entry = light default; `luminosity: dark` for dark mode; `luminosity: tinted` for tinted; all three needed
- macOS icon PNGs are not adaptive (no light/dark variants) — expected macOS behavior
