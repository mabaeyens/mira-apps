# Spec: WKWebView Chat Message Renderer

## Problem

All native Swift text rendering paths fail to correctly render LLM markdown output:

1. **`NSAttributedString(markdown:)`** — produces `presentationIntentAttributeName` for block structure (lists, headings) that UITextView/NSTextView silently ignore. Lists render as unseparated runs.
2. **`AttributedString(markdown:)` + SwiftUI `Text`** — follows CommonMark strictly: a single `\n` is a soft-wrap continuation, not a paragraph break. LLM output uses `\n` for paragraph separation everywhere, so all prose collapses to one wall of text.
3. **Previous `MarkdownUI`** — was the only working state; package has since been removed and cannot be restored.

Root constraint: the problem is not fixable by post-processing attributes or tweaking parser options. The parser contract (single `\n` = same paragraph) is load-bearing in CommonMark and Apple's implementation follows it.

## Solution

Replace prose rendering with a **per-message `WKWebView`** that runs `marked.js` (bundled, no network) to convert markdown to HTML, and `highlight.js` for code syntax highlighting. The WKWebView renders one complete message; SwiftUI handles layout and scroll.

## Architecture

```
MessageBubble (SwiftUI)
  └── assistantContent
        ├── [streaming]  Text (plain, blinking cursor) — unchanged
        └── [done]       MessageContentView (SwiftUI) — replaces current implementation
                           └── MessageWebView (WKWebView bridge)
                                 renders full markdown as HTML
```

**Key decision — full-message WKWebView, not hybrid:**
Putting the entire message (prose + code blocks + tables) in one WKWebView avoids the previous architecture's problems with segment-level UITextView isolation, allows selection to span code blocks and prose naturally (same as Claude Desktop within one message), and eliminates the need for `parseMessageSegments` / `splitTables` / `SelectableText` / `CopyableCodeBlock` as separate SwiftUI views.

Cross-bubble selection is not achievable in native apps — each message bubble is an independent WKWebView. This matches Claude Desktop behavior on macOS (per-message selection context).

## Files to create / modify

### 1. New file: `OllamaSearch/Resources/chat-renderer.html`

A self-contained HTML template bundled in the app. Contains:

- **CSS** — Mira dark theme (black background, `#FAFAF9` prose text, amber `#F59E0B` accent, monospace code styling matching current `CopyableCodeBlock`)
- **marked.js** — bundled locally (download from `https://cdn.jsdelivr.net/npm/marked/marked.min.js`, save as `Resources/marked.min.js` and load via `<script src="marked.min.js">`)
- **highlight.js** — bundled locally (core + languages used most; same theme as current Highlightr setup)
- **JavaScript** — `renderMarkdown(md)` function that calls `marked.parse(md)` and sets `document.body.innerHTML`; `ResizeObserver` that posts `document.body.scrollHeight` back to Swift via `webkit.messageHandlers.contentHeight.postMessage(h)`

```html
<!-- Structure of chat-renderer.html -->
<!DOCTYPE html>
<html>
<head>
<meta name="viewport" content="width=device-width, initial-scale=1">
<style>
  /* Reset + dark theme */
  * { margin: 0; padding: 0; box-sizing: border-box; }
  body {
    background: transparent;
    color: #FAFAF9;
    font: 17px/1.6 -apple-system, sans-serif;
    word-wrap: break-word;
    -webkit-user-select: text;
    user-select: text;
  }
  /* Headings */
  h1,h2,h3,h4 { margin: 0.75em 0 0.4em; font-weight: 600; }
  h1 { font-size: 1.25em; }
  h2 { font-size: 1.1em; }
  h3 { font-size: 1em; }
  /* Paragraphs */
  p { margin: 0.5em 0; }
  p:first-child { margin-top: 0; }
  p:last-child  { margin-bottom: 0; }
  /* Lists */
  ul, ol { margin: 0.5em 0 0.5em 1.4em; }
  li { margin: 0.2em 0; }
  /* Inline code */
  code {
    font-family: "SF Mono", Menlo, monospace;
    font-size: 0.88em;
    background: rgba(255,255,255,0.08);
    border-radius: 3px;
    padding: 0.1em 0.35em;
  }
  /* Code blocks */
  pre {
    position: relative;
    background: #1a1a1a;
    border: 1px solid rgba(255,255,255,0.1);
    border-radius: 8px;
    padding: 12px;
    overflow-x: auto;
    margin: 0.6em 0;
  }
  pre code {
    background: none;
    padding: 0;
    font-size: 0.85em;
    color: #FAFAF9;
  }
  /* Language label */
  .lang-label {
    position: absolute;
    top: 8px; left: 12px;
    font-size: 0.75em;
    color: rgba(255,255,255,0.4);
    font-family: "SF Mono", Menlo, monospace;
    text-transform: lowercase;
    pointer-events: none;
  }
  /* Copy button */
  .copy-btn {
    position: absolute;
    top: 6px; right: 8px;
    background: rgba(255,255,255,0.08);
    border: 1px solid rgba(255,255,255,0.15);
    border-radius: 5px;
    color: rgba(255,255,255,0.6);
    font-size: 0.75em;
    padding: 3px 8px;
    cursor: pointer;
    font-family: -apple-system, sans-serif;
  }
  .copy-btn:active { background: rgba(255,255,255,0.16); }
  /* Tables */
  table { border-collapse: collapse; width: 100%; margin: 0.6em 0; font-size: 0.9em; }
  th, td { border: 1px solid rgba(255,255,255,0.15); padding: 6px 10px; text-align: left; }
  th { background: rgba(255,255,255,0.06); font-weight: 600; }
  tr:nth-child(even) { background: rgba(255,255,255,0.03); }
  /* Blockquote */
  blockquote {
    border-left: 3px solid #F59E0B;
    padding-left: 12px;
    margin: 0.5em 0;
    color: rgba(250,250,249,0.7);
  }
  /* Strong / em */
  strong { font-weight: 600; color: #fff; }
  /* Links */
  a { color: #F59E0B; text-decoration: none; }
  a:hover { text-decoration: underline; }
  /* Horizontal rule */
  hr { border: none; border-top: 1px solid rgba(255,255,255,0.1); margin: 0.8em 0; }
</style>
</head>
<body id="content"></body>
<script src="marked.min.js"></script>
<script src="highlight.min.js"></script>
<script>
// Configure marked
marked.setOptions({
  breaks: true,          // <-- KEY: treat single \n as <br>, not soft wrap
  gfm: true,
  highlight: function(code, lang) {
    const l = hljs.getLanguage(lang) ? lang : 'plaintext';
    return hljs.highlight(code, { language: l }).value;
  }
});

function renderMarkdown(md) {
  document.getElementById('content').innerHTML = marked.parse(md);
  // Add copy buttons and language labels to all pre blocks
  document.querySelectorAll('pre').forEach(function(pre) {
    const code = pre.querySelector('code');
    const lang = code ? [...code.classList]
      .find(c => c.startsWith('language-'))
      ?.replace('language-', '') : null;
    if (lang) {
      const label = document.createElement('span');
      label.className = 'lang-label';
      label.textContent = lang;
      pre.appendChild(label);
      pre.style.paddingTop = '28px';
    }
    const btn = document.createElement('button');
    btn.className = 'copy-btn';
    btn.textContent = 'Copy';
    btn.addEventListener('click', function() {
      const text = code ? code.innerText : pre.innerText;
      if (window.webkit && window.webkit.messageHandlers.copyCode) {
        window.webkit.messageHandlers.copyCode.postMessage(text);
      }
      btn.textContent = 'Copied';
      setTimeout(function() { btn.textContent = 'Copy'; }, 1500);
    });
    pre.appendChild(btn);
  });
  reportHeight();
}

function reportHeight() {
  const h = document.getElementById('content').scrollHeight;
  if (window.webkit && window.webkit.messageHandlers.contentHeight) {
    window.webkit.messageHandlers.contentHeight.postMessage(h);
  }
}

// Re-report on resize (e.g. rotation, sidebar toggle)
const ro = new ResizeObserver(reportHeight);
ro.observe(document.getElementById('content'));
</script>
</html>
```

**Critical setting**: `breaks: true` in marked.js — this makes single `\n` render as `<br>`, which is how users expect LLM output to behave (not CommonMark strict mode). This is the key difference from all previous approaches.

### 2. New file: `OllamaSearch/Shared/Views/MessageWebView.swift`

Cross-platform `WKWebView` bridge. Primary responsibilities:

- Load `chat-renderer.html` from the app bundle via `loadFileURL` (allows local JS/CSS files)
- Expose `content: String` binding; call `renderMarkdown(escapedContent)` via `evaluateJavaScript` when content changes
- Handle `contentHeight` JS message → update a `@Binding var height: CGFloat` that SwiftUI uses to size the frame
- Handle `copyCode` JS message → write to `UIPasteboard` (iOS) / `NSPasteboard` (macOS)
- Configure `WKWebViewConfiguration`: `allowsInlineMediaPlayback`, disable scrolling on the WKWebView itself (SwiftUI scroll view handles it), set `backgroundColor = .clear` / `isOpaque = false`
- Use `WKNavigationDelegate` to call `renderMarkdown` after the HTML finishes loading

```swift
// Approximate struct shape:
struct MessageWebView: View {
    let content: String
    @State private var height: CGFloat = 100

    var body: some View {
        MessageWebViewRepresentable(content: content, height: $height)
            .frame(height: height)
            .frame(maxWidth: .infinity)
    }
}
```

The `MessageWebViewRepresentable` is `UIViewRepresentable` / `NSViewRepresentable` with:
- `makeUIView` / `makeNSView`: configure WKWebView, load HTML template
- `updateUIView` / `updateNSView`: call `renderMarkdown(js-escaped content)` if content changed
- `Coordinator`: `WKScriptMessageHandler` for `contentHeight` and `copyCode`

### 3. Modify: `OllamaSearch/Shared/Views/MessageBubble.swift`

- `renderedMessageText` uses `MessageWebView(content: message.content)` directly — no `MessageContentView`, no `parseMessageSegments`
- Remove `MessageContentView`, `SelectableText`, and all `parseMessageSegments` / `splitTables` call sites in this file
- Keep: streaming `Text` view (unchanged — WKWebView only for completed messages)
- Keep: `preprocessLatex()` — call it before passing content to `MessageWebView`

`parseMessageSegments`, `splitTables`, `CopyableCodeBlock`, `MarkdownTableBlock` in `InlineCode.swift` can be **deleted** (WKWebView handles all content types).

> **Note**: If deleting `InlineCode.swift` content breaks other callers (e.g. if `CopyableCodeBlock` is used elsewhere), check with `grep -rn "CopyableCodeBlock\|MarkdownTableBlock\|parseMessageSegments"` before deleting.

## Bundled JS files

Add to `OllamaSearch/Resources/`:
- `marked.min.js` — v14.x, ~50 KB. Download: `https://cdn.jsdelivr.net/npm/marked/marked.min.js`
- `highlight.min.js` — core bundle. Download: `https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.x/highlight.min.js`
- `chat-renderer.html` — template above

All three must be added to the Xcode project under the `OllamaSearch` target → "Copy Bundle Resources".

## Streaming behavior

No change needed: streaming already uses a plain SwiftUI `Text` view (with blinking cursor). WKWebView only renders the final content once `message.isStreaming == false`. No WKWebView performance concerns during streaming.

## What this fixes

| Problem | Fix |
|---|---|
| Single `\n` collapses prose to one paragraph | `breaks: true` in marked.js treats `\n` as `<br>` |
| Ordered/unordered lists render as run-on text | HTML `<ol>/<ul>` rendered by browser engine |
| Can't select across prose segments | Single browser selection context per message |
| macOS paragraphs run together | Same fix — browser rendering |
| Inline code, bold, italic broken | Full markdown support via marked.js |
| Tables broken | marked.js GFM table support |

## What does NOT change

- Streaming state (plain Text view, blinking cursor)
- `preprocessLatex()` — called before passing to WKWebView
- macOS "Copy" context menu on the assistant bubble (remains on `assistantBubble`)
- Message bubble layout (padding, user bubble styling, etc.)

## Verification checklist

1. Build iOS simulator + macOS — no errors
2. Open a conversation; confirm a completed message renders:
   - Paragraphs separated (not collapsed)
   - Ordered list: `1.` / `2.` / `3.` on separate lines with correct numbers
   - Unordered list: `-` items on separate lines with bullets
   - Inline code: monospace + subtle background
   - Code block: dark background, language label, Copy button
   - Table: grid layout, header row
   - Bold / italic text
3. Long-press / click-drag to select text — handles appear, drag spans multiple paragraphs and across a code block
4. Click "Copy" on a code block — content on clipboard
5. Messages of varying lengths — no height truncation, no extra whitespace
6. Scroll performance — no lag scrolling through a long conversation

## Risk / fallback

If `WKWebView` sizing causes persistent layout issues (known hard problem on iOS in SwiftUI):
- Use `UIScrollView(WKWebView)` bridge with `intrinsicContentSize` override (same pattern that was used for `AutosizingNSTextView`)
- Or constrain to a fixed-height estimate and allow WKWebView to scroll internally as a last resort
