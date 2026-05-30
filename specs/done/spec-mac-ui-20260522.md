# Mira macOS UI Specs — 2026-05-22

## Spec M2 — macOS sidebar neutral styling

**Problem:** The macOS sidebar uses `Color.sidebarBg` (`0x292524` — warm dark brown),
which adds heavy color contrast. Claude Desktop sidebar is near-neutral: no tint,
white/system background, items are plain text rows with minimal selection indicator.

### Goal (reference: Claude Desktop image 3)
- Sidebar background: system default (`NSColor.windowBackgroundColor` equivalent)
- Conversation rows: title + relative timestamp; no colored tag chips
- Section headers (CONVERSATIONS, PROJECTS): light gray, small caps, no heavy weight
- Selected row: subtle fill (`.quinary` or `.fill.tertiary`), no amber/orange
- No row separators visible — `.listStyle(.sidebar)` already suppresses them

### Changes — `ConversationListView.swift`

1. **Background:** Line 46 (macOS `#else` branch) — replace `.background(Color.sidebarBg)`
   with `.background(.clear)`. The `NavigationSplitView` sidebar column applies system
   sidebar material automatically on macOS.
   Also remove `sidebarBg` on lines 385 and 411 (both inside `#if os(macOS)` blocks).

2. **Selected row highlight:** Locate the `listRowBackground` for selected conversation
   rows (currently using `Color.appAccent.opacity(...)` or similar amber fill).
   Replace with:
   ```swift
   .listRowBackground(isSelected ? Color.primary.opacity(0.08) : Color.clear)
   ```

3. **Project tag chips:** Remove the tag chip row from `conversationRow`. Project
   membership is already communicated by the Projects section grouping.

4. **Timestamps:** Keep relative timestamps ("1 day ago"). Reduce font to
   `Font.sidebarSubtitle` (already defined in Theme.swift).

5. **"New Chat" button:** Change background from amber fill to
   `Color.primary.opacity(0.08)` with `Color.textPrimary` label — neutral pill.

### Changes — `Theme.swift`

No `sidebarBg` value changes needed — remove its macOS usage only. iOS sidebar
already uses it correctly (dark overlay slide-in); leave iOS path unchanged.

---

*M1 (markdown rendering), M3 (+ popover), M4 (thinking toggle in picker) — done as of 2026-05-23.*
