# Backlog

## Upcoming (prioritized)

1. **[BLOCKER] macOS prose rendering** — see Known bugs above; fix before any release
2. **iPad layout** — verify conversation list and detail pane on iPad-sized simulator
3. **Project conversation count** — badge on project rows; verify accuracy after delete

## Known bugs

- **[OPEN — 2026-05-22] macOS markdown prose rendering broken** — After today's session, assistant messages on macOS show paragraphs running together with no blank-line separation, bold definition items (e.g. `**Label**: text`) not separated, and `$\to$` LaTeX tokens not converted (only `$\rightarrow$` is in `preprocessLatex`). Tables render correctly (confirmed). Text selection works via NSTextView. The last attempted fix (2026-05-22 end of session) was changing the block separator in `buildAttr()` from `\n` + `paragraphSpacing:10` to `\n\n` — **not yet tested** as of commit. Root cause analysis: `paragraphSpacing` on a trailing `\n` is ignored by NSLayoutManager (it reads paragraph attributes from the first character of the paragraph, not the last). The `\n\n` fix creates an empty paragraph for visual spacing instead. If this still doesn't work, the likely next approach is using Swift `AttributedString(markdown:)` for the full joined content instead of per-block `NSAttributedString(markdown:)`. See `MessageBubble.swift` — `SelectableTextMacOS.buildAttr()` and `paragraphBlocks()`.

## Notes

- Full history of completed work: `git log --oneline`
- Release history: `.claude/projects/.../memory/backlog_testflight.md`
- Workflow and development practices: `WORKFLOW.md`
- Color.appAccent is canonical amber — never use Color.accent (SwiftUI redeclaration conflict)
- iOS message rendering: `MessageContentView` splits content into prose (`SelectableText` / UITextView) and fenced code blocks (`CopyableCodeBlock`). Prose gets real cursor/drag selection; code blocks have syntax highlight + copy button.
- waitingMessages: 100 entries in ChatViewModel, shown after 3s, rotates every 6s
- reconnectMessages: 103 entries in OllamaSearchApp (iOS), shown during startReconnect()
- sidebarPinned defaults to true — never auto-hides unless user clicks pin icon
- projectsExpanded (@AppStorage) persists projects section collapse state across launches
- caffeinate: server.py spawns `caffeinate -i -s -w <own_pid>` on startup; exits automatically with server
- App forces `.preferredColorScheme(.dark)` on both platforms — light mode palette exists in Theme.swift but is never shown
- startReconnect() flow: quick 2s probe → if ok, silent; if fail → banner polls startupStatus() every 2s for 90s; 503 = stay on URL (Ollama loading); unreachable = try other saved connections; on success: banner clears, loadConversations() called
- TransparentTitleBar uses NSViewRepresentable + DispatchQueue.main.async to access NSWindow after view is in hierarchy — do not simplify away
- iOS 26+ icon system: universal entry = light default; `luminosity: dark` for dark mode; `luminosity: tinted` for tinted; all three needed
- macOS icon PNGs are not adaptive (no light/dark variants) — expected macOS behavior
