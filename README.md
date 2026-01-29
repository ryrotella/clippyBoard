# ClipBoard - macOS Clipboard History Manager

A native macOS clipboard history application built with Swift and SwiftUI.

## Features

- **Clipboard History**: Automatically saves everything you copy
- **Quick Access**: Menu bar app with global keyboard shortcut (⌘⇧V)
- **Search**: Instantly find past clipboard items
- **Multiple Types**: Supports text, images, files, and links
- **Pinned Items**: Keep frequently used items always accessible
- **Privacy First**: Exclude sensitive apps, auto-clear options

## Requirements

- macOS 13.0 (Ventura) or later
- Xcode 15.0 or later

## Getting Started

1. Open `ClipBoard.xcodeproj` in Xcode
2. Build and run (⌘R)
3. Grant accessibility permissions when prompted

## Project Structure

```
ClipBoardApp/
├── docs/                    # Documentation
│   ├── implementation-plan.md
│   ├── design-decisions.md
│   └── session-notes/
├── ClipBoard/               # Main app source
│   ├── App/                 # App entry point
│   ├── Views/               # SwiftUI views
│   ├── Models/              # Data models
│   ├── Services/            # Core services
│   └── Utilities/           # Helper functions
└── ClipBoardTests/          # Unit tests
```

## License

MIT License
