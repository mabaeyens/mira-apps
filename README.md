# Mira

A native macOS and iOS chat app for local AI models, built with SwiftUI.

Mira runs entirely on your own hardware — no cloud, no subscription, no data leaving your machine. It connects to a local Python server that runs inference on a local backend ([oMLX](https://omlx.ai) by default), embeds documents locally for RAG, and can search the web on your behalf. The iPhone app pairs with the Mac over Bonjour or Tailscale for the same experience on the go.

See [CHANGELOG.md](CHANGELOG.md) for recent changes.

## Backend

The apps are the SwiftUI front end for **[mira-core](https://github.com/mabaeyens/mira-core)** — the local FastAPI server that does inference, RAG, web search, and tool calling. The server must be running for the apps to work; see [askmira.es](https://askmira.es) for an overview and TestFlight access.

**Testing it?** Tell me what's useful and what broke in [Discussions](https://github.com/mabaeyens/mira-core/discussions); I read everything.

## Features

- **Local-first** — inference runs on your Mac via oMLX (or dFlash / mlx-lm / Ollama); nothing is sent to external APIs
- **Streaming responses** — server-sent events for real-time token output
- **Adaptive thinking** — extended reasoning on complex questions; tri-state toggle (off / adaptive / force-on)
- **Web search** — the model can search the web and fetch pages when it needs to; sources surface as clickable links
- **RAG** — attach documents and let the model search them before answering
- **Long-term memory** — save facts across conversations; model uses them automatically
- **Voice input** — tap the mic to dictate; live transcription via Apple Speech (on-device, iOS only)
- **Conversation history** — persistent, named conversations with a sidebar
- **Markdown rendering** — code blocks, tables, and inline formatting via MarkdownUI
- **Model picker** — reads available models from the server; adding a model in `mira.yaml` shows up without an app update, and the backend label tracks the active model
- **iOS companion** — iPhone app connects to the Mac server over WiFi (Bonjour) or remotely (Tailscale over HTTPS), authenticating with a shared bearer token
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
| oMLX | 0.4.3+ (default inference backend) |

The server, inference backend, and default model (`Qwen3.6-35B-A3B`) are set up by [mira-core](https://github.com/mabaeyens/mira-core) — see its README for the one-command installer.

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
    └── Bonjour / Tailscale (HTTPS :8443) ──► Mac (Mira macOS)
                                                  └── localhost:8000 ──► Python server (FastAPI, mira-core)
                                                                            ├── oMLX (inference, port 8080)
                                                                            ├── nomic-embed-text-v1.5 (RAG embeddings, local)
                                                                            └── web search + page fetch (sources as links)
```

The macOS app connects to the Python server ([mira-core](https://github.com/mabaeyens/mira-core)), which runs as a macOS LaunchAgent (`com.mab.mira`) installed separately from the app. oMLX is started and managed by the server. The iOS app discovers the Mac over Bonjour (`_ollamasearch._tcp`) on the local network, or connects manually using a Tailscale hostname.

**The app requires the Mac server to run.** There is no standalone offline mode — inference happens on the Mac. For access outside your home network, install [Tailscale](https://tailscale.com) on both devices and use the **Manual URL** option with your Tailscale hostname (the server listens on HTTPS port `8443` for remote access).

Once the server is reachable beyond loopback, it requires a shared token. Set `auth_token:` in the server's `mira.yaml` (or the `MIRA_TOKEN` env var); the apps send it as `Authorization: Bearer <token>` on every request automatically. See the [mira-core README](https://github.com/mabaeyens/mira-core#access-control) for details.

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

## Development Workflow

This project is the result of a strategic collaboration between human design and AI-assisted code generation.

- **Architecture & Logic:** Fully defined by the author. This includes app structure, UI/UX decisions, state management patterns, and the client–server contract.
- **Code Generation:** The syntactic implementation and line-by-line SwiftUI code was written by **Claude Code**, following precise and iterative instructions provided by the author.
- **Supervision & Refinement:** All code was manually reviewed, tested on simulator and device, and adjusted to ensure quality, consistency, and compliance with project standards.

This approach demonstrates the ability to direct advanced AI tools to accelerate development without sacrificing creative control or technical quality.

## Contributing

Issues, ideas, and pull requests are welcome — see [CONTRIBUTING.md](CONTRIBUTING.md) for setup and conventions. Found a security issue? Please follow [SECURITY.md](SECURITY.md) rather than opening a public issue. Feel free to fork this project and build your own.

## License

This project is licensed under the **MIT License** — see the [`LICENSE`](./LICENSE) file for the full text.

> **Note on authorship:** Although much of the source code was generated by an AI, the creative direction, architecture, and final integration are human work. Usage rights are granted under the terms of the MIT License.
