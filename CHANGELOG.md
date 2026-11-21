# Changelog

## Unreleased

**New**

- **Pair from the Mac with a QR code.** The iPhone's Add Connection sheet has a Scan QR button, and a pasted `mira://pair` link in the URL field works too. Either fills the URL, label and token for you to review; nothing connects until you tap Connect. Pairing is https only (Tailscale): a link that isn't https or has no token is rejected with a plain message, and the token never appears in an alert or a log. A pasted link is cleared from the clipboard after use.
- **The macOS app is now Mira Desktop.** It installs as `Mira Desktop.app`, so it no longer collides with the notarized menu-bar `Mira.app`. iOS stays Mira. The notarized DMG is now `mira-desktop-<version>.dmg`.
- **Mira can sleep, and the app says so.** With `engine_idle_unload_minutes` set on the server, the engine unloads after that many idle minutes and wakes on the next request. The app reads `engine_state` from `/health`: a sleeping engine shows a quiet "Asleep. Wakes when you send a message." banner (never the offline banner or the Start button), and a waking one shows "Waking up…". Both appear on the empty-chat screen too, not only inside a conversation.
- **Dictation runs on the device when the language supports it.** Speech recognition was asking iOS for whatever it preferred, which can mean Apple's servers, while the permission text said it was local. It now requires on-device recognition where the language supports it, and the permission text says plainly that otherwise Apple may process the audio.
- **Connection tokens live in the Keychain, not in iCloud's key-value store.** On iPhone and iPad the access token for each saved connection is now a Keychain item (synchronizable, so it travels through end-to-end encrypted iCloud Keychain and an iPhone and iPad keep sharing a pairing). The connection's name and URL still sync through iCloud key-value storage, but the token is no longer in that JSON. Existing connections are migrated on first launch: the token is written to the Keychain, read back, and only then removed from the stored JSON. With iCloud Keychain off the token stays on that device and another device needs the connection paired again.
- **New bundle id, `com.mab.mira`.** Both apps drop the old `OllamaSearch` id, and the iCloud container is now `iCloud.com.mab.mira`. It is a new app to the App Store and TestFlight: it installs beside the old one, starts empty, and needs pairing again (scan the QR). The saved token, local data and TestFlight history do not carry over.
- **The wake starts while you type.** Focusing the composer or opening a conversation calls `POST /engine/wake`, so the 9 to 30 second load overlaps with writing the message.
- **Unload now** in the model sheet and the macOS menu bar frees the engine's memory on demand. A refusal (another client has a request in flight, or idle unload is off) says so instead of closing the sheet.

**Fixed**

- **The chat screen always shows something, and says what it is doing.** A line above the input bar reports the state of the turn and is re-read every second: "Receiving the reply… 12 s", "No data from the server for 9 s. Checking the connection…", "Connection lost. The server is still writing the reply; checking for it every 3 s (0:42).", "Reply restored from the server." When the check runs out it says so and offers Check again. The message area is never empty: it shows messages, or a spinner with a seconds count, or an error with Retry.
- **Opening a conversation shows it at once.** The app used to wait for the server (up to 60 seconds) before switching, with nothing on screen to say so. The conversation is now current from the tap: a copy seen this session appears in the same frame, a copy saved on the device a moment later, and both are refreshed from the server behind that ("Showing the saved copy. Refreshing…"). A refresh that fails leaves the saved copy up and says why. Transcripts of opened conversations are kept in the app's cache folder on the device for this (the newest 80), and removed when the conversation is deleted.
- **A dropped connection no longer strands a cut-off reply, and no longer cancels it.** The server finishes the reply and saves it even when the phone goes offline. After a stream is cut, the app checks the server every 3 seconds, for up to 10 minutes, and swaps in the finished reply when it is saved. Three faults in the first version of this are gone: the stale-connection watchdog posted `/cancel`, which made the server discard the very reply the app then waited for; in a conversation that already had a reply the check took the previous reply for the new one, removed the pending question from the screen and stopped; and a stream cut by the app going to the background was treated as finished. The wait also follows the turn when another conversation is opened meanwhile.
- **A conversation is never deleted while its reply is running or awaited.** Leaving a conversation deleted it when it looked empty, and a conversation looks empty until its first reply is saved. Now leaving deletes only a conversation this app created itself and never sent anything in, leaving a running turn neither cancels nor deletes it, and Delete is refused with an explanation while the reply is still being written. Only the Stop button tells the server to stop.
- **The message list is no longer lazy.** Every blank list so far (after a send, after a banner change, after a reload) came from the same place: a lazy list scrolled to the bottom over estimated row heights can end up where it has built no rows. The list now lays out its newest 20 messages for real and offers "Show earlier messages" above them, and it is no longer torn down and rebuilt when a banner changes or a reply is reloaded.
- **Pairing again to a saved URL keeps the new token.** Adding a connection whose URL was already saved silently kept the old entry, so after a relaunch the app reconnected with a stale token and every request returned 401. The saved entry is now updated. The connected screen also reloads models and conversations when the server URL changes.
- **The model picker says why it is empty.** A failed model list (a 401, say) no longer reads "No backends configured. Add entries to mira.yaml"; it shows the actual error.
- **A message sent to a sleeping engine is no longer cancelled mid-wake.** The 15 second stream-silence watchdog read the wake as a dropped connection, showed "Connection lost" and posted `/cancel` whenever a wake took longer than 15 seconds. The limit is now 300 seconds while the engine is not running, and chat requests allow 300 seconds instead of 60.

- **Resend replaces the failed answer instead of asking the question twice.** Tapping Resend trimmed the broken exchange from the screen but never told the server, so the question stayed in the conversation's history twice with the failed reply between them — and every later turn was built on both copies. The conversation is reloaded from the server afterwards, so what is on screen is what is actually stored. Needs mira-core v1.3.0 or newer, which added the `retry` field on `/chat`. An older server ignores the field, which leaves the old behaviour rather than breaking anything
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
