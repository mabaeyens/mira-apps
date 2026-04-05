# Xcode Project Setup

Follow these steps once Xcode is installed and you have cloned the repo.

## 1. Create the Xcode project

1. Open Xcode → **File > New > Project**
2. Choose **Multiplatform > App**
3. Product name: `OllamaSearch`
4. Bundle Identifier: `com.yourname.OllamaSearch`
5. Interface: **SwiftUI**, Language: **Swift**
6. Uncheck "Use Core Data" and "Include Tests"
7. Save to: `~/Documents/Projects/OllamaSearch/`
   - When asked to create a new folder, say **No** — the folder already exists

## 2. Add the Swift files

Xcode will create placeholder `ContentView.swift` and `OllamaSearchApp.swift` files. Delete them from the project (move to Trash), then:

1. Right-click the `OllamaSearch` group in the navigator
2. **Add Files to "OllamaSearch"…**
3. Select all folders (`Shared/`, `macOS/`, `iOS/`) — check "Create groups"
4. Click **Add**

If any file shows a **?** badge after adding, right-click it → **Integrate > Add** to register it with the target.

## 3. Configure the target

This is a **single multiplatform target** (not separate macOS/iOS targets).

1. Select the target in Project Settings
2. **General > Deployment Info**: set iOS 26.0 / macOS 26.0
3. **Build Settings > Swift Language Version**: Swift 6
4. **Signing & Capabilities**: sign with your Apple ID (personal team)
5. Add capability: **Network** (macOS — for HTTP calls to localhost)
6. Add capability: **Local Network** (iOS — required for Bonjour)

### Info.plist keys (iOS)

| Key | Value |
|-----|-------|
| `NSLocalNetworkUsageDescription` | `Mira uses the local network to find your Mac server.` |
| `NSBonjourServices` | Array → Item 0: `_ollamasearch._tcp` |
| `NSAppTransportSecurity` → `NSAllowsLocalNetworking` | `YES` |
| `CFBundleDisplayName` | `Mira` |

## 4. Add SPM dependencies

1. **File > Add Package Dependencies…**
2. Add: `https://github.com/gonzalezreal/swift-markdown-ui` (from: 2.4.0)
3. Add: `https://github.com/raspu/Highlightr` (from: 2.2.0)
4. When prompted, add both packages to the target

## 5. Build and run

### macOS

1. Select the **My Mac** destination → **⌘R**
2. First run: a file picker opens — choose the Python server project folder
3. The Mira splash screen appears while the server subprocess starts and the model loads
4. Once ready (up to 60 s on first launch), the splash dismisses and the chat window appears

### iOS

1. Connect your iPhone via USB
2. Select it as the destination → **⌘R**
3. On first launch, trust the developer certificate:
   **Settings → General → VPN & Device Management → [your Apple ID] → Trust**
4. The Mira splash appears briefly, then the connection screen — tap **Auto (Bonjour)** if on the same WiFi as the Mac

After the initial install, USB is no longer needed:
- Disconnect USB — the app connects over WiFi
- Close Xcode — the macOS app keeps the server running independently

### Remote access (Tailscale)

Bonjour only works on the local network. For access away from home:

1. Install [Tailscale](https://tailscale.com) on both your Mac and iPhone
2. In the iOS app, choose **Manual URL** and enter your Mac's Tailscale IP: `http://100.x.x.x:8000`
3. The connection works identically to home WiFi

### iOS icon appearance

iOS 18 controls icon appearance separately from dark mode. To activate the dark icon variant:

> Home screen → long-press → **Customize** → **Dark** or **Automatic**

## Notes for future development

- **Single multiplatform target** — all files in `Shared/` are compiled for both platforms; `macOS/` and `iOS/` are platform-conditional via `#if os(macOS)` / `#if os(iOS)`.
- **`@Observable` and SwiftUI** — always read `@Observable` model state inside a `View` body, not in the `App` struct body. The App scene builder does not participate in SwiftUI's observation graph; state changes will not trigger re-renders there.
- **Adding new shared files** — after creating a file in `Shared/`, right-click it in the Xcode navigator → **Integrate > Add** to register it with the target.
