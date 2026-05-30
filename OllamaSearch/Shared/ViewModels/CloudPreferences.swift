import Foundation

// Persists UI preferences to NSUbiquitousKeyValueStore so they sync across
// the user's devices automatically (requires iCloud KV entitlement).
@Observable
@MainActor
final class CloudPreferences {
    private let kv = NSUbiquitousKeyValueStore.default
    @ObservationIgnored private var isLoading = false

    var sidebarPinned: Bool = true {
        didSet { if !isLoading { kv.set(sidebarPinned, forKey: "cp_sidebarPinned") } }
    }
    var projectsExpanded: Bool = true {
        didSet { if !isLoading { kv.set(projectsExpanded, forKey: "cp_projectsExpanded") } }
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
        if kv.object(forKey: "cp_sidebarPinned") != nil {
            sidebarPinned = kv.bool(forKey: "cp_sidebarPinned")
        }
        if kv.object(forKey: "cp_projectsExpanded") != nil {
            projectsExpanded = kv.bool(forKey: "cp_projectsExpanded")
        }
        isLoading = false
    }
}
