import SwiftUI
import SwiftData

@main
struct ClipBoardApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // Settings window (accessible via app menu or programmatically)
        Settings {
            SettingsView()
        }
    }
}
