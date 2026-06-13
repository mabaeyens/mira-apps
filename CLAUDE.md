# Mira Apps — Claude Code Reference

Native apps (iOS + macOS) for Mira.

## Project Stack

- **Platform:** iOS 17+ / macOS 14+
- **Framework:** SwiftUI
- **Backend:** FastAPI (mira-core), connects via HTTPClient
- **Architecture:** MVVM with @Observable

## Entry Points

- **iOS:** `OllamaSearch/App.swift` → `iOSRootView.swift` (NavigationStack for iPhone, NavigationSplitView for iPad)
- **macOS:** `OllamaSearchApp.swift` → `MacRootView.swift` (NavigationSplitView with pinned sidebar)

## Key Patterns

- **Sidebar visibility:** NavigationSplitView with pinned `columnVisibility` binding (proven in MacRootView.swift)
- **State management:** `@Observable @MainActor` for all view models
- **Connection resilience:** Backend may sleep — handle gracefully with probes and transient banners

## Build Targets

- `OllamaSearch` (main scheme) — iOS + macOS
- Destinations: iOS Simulator, macOS, physical iPhone (sideload — set device ID in Xcode)

## Validation & Release

Before any release:
1. Run `/mira-validate` — builds simulator + sideloads to device
2. Manual smoke check (2 min): launch, open conversation, send message, check specific feature
3. Run `/mira-release` — bumps version, archives both platforms, uploads to TestFlight

**Release cadence:** One per week (Friday or Monday).
**Security audit:** Run `/security-review` last weekend of each month.

## Spec Format (5 bullets)

When a new bug or feature request arrives, write the spec to `specs/<slug>.md` before implementing. The `specs/` folder is gitignored (local only). Once implemented, the relevant detail moves to README or architecture docs — the spec file can then be deleted.

1. Problem: what is broken or missing
2. Files: which files to change and which functions to touch first
3. Constraint: a hard rule (don't show X if Y, match pattern Z)
4. Edge cases: (a) case 1, (b) case 2
5. Done: acceptance criteria (2–3 bullets)

## File Sizes

Large files consume context — use `grep` before `Read`:
- `OllamaSearchApp.swift` — ~580 lines
- `ConversationListView.swift` — ~480 lines

Example:
```bash
grep -n "func handleSend" OllamaSearchApp.swift  # Find line number
# Then Read with offset: line 245–260 (just the function, not the whole file)
```
