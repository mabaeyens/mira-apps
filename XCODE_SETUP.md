# Xcode Project Setup

Follow these steps once Xcode is installed.

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

## 3. Configure targets

The Xcode project has two targets: the macOS app and the iOS app.

For **each target**:
1. Select the target in Project Settings
2. **General > Deployment Info**: set iOS 26.0 / macOS 26.0
3. **Build Settings > Swift Language Version**: Swift 6

Assign files to the right targets:
- `Shared/**` → both targets
- `macOS/**` → macOS target only
- `iOS/**` → iOS target only

For the **macOS target**:
- **Signing & Capabilities**: sign with your Apple ID (personal team)
- Add capability: **Network** (for HTTP calls to localhost)

For the **iOS target**:
- Add capability: **Local Network** (required for Bonjour)
- In `Info.plist` add key `NSLocalNetworkUsageDescription` with value:
  `"OllamaSearch needs local network access to discover the Mac server."`
- Add key `NSBonjourServices` → Array → Item 0: `_ollamasearch._tcp`

## 4. Add SPM dependencies

1. **File > Add Package Dependencies…**
2. Add: `https://github.com/gonzalezreal/swift-markdown-ui` (from: 2.4.0)
3. Add: `https://github.com/raspu/Highlightr` (from: 2.2.0)
4. When prompted, add `MarkdownUI` to both targets; add `Highlightr` to both targets

## 5. Set the macOS app entry point

The macOS target must use `macOS/OllamaSearchApp.swift` as its `@main` struct.
The iOS target must use `iOS/OllamaSearchApp.swift`.

Because both files declare `@main`, you need to:
- In Build Settings for each target, set **Swift Active Compilation Conditions**:
  - macOS target: `MACOS`
  - iOS target: `IOS`
- Wrap `@main` in each file with `#if MACOS` / `#if IOS`

OR (simpler): rename `OllamaSearchApp.swift` to use different target membership.
Xcode handles this automatically if you uncheck the other target in the file inspector.

## 6. Build and run

1. Select the macOS scheme → **⌘R**
2. First run: a file picker opens asking for the `ollama-web-search` project folder
3. The app launches the Python server and polls `/health`
4. Once ready, the splash dismisses and the chat window appears

For iOS: select an iPhone simulator or physical device → **⌘R**
The connection screen appears — tap Auto (Bonjour) if on the same WiFi as the Mac.
