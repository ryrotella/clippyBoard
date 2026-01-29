import Foundation
import SwiftUI

enum ViewMode: String, CaseIterable {
    case grid = "grid"
    case list = "list"

    var icon: String {
        switch self {
        case .grid: return "square.grid.2x2"
        case .list: return "list.bullet"
        }
    }
}

class AppSettings: ObservableObject {
    static let shared = AppSettings()

    @AppStorage("historyLimit") var historyLimit: Int = 500
    @AppStorage("defaultViewMode") var defaultViewMode: String = ViewMode.grid.rawValue

    // Launch at login uses SMAppService
    @MainActor
    var launchAtLogin: Bool {
        get { LaunchAtLoginService.shared.isEnabled }
        set { LaunchAtLoginService.shared.isEnabled = newValue }
    }
    @AppStorage("globalShortcut") var globalShortcut: String = "⌘⇧V"
    @AppStorage("excludedApps") var excludedAppsData: Data = Data()
    @AppStorage("incognitoMode") var incognitoMode: Bool = false
    @AppStorage("autoClearDays") var autoClearDays: Int = 0 // 0 = never

    // Popout window persistence
    @AppStorage("popoutWindowX") var popoutWindowX: Double = 100
    @AppStorage("popoutWindowY") var popoutWindowY: Double = 100
    @AppStorage("popoutWindowWidth") var popoutWindowWidth: Double = 340
    @AppStorage("popoutWindowHeight") var popoutWindowHeight: Double = 500
    @AppStorage("popoutWindowFloating") var popoutWindowFloating: Bool = false

    var viewMode: ViewMode {
        get { ViewMode(rawValue: defaultViewMode) ?? .grid }
        set { defaultViewMode = newValue.rawValue }
    }

    var excludedApps: [String] {
        get {
            (try? JSONDecoder().decode([String].self, from: excludedAppsData)) ?? defaultExcludedApps
        }
        set {
            excludedAppsData = (try? JSONEncoder().encode(newValue)) ?? Data()
        }
    }

    private let defaultExcludedApps = [
        "com.agilebits.onepassword7",
        "com.agilebits.onepassword-osx",
        "com.1password.1password",
        "com.lastpass.LastPass",
        "com.bitwarden.desktop",
        "com.dashlane.dashlanephonefinal"
    ]

    func isAppExcluded(_ bundleId: String?) -> Bool {
        guard let bundleId = bundleId else { return false }
        return excludedApps.contains(bundleId)
    }

    private init() {
        // Initialize excluded apps with defaults if empty
        if excludedApps.isEmpty {
            excludedApps = defaultExcludedApps
        }
    }
}
