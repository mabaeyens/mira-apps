# Backlog

## Upcoming (prioritized)

1. **iPad layout** — verify conversation list and detail pane on iPad-sized simulator
2. **Project conversation count** — badge on project rows; verify accuracy after delete

## Known bugs

- **[FIXED — 2026-05-23] Markdown tables not horizontally scrollable** — Root cause: `renderedMessageText` was calling `MarkdownUI.Markdown()` directly, completely bypassing `MessageContentView` and `MarkdownTableBlock`. All prior fix attempts were correct but dead code. Fix (9c137e2): route `renderedMessageText` → `MessageContentView`; use `Markdown()` for prose segments (preserves headings/lists/rules) and `MarkdownTableBlock` for tables; explicit `tableWidth = cols × 160pt` on VStack inside `ScrollView(.horizontal)`; removed `.textSelection(.enabled)` from table cells (UITextView gesture interception).
- **[FIXED — 2026-05-23] iOS + macOS markdown prose rendering broken** — Root cause: UITextView/NSTextView bridges introduced for text selection replaced MarkdownUI, which broke list rendering and paragraph structure. Fix: restored `MarkdownUI.Markdown()` with `.markdownTheme(.app)` in `renderedMessageText`; removed `.textSelection(.enabled)` (caused pasteboard crash on iOS); copy is now via long-press context menu on both platforms using `UIPasteboard`/`NSPasteboard` directly.

## Notes

- Full history of completed work: `git log --oneline`
- Release history: `.claude/projects/.../memory/backlog_testflight.md`
- Workflow and development practices: `WORKFLOW.md`
- Color.appAccent is canonical amber — never use Color.accent (SwiftUI redeclaration conflict)
- Message rendering: `renderedMessageText` → `MessageContentView` splits content into segments: prose uses `Markdown(preprocessLatex())` with `.markdownTheme(.app)` (full block-level rendering), fenced code uses `CopyableCodeBlock`, GFM tables use `MarkdownTableBlock` (horizontally scrollable, 160pt columns). `SelectableText` struct in MessageBubble.swift is now dead code — safe to remove later. Long-press → Copy on assistant bubbles copies the full raw message.
- waitingMessages removed (bde4bc5) — only "Sending…" / "Thinking…" shown; blinking cursor provides activity feedback
- reconnectMessages: 103 entries in OllamaSearchApp (iOS), shown during startReconnect()
- sidebarPinned defaults to true — never auto-hides unless user clicks pin icon
- projectsExpanded (@AppStorage) persists projects section collapse state across launches
- caffeinate: server.py spawns `caffeinate -i -s -w <own_pid>` on startup; exits automatically with server
- App forces `.preferredColorScheme(.dark)` on both platforms — light mode palette exists in Theme.swift but is never shown
- startReconnect() flow: quick 2s probe → if ok, silent; if fail → banner polls startupStatus() every 2s for 90s; 503 = stay on URL (Ollama loading); unreachable = try other saved connections; on success: banner clears, loadConversations() called
- TransparentTitleBar uses NSViewRepresentable + DispatchQueue.main.async to access NSWindow after view is in hierarchy — do not simplify away
- iOS 26+ icon system: universal entry = light default; `luminosity: dark` for dark mode; `luminosity: tinted` for tinted; all three needed
- macOS icon PNGs are not adaptive (no light/dark variants) — expected macOS behavior
