# Mira Visual Elements Glossary

A reference map of plain-English UI names to their Swift/SwiftUI component names, with the exact file location in the codebase.

---

## Chat screen

### Input bar
**Swift name:** `InputBar` (`OllamaSearch/Shared/Views/InputBar.swift`)

The two-row card pinned to the bottom of the chat screen. The top row is the text field; the bottom row holds the + button, chips, model pill, and the send/stop button.

### Text field ("Message…")
**Swift name:** `TextField("Message…", text: $vm.inputText, axis: .vertical)` inside `InputBar`

The multi-line text area where you type your message. Grows vertically up to 6 lines, then scrolls. Sits in the top row of the input bar.

### Send button / Stop button
**Swift name:** `actionButton` computed property inside `InputBar`

The circle-backed icon button at the bottom-right of the input bar. Shows an up-arrow (send) when idle, a red stop square while streaming.

### Model pill
**Swift name:** Unnamed `HStack` + `Capsule` inside `InputBar`, bottom-right before the send button

Displays the active model name (e.g. "llama3.2") with a colored status dot (green = ready, yellow = loading, red = error). Non-interactive — read-only indicator.

### Project chip
**Swift name:** Unnamed `HStack` + `Capsule` inside `InputBar`, bottom-left area

Shows the name of the active project (e.g. "Work docs"). Visible only when a project is assigned to the conversation.

### Thinking chip
**Swift name:** Unnamed `HStack` + `Capsule` inside `InputBar`, bottom-left area

Shows a brain icon + "Thinking" label. Visible only when extended thinking is enabled. Tap it to turn thinking off.

### Attachment chip
**Swift name:** `attachmentChip(name:index:)` inside `InputBar`

A capsule showing a staged file's name with a dismiss × button. Displayed in a horizontal scroll row above the input bar card when one or more files are attached.

---

## Message list

### Message bubble
**Swift name:** `MessageBubble` (`OllamaSearch/Shared/Views/MessageBubble.swift`)

The rounded-rectangle container wrapping each message. User bubbles (your text) have a distinct background color; assistant bubbles render markdown inline.

### Code block
**Swift name:** `CopyableCodeBlock` inside `InlineCode.swift`

A card with a header row (language label + Copy button) above a horizontally-scrollable `HighlightedCodeView`. The header stays pinned — only the code area scrolls. Font: Menlo 16pt.

### Table block
**Swift name:** `MarkdownTableBlock` (`OllamaSearch/Shared/Views/InlineCode.swift`)

A bordered, rounded-corner block with a shaded header row and alternating-stripe data rows. Horizontally scrollable — long rows scroll right without wrapping.

---

## Sidebar

### Sidebar
**Swift name:** `ConversationListView` (`OllamaSearch/Shared/Views/ConversationListView.swift`)

The overlay panel that slides in from the left on iPhone (or the fixed left column on iPad/Mac). Contains the Mira header, a search field, the Projects disclosure group, and the Recents list.

### Conversation row
**Swift name:** Unnamed `Button` inside the `List` in `ConversationListView`

A tappable row in the Recents section showing the conversation title and relative timestamp. Tap to open that conversation.

### Project row
**Swift name:** `projectRow` or the `DisclosureGroup` header in `ConversationListView`

Collapsible section header in the Projects area. Shows the project name and icon; tapping it expands/collapses its conversation list.

---

## Global

### Welcome screen
**Swift name:** `WelcomeView` (referenced in `OllamaSearchApp.swift`)

The empty-state screen shown when no conversation is loaded — first launch or after tapping + New Chat.

### Reconnect banner
**Swift name:** Unnamed `HStack` overlay in `ChatView` / `iOSPortraitView`

A transient banner at the top of the chat area that shows a patience message while the backend is reconnecting.
