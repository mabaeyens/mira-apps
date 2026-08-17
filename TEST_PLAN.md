# Mira Test Plan

Manual checklist. Run the open items on device before a TestFlight archive, then
move whatever passed into the validated list. `CHANGELOG.md` and git history are
the record of what shipped when; this file only tracks what still needs a pass.

Three targets, not two: **iPhone, iPad and Mac**. Every item below says which.

---

## Open before the next ship

### A. Light mode — all three (never tested)

Light mode shipped 2026-05-17 and has no check here, because `backlog.md`
claimed the app forced dark. It does not. This is the largest untested surface
in the app.

Contrast was measured 2026-07-26 (mira-core `notes/mira-palette-contrast.py`),
so the numeric part is done and the link colour is fixed. What is left needs
eyes.

- [x] **Mac / iPhone / iPad**: set the system to Light → chat, sidebar and input
      bar are legible
- [x] **Markdown links in Light** are readable. They were 3.25:1 and are now
      `#9F6542` at 4.52. The only measured failure in the palette
- [x] **iPhone**: reconnect banner and the floating nav circles use
      `.ultraThinMaterial`, designed against dark. Confirm they still read
- [x] **Mac**: splash screen in Light → the amber radial wash is visible but not muddy
- [x] **Mac**: System Settings → Appearance → set a **non-default accent colour**
      (blue, pink) → the app stays amber everywhere. 35 places use
      `Color.accent` rather than `Color.appAccent`; both resolve to the same
      amber from the asset catalog, but that is asserted, not observed
- [x] **Switch appearance with the app already running** → the window background
      follows, no relaunch. The palette itself was verified to resolve
      dynamically, so this is about AppKit state held elsewhere
- [x] Inline code chips are still visible in Light. Measured at 1.57:1, which is
      *higher* than GitHub's 1.13, so this is a look check and not a defect hunt

_A closed 2026-08-13: light mode legible on Mac; user-turn bubble lightened `0xD0C8BE` → `0xE0D8CE`._

### B. macOS window chrome — Mac only

From `0208d8b`, which was reasoned from code structure and **never reproduced**.

- [ ] Cold launch, let the splash transition to the main window → Console shows
      no `_NSDetectedLayoutRecursion` / "not legal to call -layoutSubtreeIfNeeded"
- [ ] Same, with the app in the `.needsToken` state (delete the keychain item:
      `security delete-generic-password -s com.mab.mira.apitoken -a local-server`)
- [ ] Title bar looks right in both states: transparent on splash, normal on main

### C. Errors say what went wrong — all three

From `5a6a56f`. HTTP status is now checked before decoding, so failures should
name themselves instead of surfacing as "The data couldn't be read".

`scripts/checks/connection-check.sh` now covers the mapping underneath both
items below — status to error, probe outcome to sentence, and the four
connection failures staying distinguishable from each other. It needs no server.
What it cannot show is that the right code path runs on a real device, which is
what these two are for.

- [ ] Stop the server mid-session, send a message → the error names a connection
      problem, not a decode problem
- [ ] **Mac**: wrong token in the keychain → the app asks for a token; it does
      not report itself connected.
      **This failed by construction until 2026-08-11 and has never passed.** The
      readiness poll asked `/health`, which mira-core keeps in
      `_AUTH_OPEN_PATHS` (`server.py:176`), so it answered 200 for a right token,
      a wrong one, and none at all; `loadToken()` then confirmed only that *a*
      token existed. A wrong token therefore reported `.ready` and 401'd on
      every subsequent request. Both platforms now probe `/info`, a guarded
      route, once `/health` says the server is up. Retest from a genuinely wrong
      keychain entry, not an empty one — an empty one passed before the fix too
- [ ] **iPhone**: the same, from the other side — add a connection with a wrong
      token typed into the Server Token field. It used to save as good, because
      the field was never validated against anything

### D. Leftovers

- [ ] **All three**: `/compact` in a long conversation → returns a summary line,
      conversation still works afterwards
- [ ] **All three**: Stop mid-stream, then send again → one response, not two
- [ ] **All three**, build 38+: a destructive shell command → approval alert
      appears and the command text is not truncated past the point of being
      readable (security audit Part B)

---

### E. Model card and backend names — all three

Specs 1 and 2, shipped 2026-07-26 (`003463c`, `0fa90bc`, server `76b660f`).
Build-verified, plus a decode check against live server bytes. **Never run.**

- [x] Open the model card → the running model is **first and checkmarked**.
      Before this, nothing was ever checkmarked
- [x] Every selectable row shows engine, context window and size on disk, and
      no title truncates mid-word
- [~] **Stop Ollama**, reopen the card → its preset appears under "Not
      available" with a reason, greyed, and does nothing when tapped
      _(N/A — Ollama is no longer a configured backend)_
- [x] Switch to another model, then switch back → the row you came from is
      still there. Before this there was no way back
- [x] **Mac**: Mira → About Mira → "Backend" reads `mira-mlx`, not "Ollama"
- [x] After a switch, the info line in the transcript names the right engine
- [x] "Download a model" → does **not** offer Gemma 4 26B, which is installed

_E closed 2026-08-13: About → Backend reads `mira-mlx`; Ollama-stop check N/A (Ollama no longer a backend)._

### F. Nothing moved — all three

Spec 4 renamed 27 font literals to named roles. Every substitution was checked
mechanically to resolve to the same size, weight and design, so this is a
glance, not a hunt.

- [ ] Sidebar rows, chat banners, the model pill, the model card and the token
      counter all look exactly as they did. Any size change here is a bug
- [ ] **iPhone**: Settings → Accessibility → Larger Text → text grows. Half the
      labels will not, which is a **known** issue written up in
      `specs/type-scale.md`, not a regression from this change

---

### G. Startup copy — iPhone and iPad mainly

Spec 5. The reconnect messages are iOS-only; macOS has its own two states.

- [ ] **iPhone**: background the app, put the Mac to sleep, foreground again →
      the patience messages never name Ollama, and none of them quotes a
      number of seconds
- [ ] **Mac**: cold launch while the server is starting → splash reads
      "Starting Mira…", not "Starting Ollama…"

### H. Projects — iPhone and iPad

Spec 6. The API round trip is verified against the live server; what is not
verified is the UI reaching it.

- [ ] Open a conversation → ⋯ → Add to project → pick one → it moves under that
      project in the sidebar, and is still there after a relaunch
- [ ] Reopen the picker → the current project has a checkmark and is not tappable
- [ ] "Remove from project" → the conversation returns to the ungrouped list
- [ ] Rename a filed conversation → it stays in its project. This is the case
      most likely to break and the hardest to notice
- [ ] The project row's conversation count is right after filing and unfiling

### I. Memory advisory — iPhone against the Mac, plus the Mac itself

- [x] **iPhone and Mac**: the `evicted` banner renders from a real advisory
      during a real conversation. Confirmed 2026-08-08 on both, which
      also settles the live path — the 30s poll does flip the state, and the copy
      reads correctly on a phone that has plenty of memory itself

Verified underneath it: decoding against the live payload and eight degraded
shapes, all five advisories mapping to known cases, polling starting at all four
call sites, and a failed poll clearing rather than freezing a stale banner. The
two `#Preview`s in `ChatView.swift` cover layout in both appearances at 320pt.

What is left is the tail, not the feature:

- [ ] It clears by itself within ~30s of the Mac recovering, with no tap and no
      animation flash
- [ ] **Mac**: the menu bar advisory row. Built when the menu opens, so it can
      lag the banner by up to one 30s poll — expected, not a defect
- [ ] `critical` renders, not only `evicted`. Largely covered already, and worth
      knowing why before spending a Mac on it: `AdvisoryPreview` enumerates
      `MemoryAdvisory.allCases`, so `critical` is one of the two banners both
      `#Preview`s already draw — its copy and its wrapping at 320pt are checked.
      It shares the entire code path with `evicted`, which is device-verified
      above, and differs only in the string. So what is genuinely untested is
      nothing specific to `critical`, and this is optional rather than owed.
      It stays listed because it is still the *cheap* trigger if a live advisory
      is ever needed again: forcing a real eviction means pushing a ~19GB model
      out of a 32GB Mac and waiting for the reclaim, with the machine unusable
      meanwhile. **Ask first.**

---

## Every release

- [ ] **All three**: send a short message → response streams
- [ ] **All three**: model pill shows the running model
- [ ] **All three**: open an old conversation → messages load
- [ ] **iPhone**: voice input dictates into the field
- [ ] **All three**: Memories → add one, start a new conversation, it is reflected
- [ ] **iPad**: sidebar visibility survives a relaunch

## Archive checklist (final gate)

- [ ] All changes committed and pushed to `origin main`
- [ ] Xcode: Product → Clean Build Folder
- [ ] Build with the **`OllamaSearch` scheme explicitly** — auto-detection picks
      the `MarkdownUI` dependency and prints a BUILD SUCCEEDED that compiled none
      of the app
- [ ] Product → Archive (Any iOS Device destination)
- [ ] Organizer: verify the bundle version
- [ ] Distribute App → TestFlight → upload
- [ ] Build appears in App Store Connect within ~10 min

---

## Validated on device

Kept as a record so these are not re-run blindly. Re-test a line only when its
code changes. Per-release detail is in git history and `CHANGELOG.md`.

- **v0.2.0 / build 37, 2026-06-21** — iPad sidebar persistence, think-mode turn
  control, project deletion guard
- **v0.1.38, 2026-06-06** — macOS seamless sidebar and toggle, New Chat at the
  sidebar bottom, blank-on-open scroll fix, iOS status bar gradient
- **v0.1.34** — in-app model browser, iCloud sync, long-term memory, voice input
- **v0.1.32, 2026-05-24** — iPad layout, agent step indicator, project count
  badge after delete, end-to-end agentic loop, edit and resend
- **2026-07-26** — macOS auth token flow, confirmed in the running app
  (`aec50d1`, `5a6a56f`)
