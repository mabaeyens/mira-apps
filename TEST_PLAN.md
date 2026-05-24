# Mira Test Plan

Reusable checklist for pre-release validation. Run before every TestFlight archive.
Each release gets its own dated section at the top (newest first).

---

## v0.1.32 — 2026-05-24

### 1. iPad Layout

**Goal:** Confirm `NavigationSplitView` renders correctly on iPad.

Steps:
- [ ] Open Xcode, select an iPad simulator (e.g. iPad Pro 13")
- [ ] Launch the app
- [ ] Verify: conversation list on the left column, chat detail on the right
- [ ] Tap a conversation in the list — detail panel updates without pushing the list off-screen
- [ ] Rotate to portrait — layout degrades gracefully (list collapses or overlays)

Expected: Two-column layout in landscape; no blank detail pane on cold launch.

---

### 2. Agent Step Indicator

**Goal:** Confirm "Step N/15 · toolname" activity row appears during an agentic loop.

Setup: Mira server running (`python server.py` or LaunchAgent active).

Steps:
- [ ] Send a prompt that triggers tool use, e.g.: "Search the web for the latest Swift concurrency proposals and summarise the top 3"
- [ ] While the response streams, verify an activity row appears: `↻  Step 1/15 · web_search` (or similar tool name)
- [ ] Step counter increments with each tool call: Step 2/15, Step 3/15…
- [ ] Activity row disappears once the final response is complete
- [ ] Verify the response text is coherent and includes source links

Expected: Step counter visible during tool calls; clears on completion; no stale indicator left on screen.

---

### 3. Project Count Badge After Delete

**Goal:** Confirm the project badge count updates immediately after deleting a conversation.

Steps:
- [ ] In the sidebar, find a project with at least 2 conversations; note the badge count (e.g. "3")
- [ ] Delete one conversation from that project (swipe-to-delete or context menu)
- [ ] Without navigating away, verify the badge count decreases by 1 (e.g. "2")

Expected: Badge refreshes synchronously — no stale count, no manual reload needed.

---

### 4. End-to-End Agentic Loop

**Goal:** Confirm `task_done` exits the loop cleanly and the divergence guard does not false-fire.

Steps:
- [ ] Send a multi-step prompt that requires several tool calls, e.g.:
  > "Find the current Python version, check if there are any open CVEs for it, and give me a one-paragraph summary."
- [ ] Observe the activity rows: step counter increments, tool names change (search → fetch → …)
- [ ] Response completes with a coherent final answer — no truncation, no error message
- [ ] Loop exits after `task_done` — no extra tool calls after the answer appears
- [ ] Divergence guard check: repeat the same prompt a second time — response should complete normally (guard should not fire on a legitimate task)

Expected: Clean loop exit, accurate answer, no "divergence detected" or error event in the response.

---

### 5. Archive Checklist (final gate)

Run only after items 1–4 pass.

- [ ] All changes committed and pushed to `origin main`
- [ ] Xcode: Product → Clean Build Folder
- [ ] Xcode: Product → Archive (Any iOS Device destination)
- [ ] Organizer opens automatically — verify bundle version shows **0.1.32 (32)**
- [ ] Distribute App → TestFlight → upload
- [ ] Confirm build appears in App Store Connect within ~10 min

---

## Template (copy for next release)

```
## vX.Y.Z — YYYY-MM-DD

### 1. iPad Layout
- [ ] Two-column layout in landscape on iPad simulator
- [ ] Detail pane not blank on cold launch
- [ ] Portrait degrades gracefully

### 2. Agent Step Indicator
- [ ] "Step N/15 · toolname" appears during tool calls
- [ ] Clears on response completion

### 3. Project Count Badge After Delete
- [ ] Badge decrements immediately after conversation delete

### 4. End-to-End Agentic Loop
- [ ] Multi-step prompt completes with coherent answer
- [ ] No divergence guard false-fire on second run

### 5. Archive Checklist
- [ ] All changes committed and pushed
- [ ] Clean build, archive, bundle version correct
- [ ] Uploaded to TestFlight
```
