# Mira

A native macOS and iOS chat app for local AI models, built with SwiftUI.

Mira runs entirely on your own hardware — no cloud, no subscription, no data leaving your machine. It connects to a local Python server that manages an Ollama model, and pairs with an iPhone over Bonjour or Tailscale for the same experience on the go.

## Features

- **Local-first** — all inference runs on your Mac via Ollama; nothing is sent to external APIs
- **Streaming responses** — server-sent events for real-time token output
- **RAG** — attach documents and let the model search them before answering
- **Conversation history** — persistent, named conversations with a sidebar
- **Markdown rendering** — code blocks, tables, and inline formatting via MarkdownUI
- **iOS companion** — iPhone app connects to the Mac server over WiFi (Bonjour) or remotely (Tailscale)
- **Dark & light modes** — warm stone palette that adapts to system appearance

## Requirements

| Component | Version |
|-----------|---------|
| Xcode | 26+ |
| macOS (dev machine) | 26+ |
| iOS (device) | 26+ |
| Swift | 6 |
| Python | 3.11+ (for the server) |
| Ollama | latest |

## Project structure

```
OllamaSearch/
├── Shared/          # Views, ViewModels, Models, Networking — runs on both platforms
│   ├── Views/
│   ├── ViewModels/
│   ├── Models/
│   └── Networking/
├── macOS/           # macOS-only: ServerManager, splash, file picker
├── iOS/             # iOS-only: Bonjour discovery, connection screen, file picker
└── Assets.xcassets/ # App icon (light / dark / tinted), accent colour
Design/
└── AppIcon.svg      # Source SVG for the app icon (eye + star mark)
```

## Architecture

```
iPhone (Mira iOS)
    └── WiFi / Tailscale ──► Mac (Mira macOS)
                                 └── localhost:8000 ──► Python server (FastAPI)
                                                            └── Ollama (LLM)
```

The macOS app spawns and supervises the Python server as a subprocess. The iOS app discovers it via Bonjour (`_ollamasearch._tcp`) on the local network, or connects manually using a Tailscale IP.

## Building

See [XCODE_SETUP.md](XCODE_SETUP.md) for the full step-by-step Xcode setup.

Quick start for an already-configured project:

1. Open `OllamaSearch.xcodeproj` in Xcode
2. Select the **macOS** destination → **⌘R**
3. On first launch, choose the Python server project folder when prompted
4. For iOS, connect your iPhone and select it as the destination → **⌘R**

## Name

*Mira* is the Spanish imperative of *mirar* — "look" — and the name of one of the oldest variable stars observed by astronomers, a red giant whose brightness pulses on a 332-day cycle. The pulsing glow in the splash screen is a small nod to that.

---

© Miguel Angel Baeyens 2026
