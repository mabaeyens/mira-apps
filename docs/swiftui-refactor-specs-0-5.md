# SwiftUI Frontend Refactor — Specs 0–5 (Historical)

Landed in commit `9a31a7d` — "refactor: SwiftUI frontend refactor suite (Specs 0–5)".
All six specs were implemented together. Spec 5 was included despite its deferred status.

---

## Spec 0 — Typography Design System

**Problem:** `Theme.swift` had five font tokens but they were applied inconsistently or bypassed with hardcoded `system(size:)` values. Three manifestations: `sidebarMeta` weight differed across platforms; Bookerly title used two different sizes (36 vs 38pt) in two files; RAGPanel used conflicting caption weights for the same semantic role. Five hardcoded numeric sizes existed outside the token system, including `InlineCode` at 9pt (below Apple's 11pt readability floor).

**What changed:** Added `bookerlyTitle` (36pt fixed), `bookerlyBody`, and three icon size tokens (`iconSmall/Medium/Large`) to `Theme.swift`. Replaced all `system(size:)` call sites with named tokens or Apple dynamic type styles. Unified `sidebarMeta` to `.medium` weight everywhere. Raised `InlineCode` from 9pt → `.caption2` (11pt).

**Constraint honoured:** No visual change except the intentional InlineCode size fix. `sidebarMeta` canonical weight: `.medium`. Bookerly fixed at 36pt (no Dynamic Type scaling).

---

## Spec 1 — Lazy Message List

**Problem:** `MessageListView` rendered all messages in an eager `VStack` regardless of visibility. Long conversations caused frame drops during streaming and high memory pressure on iOS, where each bubble includes Markdown rendering and optional thinking-block disclosure groups.

**What changed:** Replaced the inner `VStack(spacing: 0)` wrapping `ForEach(messages)` with `LazyVStack(spacing: 0)`. All scroll control logic (`ScrollViewReader`, `.id("bottom")`, `proxy.scrollTo`, `isAtBottom` flag, `Color.clear` spacer) was left untouched.

**Constraint honoured:** Single-line change to the container; no modifications to `MessageBubble.swift`.

---

## Spec 2 — InputBar Decomposition

**Problem:** `InputBar.swift` was 654 lines with up to 15 nesting levels. A single `body` handled text input, attachment chips, model pill, speech recognition, project assignment, and file picking, with `#if os()` guards nested inside `ForEach` and `ZStack`.

**What changed:** Extracted rendering sections into private `@ViewBuilder` methods on the existing struct: `attachmentChipsRow()`, `textInputField()`, `bottomToolbar()`, `modelPill()`. Sheet modifiers stayed on the outermost `VStack`. No new files created. Target metrics: body depth ≤ 8 levels, file under 450 lines.

**Constraint honoured:** All `@State`, `@FocusState`, and `SpeechRecognizer` remained directly in `InputBar`. No behavioural changes.

---

## Spec 3 — Unify RAGPanel + SourcesPanel

**Problem:** `RAGPanel` (14 nesting levels) and `SourcesPanel` (12 nesting levels) implemented the same structural pattern (`DisclosureGroup → VStack → ForEach → HStack → VStack → Text`) with separate copies of the same modifier chains. The two had already diverged on truncation behaviour.

**What changed:** Created `DisclosureListPanel.swift` — a generic panel taking a `@ViewBuilder` row closure and a `Binding<Bool>` for disclosure state. Both panels replaced their bodies with calls to this component while retaining independent `@State var isExpanded`.

**Constraint honoured:** Pixel-identical output. Each panel's disclosure state remains independent.

---

## Spec 4 — Apply Text Style Modifiers

**Problem:** After Spec 0 unified font tokens, `RAGPanel`, `SourcesPanel`, `MemoriesView`, and `ConversationListView` still chained 5–8 modifiers on individual `Text` views. Future token changes would require touching dozens of call sites.

**What changed:** Created `MiraTextStyle.swift` with three `ViewModifier` structs: `.miraSecondaryCaption` (`sidebarMeta` font + `.secondary` color + `lineLimit(1)`), `.miraMetadataLabel` (`.caption.weight(.medium)` + `.secondary` + truncation), `.miraTimestamp` (`.caption2` + `.tertiary` + `.monospacedDigit()`). Applied across the four target files.

**Constraint honoured:** Modifiers wrap only typographic properties; layout modifiers stay at call sites. No token values duplicated from `Theme.swift`.

---

## Spec 5 — @Observable via @Environment (included despite deferred status)

**Problem:** `ChatViewModel` was passed as a parameter through 8+ view levels. Every property change re-evaluated the entire subtree, causing unnecessary re-renders during streaming — the root performance issue driving the whole refactor series.

**What changed:** `ChatViewModel` annotated with `@Observable` macro. Injected into the environment at `NavigationSplitView` level via `.environment(chatVM)` on both `MacRootView` and `iOSConnectedView`. Views below `ChatView` switched from `viewModel:` parameters to `@Environment(ChatViewModel.self)`. `MessageBubble` receives individual `Message` values directly, scoping re-renders to the bubble level.

**Constraint honoured:** `@EnvironmentObject` (deprecated) not used. Sheets inherit environment automatically. Both platform entry points inject the same instance.

---

## Why these were specced in order

Specs 1–4 each touched one concern in one or two files. Spec 5 rewrites the parameter interface of every shared view simultaneously — running it in parallel with the others would have produced conflicts in every file. The sequencing was: typography tokens first (Spec 0), then independent structural work (1–3), then style consolidation that depends on 0's tokens (Spec 4), then the horizontal view-model refactor last (Spec 5).
