# Mira — Press Kit

## About Mira

Mira is a native iOS and macOS app for running AI conversations entirely on your own hardware. It connects to a lightweight server running on your Mac and streams responses from local language models via Ollama. No account, no cloud, no data leaving your network.

The name comes from two sources: the Spanish imperative of *mirar* — "look" — and Mira Ceti, one of the oldest variable stars observed by astronomers, a red giant whose brightness pulses on a 332-day cycle. Together they capture the spirit of the project: a quiet, local intelligence that looks with you.

**Version:** 1.0  
**Platforms:** iOS 18+, macOS 15+  
**Developer:** Miguel Angel Baeyens  
**Contact:** https://linkedin.com/in/mabaeyens  

---

## Key facts

- Runs AI models entirely on a local Mac — nothing sent to any server
- Native SwiftUI on both iPhone and Mac — not a web app or Electron wrapper
- Auto-discovers your Mac on Wi-Fi via Bonjour — no IP addresses to configure
- Works remotely over Tailscale for secure access from anywhere
- Supports any model that runs in Ollama: Llama, Mistral, Gemma, Qwen, and more
- Persistent conversation history stored locally on your Mac
- Free download, no subscription

---

## Design

**Primary color:** Amber `#D09268` (dark mode) / `#C07A4F` (light mode)  
**Background:** Warm stone `#1C1917`  
**Typography:** Bookerly (display headings), San Francisco (UI)  
**Icon:** An eye and four-pointed star in amber on a dark stone background

---

## Assets in this folder

| File | Description |
|------|-------------|
| `app-icon.svg` | Full app icon with background — square, 1024×1024 viewBox |
| `app-icon-1024.png` | App icon PNG, 1024×1024, dark variant |
| `app-icon-tinted-1024.png` | App icon PNG, 1024×1024, monochrome/tinted variant |
| `logomark.svg` | Eye+star mark only, transparent background, amber — for use on dark backgrounds |

Screenshots are not included here. See `marketing.md` for the full screenshot plan.

---

## One-paragraph description (short)

Mira is a native iPhone and Mac app that lets you have AI conversations using models running entirely on your own machine. It connects to a local server via Wi-Fi — no account, no cloud, no data leaving your network. Built with SwiftUI, it feels like a first-party Apple app: Bonjour auto-discovery, persistent conversation history, and a warm, minimal design language.

## One-paragraph description (long)

Mira is a native iOS and macOS client for local language models. It pairs with a lightweight Python server running as a macOS login item and streams responses from Ollama — supporting Llama, Mistral, Gemma, Qwen, and any other model you choose to run. On the same Wi-Fi network, your iPhone finds your Mac automatically via Bonjour with no configuration. Away from home, Tailscale provides encrypted remote access. Everything — conversations, history, model weights — stays on your hardware. Mira is built for people who want the capability of modern AI without surrendering their data to get it.
