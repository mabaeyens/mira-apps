# Mira Test Plan

Manual checklist. Run the open items on device before a TestFlight archive, then
move whatever passed into the validated list. `CHANGELOG.md` and git history are
the record of what shipped when; this file only tracks what still needs a pass.

Three targets, not two: **iPhone, iPad and Mac**. Every item below says which.

---

## Open before the next ship

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

### F. Type scale and Dynamic Type — all three

Spec 4 named the font roles; the Dynamic Type fonts pass (`1ea5898`, verified
2026-08-19) then mapped every iOS role onto a stock text style, so iOS text and
icons now scale with Larger Text. The type-scale findings (2026-08-19) added two
**deliberate** size changes on top — so, unlike the earlier "nothing moved" pass,
some things here are meant to look different.

- [ ] **iPhone**: Settings → Accessibility → Larger Text → chat, sidebar, compose
      bar, model picker and connection-sheet text all grow now (they did not
      before the fonts pass). Container frames are still fixed, so at the largest
      sizes some glyphs may clip their boxes — **known**, deferred to the frame
      pass in `specs/dynamic-type.md`, not a regression
- [ ] **All three**: at the default text size, everything *except* the two changes
      below looks exactly as before. Any other size shift is a bug
- [ ] **Mac**: model picker → the "MODELS" / "NOT AVAILABLE" group header is no
      longer larger than the row subtitle under it (subtitle went 10→12pt via the
      new `rowSubtitle` role). This was the visible inversion the change fixes
- [ ] **iPhone**: the "Add to Chat" (+) sheet and the conversation options (⋯)
      sheet now match — title 17 semibold, row label 17, row icon 20. Put them
      side by side; they used to disagree on all three

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

The `evicted` banner and its live 30s-poll path are device-verified (2026-08-08,
in the validated log). What is left is the tail below.

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

- **2026-08-13** — Light mode on all three (legibility, Markdown links, accent
  independence, live appearance switch, inline-code chips; user bubble lightened
  `0xD0C8BE` → `0xE0D8CE`); model card and backend names (running model first and
  checkmarked, row-back after a switch, About → Backend reads `mira-mlx`, Gemma 4
  not offered). Ollama "Not available" check retired — Ollama is no longer a backend
- **2026-08-08** — Memory `evicted` advisory banner from a real advisory, iPhone
  and Mac (live 30s-poll path). Section I tail (self-clear, menu-bar row,
  `critical`) still open
- **v0.2.0 / build 37, 2026-06-21** — iPad sidebar persistence, think-mode turn
  control, project deletion guard
- **v0.1.38, 2026-06-06** — macOS seamless sidebar and toggle, New Chat at the
  sidebar bottom, blank-on-open scroll fix, iOS status bar gradient
- **v0.1.34** — in-app model browser, iCloud sync, long-term memory, voice input
- **v0.1.32, 2026-05-24** — iPad layout, agent step indicator, project count
  badge after delete, end-to-end agentic loop, edit and resend
- **2026-07-26** — macOS auth token flow, confirmed in the running app
  (`aec50d1`, `5a6a56f`)
