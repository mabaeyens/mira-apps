# Contributing to Mira

Thanks for your interest in Mira — the native macOS + iOS apps for local AI models.
This is a small, single-maintainer project, but issues, ideas, and pull requests are
welcome. Feel free to fork it and build something of your own.

## Reporting bugs and requesting features

Open an [issue](https://github.com/mabaeyens/mira-apps/issues). The issue template will
prompt you for the platform (iOS / iPadOS / macOS), OS version, app version + build, and
the mira-core server version — please fill those in, they make bugs far easier to reproduce.

**Security issues do not go in public issues** — see [SECURITY.md](SECURITY.md).

## Prerequisites

| Tool | Version |
|------|---------|
| Xcode | 26+ |
| macOS (dev machine) | 26+ |
| iOS (device) | 26+ |
| Swift | 6 |

The apps are a front end for the **[mira-core](https://github.com/mabaeyens/mira-core)**
server — you need a running server to do anything useful. Install it first (its README has a
one-command installer), then come back here.

## Building

See [XCODE_SETUP.md](XCODE_SETUP.md) for full setup. Quick start once configured:

1. Make sure the mira-core server is running.
2. Open `OllamaSearch.xcodeproj` in Xcode.
3. Select the **macOS** destination → **⌘R**, or connect an iPhone and select it → **⌘R**.

## Workflow

- **Spec first.** For anything non-trivial, jot a short spec (problem, files to touch,
  a hard constraint, edge cases, acceptance criteria) before writing code.
- **One feature or fix per pull request.** Keep commits coherent — squash trial-and-error
  noise before opening the PR.
- **Match the surrounding code.** Mira is SwiftUI + MVVM: view models are
  `@Observable @MainActor`, networking goes through the shared `APIClient` / `SSEClient`,
  and connection handling is intentionally resilient (probe first, show a banner only on
  failure). Follow the patterns already in `OllamaSearch/Shared/`.

## Before you open a pull request

- Build for the **iOS Simulator** *and* a **macOS** destination — both targets share code,
  so a change can pass on one and break the other.
- Smoke-test the actual change: launch, open a conversation, send a message, exercise the
  feature you touched.
- Don't commit secrets, API keys, or local config (`mira.yaml`, signing credentials, etc.).
- Update the README / CHANGELOG if the change is user-facing.

## Pull request

Fill in the PR template (summary, linked issue, platforms tested, screenshots for UI
changes). Then open it against `main`.
