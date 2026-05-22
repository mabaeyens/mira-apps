# Mira Apps — Claude Code Reference

Native apps (iOS + macOS) for Mira. See `workflow.md` for session guidance and `../MIRA_WORKFLOW.md` for complete development workflow.

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

See `workflow.md` for full pattern reference and sibling app cross-checks.

## Build Targets

- `OllamaSearch` (main scheme) — iOS + macOS
- Destinations: iOS Simulator, macOS, iPhone Miguel (sideload via id=68256925-7395-58B9-BC9C-7A403153C7CB)

## Validation & Release

Before any release:
1. Run `/mira-validate` — builds simulator + sideloads to device
2. Manual smoke check (2 min): launch, open conversation, send message, check specific feature
3. Run `/mira-release` — bumps version, archives both platforms, uploads to TestFlight

**Release cadence:** One per week (Friday or Monday). See section 7 of `../MIRA_WORKFLOW.md`.

## Workflow Reference

See `../MIRA_WORKFLOW.md` for:
- Session checklist and 5-bullet spec format (section 2)
- Validation before releasing (section 5)
- Release cadence (1 per week, section 7)
- Monthly security audit (section 6)
- Token efficiency tips (sections 1 and 8)

## File Sizes

Large files consume context — use `grep` before `Read`:
- `OllamaSearchApp.swift` — ~580 lines
- `ConversationListView.swift` — ~480 lines

Example:
```bash
grep -n "func handleSend" OllamaSearchApp.swift  # Find line number
# Then Read with offset: line 245–260 (just the function, not the whole file)
```
