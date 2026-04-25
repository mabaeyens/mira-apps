# Backlog

## Done
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


## Pending
- Show active project in chat view header — a small pill above the input bar confirms which project is active; `vm.activeProject` is already computed and ready to use
- Step 4: github_clone_repo tool + "Clone repo as project" action in AddProjectSheet

## Notes
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
