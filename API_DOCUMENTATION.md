# ClipBoard Local API Documentation

ClipBoard provides a local HTTP API for integration with agents, automation tools, and other applications. The API is disabled by default and runs only on localhost for security.

---

## Configuration

### Enable the API

1. Open ClipBoard Settings (right-click menu bar icon → Settings)
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

## Base URL

```
http://localhost:19847
```

---

## Endpoints

### Health Check

Check if the API server is running.

```
GET /api/health
```

**Response:**
```json
{
  "status": "ok",
  "version": "1.0"
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
    },
    {
      "id": "550e8400-e29b-41d4-a716-446655440001",
      "type": "url",
      "text": "https://example.com",
      "timestamp": "2026-02-02T10:25:00Z",
      "sourceApp": "Chrome",
      "isPinned": true,
      "characterCount": 19
    },
    {
      "id": "550e8400-e29b-41d4-a716-446655440002",
      "type": "image",
      "text": "",
      "timestamp": "2026-02-02T10:20:00Z",
      "sourceApp": "Preview",
      "isPinned": false,
      "characterCount": 0
    }
  ]
}
```

**Item Types:**
- `text` - Plain text content
- `url` - URL/link
- `image` - Image data (screenshot or copied image)
- `file` - File reference

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
  "content": "The full text content of the clipboard item...",
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

> Note: For images, use the `/api/screenshots/:id/image` endpoint to get the actual image data.

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
    },
    {
      "id": "550e8400-e29b-41d4-a716-446655440003",
      "timestamp": "2026-02-02T10:15:00Z",
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
- Content-Type: `image/png`
- Body: Raw PNG image data

**Example with curl:**
```bash
curl -H "Authorization: Bearer YOUR_TOKEN" \
  http://localhost:19847/api/screenshots/550e8400-e29b-41d4-a716-446655440002/image \
  -o screenshot.png
```

---

## Error Responses

### 400 Bad Request
```json
{
  "error": "Invalid request"
}
```

### 401 Unauthorized
```json
{
  "error": "Unauthorized"
}
```

Missing or invalid Bearer token.

### 404 Not Found
```json
{
  "error": "Not found"
}
```

Endpoint or resource doesn't exist.

### 405 Method Not Allowed
```json
{
  "error": "Method not allowed"
}
```

Only GET requests are supported.

### 500 Internal Server Error
```json
{
  "error": "Database not initialized"
}
```

---

## Example Usage

### curl

```bash
# Set your token
TOKEN="your-api-token-here"

# Health check
curl -H "Authorization: Bearer $TOKEN" http://localhost:19847/api/health

# List items
curl -H "Authorization: Bearer $TOKEN" http://localhost:19847/api/items

# Get specific item
curl -H "Authorization: Bearer $TOKEN" http://localhost:19847/api/items/550e8400-e29b-41d4-a716-446655440000

# List screenshots
curl -H "Authorization: Bearer $TOKEN" http://localhost:19847/api/screenshots

# Download screenshot
curl -H "Authorization: Bearer $TOKEN" \
  http://localhost:19847/api/screenshots/550e8400-e29b-41d4-a716-446655440002/image \
  -o screenshot.png
```

### Python

```python
import requests

BASE_URL = "http://localhost:19847"
TOKEN = "your-api-token-here"

headers = {
    "Authorization": f"Bearer {TOKEN}"
}

# List all items
response = requests.get(f"{BASE_URL}/api/items", headers=headers)
items = response.json()["items"]

for item in items:
    print(f"{item['type']}: {item['text'][:50]}...")

# Get latest text item
text_items = [i for i in items if i["type"] == "text"]
if text_items:
    item_id = text_items[0]["id"]
    response = requests.get(f"{BASE_URL}/api/items/{item_id}", headers=headers)
    content = response.json()["content"]
    print(f"Latest text: {content}")
```

### JavaScript/Node.js

```javascript
const BASE_URL = 'http://localhost:19847';
const TOKEN = 'your-api-token-here';

async function getClipboardItems() {
  const response = await fetch(`${BASE_URL}/api/items`, {
    headers: {
      'Authorization': `Bearer ${TOKEN}`
    }
  });

  const data = await response.json();
  return data.items;
}

async function getItemContent(id) {
  const response = await fetch(`${BASE_URL}/api/items/${id}`, {
    headers: {
      'Authorization': `Bearer ${TOKEN}`
    }
  });

  return response.json();
}

// Usage
const items = await getClipboardItems();
console.log(`Found ${items.length} items`);
```

---

## Security Notes

1. **Localhost Only** - The API only binds to localhost (127.0.0.1) and cannot be accessed from other machines.

2. **Token Storage** - The API token is stored in macOS Keychain for security.

3. **Read-Only** - The API is read-only. It cannot modify or delete clipboard items.

4. **No Sensitive Content** - Items marked as sensitive (passwords, API keys) are not returned with their content through the API.

5. **CORS** - The API includes `Access-Control-Allow-Origin: *` headers for browser-based access.

---

## Troubleshooting

### API Not Responding

1. Check that the API is enabled in Settings → Advanced
2. Verify the correct port number
3. Check if another application is using the port

### Authentication Failing

1. Ensure you're using the correct token from Settings
2. Check the Authorization header format: `Bearer TOKEN`
3. Try regenerating the token

### Empty Response

1. Clipboard history may be empty
2. Check if Incognito mode is enabled (items won't be saved)
