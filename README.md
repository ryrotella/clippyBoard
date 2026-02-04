# ClippyBoard

**Your clipboard, supercharged.**

A powerful, privacy-focused clipboard history manager for macOS. Keep your clipboard history local, searchable, and accessible.

![macOS](https://img.shields.io/badge/macOS-14.0%2B-blue)
![License](https://img.shields.io/badge/license-MIT-green)

---

## Features

### Clipboard History
- Automatically saves everything you copy (text, images, files, URLs)
- Instant search through your clipboard history
- Pin important items for quick access
- Filter by type: Text, Images, Files, URLs

### Privacy First
- **100% local** — Your data never leaves your Mac
- **Sensitive content detection** — Automatically detects passwords, API keys, tokens
- **Touch ID protection** — Secure sensitive items with biometric authentication
- **Incognito mode** — Pause clipboard capture anytime

### Beautiful Interface
- **Sliding panel** — Slides in from any screen edge
- **Drag to detach** — Pull the panel to create a floating window
- **Dark mode support** — Follows system appearance
- **Customizable** — Adjust opacity, position, and behavior

### Keyboard-Driven
- **Global hotkey** — Open from anywhere (default: `Cmd+Shift+V`)
- **Quick paste** — Recent items with `Option+1` through `Option+5`
- **Customizable shortcuts** — Set your own key combinations - thank you to @soffes and his HotKey for MacOS [repo!](https://github.com/soffes/HotKey)

### Screenshot History
- Automatically captures screenshots to clipboard history
- Quick access to recent screenshots from the panel
- Works with `Cmd+Shift+3`, `Cmd+Shift+4`, and `Cmd+Shift+5`
- Thumbnails preview in clipboard list
- Requires Full Disk Access permission (optional)

### AI Agent API
- Local REST API for automation and AI integration
- Full CRUD operations on clipboard items
- Search, copy, paste programmatically
- Bearer token authentication
- Perfect for AI assistants and automation scripts

---

## Installation

### Download DMG

1. Download the latest `.dmg` from [Releases](https://github.com/ryrotella/clippyBoard/releases)
2. Open the DMG and drag ClippyBoard to Applications
3. Launch from Applications
4. Grant permissions when prompted

### Build from Source

```bash
git clone https://github.com/ryrotella/clippyBoard.git
cd clippyBoard
open ClipBoard/ClippyBoard/ClippyBoard.xcodeproj
```

Build and run with Xcode (`Cmd+R`).

---

## Requirements

- macOS 14.0 (Sonoma) or later
- Apple Silicon or Intel Mac

---

## Permissions

| Permission | Required | Purpose |
|------------|----------|---------|
| Accessibility | Optional | Click-to-paste and API paste automation |
| Full Disk Access | Optional | Screenshot history capture |

ClippyBoard works without these permissions in copy-only mode.

### Enabling Screenshot History

1. Open **System Settings** → **Privacy & Security** → **Full Disk Access**
2. Click the **+** button and add ClippyBoard
3. Restart ClippyBoard

Screenshots will now automatically appear in your clipboard history.

---

## Quick Start

| Action | How |
|--------|-----|
| Open ClippyBoard | Click menu bar icon or `Cmd+Shift+V` |
| Copy item | Click any item |
| Search | Start typing |
| Filter by type | Click All / Text / Image / File / URL |
| Pin item | Right-click → Pin |
| Settings | Right-click menu bar icon → Settings |

---

## API

ClippyBoard includes a local REST API for automation and AI agents.

### Enable API

Settings → Advanced → Enable Local API

### Example Usage

```bash
# Health check
curl -H "Authorization: Bearer YOUR_TOKEN" http://localhost:19847/api/health

# List clipboard items
curl -H "Authorization: Bearer YOUR_TOKEN" http://localhost:19847/api/items

# Create an item
curl -X POST -H "Authorization: Bearer YOUR_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"content": "Hello World", "sourceAppName": "My Script"}' \
  http://localhost:19847/api/items

# Search
curl -H "Authorization: Bearer YOUR_TOKEN" \
  "http://localhost:19847/api/search?q=hello"
```

### Endpoints

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/api/health` | Health check |
| GET | `/api/items` | List items (max 100) |
| GET | `/api/items/:id` | Get single item |
| POST | `/api/items` | Create text/URL item |
| DELETE | `/api/items/:id` | Delete item |
| PUT | `/api/items/:id/pin` | Toggle pin |
| POST | `/api/items/:id/copy` | Copy to clipboard |
| POST | `/api/items/:id/paste` | Copy and paste |
| GET | `/api/search?q=` | Search items |
| GET | `/api/screenshots` | List screenshots |
| GET | `/api/screenshots/:id/image` | Get screenshot image |

See [API_DOCUMENTATION.md](API_DOCUMENTATION.md) for full details.

### Security Features (v1.2)

- Localhost-only connections
- Rate limiting (60 requests/minute)
- Request size limits (1MB max)
- Connection timeouts (30s)
- Constant-time token comparison

---

## Project Structure

```
ClipBoardApp/
├── ClipBoard/ClippyBoard/       # Xcode project
│   └── ClippyBoard/
│       ├── App/                 # App entry point
│       ├── Views/               # SwiftUI views
│       ├── Models/              # Data models
│       ├── Services/            # Core services
│       └── Utilities/           # Helpers
├── docs/                        # Documentation
├── API_DOCUMENTATION.md         # API reference
└── ExportOptions.plist          # Build config
```

---

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Submit a pull request

---

## License

MIT License — See [LICENSE](LICENSE) for details.

---

**Made with ♥ for clipboard power users.**
