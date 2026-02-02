import Foundation
import SwiftUI
import Carbon

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

// MARK: - Appearance Mode

enum AppearanceMode: String, CaseIterable {
    case system = "system"
    case light = "light"
    case dark = "dark"
    case highContrast = "highContrast"

    var displayName: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        case .highContrast: return "High Contrast"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        case .highContrast: return .dark // High contrast uses dark with special colors
        }
    }
}

// MARK: - Row Density

enum RowDensity: String, CaseIterable {
    case compact = "compact"
    case comfortable = "comfortable"
    case spacious = "spacious"

    var displayName: String {
        rawValue.capitalized
    }

    var verticalPadding: CGFloat {
        switch self {
        case .compact: return 6
        case .comfortable: return 10
        case .spacious: return 14
        }
    }

    var spacing: CGFloat {
        switch self {
        case .compact: return 8
        case .comfortable: return 12
        case .spacious: return 16
        }
    }
}

// MARK: - Panel Mode

enum PanelMode: String, CaseIterable {
    case slidingPanel = "slidingPanel"
    case popover = "popover"

    var displayName: String {
        switch self {
        case .slidingPanel: return "Sliding Panel"
        case .popover: return "Classic Popover"
        }
    }
}

// MARK: - Panel Edge

enum PanelEdge: String, CaseIterable {
    case left = "left"
    case right = "right"
    case top = "top"
    case bottom = "bottom"

    var displayName: String {
        rawValue.capitalized
    }
}

// MARK: - Thumbnail Size

enum ThumbnailSize: String, CaseIterable {
    case small = "small"
    case medium = "medium"
    case large = "large"

    var displayName: String {
        rawValue.capitalized
    }

    var smallSize: CGFloat {
        switch self {
        case .small: return 40
        case .medium: return 48
        case .large: return 60
        }
    }

    var largeSize: CGFloat {
        switch self {
        case .small: return 80
        case .medium: return 100
        case .large: return 140
        }
    }
}

// MARK: - Keyboard Shortcut

struct KeyboardShortcut: Codable, Equatable {
    var keyCode: UInt32
    var modifiers: UInt32

    var displayString: String {
        var parts: [String] = []
        if modifiers & UInt32(controlKey) != 0 { parts.append("⌃") }
        if modifiers & UInt32(optionKey) != 0 { parts.append("⌥") }
        if modifiers & UInt32(shiftKey) != 0 { parts.append("⇧") }
        if modifiers & UInt32(cmdKey) != 0 { parts.append("⌘") }
        parts.append(keyCodeToString(keyCode))
        return parts.joined()
    }

    private func keyCodeToString(_ code: UInt32) -> String {
        let keyMap: [UInt32: String] = [
            0x00: "A", 0x01: "S", 0x02: "D", 0x03: "F", 0x04: "H",
            0x05: "G", 0x06: "Z", 0x07: "X", 0x08: "C", 0x09: "V",
            0x0B: "B", 0x0C: "Q", 0x0D: "W", 0x0E: "E", 0x0F: "R",
            0x10: "Y", 0x11: "T", 0x12: "1", 0x13: "2", 0x14: "3",
            0x15: "4", 0x16: "6", 0x17: "5", 0x18: "=", 0x19: "9",
            0x1A: "7", 0x1B: "-", 0x1C: "8", 0x1D: "0", 0x1E: "]",
            0x1F: "O", 0x20: "U", 0x21: "[", 0x22: "I", 0x23: "P",
            0x25: "L", 0x26: "J", 0x28: "K", 0x2D: "N", 0x2E: "M",
            0x31: "Space", 0x24: "↩", 0x30: "Tab", 0x33: "⌫", 0x35: "Esc"
        ]
        return keyMap[code] ?? "?"
    }

    static let defaultPopover = KeyboardShortcut(keyCode: 0x09, modifiers: UInt32(cmdKey | shiftKey)) // ⌘⇧V
    static let defaultPopout = KeyboardShortcut(keyCode: 0x0B, modifiers: UInt32(cmdKey | shiftKey)) // ⌘⇧B
}

// MARK: - App Settings

class AppSettings: ObservableObject {
    static let shared = AppSettings()

    // MARK: - General Settings
    @AppStorage("historyLimit") var historyLimit: Int = 500
    @AppStorage("defaultViewMode") var defaultViewMode: String = ViewMode.grid.rawValue

    // Launch at login uses SMAppService
    @MainActor
    var launchAtLogin: Bool {
        get { LaunchAtLoginService.shared.isEnabled }
        set { LaunchAtLoginService.shared.isEnabled = newValue }
    }
    @AppStorage("excludedApps") var excludedAppsData: Data = Data()
    @AppStorage("incognitoMode") var incognitoMode: Bool = false
    @AppStorage("autoClearDays") var autoClearDays: Int = 0 // 0 = never
    @AppStorage("sensitiveContentProtection") var sensitiveContentProtection: Bool = true // Require auth for passwords/tokens

    // MARK: - Keyboard Shortcuts (stored as JSON)
    @AppStorage("popoverShortcutData") var popoverShortcutData: Data = Data()
    @AppStorage("popoutShortcutData") var popoutShortcutData: Data = Data()

    var popoverShortcut: KeyboardShortcut {
        get {
            (try? JSONDecoder().decode(KeyboardShortcut.self, from: popoverShortcutData)) ?? .defaultPopover
        }
        set {
            popoverShortcutData = (try? JSONEncoder().encode(newValue)) ?? Data()
            objectWillChange.send()
            NotificationCenter.default.post(name: .shortcutsDidChange, object: nil)
        }
    }

    var popoutShortcut: KeyboardShortcut {
        get {
            (try? JSONDecoder().decode(KeyboardShortcut.self, from: popoutShortcutData)) ?? .defaultPopout
        }
        set {
            popoutShortcutData = (try? JSONEncoder().encode(newValue)) ?? Data()
            objectWillChange.send()
            NotificationCenter.default.post(name: .shortcutsDidChange, object: nil)
        }
    }

    // Popout window persistence
    @AppStorage("popoutWindowX") var popoutWindowX: Double = 100
    @AppStorage("popoutWindowY") var popoutWindowY: Double = 100
    @AppStorage("popoutWindowWidth") var popoutWindowWidth: Double = 340
    @AppStorage("popoutWindowHeight") var popoutWindowHeight: Double = 500
    @AppStorage("popoutWindowFloating") var popoutWindowFloating: Bool = false

    // MARK: - Appearance Settings

    /// Appearance mode (system/light/dark/high contrast)
    @AppStorage("appearanceMode") var appearanceModeRaw: String = AppearanceMode.system.rawValue

    /// Text size scale factor (0.8 to 1.5, where 1.0 is default)
    @AppStorage("textSizeScale") var textSizeScale: Double = 1.0

    /// Accent color for highlights (stored as hex string)
    @AppStorage("accentColorHex") var accentColorHex: String = ""

    /// Show separators between rows
    @AppStorage("showRowSeparators") var showRowSeparators: Bool = true

    /// Separator color (stored as hex string, empty = default)
    @AppStorage("separatorColorHex") var separatorColorHex: String = ""

    /// Row density setting
    @AppStorage("rowDensity") var rowDensityRaw: String = RowDensity.comfortable.rawValue

    /// Thumbnail size setting
    @AppStorage("thumbnailSize") var thumbnailSizeRaw: String = ThumbnailSize.medium.rawValue

    /// Window opacity (0.5 to 1.0)
    @AppStorage("windowOpacity") var windowOpacity: Double = 1.0

    /// Show source app icon
    @AppStorage("showSourceAppIcon") var showSourceAppIcon: Bool = true

    /// Show timestamps
    @AppStorage("showTimestamps") var showTimestamps: Bool = true

    /// Show content type badges
    @AppStorage("showTypeBadges") var showTypeBadges: Bool = true

    /// Max preview lines (1-4)
    @AppStorage("maxPreviewLines") var maxPreviewLines: Int = 2

    // MARK: - Display Mode Settings

    /// Simplified display mode (hides type badges, shows minimal info)
    @AppStorage("simplifiedDisplay") var simplifiedDisplay: Bool = false

    /// Show explicit copy button on each row
    @AppStorage("showCopyButton") var showCopyButton: Bool = true

    // MARK: - Copy Feedback Settings

    /// Show toast notification when copying
    @AppStorage("copyFeedbackToast") var copyFeedbackToast: Bool = true

    /// Play sound when copying
    @AppStorage("copyFeedbackSound") var copyFeedbackSound: Bool = false

    // MARK: - Click-to-Paste Settings

    /// Enable click-to-paste (requires Accessibility permission)
    @AppStorage("clickToPaste") var clickToPaste: Bool = true

    // MARK: - Panel Mode Settings

    /// Panel mode: slidingPanel (default) or popover
    @AppStorage("panelMode") var panelMode: String = PanelMode.slidingPanel.rawValue

    /// Panel edge for sliding panel (left, right, top, bottom)
    @AppStorage("panelEdge") var panelEdge: String = PanelEdge.left.rawValue

    /// Sliding panel width
    @AppStorage("slidingPanelWidth") var slidingPanelWidth: Double = 380

    /// Sliding panel height (for top/bottom edges)
    @AppStorage("slidingPanelHeight") var slidingPanelHeight: Double = 520

    // MARK: - Quick Access Shortcuts

    /// Quick access shortcuts data (⌥1 through ⌥5)
    @AppStorage("quickAccessShortcutsEnabled") var quickAccessShortcutsEnabled: Bool = true

    // MARK: - API Settings

    /// Enable local API server
    @AppStorage("apiEnabled") var apiEnabled: Bool = false

    /// API server port
    @AppStorage("apiPort") var apiPort: Int = 19847

    // MARK: - Onboarding

    /// Whether onboarding has been completed
    @AppStorage("onboardingCompleted") var onboardingCompleted: Bool = false

    // MARK: - Appearance Computed Properties

    var rowDensity: RowDensity {
        get { RowDensity(rawValue: rowDensityRaw) ?? .comfortable }
        set { rowDensityRaw = newValue.rawValue }
    }

    var thumbnailSizeSetting: ThumbnailSize {
        get { ThumbnailSize(rawValue: thumbnailSizeRaw) ?? .medium }
        set { thumbnailSizeRaw = newValue.rawValue }
    }

    var accentColor: Color? {
        get {
            guard !accentColorHex.isEmpty else { return nil }
            return Color(hex: accentColorHex)
        }
        set {
            accentColorHex = newValue?.toHex() ?? ""
        }
    }

    var appearanceMode: AppearanceMode {
        get { AppearanceMode(rawValue: appearanceModeRaw) ?? .system }
        set { appearanceModeRaw = newValue.rawValue }
    }

    var separatorColor: Color? {
        get {
            guard !separatorColorHex.isEmpty else { return nil }
            return Color(hex: separatorColorHex)
        }
        set {
            separatorColorHex = newValue?.toHex() ?? ""
        }
    }

    var panelModeSetting: PanelMode {
        get { PanelMode(rawValue: panelMode) ?? .slidingPanel }
        set { panelMode = newValue.rawValue }
    }

    var panelEdgeSetting: PanelEdge {
        get { PanelEdge(rawValue: panelEdge) ?? .left }
        set { panelEdge = newValue.rawValue }
    }

    /// Returns the effective separator color based on appearance mode
    var effectiveSeparatorColor: Color {
        if let custom = separatorColor {
            return custom
        }
        // Default colors based on appearance mode
        switch appearanceMode {
        case .highContrast:
            return .white.opacity(0.5)
        default:
            return Color(nsColor: .separatorColor)
        }
    }

    /// Returns true if high contrast mode is enabled
    var isHighContrast: Bool {
        appearanceMode == .highContrast
    }

    /// Scaled font size based on text size scale
    func scaledSize(_ baseSize: CGFloat) -> CGFloat {
        baseSize * textSizeScale
    }

    // MARK: - Appearance Defaults

    static let defaultTextSizeScale: Double = 1.0
    static let defaultRowDensity: RowDensity = .comfortable
    static let defaultThumbnailSize: ThumbnailSize = .medium
    static let defaultWindowOpacity: Double = 1.0
    static let defaultMaxPreviewLines: Int = 2

    func resetAppearanceToDefaults() {
        appearanceModeRaw = AppearanceMode.system.rawValue
        textSizeScale = Self.defaultTextSizeScale
        accentColorHex = ""
        separatorColorHex = ""
        showRowSeparators = true
        rowDensityRaw = Self.defaultRowDensity.rawValue
        thumbnailSizeRaw = Self.defaultThumbnailSize.rawValue
        windowOpacity = Self.defaultWindowOpacity
        showSourceAppIcon = true
        showTimestamps = true
        showTypeBadges = true
        maxPreviewLines = Self.defaultMaxPreviewLines
        simplifiedDisplay = false
        showCopyButton = true
        copyFeedbackToast = true
        copyFeedbackSound = false
        panelMode = PanelMode.slidingPanel.rawValue
        panelEdge = PanelEdge.left.rawValue
    }

    func resetShortcutsToDefaults() {
        popoverShortcutData = Data()
        popoutShortcutData = Data()
        objectWillChange.send()
        NotificationCenter.default.post(name: .shortcutsDidChange, object: nil)
    }

    // MARK: - General Computed Properties

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
        // 1Password
        "com.agilebits.onepassword7",
        "com.agilebits.onepassword-osx",
        "com.1password.1password",
        // LastPass
        "com.lastpass.LastPass",
        // Bitwarden
        "com.bitwarden.desktop",
        "com.bitwarden.desktop.safari",
        // Dashlane
        "com.dashlane.dashlanephonefinal",
        // KeePassXC
        "org.keepassxc.keepassxc",
        // Enpass
        "io.enpass.mac",
        // RoboForm
        "com.siber.roboform",
        // Keeper
        "com.callpod.keepersecuritymac",
        // NordPass
        "com.nordpass.macos.NordPass",
        // Apple Passwords & Keychain
        "com.apple.Passwords",
        "com.apple.keychainaccess"
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

// MARK: - Notification Names

extension Notification.Name {
    static let shortcutsDidChange = Notification.Name("shortcutsDidChange")
}

// MARK: - Color Hex Extension

extension Color {
    init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        guard hexSanitized.count == 6 else { return nil }

        var rgb: UInt64 = 0
        guard Scanner(string: hexSanitized).scanHexInt64(&rgb) else { return nil }

        self.init(
            red: Double((rgb & 0xFF0000) >> 16) / 255.0,
            green: Double((rgb & 0x00FF00) >> 8) / 255.0,
            blue: Double(rgb & 0x0000FF) / 255.0
        )
    }

    func toHex() -> String? {
        // Convert to RGB color space to handle grayscale colors
        guard let rgbColor = NSColor(self).usingColorSpace(.deviceRGB),
              let components = rgbColor.cgColor.components,
              components.count >= 3 else {
            return nil
        }

        let r = Int(components[0] * 255)
        let g = Int(components[1] * 255)
        let b = Int(components[2] * 255)

        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
