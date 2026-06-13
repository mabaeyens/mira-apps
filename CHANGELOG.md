# Changelog

## v0.1.38

- macOS sidebar is now seamless — no divider line, solid background (no wallpaper bleed), New Chat moved to the bottom
- Toolbar button hides and shows the sidebar with a slide animation
- Fixed blank conversation view on open across all platforms (iOS, iPadOS, macOS)
- Model picker now reads backend presets from the server — adding a new model in `mira.yaml` appears in the picker without an app update
- Backend status banners ("X is not running", "Starting X…") show the actual active model name
- Gemma 4 26B added to the model download list (requires oMLX 0.4.3+)

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
