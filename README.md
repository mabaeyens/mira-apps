# Mira

A native macOS and iOS chat app for local AI models, built with SwiftUI.

Mira runs entirely on your own hardware — no cloud, no subscription, no data leaving your machine. It connects to a local Python server (mlx-lm for inference, sentence-transformers for RAG embeddings) and pairs with an iPhone over Bonjour or Tailscale for the same experience on the go.

## Features

- **Local-first** — inference runs on your Mac via mlx-lm; nothing is sent to external APIs
- **Streaming responses** — server-sent events for real-time token output
- **RAG** — attach documents and let the model search them before answering
- **Long-term memory** — save facts across conversations; model uses them automatically
- **Voice input** — tap the mic to dictate; live transcription via Apple Speech (on-device, iOS only)
- **Conversation history** — persistent, named conversations with a sidebar
- **Markdown rendering** — code blocks, tables, and inline formatting via MarkdownUI
- **iOS companion** — iPhone app connects to the Mac server over WiFi (Bonjour) or remotely (Tailscale)
- **Splash screens** — animated Mira logo while the server and model load (macOS and iOS)
- **About screen** — accessible from the macOS app menu and iOS info button
- **Adaptive app icon** — light, dark, and tinted variants for iOS 18 home screen modes
- **Dark mode** — warm stone palette

## Requirements

| Component | Version |
|-----------|---------|
| Xcode | 26+ |
| macOS (dev machine) | 26+ |
| iOS (device) | 26+ |
| Swift | 6 |
| Python | 3.12+ (for the server) |
| mlx-lm | 0.31.3+ (inference) |

## Project structure

```
OllamaSearch/
├── Shared/          # Views, ViewModels, Models, Networking — runs on both platforms
│   ├── Views/       # ChatView, MiraLogo, AboutView, SplashView helpers, …
│   ├── ViewModels/
│   ├── Models/
│   └── Networking/
├── macOS/           # ServerManager, MacRootView, SplashView, file picker
├── iOS/             # Bonjour discovery, ConnectionView, file picker
└── Assets.xcassets/ # App icon (light / dark / tinted), accent colour
Design/
└── AppIcon.svg      # Source SVG for the app icon (eye + star mark)
```

## Architecture

```
iPhone (Mira iOS)
    └── WiFi / Tailscale ──► Mac (Mira macOS)
                                 └── localhost:8000 ──► Python server (FastAPI)
                                                            └── mlx-lm (inference, port 8080)
                                                            └── sentence-transformers (RAG embeddings, local)
```

The macOS app connects to the Python server, which runs as a macOS LaunchAgent (`com.mab.mira`) installed separately from the app. The iOS app discovers the Mac over Bonjour (`_ollamasearch._tcp`) on the local network, or connects manually using a Tailscale IP.

**The app requires the Mac server to run.** There is no standalone offline mode — inference happens on the Mac. For access outside your home network, install [Tailscale](https://tailscale.com) on both devices and use the **Manual URL** option with your Tailscale IP.

## iOS icon appearance

iOS 18 manages icon appearance (light/dark/tinted) separately from system dark mode. To see the dark icon variant:

> Home screen → long-press → **Customize** → select **Dark** or **Automatic**

## Building

See [XCODE_SETUP.md](XCODE_SETUP.md) for the full step-by-step Xcode setup.

Quick start for an already-configured project:

1. Ensure the Mira server LaunchAgent is installed and running (see [mira-core](https://github.com/mabaeyens/mira-core))
2. Open `OllamaSearch.xcodeproj` in Xcode
3. Select the **macOS** destination → **⌘R**
4. For iOS, connect your iPhone and select it as the destination → **⌘R**

## Name

*Mira* is the Spanish imperative of *mirar* — "look" — and the name of one of the oldest variable stars observed by astronomers, a red giant whose brightness pulses on a 332-day cycle. The pulsing glow in the splash screen is a small nod to that.

---

© Miguel Angel Baeyens 2026
