# Backlog

## Done
- [2026-04-25] iOS app icon: explicit dark variant points to same PNG as universal — light and dark modes show identical icon; tinted stays separate
- [2026-04-25] macOS SplashView: transparent title bar (no visible seam) + radial gradient background matching app icon (#272220 center → #1C1917 edge)
- [2026-04-25] AccentColor.colorset filled with amber (#D09268 dark / #C07A4F light) — was empty, system controls were getting default blue tint
- [2026-04-25] Bump version 0.1.2 (build 2) — macOS thin-client rearchitecture (launchd LaunchAgent)

## Pending
- Restructure GitHub repos according to architecture: server.py LaunchAgent, ollama-web frontend/server, OllamaSearch mobile apps
- Automate Xcode and App Store distribution (certificates, encryption entitlements)
- Remove (c) copyright notice
- Make repos available through Obsidian
- Fix Ollama API connection refused error on startup (Ollama not running race condition)
- iOS: conversation delete / rename (swipe-to-delete, tap-to-rename in sidebar)
- iOS: reset / clear current chat button (web UI has one, iOS doesn't)
- Both: conversation search / filter in sidebar
- Both: inline image thumbnail preview in chat bubbles
- macOS: server startup UX — silent failure when Ollama isn't running

## Notes
- App forces `.preferredColorScheme(.dark)` on both iOS and macOS — light mode palette exists in Theme.swift but is never shown; `Design/AppIconLight.svg` is unused (can be deleted)
- TransparentTitleBar uses NSViewRepresentable + DispatchQueue.main.async to access NSWindow after view is in hierarchy — standard macOS pattern, do not simplify away
- iOS 26+ icon system: universal entry = light mode default; explicit `luminosity: dark` for dark mode; `luminosity: tinted` for tinted. All three needed for full coverage.
- macOS icon PNGs are not adaptive (no light/dark variants) — expected macOS behavior
