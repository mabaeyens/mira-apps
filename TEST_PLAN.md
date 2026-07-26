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

- [ ] **Mac / iPhone / iPad**: set the system to Light → chat, sidebar and input
      bar are legible, nothing is beige-on-cream
- [ ] Inline code and fenced code blocks in Light → the chip is distinguishable
      from the page (both use `userBubbleBg` over `appBg`, closest pair in the palette)
- [ ] **Switch appearance with the app already running** → the window background
      follows, no relaunch needed. Most likely thing to fail
- [ ] **Mac**: splash screen in Light → the amber radial wash is visible but not muddy
- [ ] **iPhone**: reconnect banner and the floating nav circles use
      `.ultraThinMaterial`, designed against dark. Confirm they still read

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

- [ ] Stop the server mid-session, send a message → the error names a connection
      problem, not a decode problem
- [ ] **Mac**: wrong token in the keychain → the app asks for a token; it does
      not report itself connected

### D. Leftovers

- [ ] **All three**: `/compact` in a long conversation → returns a summary line,
      conversation still works afterwards
- [ ] **All three**: Stop mid-stream, then send again → one response, not two
- [ ] **All three**, build 38+: a destructive shell command → approval alert
      appears and the command text is not truncated past the point of being
      readable (security audit Part B)

---

## Coming from the consistency roadmap

**Do not run these yet.** Nothing below is implemented; `specs/ROADMAP.md`
tracks the work. Listed here so the checks exist before the code does.

- [ ] **All three**: the model card marks the model that is actually running
      (today nothing is checkmarked) — spec 2
- [ ] **All three**: no row in the model card fails when tapped — spec 2
- [ ] **Mac**: About panel "Backend" row reads `mira-mlx`, not "Ollama" — spec 1
- [ ] **All three**: switching model shows the right backend name in the info
      line — spec 1
- [ ] **All three**: startup messages do not name Ollama — spec 5
- [ ] **iPhone / iPad**: assign a conversation to a project → it moves in the
      sidebar and survives relaunch — spec 6

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
- **2026-07-26** — macOS auth token flow, confirmed by Miguel in the running app
  (`aec50d1`, `5a6a56f`)
