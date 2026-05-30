# Mira Test Plan

Reusable checklist for pre-release validation. Run before every TestFlight archive.
Each release gets its own dated section at the top (newest first).

---

## v0.1.34 — pending release

### 1. In-App Model Browser

**Goal:** Confirm model switching works end-to-end from the UI.

Steps:
- [ ] Tap model pill/name in toolbar → model sheet opens
- [ ] Sheet lists models with active/available indicators
- [ ] Tap an inactive model → confirmation alert appears (warns ~30–60s pause) → confirm
- [ ] Progress states cycle: "Stopping…" → "Starting…" → "Loading weights…" → "Almost ready…"
- [ ] Chat resumes with the new model (send a message to confirm)
- [ ] While switching: chat input is blocked; toolbar shows switching status

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
- [ ] Tap mic button in InputBar — iOS permission sheet appears for microphone + speech recognition
- [ ] Grant permissions → speak a sentence → words appear live in the text field
- [ ] Tap mic again (or wait 3s of silence) → recording stops; text remains editable
- [ ] Edit transcribed text if needed → tap send → response streams normally
- [ ] Denial path: revoke Microphone in Settings → Privacy → tap mic → alert appears, no crash
- [ ] Streaming guard: while AI is responding, mic button must be grayed out (disabled)

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
