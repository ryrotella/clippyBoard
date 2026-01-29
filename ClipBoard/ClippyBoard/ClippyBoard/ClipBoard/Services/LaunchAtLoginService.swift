import Foundation
import ServiceManagement

@MainActor
class LaunchAtLoginService {
    static let shared = LaunchAtLoginService()

    private init() {}

    var isEnabled: Bool {
        get {
            SMAppService.mainApp.status == .enabled
        }
        set {
            do {
                if newValue {
                    try SMAppService.mainApp.register()
                    print("LaunchAtLogin: Registered successfully")
                } else {
                    try SMAppService.mainApp.unregister()
                    print("LaunchAtLogin: Unregistered successfully")
                }
            } catch {
                print("LaunchAtLogin: Failed to \(newValue ? "register" : "unregister"): \(error)")
            }
        }
    }

    var statusDescription: String {
        switch SMAppService.mainApp.status {
        case .enabled:
            return "Enabled"
        case .notRegistered:
            return "Not registered"
        case .notFound:
            return "Not found"
        case .requiresApproval:
            return "Requires approval in System Settings"
        @unknown default:
            return "Unknown"
        }
    }
}
