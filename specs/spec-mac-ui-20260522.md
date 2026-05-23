# Mira macOS UI Specs — 2026-05-22

Four self-contained specs. Implement one at a time; build-check before moving on.
Inspiration: Claude Desktop screenshots (images 2–5 from session).

---

## Spec M1 — macOS markdown & code rendering

**Problem:** `macOSMessageText` in `MessageBubble.swift` uses `AttributedString` with
`.inlineOnlyPreservingWhitespace`. Block markdown (headings `###`, bullet lists `*`,
numbered lists, horizontal rules, tables) is stripped and rendered as raw characters.

**Fix:** Mirror the iOS `MessageContentView` split approach on macOS.

### Changes — `MessageBubble.swift`

Replace `macOSMessageText` (currently ~10 lines, `#else` branch of `renderedMessageText`):

```
private var macOSMessageText: some View {
    // Reuse the same segment parser iOS uses
    let segments = parseMessageSegments(preprocessLatex(message.content))
    return VStack(alignment: .leading, spacing: 8) {
        ForEach(Array(segments.enumerated()), id: \.offset) { _, seg in
            switch seg {
            case .text(let prose):
                macOSProse(prose)
            case .codeBlock(let lang, let code):
                CopyableCodeBlock(language: lang, content: code)
            }
        }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
}

private func macOSProse(_ prose: String) -> some View {
    let trimmed = prose.trimmingCharacters(in: .newlines)
    guard !trimmed.isEmpty else { return AnyView(EmptyView()) }
    let attr = (try? AttributedString(
        markdown: trimmed,
        options: .init(interpretedSyntax: .full)
    )) ?? AttributedString(trimmed)
    return AnyView(
        Text(attr)
            .font(.chatBody)
            .foregroundStyle(Color.textPrimary)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    )
}
```

**Note:** `CopyableCodeBlock` already exists in `InlineCode.swift` and is platform-agnostic;
no guard needed. `parseMessageSegments` and `preprocessLatex` are file-scope functions
in `InlineCode.swift`, already compiled for both platforms.

**Streaming:** Leave the streaming branch (`message.isStreaming`) unchanged — it already
renders raw text with the blinking cursor. Formatting applies only after streaming ends.

---

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

1. **Background:** Remove `.background(Color.sidebarBg)` from the outer container.
   Replace with `.background(.clear)` — the `NavigationSplitView` sidebar column
   applies the system sidebar material automatically on macOS.

2. **Selected row highlight:** Locate the `listRowBackground` for selected conversation
   rows (currently using `Color.appAccent.opacity(...)` or similar amber fill).
   Replace with:
   ```swift
   .listRowBackground(isSelected ? Color.primary.opacity(0.08) : Color.clear)
   ```

3. **Project tag chips:** The colored tag labels on conversation rows (e.g. "python-stuff",
   "mira-core" in orange rounded capsules — visible in Image 1) add visual noise.
   Remove the tag chip row entirely from `conversationRow`. Project membership is
   already communicated by the Projects section grouping.

4. **Timestamps:** Keep relative timestamps ("1 day ago") — they match Claude Desktop.
   Reduce font to `Font.sidebarSubtitle` (already defined in Theme.swift).

5. **"New Chat" button:** Keep existing placement; change background from amber fill to
   `Color.primary.opacity(0.08)` with `Color.textPrimary` label — neutral pill, not
   orange. (Claude Desktop: white pill, dark text.)

### Changes — `Theme.swift`

No `sidebarBg` value changes needed — we remove its usage on macOS. iOS sidebar
already uses it correctly (dark overlay slide-in); leave the iOS path unchanged.

---

## Spec M3 — macOS "+" as a popover (not a sheet)

**Problem:** The InputBar `+` button opens a `.sheet` on macOS. A centered modal sheet
is heavy UX for a quick options menu. Claude Desktop (Image 4) uses a contextual
popover anchored to the `+` button — compact, dismissible by clicking away.

### Changes — `InputBar.swift`

1. Replace the macOS branch of `.sheet(isPresented: showAddToChat)`:

   **Before (macOS):**
   ```swift
   .sheet(isPresented: showAddToChat) {
       addToChatSheet
   }
   ```

   **After (macOS):**
   ```swift
   .popover(isPresented: showAddToChat, arrowEdge: .top) {
       addToChatPopoverMac
           .frame(width: 280)
   }
   ```

2. Add `addToChatPopoverMac` view (macOS-only, place after `addToChatSheet`):
   ```swift
   #if os(macOS)
   private var addToChatPopoverMac: some View {
       VStack(spacing: 0) {
           addToChatRow(icon: "paperclip", label: "Files & Images", trailing: nil) {
               // same file-picker trigger as current macOS sheet
               Task { await vm.pickFile() }
               showAddToChat.wrappedValue = false
           }
           Divider()
           addToChatRow(
               icon: vm.thinkingEnabled ? "brain.fill" : "brain",
               label: "Thinking",
               trailing: AnyView(Toggle("", isOn: $vm.thinkingEnabled).labelsHidden())
           ) { }
       }
       .padding(.vertical, 4)
   }
   #endif
   ```

   The existing `addToChatRow` helper already exists and accepts icon + label + trailing
   AnyView. No new helpers needed.

3. The existing `addToChatSheet` (full-screen sheet style, macOS) remains in the file
   but is no longer presented — it can be cleaned up in a future pass.

**Behavior:** Clicking `+` anchors a popover just above the button. Clicking outside
dismisses it. No modal overlay.

---

## Spec M4 — Thinking toggle in model picker

**Problem:** `ModelPickerView` only offers model switching (omlx / ollama backends).
Claude Desktop (Image 5) surfaces an "Adaptive thinking" toggle directly in the
model picker dropdown — one place for all inference settings.

### Changes — `ModelPickerView.swift`

The `modelListView` private var currently lists model rows. Add a thinking row after the
list, separated by a Divider.

Locate `modelListView` (approx line 100+). At the end of its `VStack`, append:

```swift
Divider()
    .padding(.horizontal, 16)

// Thinking toggle row
HStack(spacing: 12) {
    VStack(alignment: .leading, spacing: 2) {
        Text("Thinking")
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(Color.textPrimary)
        Text("Reasons before answering")
            .font(.system(size: 12))
            .foregroundStyle(Color.textSecondary)
    }
    Spacer()
    Toggle("", isOn: $thinkingEnabled)
        .labelsHidden()
        .tint(Color.appAccent)
}
.padding(.horizontal, 20)
.padding(.vertical, 12)
```

**ModelPickerView needs a new binding:**
```swift
@Binding var thinkingEnabled: Bool
```

Update all call sites that create `ModelPickerView` to pass `thinkingEnabled: $vm.thinkingEnabled`.

**Grep for call sites:**
```bash
grep -rn "ModelPickerView(" OllamaSearch/
```

**Effect:** The thinking chip in `InputBar` (shows "Thinking" when on, tap to dismiss)
continues to work as a quick status indicator. The picker toggle is the primary
persistent control on macOS.

---

## Implementation order

1. M1 (markdown) — isolated to `MessageBubble.swift`, no state changes, low risk
2. M4 (thinking toggle in picker) — small binding addition, clear scope
3. M3 (popover) — replaces a sheet presentation, macOS-only
4. M2 (sidebar) — most visual surface area; do last so M1–M3 are stable first
