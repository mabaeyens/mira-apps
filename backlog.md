# Backlog

## Done
- [2026-04-26] fix: blank screen during inference — LazyVStack deferred height computation caused scrollTo(bottomAnchor) to overshoot past actual content when new messages were appended; replaced with VStack so heights are always known before scroll is attempted
- [2026-04-26] Design/ cleanup — removed AppIcon.svg, AppIconTinted.svg, OptionA.svg, mira_icon_C.svg.png (obsolete/generated); added mira_icon_C_animated.svg (SMIL-animated, mirrors MiraLogo.swift: elliptical orbit, breathing glow, z-depth opacity)
- [2026-04-26] Press kit — created press/ folder with app-icon.svg, app-icon-1024.png, app-icon-tinted-1024.png, logomark.svg (transparent bg, amber mark), and README.md with short/long descriptions, key facts, and asset guide
- [2026-04-26] marketing.md — App Store metadata (promotional text, description, keywords, URLs), screenshot plan with caption overlays for iPhone/iPad/Mac, competitive analysis, short/medium/long-term feature backlog, and submission risk notes
- [2026-04-26] AboutView text revised — three paragraphs, added "Latin word for wonder" and "double stars", fixed second paragraph to open with "With Mira, inference runs entirely on your Mac"
- [2026-04-26] Welcome screen logo enlarged from 88→120pt on iPad new-conversation screen
- [2026-04-26] Chat body font reverted to system `.body` (17pt) on iOS — was hardcoded 20pt; markdown body also reverted to 17pt to match
- [2026-04-26] Fallback title on stream timeout — if server never emits a `.title` event on the first message (timeout/network drop), ChatViewModel now uses the first 60 chars of the user's prompt as the conversation title so the sidebar always shows something identifiable
- [2026-04-25] Claude Code allowlist expanded — added compound git command patterns (status+diff, pull+add+status, push+echo) so mira-core wrap/status commands run without permission prompts
- [2026-04-25] Architecture docs — created docs/diagram.md (5 Mermaid diagrams: system overview, turn lifecycle, cancel flow, RAG pipeline, iOS/macOS connection flows); updated docs/architecture.md in mira-core with missing events (title, compress, heartbeat), context compression section, full endpoint reference table, and iOS/macOS client integration section
- [2026-04-25] Code audit LOW fixes — force-unwrap comment (A9), cancel error logging via OSLog (A10), HTTP non-localhost warning in ConnectionView (A11), owner/repo regex validation in AddProjectSheet (A12), cursor blink replaced with TimelineView (A13), Swift package upper-bound pins (A14), search debounce 200ms (A15)
- [2026-04-25] Claude Code allowlist expanded — added cd * && git status/diff/log/cat patterns to .claude/settings.json so wrap/status commands run without permission prompts
- [2026-04-25] Code audit MEDIUM fixes — file I/O moved to background tasks (A2/A3), unknown SSE events logged (A5), multipart boundary hardened + filenames percent-encoded (A6), role string replaced with exhaustive switch (A8), token stats batched (A4)
- [2026-04-25] Security hardening — resolved all HIGH issues identified in code audit
- [2026-04-25] Claude Code skills created and documented — mira-release (full TestFlight pipeline), mira-server (LaunchAgent management), mira-status (cross-project warm start); .claude/settings.json and settings.local.json committed
- [2026-04-25] AboutView: always full-sheet with X close button — removed presentationDetents from both iOS sheet call sites; added xmark.circle.fill dismiss button via ZStack overlay
- [2026-04-25] mira-core /ask endpoint — ephemeral one-shot POST to Gemma4/Ollama, no conversation saved, no tools, no DB writes; accepts optional system prompt; enables Claude Code orchestration delegation
- [2026-04-25] Active project pill in chat header — amber capsule above input bar shows folder/network icon + project name; visible only when conversation has an active project; `vm.activeProject` drives it with no extra state
- [2026-04-25] Project picker UI — Projects section in sidebar, tap to start scoped chat, Add Project sheet (name + local path + GitHub repo), project badge on conversation rows, loadProjects on startup
- [2026-04-25] TestFlight build — v0.1.4 (build 4) shipped to devices
- [2026-04-25] Obsidian — confirmed keep as-is (free for local use; open vault pointing at ~/.claude/ or project dirs)
- [2026-04-25] macOS: server startup UX — /health returns 503 during Ollama warm-up (up to 25s); macOS splash polls for 60s, shows "Starting Ollama…" on 503 vs "Connecting…" on unreachable; first chat can no longer silently fail before model is ready
- [2026-04-25] iOS: new-chat button — square.and.pencil toolbar button in detail pane calls newConversation(); equivalent to macOS New Chat menu command
- [2026-04-25] Both: inline image thumbnails — Message.imageAttachments: [Data] populated on send; MessageBubble renders 120×120 thumbnails above text in user bubbles on iOS and macOS
- [2026-04-25] Both: conversation search — .searchable() on sidebar list, client-side filter on title, works on iOS and macOS with no server changes
- [2026-04-25] iOS: conversation rename — swipe-left reveals Rename action, context-menu also has Rename; alert pre-fills current title; PATCH /conversations/{id} endpoint added to server.py; renameConversation wired through APIClient → ChatViewModel → ConversationListView
- [2026-04-25] Fix Ollama startup race condition — server.py lifespan pre-warm now retries up to 5× with 5s delay so model loads even when Ollama starts after the server on login
- [2026-04-25] Removed © copyright notice from AboutView — app doesn't need it
- [2026-04-25] GitHub repos already structured as local folders (mira-apps, mira-core) — no restructure needed
- [2026-04-25] Removed Bonjour/mDNS discovery from iOS ConnectionView — replaced with saved connections only; fixed IP via DHCP reservation makes auto-discovery redundant; eliminates 12-second timeout and "No server found" failures
- [2026-04-25] iOS TestFlight upload aligned to v0.1.2 build 2 — matched macOS; fixed ExportOptions-iOS.plist and ExportOptions-macOS.plist to include `destination: upload` so future CLI releases upload directly without Xcode Organizer
- [2026-04-25] iOS/macOS font sizes: chat body 16→20pt on iOS, markdown theme updated to match, status bar badges 11→13pt; macOS unchanged
- [2026-04-25] iOS URL switcher: ConnectionView replaced with list-based UI — saved connections (tap to connect, swipe to delete), Bonjour row, Add sheet; SavedConnectionsStore persists to UserDefaults with migration from old localURL/remoteURL keys; autoConnect() updated to use saved connections
- [2026-04-25] server shell sandbox: run_shell now rejects commands referencing absolute paths outside WORKSPACE_ROOT (e.g. ls /, cat /etc/passwd), closing gap where cwd was sandboxed but command arguments were not
- [2026-04-25] server prompt: added Rule 1 — model must answer capability questions from the system prompt without calling tools (fixes model calling list_files/run_shell when asked "what tools do you have?")
- [2026-04-25] mira-release skill: rewritten to automate full TestFlight pipeline — xcodebuild clean archive + export/upload for iOS and macOS from the command line; ExportOptions-iOS.plist fixed (method: app-store → app-store-connect)
- [2026-04-25] ITSAppUsesNonExemptEncryption = NO added to Info.plist — eliminates App Store Connect encryption compliance question permanently for both platforms
- [2026-04-25] Color.accent renamed to Color.appAccent — fixes build failure on Xcode 26.4 where SwiftUI auto-generates Color.accent from the AccentColor asset, causing a redeclaration conflict
- [2026-04-25] iOS app icon: explicit dark variant points to same PNG as universal — light and dark modes show identical icon; tinted stays separate
- [2026-04-25] macOS SplashView: transparent title bar (no visible seam) + radial gradient background matching app icon (#272220 center → #1C1917 edge)
- [2026-04-25] AccentColor.colorset filled with amber (#D09268 dark / #C07A4F light) — was empty, system controls were getting default blue tint
- [2026-04-25] Bump version 0.1.2 (build 2) — macOS thin-client rearchitecture (launchd LaunchAgent)

## Pending


## Notes
- Claude Code ↔ Mira orchestration: Claude delegates simple tasks (summarization, classification, drafts) to Mira via `POST /ask`. Gemma4 handles easy work; Claude keeps multi-step reasoning and complex tool chains. Invoke: `curl -s -X POST http://localhost:8000/ask -H "Content-Type: application/json" -d '{"prompt":"...","system":"..."}'`
- /ask is intentionally tool-free and stateless — do not add tool dispatch to it; use /chat for agentic turns
- Project model lives in Conversation.swift (not a separate file) to avoid project.pbxproj changes; same for AddProjectSheet in ConversationListView.swift
- `vm.activeProject` is a computed property derived from currentConvId + conversations + projects — no extra state needed, automatically tracks conversation switches
- iOS server connection: Bonjour removed in favour of saved connections + DHCP reservation on TP-Link AX73. Add Tailscale hostname as a second saved connection when remote access is needed.
- mira-core shell_tools.py: `run_shell` sandbox now rejects absolute paths outside WORKSPACE_ROOT; also added prompt Rule 1 (capability questions answered from system prompt, no tool calls). Server must be restarted after these changes — use `/mira-server restart`.
- SavedConnectionsStore migrates old `localURL` / `remoteURL` UserDefaults keys on first run; both keys are still written by legacy code paths but are no longer the source of truth for autoConnect().
- Color.appAccent is the canonical brand amber in Theme.swift — do not use Color.accent (now auto-generated by SwiftUI from AccentColor asset and will conflict).
- App forces `.preferredColorScheme(.dark)` on both iOS and macOS — light mode palette exists in Theme.swift but is never shown; `Design/AppIconLight.svg` was deleted (was never used)
- TransparentTitleBar uses NSViewRepresentable + DispatchQueue.main.async to access NSWindow after view is in hierarchy — standard macOS pattern, do not simplify away
- iOS 26+ icon system: universal entry = light mode default; explicit `luminosity: dark` for dark mode; `luminosity: tinted` for tinted. All three needed for full coverage.
- macOS icon PNGs are not adaptive (no light/dark variants) — expected macOS behavior
