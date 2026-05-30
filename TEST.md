# Mira — Pending Device Tests

Features committed but not yet manually verified on iPhone Miguel.
Run these before the next release. Check off and delete entries when confirmed on device.

---

## M5 — Voice Input (committed 83379b0)

- [ ] Tap mic button in InputBar → iOS permission sheet appears for microphone + speech recognition
- [ ] Grant permissions → speak a sentence → words appear live in the text field
- [ ] Tap mic again (or wait 3s silence) → recording stops; text is editable before send
- [ ] Send after voice input works normally
- [ ] Denial path: revoke Microphone in Settings → Privacy → tap mic → alert shown, no crash
- [ ] Streaming guard: while AI is responding, mic button is grayed out (disabled)

---

## M4 — Long-Term Memory

- [ ] Tap brain icon in sidebar → Memories panel opens → tap "+" → add a memory → save
- [ ] Start a new conversation → ask something that should trigger the memory → AI reflects it
- [ ] Long-press an assistant message → "Remember this" → sheet pre-fills → save → appears in Memories panel

---

## M3 — iCloud Sync (setup required first)

iCloud capability must be added manually in Xcode before testing:
1. Open `OllamaSearch.xcodeproj`
2. Select the `OllamaSearch` target → **Signing & Capabilities** → **+**
3. Add **iCloud** → check "Key-value storage" and "iCloud Documents"
4. Container: `iCloud.com.mab.OllamaSearch`

- [ ] iCloud capability added in Xcode (setup step)
- [ ] Conversations visible on both simulator and device after iCloud sync
