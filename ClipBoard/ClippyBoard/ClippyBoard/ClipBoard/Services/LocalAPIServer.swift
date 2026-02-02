import Foundation
import Network
import SwiftData
import AppKit
import os

/// Local HTTP API server for agent compatibility
/// Provides read-only access to clipboard items and screenshots via localhost
@MainActor
class LocalAPIServer: ObservableObject {
    static let shared = LocalAPIServer()

    @Published private(set) var isRunning = false
    @Published private(set) var port: Int = 19847

    private var listener: NWListener?
    private var modelContainer: ModelContainer?
    private var apiToken: String?

    private init() {
        loadOrGenerateToken()
    }

    func setModelContainer(_ container: ModelContainer) {
        self.modelContainer = container
    }

    // MARK: - Token Management

    private func loadOrGenerateToken() {
        // Try to load from Keychain
        if let existingToken = KeychainHelper.load(key: "ClipBoardAPIToken") {
            apiToken = existingToken
        } else {
            // Generate new token
            let newToken = UUID().uuidString
            KeychainHelper.save(key: "ClipBoardAPIToken", value: newToken)
            apiToken = newToken
        }
    }

    func regenerateToken() {
        let newToken = UUID().uuidString
        KeychainHelper.save(key: "ClipBoardAPIToken", value: newToken)
        apiToken = newToken
        AppLogger.clipboard.info("API token regenerated")
    }

    var currentToken: String? {
        apiToken
    }

    // MARK: - Server Control

    func start() {
        guard !isRunning else { return }
        guard AppSettings.shared.apiEnabled else { return }

        port = AppSettings.shared.apiPort

        do {
            let parameters = NWParameters.tcp
            parameters.allowLocalEndpointReuse = true

            listener = try NWListener(using: parameters, on: NWEndpoint.Port(integerLiteral: UInt16(port)))

            listener?.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in
                    switch state {
                    case .ready:
                        self?.isRunning = true
                        AppLogger.clipboard.info("API server started on port \(self?.port ?? 0)")
                    case .failed(let error):
                        AppLogger.clipboard.error("API server failed: \(error.localizedDescription)")
                        self?.isRunning = false
                    case .cancelled:
                        self?.isRunning = false
                    default:
                        break
                    }
                }
            }

            listener?.newConnectionHandler = { [weak self] connection in
                Task { @MainActor in
                    self?.handleConnection(connection)
                }
            }

            listener?.start(queue: .main)
        } catch {
            AppLogger.clipboard.error("Failed to start API server: \(error.localizedDescription)")
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        isRunning = false
        AppLogger.clipboard.info("API server stopped")
    }

    // MARK: - Connection Handling

    private func handleConnection(_ connection: NWConnection) {
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                Task { @MainActor in
                    self?.receiveRequest(on: connection)
                }
            case .failed, .cancelled:
                connection.cancel()
            default:
                break
            }
        }

        connection.start(queue: .main)
    }

    private func receiveRequest(on connection: NWConnection) {
        // Accumulate all data until we have a complete request
        var accumulatedData = Data()

        func receiveChunk() {
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
                if let data = data {
                    accumulatedData.append(data)
                }

                // Check if we have a complete HTTP request
                if let requestString = String(data: accumulatedData, encoding: .utf8),
                   requestString.contains("\r\n\r\n") {
                    // Check Content-Length to see if we need the body
                    if let contentLengthRange = requestString.range(of: "Content-Length: ", options: .caseInsensitive),
                       let endOfLine = requestString[contentLengthRange.upperBound...].firstIndex(of: "\r"),
                       let contentLength = Int(String(requestString[contentLengthRange.upperBound..<endOfLine])),
                       let bodyStart = requestString.range(of: "\r\n\r\n") {

                        let headerEndIndex = requestString.distance(from: requestString.startIndex, to: bodyStart.upperBound)
                        let currentBodyLength = accumulatedData.count - headerEndIndex

                        // Need more data for body
                        if currentBodyLength < contentLength && !isComplete && error == nil {
                            Task { @MainActor in
                                receiveChunk()
                            }
                            return
                        }
                    }

                    // Process the complete request
                    Task { @MainActor in
                        self?.processRequest(data: accumulatedData, connection: connection)
                    }
                    return
                }

                // Need more data for headers
                if !isComplete && error == nil {
                    Task { @MainActor in
                        receiveChunk()
                    }
                } else {
                    // Process whatever we have
                    Task { @MainActor in
                        self?.processRequest(data: accumulatedData, connection: connection)
                    }
                }
            }
        }

        receiveChunk()
    }

    private func processRequest(data: Data, connection: NWConnection) {
        guard let requestString = String(data: data, encoding: .utf8) else {
            sendResponse(connection: connection, statusCode: 400, body: ["error": "Invalid request"])
            return
        }

        // Parse HTTP request
        let lines = requestString.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else {
            sendResponse(connection: connection, statusCode: 400, body: ["error": "Invalid request"])
            return
        }

        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2 else {
            sendResponse(connection: connection, statusCode: 400, body: ["error": "Invalid request"])
            return
        }

        let method = String(parts[0])
        let path = String(parts[1])

        // Extract Authorization header
        var authToken: String?
        for line in lines {
            if line.lowercased().hasPrefix("authorization:") {
                let value = line.dropFirst("authorization:".count).trimmingCharacters(in: .whitespaces)
                if value.hasPrefix("Bearer ") {
                    authToken = String(value.dropFirst("Bearer ".count))
                }
            }
        }

        // Verify token
        guard authToken == apiToken else {
            sendResponse(connection: connection, statusCode: 401, body: ["error": "Unauthorized"])
            return
        }

        // Extract request body (after blank line)
        var requestBody: Data?
        if let bodyStart = requestString.range(of: "\r\n\r\n") {
            let bodyString = String(requestString[bodyStart.upperBound...])
            requestBody = bodyString.data(using: .utf8)
        }

        // Route request
        Task { @MainActor in
            await self.routeRequest(method: method, path: path, body: requestBody, connection: connection)
        }
    }

    private func routeRequest(method: String, path: String, body: Data?, connection: NWConnection) async {
        // Parse path
        let pathComponents = path.split(separator: "/").map(String.init)

        switch method {
        case "GET":
            if pathComponents == ["api", "items"] {
                await handleGetItems(connection: connection)
            } else if pathComponents.count == 3 && pathComponents[0] == "api" && pathComponents[1] == "items" {
                await handleGetItem(id: pathComponents[2], connection: connection)
            } else if pathComponents == ["api", "screenshots"] {
                await handleGetScreenshots(connection: connection)
            } else if pathComponents.count == 4 && pathComponents[0] == "api" && pathComponents[1] == "screenshots" && pathComponents[3] == "image" {
                await handleGetScreenshotImage(id: pathComponents[2], connection: connection)
            } else if pathComponents == ["api", "health"] {
                sendResponse(connection: connection, statusCode: 200, body: ["status": "ok", "version": "1.1"])
            } else if pathComponents == ["api", "search"] {
                // Extract query parameter
                if let queryStart = path.range(of: "?q=") {
                    let query = String(path[queryStart.upperBound...]).removingPercentEncoding ?? ""
                    await handleSearch(query: query, connection: connection)
                } else {
                    sendResponse(connection: connection, statusCode: 400, body: ["error": "Missing query parameter 'q'"])
                }
            } else {
                sendResponse(connection: connection, statusCode: 404, body: ["error": "Not found"])
            }

        case "POST":
            if pathComponents == ["api", "items"] {
                await handleCreateItem(body: body, connection: connection)
            } else if pathComponents.count == 4 && pathComponents[0] == "api" && pathComponents[1] == "items" && pathComponents[3] == "copy" {
                // POST /api/items/{id}/copy - Copy item to system clipboard
                await handleCopyItem(id: pathComponents[2], connection: connection)
            } else if pathComponents.count == 4 && pathComponents[0] == "api" && pathComponents[1] == "items" && pathComponents[3] == "paste" {
                // POST /api/items/{id}/paste - Copy to clipboard and simulate Cmd+V
                await handlePasteItem(id: pathComponents[2], connection: connection)
            } else if pathComponents == ["api", "paste"] {
                // POST /api/paste - Paste current clipboard content (just simulate Cmd+V)
                await handlePasteClipboard(connection: connection)
            } else {
                sendResponse(connection: connection, statusCode: 404, body: ["error": "Not found"])
            }

        case "DELETE":
            if pathComponents.count == 3 && pathComponents[0] == "api" && pathComponents[1] == "items" {
                await handleDeleteItem(id: pathComponents[2], connection: connection)
            } else {
                sendResponse(connection: connection, statusCode: 404, body: ["error": "Not found"])
            }

        case "PUT":
            if pathComponents.count == 4 && pathComponents[0] == "api" && pathComponents[1] == "items" && pathComponents[3] == "pin" {
                await handleTogglePin(id: pathComponents[2], connection: connection)
            } else {
                sendResponse(connection: connection, statusCode: 404, body: ["error": "Not found"])
            }

        default:
            sendResponse(connection: connection, statusCode: 405, body: ["error": "Method not allowed"])
        }
    }

    // MARK: - API Handlers

    private func handleGetItems(connection: NWConnection) async {
        guard let modelContainer = modelContainer else {
            sendResponse(connection: connection, statusCode: 500, body: ["error": "Database not initialized"])
            return
        }

        let context = modelContainer.mainContext
        let descriptor = FetchDescriptor<ClipboardItem>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )

        do {
            let items = try context.fetch(descriptor)
            let response = items.prefix(100).map { item in
                [
                    "id": item.id.uuidString,
                    "type": item.contentType,
                    "text": item.textContent ?? "",
                    "timestamp": ISO8601DateFormatter().string(from: item.timestamp),
                    "sourceApp": item.sourceAppName ?? "",
                    "isPinned": item.isPinned,
                    "characterCount": item.characterCount ?? 0
                ] as [String: Any]
            }
            sendResponse(connection: connection, statusCode: 200, body: ["items": response])
        } catch {
            sendResponse(connection: connection, statusCode: 500, body: ["error": error.localizedDescription])
        }
    }

    private func handleGetItem(id: String, connection: NWConnection) async {
        guard let modelContainer = modelContainer,
              let uuid = UUID(uuidString: id) else {
            sendResponse(connection: connection, statusCode: 400, body: ["error": "Invalid ID"])
            return
        }

        let context = modelContainer.mainContext
        let descriptor = FetchDescriptor<ClipboardItem>(
            predicate: #Predicate { $0.id == uuid }
        )

        do {
            let items = try context.fetch(descriptor)
            guard let item = items.first else {
                sendResponse(connection: connection, statusCode: 404, body: ["error": "Item not found"])
                return
            }

            var response: [String: Any] = [
                "id": item.id.uuidString,
                "type": item.contentType,
                "timestamp": ISO8601DateFormatter().string(from: item.timestamp),
                "sourceApp": item.sourceAppName ?? "",
                "isPinned": item.isPinned
            ]

            // Include content for text/url types
            if item.contentTypeEnum == .text || item.contentTypeEnum == .url {
                response["content"] = item.textContent ?? ""
            }

            sendResponse(connection: connection, statusCode: 200, body: response)
        } catch {
            sendResponse(connection: connection, statusCode: 500, body: ["error": error.localizedDescription])
        }
    }

    private func handleGetScreenshots(connection: NWConnection) async {
        guard let modelContainer = modelContainer else {
            sendResponse(connection: connection, statusCode: 500, body: ["error": "Database not initialized"])
            return
        }

        let context = modelContainer.mainContext
        let descriptor = FetchDescriptor<ClipboardItem>(
            predicate: #Predicate { $0.contentType == "image" },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )

        do {
            let items = try context.fetch(descriptor)
            let response = items.prefix(50).map { item in
                [
                    "id": item.id.uuidString,
                    "timestamp": ISO8601DateFormatter().string(from: item.timestamp),
                    "sourceApp": item.sourceAppName ?? ""
                ] as [String: Any]
            }
            sendResponse(connection: connection, statusCode: 200, body: ["screenshots": response])
        } catch {
            sendResponse(connection: connection, statusCode: 500, body: ["error": error.localizedDescription])
        }
    }

    private func handleGetScreenshotImage(id: String, connection: NWConnection) async {
        guard let modelContainer = modelContainer,
              let uuid = UUID(uuidString: id) else {
            sendResponse(connection: connection, statusCode: 400, body: ["error": "Invalid ID"])
            return
        }

        let context = modelContainer.mainContext
        let descriptor = FetchDescriptor<ClipboardItem>(
            predicate: #Predicate { $0.id == uuid && $0.contentType == "image" }
        )

        do {
            let items = try context.fetch(descriptor)
            guard let item = items.first else {
                sendResponse(connection: connection, statusCode: 404, body: ["error": "Screenshot not found"])
                return
            }

            // Return image data
            sendImageResponse(connection: connection, imageData: item.content)
        } catch {
            sendResponse(connection: connection, statusCode: 500, body: ["error": error.localizedDescription])
        }
    }

    // MARK: - Write Handlers (AI Agent Support)

    private func handleCreateItem(body: Data?, connection: NWConnection) async {
        guard let modelContainer = modelContainer else {
            sendResponse(connection: connection, statusCode: 500, body: ["error": "Database not initialized"])
            return
        }

        // Debug: check what body we received
        guard let body = body else {
            sendResponse(connection: connection, statusCode: 400, body: ["error": "No body received"])
            return
        }

        // Trim any whitespace/newlines from the body
        guard let bodyString = String(data: body, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !bodyString.isEmpty,
              let cleanBody = bodyString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: cleanBody) as? [String: Any] else {
            let bodyPreview = String(data: body, encoding: .utf8)?.prefix(100) ?? "nil"
            sendResponse(connection: connection, statusCode: 400, body: ["error": "Invalid JSON body", "received": String(bodyPreview)])
            return
        }

        // Required field: content (text)
        guard let content = json["content"] as? String else {
            sendResponse(connection: connection, statusCode: 400, body: ["error": "Missing required field 'content'"])
            return
        }

        // Optional fields
        let contentType = (json["type"] as? String) ?? "text"
        let sourceApp = json["sourceApp"] as? String
        let sourceAppName = json["sourceAppName"] as? String ?? "API"
        let isPinned = json["isPinned"] as? Bool ?? false
        let isSensitive = json["isSensitive"] as? Bool ?? false

        // Validate content type
        guard ["text", "url"].contains(contentType) else {
            sendResponse(connection: connection, statusCode: 400, body: ["error": "Only 'text' and 'url' types supported via API"])
            return
        }

        let context = modelContainer.mainContext

        // Create the item
        let item = ClipboardItem(
            content: content.data(using: .utf8) ?? Data(),
            textContent: content,
            contentType: contentType,
            sourceApp: sourceApp,
            sourceAppName: sourceAppName,
            isPinned: isPinned,
            characterCount: content.count,
            searchableText: content.lowercased(),
            isSensitive: isSensitive
        )

        context.insert(item)

        do {
            try context.save()
            AppLogger.clipboard.info("Created item via API: \(item.id.uuidString)")

            sendResponse(connection: connection, statusCode: 201, body: [
                "id": item.id.uuidString,
                "type": item.contentType,
                "timestamp": ISO8601DateFormatter().string(from: item.timestamp),
                "message": "Item created successfully"
            ])
        } catch {
            sendResponse(connection: connection, statusCode: 500, body: ["error": error.localizedDescription])
        }
    }

    private func handleDeleteItem(id: String, connection: NWConnection) async {
        guard let modelContainer = modelContainer,
              let uuid = UUID(uuidString: id) else {
            sendResponse(connection: connection, statusCode: 400, body: ["error": "Invalid ID"])
            return
        }

        let context = modelContainer.mainContext
        let descriptor = FetchDescriptor<ClipboardItem>(
            predicate: #Predicate { $0.id == uuid }
        )

        do {
            let items = try context.fetch(descriptor)
            guard let item = items.first else {
                sendResponse(connection: connection, statusCode: 404, body: ["error": "Item not found"])
                return
            }

            context.delete(item)
            try context.save()
            AppLogger.clipboard.info("Deleted item via API: \(id)")

            sendResponse(connection: connection, statusCode: 200, body: ["message": "Item deleted successfully"])
        } catch {
            sendResponse(connection: connection, statusCode: 500, body: ["error": error.localizedDescription])
        }
    }

    private func handleTogglePin(id: String, connection: NWConnection) async {
        guard let modelContainer = modelContainer,
              let uuid = UUID(uuidString: id) else {
            sendResponse(connection: connection, statusCode: 400, body: ["error": "Invalid ID"])
            return
        }

        let context = modelContainer.mainContext
        let descriptor = FetchDescriptor<ClipboardItem>(
            predicate: #Predicate { $0.id == uuid }
        )

        do {
            let items = try context.fetch(descriptor)
            guard let item = items.first else {
                sendResponse(connection: connection, statusCode: 404, body: ["error": "Item not found"])
                return
            }

            item.isPinned.toggle()
            try context.save()
            AppLogger.clipboard.info("Toggled pin via API: \(id) -> \(item.isPinned)")

            sendResponse(connection: connection, statusCode: 200, body: [
                "id": item.id.uuidString,
                "isPinned": item.isPinned,
                "message": item.isPinned ? "Item pinned" : "Item unpinned"
            ])
        } catch {
            sendResponse(connection: connection, statusCode: 500, body: ["error": error.localizedDescription])
        }
    }

    private func handleCopyItem(id: String, connection: NWConnection) async {
        guard let modelContainer = modelContainer,
              let uuid = UUID(uuidString: id) else {
            sendResponse(connection: connection, statusCode: 400, body: ["error": "Invalid ID"])
            return
        }

        let context = modelContainer.mainContext
        let descriptor = FetchDescriptor<ClipboardItem>(
            predicate: #Predicate { $0.id == uuid }
        )

        do {
            let items = try context.fetch(descriptor)
            guard let item = items.first else {
                sendResponse(connection: connection, statusCode: 404, body: ["error": "Item not found"])
                return
            }

            // Copy to system clipboard
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()

            switch item.contentTypeEnum {
            case .text, .url:
                if let text = item.textContent {
                    pasteboard.setString(text, forType: .string)
                }
            case .image:
                if let image = NSImage(data: item.content) {
                    pasteboard.writeObjects([image])
                }
            case .file:
                if let pathsString = item.textContent {
                    let paths = pathsString.components(separatedBy: "\n")
                    let urls = paths.compactMap { URL(fileURLWithPath: $0) }
                    pasteboard.writeObjects(urls as [NSURL])
                }
            }

            AppLogger.clipboard.info("Copied item to clipboard via API: \(id)")
            sendResponse(connection: connection, statusCode: 200, body: ["message": "Item copied to clipboard"])
        } catch {
            sendResponse(connection: connection, statusCode: 500, body: ["error": error.localizedDescription])
        }
    }

    private func handlePasteItem(id: String, connection: NWConnection) async {
        guard let modelContainer = modelContainer,
              let uuid = UUID(uuidString: id) else {
            sendResponse(connection: connection, statusCode: 400, body: ["error": "Invalid ID"])
            return
        }

        let context = modelContainer.mainContext
        let descriptor = FetchDescriptor<ClipboardItem>(
            predicate: #Predicate { $0.id == uuid }
        )

        do {
            let items = try context.fetch(descriptor)
            guard let item = items.first else {
                sendResponse(connection: connection, statusCode: 404, body: ["error": "Item not found"])
                return
            }

            // Copy to system clipboard
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()

            switch item.contentTypeEnum {
            case .text, .url:
                if let text = item.textContent {
                    pasteboard.setString(text, forType: .string)
                }
            case .image:
                if let image = NSImage(data: item.content) {
                    pasteboard.writeObjects([image])
                }
            case .file:
                if let pathsString = item.textContent {
                    let paths = pathsString.components(separatedBy: "\n")
                    let urls = paths.compactMap { URL(fileURLWithPath: $0) }
                    pasteboard.writeObjects(urls as [NSURL])
                }
            }

            // Small delay then simulate Cmd+V
            try? await Task.sleep(nanoseconds: 50_000_000)
            let success = await AccessibilityService.shared.simulatePaste()

            AppLogger.clipboard.info("Pasted item via API: \(id), success: \(success)")
            sendResponse(connection: connection, statusCode: 200, body: [
                "message": success ? "Item pasted successfully" : "Item copied but paste simulation failed (check accessibility permissions)",
                "pasteSimulated": success
            ])
        } catch {
            sendResponse(connection: connection, statusCode: 500, body: ["error": error.localizedDescription])
        }
    }

    private func handlePasteClipboard(connection: NWConnection) async {
        // Just simulate Cmd+V for whatever is currently in the clipboard
        let success = await AccessibilityService.shared.simulatePaste()

        AppLogger.clipboard.info("Paste clipboard via API, success: \(success)")
        sendResponse(connection: connection, statusCode: 200, body: [
            "message": success ? "Paste simulated successfully" : "Paste simulation failed (check accessibility permissions)",
            "pasteSimulated": success
        ])
    }

    private func handleSearch(query: String, connection: NWConnection) async {
        guard let modelContainer = modelContainer else {
            sendResponse(connection: connection, statusCode: 500, body: ["error": "Database not initialized"])
            return
        }

        let context = modelContainer.mainContext
        let lowercaseQuery = query.lowercased()

        let descriptor = FetchDescriptor<ClipboardItem>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )

        do {
            let allItems = try context.fetch(descriptor)

            // Filter items that contain the search query
            let matchingItems = allItems.filter { item in
                item.searchableText.contains(lowercaseQuery) ||
                (item.textContent?.lowercased().contains(lowercaseQuery) ?? false)
            }

            let response = matchingItems.prefix(50).map { item in
                [
                    "id": item.id.uuidString,
                    "type": item.contentType,
                    "text": item.textContent ?? "",
                    "timestamp": ISO8601DateFormatter().string(from: item.timestamp),
                    "sourceApp": item.sourceAppName ?? "",
                    "isPinned": item.isPinned
                ] as [String: Any]
            }

            sendResponse(connection: connection, statusCode: 200, body: [
                "query": query,
                "count": response.count,
                "items": response
            ])
        } catch {
            sendResponse(connection: connection, statusCode: 500, body: ["error": error.localizedDescription])
        }
    }

    // MARK: - Response Helpers

    private func sendResponse(connection: NWConnection, statusCode: Int, body: [String: Any]) {
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: body, options: .prettyPrinted)
            let statusText = httpStatusText(for: statusCode)

            let response = """
            HTTP/1.1 \(statusCode) \(statusText)\r
            Content-Type: application/json\r
            Content-Length: \(jsonData.count)\r
            Access-Control-Allow-Origin: *\r
            \r

            """

            var responseData = response.data(using: .utf8)!
            responseData.append(jsonData)

            connection.send(content: responseData, completion: .contentProcessed { _ in
                connection.cancel()
            })
        } catch {
            connection.cancel()
        }
    }

    private func sendImageResponse(connection: NWConnection, imageData: Data) {
        let response = """
        HTTP/1.1 200 OK\r
        Content-Type: image/png\r
        Content-Length: \(imageData.count)\r
        Access-Control-Allow-Origin: *\r
        \r

        """

        var responseData = response.data(using: .utf8)!
        responseData.append(imageData)

        connection.send(content: responseData, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func httpStatusText(for code: Int) -> String {
        switch code {
        case 200: return "OK"
        case 201: return "Created"
        case 400: return "Bad Request"
        case 401: return "Unauthorized"
        case 404: return "Not Found"
        case 405: return "Method Not Allowed"
        case 500: return "Internal Server Error"
        default: return "Unknown"
        }
    }
}

// MARK: - Keychain Helper

enum KeychainHelper {
    static func save(key: String, value: String) {
        let data = value.data(using: .utf8)!

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecValueData as String: data
        ]

        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }

    static func load(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var dataTypeRef: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &dataTypeRef)

        guard status == errSecSuccess,
              let data = dataTypeRef as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return nil
        }

        return value
    }

    static func delete(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]

        SecItemDelete(query as CFDictionary)
    }
}
