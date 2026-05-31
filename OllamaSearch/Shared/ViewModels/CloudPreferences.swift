import Foundation

// Persists UI preferences to NSUbiquitousKeyValueStore so they sync across
// the user's devices automatically (requires iCloud KV entitlement).
@Observable
@MainActor
final class CloudPreferences {
    private let kv = NSUbiquitousKeyValueStore.default
    @ObservationIgnored private var isLoading = false

    var projectsExpanded: Bool = true {
        didSet { if !isLoading { kv.set(projectsExpanded, forKey: "cp_projectsExpanded") } }
    }

    var speechLanguage: String = "auto" {
        didSet { if !isLoading { kv.set(speechLanguage, forKey: "cp_speechLanguage") } }
    }

    init() {
        reload()
        NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: kv,
            queue: .main
        ) { [weak self] _ in self?.reload() }
        kv.synchronize()
    }

    private func reload() {
        isLoading = true
        if kv.object(forKey: "cp_projectsExpanded") != nil {
            projectsExpanded = kv.bool(forKey: "cp_projectsExpanded")
        }
        if kv.object(forKey: "cp_speechLanguage") != nil {
            speechLanguage = kv.string(forKey: "cp_speechLanguage") ?? "auto"
        }
        isLoading = false
    }
}
