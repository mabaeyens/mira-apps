# Changelog

## Unreleased

**Fixed**

- **Resend replaces the failed answer instead of asking the question twice.** Tapping Resend trimmed the broken exchange from the screen but never told the server, so the question stayed in the conversation's history twice with the failed reply between them — and every later turn was built on both copies. The conversation is reloaded from the server afterwards, so what is on screen is what is actually stored. Needs a mira-core with the `retry` field on `/chat` — landed after v1.2.0 and not yet in a tagged release. An older server ignores the field, which leaves the old behaviour rather than breaking anything
- **A refused connection says so immediately.** A 403 from the host gate — the address is missing from `allowed_hosts` — was indistinguishable from a sleeping Mac, so the app spent 90 seconds retrying and then went orange with no explanation. The reason now appears on the first attempt and stays up. Retrying continues throughout, so fixing `mira.yaml` on the Mac is picked up without relaunching the app

## v0.3.0

**New**

- Mira now says when something else on the Mac has pushed the model out of memory, so a reply that suddenly takes fifteen seconds has a visible cause instead of none. Advisory only — it never blocks sending — and it clears itself once the model is back. Needs mira-core v1.2.0 or newer
- **iOS: "Add to project" now files the conversation.** The control existed and did nothing: the sheet opened, the projects listed, the row was tappable, the sheet dismissed, and the project stayed empty — with no error, so it read as success
- The model picker shows the model that is actually running, and hides presets that cannot be selected with a reason why. Before this, every row could come back unselectable, with no row for the model answering you and no way back to it after switching away

**Fixed**

- Backends are named correctly everywhere. mira-mlx has been the default since July and the About panel, the model-switch line and the input bar all still said "Ollama" — three copies of the same mapping, each falling through to the same wrong answer
- Startup and reconnect messages no longer name an engine that is not running, and no longer promise a 15–30 second wait the logs do not support
- A server that refused the connection is told apart from one that was never reached. A 403 from the host gate now points at `allowed_hosts` and a 401 at the token field, instead of blaming your network and URL when both were fine
- HTTP errors surface as errors. A 401 used to arrive as "the data couldn't be read because it is missing", three layers from the cause and reading like data loss
- Markdown links are legible in light mode — they were at 3.25:1 against the 4.5:1 that normal text needs. Dark mode was already fine and is unchanged
- **macOS: the app reads its API token from the keychain**, not from a path inside the sandbox container where the file never was. Every authenticated request had been failing, so conversations listed from cache while no messages ever loaded and sending failed. This had never worked in a sandboxed build
- macOS: fixed the title-bar views fighting over the window during the open animation, which logged an AppKit layout recursion at every launch

**Performance**

- Attached images are downscaled before upload — 3.6× smaller across the test set, 5.5 MB → 1.1 MB on a 12 MP photo. The server already caps images at 1 MP, so the full-size pixels were decoded and thrown away. Orientation is baked in so portrait photos no longer arrive sideways, PNG screenshots stay PNG to keep small text sharp, and the shrunk copy is discarded if it did not actually come out smaller

## v0.2.1

- Destructive actions (deleting a file, `rm -rf`, merging a PR, deleting a branch) now ask for an explicit tap to approve before they run
- Deployment targets lowered to iOS 18 / macOS 15 (from 26), widening device compatibility
- Added a privacy policy (PRIVACY.md) — no data is collected
- Fixed the iOS marketing app icon: removed a stray alpha channel that could cause App Store validation issues

## v0.2.0

- iPad: the sidebar no longer auto-hides when you open a conversation — you control it with a toolbar button and the choice persists across conversations and launches
- Model picker: removed the backend tag from the model rows (the active backend is shown on the About screen instead) — cleaner Switch Model and download lists

## v0.1.38

- Deleting a project is now guarded — the app shows the server's message and keeps the project while its files still exist (delete the local folder or GitHub repo first)
- macOS sidebar is now seamless — no divider line, solid background (no wallpaper bleed), New Chat moved to the bottom
- Toolbar button hides and shows the sidebar with a slide animation
- Fixed blank conversation view on open across all platforms (iOS, iPadOS, macOS)
- Model picker now reads backend presets from the server — adding a new model in `mira.yaml` appears in the picker without an app update
- Backend status banners ("X is not running", "Starting X…") show the actual active model name
- Gemma 4 26B added to the model download list (requires oMLX 0.4.3+)
- Stop and compact now act only on the open conversation (multi-conversation scoping)

## v0.1.37

- Scroll-to-bottom deferred until messages finish loading (eliminates jump on open)
- Status bar gradient added below conversation header
- Brand font switched from Bookerly to Lora (OFL-licensed)

## v0.1.36

- **dFlash backend label** — model pill and picker show the active backend across all UI touchpoints
- **Conversation lifecycle** — delete unsent (empty) conversations; rename conversation on failed send
- **SwiftUI refactor** — state management cleaned up across ChatView, sidebar, and sheet presentation
- Native macOS sidebar and sheets restored; tri-state thinking mode (off / adaptive / force-on)
- Attachment display fixed; scroll feedback loop and AppKit constraint faults eliminated
- Model picker fills full sheet height on iOS; background, fonts, and layout fixes across platforms
- macOS: dictation, memories add button, popover thinking toggle, splash gradient fixes

## v0.1.35

- Thinking content displayed and persisted in conversation history
- Thinking toggle restored as force-on override (thinking is adaptive by default)
- Voice input locale support added; sidebar pin toggle removed
- Syntax highlighting language map extended for inline code blocks
- URLSession delegate nil fix in SSEClient; cert pinning reverted in favour of HTTP on LAN
