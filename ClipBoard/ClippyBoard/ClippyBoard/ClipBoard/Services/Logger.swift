import os

/// Centralized logging utility using OSLog for structured, privacy-aware logging
enum AppLogger {
    private static let subsystem = "com.app.ClippyBoard"

    /// Logger for clipboard-related operations
    static let clipboard = Logger(subsystem: subsystem, category: "clipboard")

    /// Logger for screenshot-related operations
    static let screenshot = Logger(subsystem: subsystem, category: "screenshot")

    /// Logger for general app operations
    static let general = Logger(subsystem: subsystem, category: "general")

    /// Logger for database operations
    static let database = Logger(subsystem: subsystem, category: "database")

    /// Logger for hotkey operations
    static let hotkeys = Logger(subsystem: subsystem, category: "hotkeys")
}
