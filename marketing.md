# Mira — App Store Marketing

## App Store metadata

### Promotional text
*(170 chars max — can be updated without a new app version)*

> Your conversations stay on your Mac. Mira connects to local AI models you run yourself — no cloud, no data sent anywhere, no subscriptions.

### Description

> Mira is a native iOS and macOS client for AI models running entirely on your own hardware. It connects to the Mira server — a lightweight process you run on your Mac — and streams responses from Ollama, a local model runner. Nothing leaves your network.
>
> **How it works**
> Install the Mira server on your Mac. It starts automatically at login. Open the iOS app on your iPhone and Mira finds your Mac on the local network via Bonjour, or you can connect remotely through Tailscale. Once connected, you get a full conversation interface backed by any model Ollama supports: Llama, Mistral, Gemma, Qwen, and more.
>
> **Privacy by design**
> No account. No API key. No telemetry. Your messages are processed by a model running on your own machine and stored in a local database on your Mac. Mira cannot access your conversations because they never leave your home network.
>
> **What you need**
> • A Mac running macOS 15 or later with Ollama installed
> • The Mira server (free, open source) installed as a login item on that Mac
> • iPhone on iOS 18 or later on the same Wi-Fi network, or Tailscale for remote access
>
> **Features**
> • Streaming responses with markdown rendering and code highlighting
> • Persistent conversation history with auto-generated titles
> • Bonjour auto-discovery — no IP addresses to type on local Wi-Fi
> • Tailscale support for secure remote access from anywhere
> • macOS menu bar app with the same conversation history
>
> Mira is built for people who want the capability of modern AI without surrendering their data to do it.

### Keywords
*(100 chars max, comma-separated, no spaces after commas)*

```
local AI,private AI,Ollama,offline chat,LLM client,no cloud,AI assistant,on-device AI
```

*(87 chars)*

### URLs

| Field | URL |
|-------|-----|
| Support URL | https://linkedin.com/in/mabaeyens |
| Marketing URL | https://linkedin.com/in/mabaeyens |

> **Note:** LinkedIn is a placeholder. For public App Store submission, replace with a dedicated support page or GitHub repo URL — Apple reviewers sometimes flag LinkedIn as insufficient.

---

## Screenshots

### Required sizes

| Platform | Display | Resolution |
|----------|---------|------------|
| iPhone | 6.9" (iPhone 16 Pro Max) | 1320 × 2868 px |
| iPad | 13" iPad Pro | 2064 × 2752 px |
| Mac | — | 1440 × 900 or 2560 × 1600 px |

Uploading the largest size for each platform covers all smaller sizes automatically.

---

### iPhone — 5 screenshots (portrait)

| # | Screen to capture | Caption overlay |
|---|-------------------|-----------------|
| 1 | Active chat with a markdown response (bullet points or headers) | **Runs entirely on your Mac.** No cloud. No account. |
| 2 | Conversation list (sidebar) showing 4–6 realistically named conversations | **Your history, stored locally.** Private by design. |
| 3 | Empty state — "How can I help?" with the Mira logo centered | **Meet Mira.** Local AI, beautifully simple. |
| 4 | A code-heavy response with syntax highlighting | **Ask anything technical.** Code highlighting built in. |
| 5 | Connection screen showing "Found Mira on your network" | **Finds your Mac automatically.** Just open and go. |

---

### iPad — 3–5 screenshots (landscape preferred)

| # | Screen to capture | Caption overlay |
|---|-------------------|-----------------|
| 1 | Landscape split view — sidebar + active chat | **Full conversation history at a glance.** |
| 2 | Portrait — same active chat | **Adapts to how you work.** |
| 3 | Long or code-heavy response (more screen real estate) | **Rich responses, rendered natively.** |

---

### Mac — 4 screenshots

| # | Screen to capture | Caption overlay |
|---|-------------------|-----------------|
| 1 | Full window, dark mode — sidebar + active conversation | **A native Mac app, not a web wrapper.** |
| 2 | Menu bar icon visible at top of screen | **Runs quietly in the background. Always ready.** |
| 3 | Light mode — same layout | **Dark or light. Your choice.** |
| 4 | Sidebar scrolled to show a long conversation thread | **Conversations that persist, privately.** |

---

### Tips for quality screenshots

- **Populate the conversation list with realistic titles**: "Explain black holes", "Python script for CSV export", "Dinner ideas for 6 people" — never "test" or placeholder text.
- **Run a capable model** (Llama 3.1, Mistral, Gemma) and ask a question that produces a genuinely good response before screenshotting.
- **Capture after response is fully rendered** — never show a loading state or spinner.
- **Add caption overlays** — composite text in Figma or Preview, or use App Store Connect's built-in screenshot frame tool. This is the single biggest difference between a hobby listing and a professional one.
- **Use a real device or high-resolution simulator** — blurry or pixelated screenshots signal low quality immediately.

---

## Differentiation — how Mira stands out

### The competitive landscape

| App | Platform | Model source | Key weakness vs Mira |
|-----|----------|-------------|----------------------|
| Open WebUI | Web (self-hosted) | Ollama / any | Browser app, not native — no iOS feel, no Bonjour |
| Enchanted | iOS + macOS | Ollama | SwiftUI but generic design, no brand story |
| LM Studio | macOS | Bundled | Desktop-only, no iOS client, heavy |
| Msty | macOS + iOS | Multiple | Paid, cloud-optional, loses the privacy purity angle |
| Jan | Desktop (Electron) | Bundled | Not native, no iOS |
| BoltAI | macOS | Multiple providers | Paid, cloud-first, not local-only |
| Ollama built-in UI | Terminal / web | Ollama | No UI to speak of |

Mira's current moat: **native SwiftUI + Bonjour zero-config + genuine privacy story + coherent design language**. No other app in this space has all four.

---

### Short-term ideas (v1.x — weeks)

- **Conversation export** — export any thread as a clean `.md` or `.txt` file via the iOS Share Sheet. Simple, no competitor does it well on mobile. Power users want this.
- **Full-text conversation search** — search across all conversation history. Missing from most local apps. High perceived value for returning users.
- **System prompt per conversation** — save a custom persona or instruction set with each thread. "Always reply in Spanish", "Act as a senior engineer reviewing my code."
- **Model switcher** — choose which Ollama model to use per conversation. Show model name in the conversation header.
- **Haptic feedback** — subtle haptic on stream start and end. Tiny touch, memorable on iPhone. No competitor bothers.
- **Spotlight indexing** — index conversation titles so users can find old chats from the iOS home screen search. Feels deeply native.

### Medium-term ideas (v1.x–v2 — months)

- **iOS Share Extension** — select text in Safari, Mail, Notes → "Ask Mira…" sends it as context. The fastest path from any app to a local AI. Strong differentiator.
- **Siri Shortcut** — "Hey Siri, ask Mira to…" opens the app with a pre-filled prompt. Apple ecosystem depth no web app can match.
- **File context** — drag a PDF, text file, or image onto the Mac app and include it as conversation context. No RAG pipeline needed — just smart truncation and paste. Covers 80% of the "chat with my document" use case with 5% of the complexity.
- **Voice input** — iOS microphone → on-device speech recognition → send as text. Whisper via Ollama or iOS Speech framework. Hands-free local AI.
- **Multiple server profiles** — save "Home Mac" and "Work Mac" as named profiles. Switch between them from the connection screen.
- **macOS Services menu** — select text anywhere on macOS → right-click → "Ask Mira". System-level integration that feels impossible from a web app.
- **iOS home screen widget** — "Last conversation" shortcut or a quick-start button. Presence on the home screen = top-of-mind.

### Long-term / brand ideas (strategic)

- **"The quiet AI" positioning** — lean into being the anti-ChatGPT. No engagement loops, no notifications, no dark patterns, no upsells. A tool that respects your attention. This is a brand story, not just a feature.
- **Companion website** — even a single-page site with the logo, the name etymology (Mira Ceti, mirar, wonderful), and a GitHub link. More credible than LinkedIn as a support URL. Costs nothing with GitHub Pages.
- **"Setup in 5 minutes" screen recording** — the server dependency is the biggest conversion drop-off. A 3-minute screen recording walkthrough (Ollama install → server install → open iOS app → connected) posted anywhere removes the friction for curious users.
- **Open source the iOS app** — mira-core is already public. Open-sourcing mira-apps would generate GitHub stars, PRs, and word-of-mouth in the self-hosting / local AI community (r/LocalLLaMA, Hacker News, etc.). The App Store binary can still be paid or free.
- **Press kit in the repo** — a `press/` folder with the logo SVG, app icon PNG, a one-paragraph description, and two or three screenshots. Makes it trivial for tech bloggers to write about Mira without asking you for assets.
- **TestFlight public link** — share a public TestFlight link on r/LocalLLaMA or Hacker News Show HN before the App Store launch. Builds early users, surface bugs, and generates organic buzz in exactly the right audience.

---

## Submission risk: server dependency

Mira requires the Mac server + Ollama running to function. An Apple reviewer opening the app cold will see "Connecting to server…" indefinitely. **This is the most likely cause of rejection.**

Mitigations to consider before public App Store submission:
1. Add a clear error screen after the connection timeout with setup instructions and a link to the GitHub repo.
2. Include setup instructions in the App Review Notes field in App Store Connect (reviewers read these).
3. Optionally: provide a demo mode or offline fallback for reviewers.

For TestFlight (current stage), this is less of a concern.
