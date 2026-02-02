# ClippyBoard Local API Documentation

ClippyBoard provides a local HTTP API for integration with AI agents, automation tools, and other applications. The API runs only on localhost for security.

**Version:** 1.1
**Base URL:** `http://localhost:19847`

---

## Table of Contents

1. [Configuration](#configuration)
2. [Authentication](#authentication)
3. [Endpoints Overview](#endpoints-overview)
4. [Read Endpoints](#read-endpoints)
5. [Write Endpoints](#write-endpoints)
6. [Paste Endpoints](#paste-endpoints)
7. [Error Responses](#error-responses)
8. [Examples](#examples)
9. [Security Notes](#security-notes)
10. [Troubleshooting](#troubleshooting)

---

## Configuration

### Enable the API

1. Open ClippyBoard Settings (Option+click or right-click menu bar icon → Settings)
2. Go to the **Advanced** tab
3. Toggle **Enable Local API** on
4. Optionally change the port (default: 19847)

### Settings

| Setting | Default | Description |
|---------|---------|-------------|
| `apiEnabled` | `false` | Enable/disable the API server |
| `apiPort` | `19847` | Port number for the API server |

---

## Authentication

All API requests require Bearer token authentication.

### Getting Your Token

1. Open Settings → Advanced tab
2. Click **Copy** next to the API Token field
3. Store the token securely

### Using the Token

Include the token in the `Authorization` header:

```
Authorization: Bearer YOUR_TOKEN_HERE
```

### Regenerating the Token

Click **Regenerate Token** in Settings → Advanced to create a new token. The old token will immediately become invalid.

---

## Endpoints Overview

| Method | Endpoint | Description |
|--------|----------|-------------|
| `GET` | `/api/health` | Health check |
| `GET` | `/api/items` | List clipboard items |
| `GET` | `/api/items/:id` | Get single item details |
| `GET` | `/api/search?q=query` | Search items |
| `GET` | `/api/screenshots` | List screenshots |
| `GET` | `/api/screenshots/:id/image` | Get screenshot as PNG |
| `POST` | `/api/items` | Create new item |
| `POST` | `/api/items/:id/copy` | Copy item to system clipboard |
| `POST` | `/api/items/:id/paste` | Copy item and simulate Cmd+V |
| `POST` | `/api/paste` | Simulate Cmd+V (current clipboard) |
| `PUT` | `/api/items/:id/pin` | Toggle pin status |
| `DELETE` | `/api/items/:id` | Delete item |

---

## Read Endpoints

### Health Check

Check if the API server is running.

```
GET /api/health
```

**Response:**
```json
{
  "status": "ok",
  "version": "1.1"
}
```

---

### List Clipboard Items

Get recent clipboard items (max 100).

```
GET /api/items
```

**Response:**
```json
{
  "items": [
    {
      "id": "550e8400-e29b-41d4-a716-446655440000",
      "type": "text",
      "text": "Hello, World!",
      "timestamp": "2026-02-02T10:30:00Z",
      "sourceApp": "Safari",
      "isPinned": false,
      "characterCount": 13
    }
  ]
}
```

**Item Types:**
| Type | Description |
|------|-------------|
| `text` | Plain text content |
| `url` | URL/link |
| `image` | Image data (screenshot or copied image) |
| `file` | File reference |

---

### Get Single Item

Get details for a specific clipboard item.

```
GET /api/items/:id
```

**Parameters:**
- `id` - UUID of the clipboard item

**Response (text/url):**
```json
{
  "id": "550e8400-e29b-41d4-a716-446655440000",
  "type": "text",
  "content": "The full text content...",
  "timestamp": "2026-02-02T10:30:00Z",
  "sourceApp": "Safari",
  "isPinned": false
}
```

**Response (image/file):**
```json
{
  "id": "550e8400-e29b-41d4-a716-446655440002",
  "type": "image",
  "timestamp": "2026-02-02T10:20:00Z",
  "sourceApp": "Preview",
  "isPinned": false
}
```

> **Note:** For images, use `/api/screenshots/:id/image` to get the actual image data.

---

### Search Items

Search clipboard history by text content.

```
GET /api/search?q=query
```

**Parameters:**
- `q` - Search query (URL-encoded)

**Response:**
```json
{
  "query": "hello",
  "count": 3,
  "items": [
    {
      "id": "550e8400-e29b-41d4-a716-446655440000",
      "type": "text",
      "text": "Hello, World!",
      "timestamp": "2026-02-02T10:30:00Z",
      "sourceApp": "Safari",
      "isPinned": false
    }
  ]
}
```

---

### List Screenshots

Get recent screenshot items (max 50).

```
GET /api/screenshots
```

**Response:**
```json
{
  "screenshots": [
    {
      "id": "550e8400-e29b-41d4-a716-446655440002",
      "timestamp": "2026-02-02T10:20:00Z",
      "sourceApp": "Screenshot"
    }
  ]
}
```

---

### Get Screenshot Image

Get the actual image data for a screenshot.

```
GET /api/screenshots/:id/image
```

**Parameters:**
- `id` - UUID of the screenshot item

**Response:**
- **Content-Type:** `image/png`
- **Body:** Raw PNG image data

---

## Write Endpoints

### Create Item

Add a new item to clipboard history.

```
POST /api/items
Content-Type: application/json
```

**Request Body:**
```json
{
  "content": "Text content to save",
  "type": "text",
  "sourceAppName": "My AI Agent",
  "isPinned": false,
  "isSensitive": false
}
```

**Fields:**

| Field | Required | Default | Description |
|-------|----------|---------|-------------|
| `content` | Yes | - | The text content to save |
| `type` | No | `"text"` | Content type: `"text"` or `"url"` |
| `sourceApp` | No | - | Bundle identifier |
| `sourceAppName` | No | `"API"` | Display name shown in UI |
| `isPinned` | No | `false` | Pin the item |
| `isSensitive` | No | `false` | Mark as sensitive (requires auth to view) |

**Response (201 Created):**
```json
{
  "id": "550e8400-e29b-41d4-a716-446655440000",
  "type": "text",
  "timestamp": "2026-02-02T10:30:00Z",
  "message": "Item created successfully"
}
```

---

### Copy Item to Clipboard

Copy an existing item to the system clipboard (without pasting).

```
POST /api/items/:id/copy
```

**Response:**
```json
{
  "message": "Item copied to clipboard"
}
```

---

### Toggle Pin

Pin or unpin a clipboard item.

```
PUT /api/items/:id/pin
```

**Response:**
```json
{
  "id": "550e8400-e29b-41d4-a716-446655440000",
  "isPinned": true,
  "message": "Item pinned"
}
```

---

### Delete Item

Remove an item from clipboard history.

```
DELETE /api/items/:id
```

**Response:**
```json
{
  "message": "Item deleted successfully"
}
```

---

## Paste Endpoints

These endpoints require **Accessibility permission** to simulate keyboard input.

### Paste Item

Copy an item to the clipboard AND simulate Cmd+V to paste it into the active application.

```
POST /api/items/:id/paste
```

**Response:**
```json
{
  "message": "Item pasted successfully",
  "pasteSimulated": true
}
```

**Response (if Accessibility permission missing):**
```json
{
  "message": "Item copied but paste simulation failed (check accessibility permissions)",
  "pasteSimulated": false
}
```

---

### Paste Current Clipboard

Simulate Cmd+V to paste whatever is currently in the system clipboard.

```
POST /api/paste
```

**Response:**
```json
{
  "message": "Paste simulated successfully",
  "pasteSimulated": true
}
```

> **Important:** The target application must be focused before calling paste endpoints. Consider adding a delay in your automation to allow window focus.

---

## Error Responses

| Code | Description |
|------|-------------|
| `400` | Bad Request - Invalid JSON, missing required fields, or invalid ID |
| `401` | Unauthorized - Missing or invalid token |
| `404` | Not Found - Endpoint or resource doesn't exist |
| `405` | Method Not Allowed - Wrong HTTP method |
| `500` | Internal Server Error |

**Example Error Response:**
```json
{
  "error": "Invalid JSON body"
}
```

---

## Examples

### curl

```bash
# Set your token
TOKEN="your-api-token-here"

# Health check
curl -H "Authorization: Bearer $TOKEN" \
  http://localhost:19847/api/health

# List items
curl -H "Authorization: Bearer $TOKEN" \
  http://localhost:19847/api/items

# Search items
curl -H "Authorization: Bearer $TOKEN" \
  "http://localhost:19847/api/search?q=hello"

# Get specific item
curl -H "Authorization: Bearer $TOKEN" \
  http://localhost:19847/api/items/UUID-HERE

# Create a new item
curl -X POST -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"content": "Hello from API", "sourceAppName": "My Script"}' \
  http://localhost:19847/api/items

# Copy item to clipboard
curl -X POST -H "Authorization: Bearer $TOKEN" \
  http://localhost:19847/api/items/UUID-HERE/copy

# Paste item (copy + Cmd+V)
curl -X POST -H "Authorization: Bearer $TOKEN" \
  http://localhost:19847/api/items/UUID-HERE/paste

# Paste current clipboard
curl -X POST -H "Authorization: Bearer $TOKEN" \
  http://localhost:19847/api/paste

# Pin an item
curl -X PUT -H "Authorization: Bearer $TOKEN" \
  http://localhost:19847/api/items/UUID-HERE/pin

# Delete an item
curl -X DELETE -H "Authorization: Bearer $TOKEN" \
  http://localhost:19847/api/items/UUID-HERE

# Download screenshot
curl -H "Authorization: Bearer $TOKEN" \
  http://localhost:19847/api/screenshots/UUID-HERE/image \
  -o screenshot.png
```

### Python

```python
import requests
import time

BASE_URL = "http://localhost:19847"
TOKEN = "your-api-token-here"

headers = {
    "Authorization": f"Bearer {TOKEN}",
    "Content-Type": "application/json"
}

# Create a new clipboard item
def create_item(content, source="Python Script"):
    response = requests.post(
        f"{BASE_URL}/api/items",
        headers=headers,
        json={
            "content": content,
            "sourceAppName": source,
            "type": "text"
        }
    )
    return response.json()

# Search clipboard history
def search(query):
    response = requests.get(
        f"{BASE_URL}/api/search",
        headers=headers,
        params={"q": query}
    )
    return response.json()

# Paste an item (with delay for window focus)
def paste_item(item_id, delay=0.5):
    time.sleep(delay)  # Allow time to focus target window
    response = requests.post(
        f"{BASE_URL}/api/items/{item_id}/paste",
        headers=headers
    )
    return response.json()

# Get all screenshots
def get_screenshots():
    response = requests.get(
        f"{BASE_URL}/api/screenshots",
        headers=headers
    )
    return response.json()

# Download a screenshot
def download_screenshot(screenshot_id, filename):
    response = requests.get(
        f"{BASE_URL}/api/screenshots/{screenshot_id}/image",
        headers=headers
    )
    with open(filename, "wb") as f:
        f.write(response.content)

# Example usage
if __name__ == "__main__":
    # Create an item
    result = create_item("Hello from Python!")
    print(f"Created: {result}")

    # Search for it
    results = search("Python")
    print(f"Found {results['count']} items")

    # Paste the first result
    if results["items"]:
        item_id = results["items"][0]["id"]
        print("Focusing target window...")
        paste_result = paste_item(item_id, delay=2)
        print(f"Paste result: {paste_result}")
```

### JavaScript / Node.js

```javascript
const BASE_URL = 'http://localhost:19847';
const TOKEN = 'your-api-token-here';

const headers = {
  'Authorization': `Bearer ${TOKEN}`,
  'Content-Type': 'application/json'
};

// Create a new clipboard item
async function createItem(content, source = 'Node.js') {
  const response = await fetch(`${BASE_URL}/api/items`, {
    method: 'POST',
    headers,
    body: JSON.stringify({
      content,
      sourceAppName: source,
      type: 'text'
    })
  });
  return response.json();
}

// Search clipboard history
async function search(query) {
  const response = await fetch(
    `${BASE_URL}/api/search?q=${encodeURIComponent(query)}`,
    { headers }
  );
  return response.json();
}

// Paste an item
async function pasteItem(itemId) {
  const response = await fetch(`${BASE_URL}/api/items/${itemId}/paste`, {
    method: 'POST',
    headers
  });
  return response.json();
}

// Copy item to clipboard (without pasting)
async function copyItem(itemId) {
  const response = await fetch(`${BASE_URL}/api/items/${itemId}/copy`, {
    method: 'POST',
    headers
  });
  return response.json();
}

// Get all items
async function getItems() {
  const response = await fetch(`${BASE_URL}/api/items`, { headers });
  return response.json();
}

// Example usage
(async () => {
  // Create an item
  const created = await createItem('Hello from Node.js!');
  console.log('Created:', created);

  // List all items
  const items = await getItems();
  console.log(`Total items: ${items.items.length}`);

  // Search
  const results = await search('Node');
  console.log(`Found ${results.count} matching items`);
})();
```

### Shortcuts / Automator (macOS)

You can use the API from macOS Shortcuts or Automator:

```bash
# In a "Run Shell Script" action:
curl -s -X POST \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"content": "'"$1"'", "sourceAppName": "Shortcuts"}' \
  http://localhost:19847/api/items
```

---

## Security Notes

1. **Localhost Only** - The API only binds to localhost (127.0.0.1) and cannot be accessed from other machines.

2. **Token Storage** - The API token is stored in macOS Keychain for security.

3. **Write Limitations** - Only text and URL content types can be created via API. Images and files must be added through the clipboard.

4. **Sensitive Content** - Items marked as sensitive are still accessible via API if you have the token. The sensitivity flag affects UI behavior (requires Touch ID to view).

5. **Paste Permission** - The paste endpoints require Accessibility permission (`System Settings > Privacy & Security > Accessibility`).

6. **CORS** - The API includes `Access-Control-Allow-Origin: *` headers for browser-based access.

---

## Troubleshooting

### API Not Responding

1. Check that the API is enabled in Settings → Advanced
2. Verify the correct port number (default: 19847)
3. Check if another application is using the port
4. Restart ClippyBoard after enabling the API

### Authentication Failing

1. Ensure you're using the correct token from Settings
2. Check the Authorization header format: `Bearer TOKEN` (with space)
3. Try regenerating the token in Settings
4. Make sure there are no extra spaces or newlines in the token

### Paste Not Working

1. Grant Accessibility permission in System Settings
2. Ensure the target application is focused before calling paste
3. Add a delay (1-2 seconds) in your automation for window focus
4. Check the `pasteSimulated` field in the response

### Write Operations Failing

1. Ensure you're using POST/PUT/DELETE methods correctly
2. Include `Content-Type: application/json` header for POST requests
3. Verify JSON body format (use single quotes in bash for JSON)
4. Check that the item ID exists for update/delete operations

### Empty Response

1. Clipboard history may be empty
2. Check if Incognito mode is enabled (items won't be saved)
3. Verify the app has been running to capture clipboard changes
