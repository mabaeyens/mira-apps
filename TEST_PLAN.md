# Mira Test Plan

Reusable checklist for pre-release validation. Run before every TestFlight archive.
Each release gets its own dated section at the top (newest first).

---

## v0.1.35 — pending release

### 1. Offline Memory Cache

**Goal:** Memories are visible even when the Mac server is unreachable (off-LAN / cellular).

Steps:
- [ ] While on home WiFi: open Memories panel → memories load from server → disconnect from WiFi (or turn off Mac server)
- [ ] Re-open Memories panel → cached memories still appear (no error alert)
- [ ] Add a memory while online → reconnect → verify it persists server-side
- [ ] Delete a memory while online → verify removal reflected immediately

Expected: No error alert when offline; cached list shown instead. Online add/delete keep cache in sync.

---

### 2. LAN HTTPS (Certificate Pinning)

**Goal:** iOS can connect to the Mac server over LAN via HTTPS without a device trust profile.

Steps:
- [ ] In iOS Connection screen: add `https://192.168.x.x:8443` (replace with Mac's LAN IP)
- [ ] Select that connection → app connects without a certificate error or trust prompt
- [ ] Send a message — response streams correctly over HTTPS
- [ ] HTTP LAN alert: verify banner does NOT appear (connection is encrypted)
- [ ] Tailscale connection (`https://miguels-macbook-pro.tail51ad7d.ts.net:8443`) still works

Expected: Encrypted LAN connection with no user-visible cert warnings; same pinned cert works for both LAN and Tailscale hostnames.

---

### 3. Standard Checks

- [ ] Send a short message — response streams correctly (macOS + iOS)
- [ ] Memories: add → new conversation → AI reflects it

---

### 4. Archive Checklist (final gate)

Run only after items 1–3 pass.

- [ ] All changes committed and pushed to `origin main`
- [ ] Xcode: Product → Clean Build Folder
- [ ] Xcode: Product → Archive (Any iOS Device destination)
- [ ] Organizer opens automatically — verify bundle version shows correct number
- [ ] Distribute App → TestFlight → upload
- [ ] Confirm build appears in App Store Connect within ~10 min

---

## v0.1.34 — pending release

### 1. In-App Model Browser

**Goal:** Confirm model switching works end-to-end from the UI.

Steps:
- [X] Tap model pill/name in toolbar → model sheet opens
- [X] Sheet lists models with active/available indicators
- [X] Tap an inactive model → confirmation alert appears (warns ~30–60s pause) → confirm
- [X] Progress states cycle: "Stopping…" → "Starting…" → "Loading weights…" → "Almost ready…"
- [X] Chat resumes with the new model (send a message to confirm)
- [X] While switching: chat input is blocked; toolbar shows switching status

Expected: Full switch completes without crash; input re-enabled after switch.

---

### 2. iCloud Sync (M3) — setup required first

**Goal:** Confirm conversations sync between simulator and device via iCloud.

Setup (one-time, manual in Xcode):
1. Open `OllamaSearch.xcodeproj`
2. Select the `OllamaSearch` target → **Signing & Capabilities** → **+**
3. Add **iCloud** → check "Key-value storage" and "iCloud Documents"
4. Container: `iCloud.com.mab.OllamaSearch`

Steps:
- [X] iCloud capability added in Xcode (setup step above)
- [X] Create a conversation on simulator → verify it appears on iPhone Miguel (or vice versa)

Expected: Conversations visible on both simulator and device after iCloud sync.

---

### 3. Long-Term Memory (M4)

**Goal:** Confirm memories persist across conversations and the model uses them.

Steps:
- [X] Tap brain icon → Memories panel opens
- [X] Tap "+" → add a memory (e.g. "My name is Miguel") → save
- [X] Start a new conversation → ask "What's my name?" → AI answers with the saved memory
- [X] Long-press an assistant message → tap "Remember this" → sheet pre-fills → save → appears in Memories panel

Expected: Memory saved to server, injected into system prompt on next conversation.

---

### 4. Voice Input (M5) — iOS only

**Goal:** Confirm mic button transcribes speech and feeds it into the input field.

Steps:
- [X] Tap mic button in InputBar — iOS permission sheet appears for microphone + speech recognition
- [X] Grant permissions → speak a sentence → words appear live in the text field
- [X] Tap mic again (or wait 3s of silence) → recording stops; text remains editable
- [X] Edit transcribed text if needed → tap send → response streams normally
- [X] Denial path: revoke Microphone in Settings → Privacy → tap mic → alert appears, no crash
- [X] Streaming guard: while AI is responding, mic button must be grayed out (disabled)

Expected: On-device transcription via Apple Speech; no external API calls; macOS build unaffected.

---

### 5. Standard Checks

- [X] Send a short message — response streams correctly (macOS + iOS)
- [X] RAG: attach a PDF → `rag_indexing` banner appears → response uses document content (Ollama not required)
- [X] Model pill: toolbar shows human-readable name (not raw HuggingFace path)
- [X] Thinking toggle: brain icon in input bar is disabled/hidden on mlx-lm backend
- [X] HTTP LAN alert: banner visible when connecting via plain HTTP on LAN; absent on Tailscale/HTTPS

---

### 6. Archive Checklist (final gate)

Run only after items 1–5 pass.

- [ ] All changes committed and pushed to `origin main`
- [ ] Xcode: Product → Clean Build Folder
- [ ] Xcode: Product → Archive (Any iOS Device destination)
- [ ] Organizer opens automatically — verify bundle version shows correct number
- [ ] Distribute App → TestFlight → upload
- [ ] Confirm build appears in App Store Connect within ~10 min

---

## v0.1.32 — 2026-05-24

### 1. iPad Layout

**Goal:** Confirm `NavigationSplitView` renders correctly on iPad.

Steps:
- [x] Open Xcode, select an iPad simulator (e.g. iPad Pro 13")
- [x] Launch the app
- [x] Verify: conversation list on the left column, chat detail on the right
- [x] Tap a conversation in the list — detail panel updates without pushing the list off-screen
- [x] Rotate to portrait — layout degrades gracefully (list collapses or overlays)

Expected: Two-column layout in landscape; no blank detail pane on cold launch.

---

### 2. Agent Step Indicator

**Goal:** Confirm "Step N/15 · toolname" activity row appears during an agentic loop.

Setup: Mira server running (`python server.py` or LaunchAgent active).

Steps:
- [x] Send a prompt that triggers tool use, e.g.: "Search the web for the latest Swift concurrency proposals and summarise the top 3"
- [x] While the response streams, verify an activity row appears: `↻  Step 1/15 · web_search` (or similar tool name)
- [x] Step counter increments with each tool call: Step 2/15, Step 3/15…
- [x] Activity row disappears once the final response is complete
- [x] Verify the response text is coherent and includes source links

Expected: Step counter visible during tool calls; clears on completion; no stale indicator left on screen.

---

### 3. Project Count Badge After Delete

**Goal:** Confirm the project badge count updates immediately after deleting a conversation.

Steps:
- [x] In the sidebar, find a project with at least 2 conversations; note the badge count (e.g. "3")
- [x] Delete one conversation from that project (swipe-to-delete or context menu)
- [x] Without navigating away, verify the badge count decreases by 1 (e.g. "2")

Expected: Badge refreshes synchronously — no stale count, no manual reload needed.

---

### 4. End-to-End Agentic Loop

**Goal:** Confirm `task_done` exits the loop cleanly and the divergence guard does not false-fire.

Steps:
- [x] Send a multi-step prompt that requires several tool calls, e.g.:
  > "Find the current Python version, check if there are any open CVEs for it, and give me a one-paragraph summary."
- [x] Observe the activity rows: step counter increments, tool names change (search → fetch → …)
- [x] Response completes with a coherent final answer — no truncation, no error message
- [x] Loop exits after `task_done` — no extra tool calls after the answer appears
- [x] Divergence guard check: repeat the same prompt a second time — response should complete normally (guard should not fire on a legitimate task)

Expected: Clean loop exit, accurate answer, no "divergence detected" or error event in the response.

---

### 6. Edit and Resend (Bug Fix)

**Goal:** Confirm Edit and Resend work after a successful response, not only after a failure.

Steps:
- [x] Send any message and wait for a complete response
- [x] Tap **Resend** (↺) — conversation rewinds to just before that turn and re-sends automatically
- [x] Tap **Edit** (pencil) — conversation rewinds and the message text appears in the input field
- [x] macOS: same buttons in the bottom-left action bar behave identically
- [x] Error case: disconnect server, send a message — bubble-level Edit/Resend on the user bubble still appears and works

Expected: Edit/Resend work on every completed turn, not only when the server returned an error.

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

### 1. Voice Input (M5)
- [ ] Tap mic → permission sheet → grant → speak → live transcription in text field
- [ ] Tap mic again or wait 3s → stops; text editable → send works
- [ ] Denial path: revoke in Settings → alert shown, no crash
- [ ] Streaming guard: mic disabled while AI responds

### 2. Long-Term Memory (M4)
- [ ] Add memory → new conversation → AI reflects it
- [ ] "Remember this" context menu → sheet pre-fills → save works

### 3. iPad Layout
- [ ] Two-column layout in landscape on iPad simulator
- [ ] Detail pane not blank on cold launch
- [ ] Portrait degrades gracefully

### 4. Agent Step Indicator
- [ ] "Step N/15 · toolname" appears during tool calls
- [ ] Clears on response completion

### 5. Standard Checks
- [ ] Send a message — response streams correctly
- [ ] [describe the specific change being validated]

### 6. Archive Checklist
- [ ] All changes committed and pushed
- [ ] Clean build, archive, bundle version correct
- [ ] Uploaded to TestFlight
```
