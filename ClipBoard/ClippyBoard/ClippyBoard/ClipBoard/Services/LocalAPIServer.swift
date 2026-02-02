import Foundation
@preconcurrency import Network
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

    // MARK: - Security Configuration

    /// Maximum request size (1MB)
    private let maxRequestSize = 1024 * 1024

    /// Connection timeout in seconds
    private let connectionTimeout: TimeInterval = 30

    /// Rate limiting: max connections per minute per IP
    private let maxConnectionsPerMinute = 60
    private var connectionAttempts: [String: [Date]] = [:]

    /// Active timeout tasks keyed by connection object identifier
    private var connectionTimeouts: [ObjectIdentifier: DispatchWorkItem] = [:]

    /// Cached date formatter for performance
    private static let iso8601Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        return formatter
    }()

    private init() {
        loadOrGenerateToken()
    }

    func setModelContainer(_ container: ModelContainer) {
        self.modelContainer = container
    }

    // MARK: - Token Management

    private func loadOrGenerateToken() {
        if let existingToken = KeychainHelper.load(key: "ClipBoardAPIToken") {
            apiToken = existingToken
        } else {
            let newToken = UUID().uuidString
            if KeychainHelper.save(key: "ClipBoardAPIToken", value: newToken) {
                apiToken = newToken
            } else {
                AppLogger.clipboard.error("Failed to save API token to Keychain")
                apiToken = newToken
            }
        }
    }

    func regenerateToken() {
        let newToken = UUID().uuidString
        if KeychainHelper.save(key: "ClipBoardAPIToken", value: newToken) {
            objectWillChange.send()
            apiToken = newToken
            AppLogger.clipboard.info("API token regenerated")
        } else {
            AppLogger.clipboard.error("Failed to save regenerated API token")
        }
    }

    var currentToken: String? {
        apiToken
    }

    // MARK: - Security Helpers

    /// Constant-time string comparison to prevent timing attacks
    private func secureCompare(_ a: String?, _ b: String?) -> Bool {
        guard let aData = a?.data(using: .utf8),
              let bData = b?.data(using: .utf8) else {
            return false
        }

        guard aData.count == bData.count else {
            return false
        }

        var result: UInt8 = 0
        for (aByte, bByte) in zip(aData, bData) {
            result |= aByte ^ bByte
        }
        return result == 0
    }

    /// Check if connection should be allowed based on rate limiting
    private func shouldAllowConnection(from endpoint: NWEndpoint?) -> Bool {
        guard let endpoint = endpoint else { return true }

        let endpointKey = "\(endpoint)"
        let now = Date()
        let oneMinuteAgo = now.addingTimeInterval(-60)

        // Clean up old entries
        connectionAttempts[endpointKey] = connectionAttempts[endpointKey]?.filter { $0 > oneMinuteAgo } ?? []

        // Check rate limit
        let recentAttempts = connectionAttempts[endpointKey]?.count ?? 0
        if recentAttempts >= maxConnectionsPerMinute {
            AppLogger.clipboard.warning("Rate limit exceeded for endpoint: \(endpointKey)")
            return false
        }

        // Record this attempt
        connectionAttempts[endpointKey, default: []].append(now)
        return true
    }

    /// Detect MIME type from image data magic bytes
    private func mimeTypeForImageData(_ data: Data) -> String {
        guard data.count >= 8 else { return "application/octet-stream" }

        let bytes = Array(data.prefix(8))

        // PNG: 89 50 4E 47 0D 0A 1A 0A
        if bytes.starts(with: [0x89, 0x50, 0x4E, 0x47]) {
            return "image/png"
        }
        // JPEG: FF D8 FF
        if bytes.starts(with: [0xFF, 0xD8, 0xFF]) {
            return "image/jpeg"
        }
        // GIF: 47 49 46 38
        if bytes.starts(with: [0x47, 0x49, 0x46, 0x38]) {
            return "image/gif"
        }
        // WebP: 52 49 46 46 ... 57 45 42 50
        if bytes.starts(with: [0x52, 0x49, 0x46, 0x46]) && data.count >= 12 {
            let webpBytes = Array(data[8..<12])
            if webpBytes == [0x57, 0x45, 0x42, 0x50] {
                return "image/webp"
            }
        }
        // TIFF: 49 49 2A 00 or 4D 4D 00 2A
        if bytes.starts(with: [0x49, 0x49, 0x2A, 0x00]) || bytes.starts(with: [0x4D, 0x4D, 0x00, 0x2A]) {
            return "image/tiff"
        }
        // BMP: 42 4D
        if bytes.starts(with: [0x42, 0x4D]) {
            return "image/bmp"
        }

        return "image/png" // Default fallback
    }

    /// Parse query parameters from URL path
    private func parseQueryParameters(from path: String) -> [String: String] {
        guard let questionMarkIndex = path.firstIndex(of: "?") else {
            return [:]
        }

        let queryString = String(path[path.index(after: questionMarkIndex)...])
        var params: [String: String] = [:]

        for pair in queryString.split(separator: "&") {
            let parts = pair.split(separator: "=", maxSplits: 1)
            if parts.count == 2 {
                let key = String(parts[0])
                let value = String(parts[1]).removingPercentEncoding ?? String(parts[1])
                params[key] = value
            }
        }

        return params
    }

    /// Extract path without query parameters
    private func pathWithoutQuery(_ path: String) -> String {
        if let questionMarkIndex = path.firstIndex(of: "?") {
            return String(path[..<questionMarkIndex])
        }
        return path
    }

    // MARK: - Server Control

    func start() {
        guard !isRunning else { return }
        guard AppSettings.shared.apiEnabled else { return }

        self.port = AppSettings.shared.apiPort

        // Validate port range
        guard self.port > 0 && self.port <= 65535 else {
            AppLogger.clipboard.error("Invalid port number: \(self.port). Must be between 1 and 65535.")
            return
        }

        do {
            let parameters = NWParameters.tcp
            parameters.allowLocalEndpointReuse = true

            // Create listener on the specified port
            listener = try NWListener(using: parameters, on: NWEndpoint.Port(integerLiteral: UInt16(self.port)))

            let serverPort = self.port
            listener?.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in
                    switch state {
                    case .ready:
                        self?.isRunning = true
                        AppLogger.clipboard.info("API server started on localhost:\(serverPort)")
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
        connectionAttempts.removeAll()
        // Cancel all pending connection timeouts
        connectionTimeouts.values.forEach { $0.cancel() }
        connectionTimeouts.removeAll()
        AppLogger.clipboard.info("API server stopped")
    }

    // MARK: - Connection Handling

    private func handleConnection(_ connection: NWConnection) {
        // SECURITY: Only allow connections from localhost
        if case let .hostPort(host, _) = connection.endpoint {
            let hostString = "\(host)"
            let isLocalhost = hostString == "127.0.0.1" || hostString == "::1" || hostString.contains("localhost")
            if !isLocalhost {
                AppLogger.clipboard.warning("Rejected non-localhost connection from: \(hostString)")
                connection.cancel()
                return
            }
        }

        // Rate limiting check
        guard shouldAllowConnection(from: connection.endpoint) else {
            sendResponse(connection: connection, statusCode: 429, body: ["error": "Too many requests"])
            return
        }

        // Connection timeout
        let connectionId = ObjectIdentifier(connection)
        let timeoutWork = DispatchWorkItem { [weak self, weak connection] in
            connection?.cancel()
            Task { @MainActor in
                self?.connectionTimeouts.removeValue(forKey: connectionId)
            }
        }
        connectionTimeouts[connectionId] = timeoutWork
        DispatchQueue.main.asyncAfter(deadline: .now() + connectionTimeout, execute: timeoutWork)

        connection.stateUpdateHandler = { [weak self, weak connection] state in
            guard let connection = connection else { return }
            switch state {
            case .ready:
                Task { @MainActor in
                    self?.receiveRequest(on: connection)
                }
            case .failed, .cancelled:
                Task { @MainActor in
                    self?.cancelTimeout(for: connection)
                }
                connection.cancel()
            default:
                break
            }
        }

        connection.start(queue: .main)
    }

    private func cancelTimeout(for connection: NWConnection) {
        let connectionId = ObjectIdentifier(connection)
        connectionTimeouts[connectionId]?.cancel()
        connectionTimeouts.removeValue(forKey: connectionId)
    }

    private func receiveRequest(on connection: NWConnection) {
        var accumulatedData = Data()
        let maxSize = self.maxRequestSize

        func receiveChunk() {
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
                if let data = data {
                    accumulatedData.append(data)

                    // SECURITY: Enforce maximum request size
                    if accumulatedData.count > maxSize {
                        Task { @MainActor in
                            self?.cancelTimeout(for: connection)
                            self?.sendResponse(connection: connection, statusCode: 413, body: ["error": "Request too large"])
                        }
                        return
                    }
                }

                if let requestString = String(data: accumulatedData, encoding: .utf8),
                   requestString.contains("\r\n\r\n") {
                    if let contentLengthRange = requestString.range(of: "Content-Length: ", options: .caseInsensitive),
                       let endOfLine = requestString[contentLengthRange.upperBound...].firstIndex(of: "\r"),
                       let contentLength = Int(String(requestString[contentLengthRange.upperBound..<endOfLine])),
                       let bodyStart = requestString.range(of: "\r\n\r\n") {

                        let headerEndIndex = requestString.distance(from: requestString.startIndex, to: bodyStart.upperBound)
                        let currentBodyLength = accumulatedData.count - headerEndIndex

                        if currentBodyLength < contentLength && !isComplete && error == nil {
                            Task { @MainActor in
                                receiveChunk()
                            }
                            return
                        }
                    }

                    Task { @MainActor in
                        self?.cancelTimeout(for: connection)
                        self?.processRequest(data: accumulatedData, connection: connection)
                    }
                    return
                }

                if !isComplete && error == nil {
                    Task { @MainActor in
                        receiveChunk()
                    }
                } else {
                    Task { @MainActor in
                        self?.cancelTimeout(for: connection)
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

        // Handle CORS preflight
        if method == "OPTIONS" {
            sendCorsPreflightResponse(connection: connection)
            return
        }

        var authToken: String?
        for line in lines {
            if line.lowercased().hasPrefix("authorization:") {
                let value = line.dropFirst("authorization:".count).trimmingCharacters(in: .whitespaces)
                if value.hasPrefix("Bearer ") {
                    authToken = String(value.dropFirst("Bearer ".count))
                }
            }
        }

        // SECURITY: Constant-time token comparison to prevent timing attacks
        guard secureCompare(authToken, apiToken) else {
            sendResponse(connection: connection, statusCode: 401, body: ["error": "Unauthorized"])
            return
        }

        var requestBody: Data?
        if let bodyStart = requestString.range(of: "\r\n\r\n") {
            let bodyString = String(requestString[bodyStart.upperBound...])
            requestBody = bodyString.data(using: .utf8)
        }

        Task { @MainActor in
            await self.routeRequest(method: method, path: path, body: requestBody, connection: connection)
        }
    }

    private func routeRequest(method: String, path: String, body: Data?, connection: NWConnection) async {
        let cleanPath = pathWithoutQuery(path)
        let pathComponents = cleanPath.split(separator: "/").map(String.init)
        let queryParams = parseQueryParameters(from: path)

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
                sendResponse(connection: connection, statusCode: 200, body: ["status": "ok", "version": "1.2"])
            } else if pathComponents == ["api", "search"] {
                if let query = queryParams["q"], !query.isEmpty {
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
                await handleCopyItem(id: pathComponents[2], connection: connection)
            } else if pathComponents.count == 4 && pathComponents[0] == "api" && pathComponents[1] == "items" && pathComponents[3] == "paste" {
                await handlePasteItem(id: pathComponents[2], connection: connection)
            } else if pathComponents == ["api", "paste"] {
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
        var descriptor = FetchDescriptor<ClipboardItem>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        descriptor.fetchLimit = 100

        do {
            let items = try context.fetch(descriptor)
            let response = items.map { item in
                [
                    "id": item.id.uuidString,
                    "type": item.contentType,
                    "text": item.textContent ?? "",
                    "timestamp": Self.iso8601Formatter.string(from: item.timestamp),
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
                "timestamp": Self.iso8601Formatter.string(from: item.timestamp),
                "sourceApp": item.sourceAppName ?? "",
                "isPinned": item.isPinned
            ]

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
        var descriptor = FetchDescriptor<ClipboardItem>(
            predicate: #Predicate { $0.contentType == "image" },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        descriptor.fetchLimit = 50

        do {
            let items = try context.fetch(descriptor)
            let response = items.map { item in
                [
                    "id": item.id.uuidString,
                    "timestamp": Self.iso8601Formatter.string(from: item.timestamp),
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

        guard let body = body else {
            sendResponse(connection: connection, statusCode: 400, body: ["error": "No body received"])
            return
        }

        guard let bodyString = String(data: body, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !bodyString.isEmpty,
              let cleanBody = bodyString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: cleanBody) as? [String: Any] else {
            let bodyPreview = String(data: body, encoding: .utf8)?.prefix(100) ?? "nil"
            sendResponse(connection: connection, statusCode: 400, body: ["error": "Invalid JSON body", "received": String(bodyPreview)])
            return
        }

        guard let content = json["content"] as? String else {
            sendResponse(connection: connection, statusCode: 400, body: ["error": "Missing required field 'content'"])
            return
        }

        let contentType = (json["type"] as? String) ?? "text"
        let sourceApp = json["sourceApp"] as? String
        let sourceAppName = json["sourceAppName"] as? String ?? "API"
        let isPinned = json["isPinned"] as? Bool ?? false
        let isSensitive = json["isSensitive"] as? Bool ?? false

        guard ["text", "url"].contains(contentType) else {
            sendResponse(connection: connection, statusCode: 400, body: ["error": "Only 'text' and 'url' types supported via API"])
            return
        }

        let context = modelContainer.mainContext

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
                "timestamp": Self.iso8601Formatter.string(from: item.timestamp),
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

    // MARK: - Clipboard Operations Helper

    /// Copy a clipboard item to the system pasteboard
    private func copyItemToPasteboard(_ item: ClipboardItem) {
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

            copyItemToPasteboard(item)

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

            copyItemToPasteboard(item)

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

        // Limit initial fetch for performance
        var descriptor = FetchDescriptor<ClipboardItem>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        descriptor.fetchLimit = 200

        do {
            let allItems = try context.fetch(descriptor)

            let matchingItems = allItems.filter { item in
                item.searchableText.contains(lowercaseQuery) ||
                (item.textContent?.lowercased().contains(lowercaseQuery) ?? false)
            }

            let response = matchingItems.prefix(50).map { item in
                [
                    "id": item.id.uuidString,
                    "type": item.contentType,
                    "text": item.textContent ?? "",
                    "timestamp": Self.iso8601Formatter.string(from: item.timestamp),
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
            Access-Control-Allow-Origin: http://localhost\r
            Access-Control-Allow-Methods: GET, POST, PUT, DELETE, OPTIONS\r
            Access-Control-Allow-Headers: Authorization, Content-Type\r
            \r

            """

            guard var responseData = response.data(using: .utf8) else {
                connection.cancel()
                return
            }
            responseData.append(jsonData)

            connection.send(content: responseData, completion: .contentProcessed { _ in
                connection.cancel()
            })
        } catch {
            connection.cancel()
        }
    }

    private func sendCorsPreflightResponse(connection: NWConnection) {
        let response = """
        HTTP/1.1 204 No Content\r
        Access-Control-Allow-Origin: http://localhost\r
        Access-Control-Allow-Methods: GET, POST, PUT, DELETE, OPTIONS\r
        Access-Control-Allow-Headers: Authorization, Content-Type\r
        Access-Control-Max-Age: 86400\r
        \r

        """

        guard let responseData = response.data(using: .utf8) else {
            connection.cancel()
            return
        }

        connection.send(content: responseData, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func sendImageResponse(connection: NWConnection, imageData: Data) {
        let mimeType = mimeTypeForImageData(imageData)

        let response = """
        HTTP/1.1 200 OK\r
        Content-Type: \(mimeType)\r
        Content-Length: \(imageData.count)\r
        Access-Control-Allow-Origin: http://localhost\r
        \r

        """

        guard var responseData = response.data(using: .utf8) else {
            connection.cancel()
            return
        }
        responseData.append(imageData)

        connection.send(content: responseData, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func httpStatusText(for code: Int) -> String {
        switch code {
        case 200: return "OK"
        case 201: return "Created"
        case 204: return "No Content"
        case 400: return "Bad Request"
        case 401: return "Unauthorized"
        case 404: return "Not Found"
        case 405: return "Method Not Allowed"
        case 413: return "Payload Too Large"
        case 429: return "Too Many Requests"
        case 500: return "Internal Server Error"
        default: return "Unknown"
        }
    }
}

// MARK: - Keychain Helper

enum KeychainHelper {
    @discardableResult
    static func save(key: String, value: String) -> Bool {
        guard let data = value.data(using: .utf8) else {
            return false
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecValueData as String: data
        ]

        // Delete any existing item first
        let deleteStatus = SecItemDelete(query as CFDictionary)
        if deleteStatus != errSecSuccess && deleteStatus != errSecItemNotFound {
            // Log but continue - we'll try to add anyway
        }

        let addStatus = SecItemAdd(query as CFDictionary, nil)
        return addStatus == errSecSuccess
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

    @discardableResult
    static func delete(key: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]

        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
