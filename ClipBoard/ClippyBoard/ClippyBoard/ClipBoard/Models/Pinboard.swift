import Foundation
import SwiftData

@Model
final class Pinboard {
    var id: UUID
    var name: String // "Clipboard", "Useful Links", etc.
    var icon: String? // SF Symbol name
    var isDefault: Bool // "Clipboard" tab is default
    var sortOrder: Int

    init(
        id: UUID = UUID(),
        name: String,
        icon: String? = nil,
        isDefault: Bool = false,
        sortOrder: Int = 0
    ) {
        self.id = id
        self.name = name
        self.icon = icon
        self.isDefault = isDefault
        self.sortOrder = sortOrder
    }

    static func createDefault() -> Pinboard {
        Pinboard(
            name: "Clipboard",
            icon: "clipboard",
            isDefault: true,
            sortOrder: 0
        )
    }
}
