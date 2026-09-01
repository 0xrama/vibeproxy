import Foundation
import Combine

/// Fork-specific efficiency preferences shared between the settings UI and app lifecycle.
final class EfficiencySettings: ObservableObject {
    static let shared = EfficiencySettings()

    private enum Keys {
        static let onDemandBackend = "vibeproxy.fork.onDemandBackend"
        static let idleTimeoutMinutes = "vibeproxy.fork.idleTimeoutMinutes"
    }

    private enum Defaults {
        static let idleTimeoutMinutes = 15
        static let timeoutChoices = [5, 10, 15, 30, 60]
    }

    /// Keep the local proxy listening but only run the CLIProxyAPI backend while requests flow.
    @Published var onDemandBackendEnabled: Bool {
        didSet {
            guard oldValue != onDemandBackendEnabled else { return }
            UserDefaults.standard.set(onDemandBackendEnabled, forKey: Keys.onDemandBackend)
            onChange?()
        }
    }

    /// Stop the backend after this many minutes without traffic.
    @Published var idleTimeoutMinutes: Int {
        didSet {
            guard oldValue != idleTimeoutMinutes else { return }
            UserDefaults.standard.set(idleTimeoutMinutes, forKey: Keys.idleTimeoutMinutes)
        }
    }

    var idleTimeoutSeconds: TimeInterval {
        TimeInterval(idleTimeoutMinutes) * 60
    }

    static var availableTimeoutChoices: [Int] {
        Defaults.timeoutChoices
    }

    /// Fired on the publishing thread whenever a setting changes in a way the app delegate must react to.
    var onChange: (() -> Void)?

    private init() {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: Keys.onDemandBackend) == nil {
            onDemandBackendEnabled = true
        } else {
            onDemandBackendEnabled = defaults.bool(forKey: Keys.onDemandBackend)
        }
        let storedTimeout = defaults.integer(forKey: Keys.idleTimeoutMinutes)
        idleTimeoutMinutes = Defaults.timeoutChoices.contains(storedTimeout)
            ? storedTimeout
            : Defaults.idleTimeoutMinutes
    }
}
