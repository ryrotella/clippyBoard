import Foundation
import Network
import SwiftData
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
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            if let data = data, !data.isEmpty {
                Task { @MainActor in
                    self?.processRequest(data: data, connection: connection)
                }
            }
            if isComplete || error != nil {
                connection.cancel()
            }
        }
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

        // Route request
        Task { @MainActor in
            await self.routeRequest(method: method, path: path, connection: connection)
        }
    }

    private func routeRequest(method: String, path: String, connection: NWConnection) async {
        guard method == "GET" else {
            sendResponse(connection: connection, statusCode: 405, body: ["error": "Method not allowed"])
            return
        }

        // Parse path
        let pathComponents = path.split(separator: "/").map(String.init)

        if pathComponents == ["api", "items"] {
            await handleGetItems(connection: connection)
        } else if pathComponents.count == 3 && pathComponents[0] == "api" && pathComponents[1] == "items" {
            await handleGetItem(id: pathComponents[2], connection: connection)
        } else if pathComponents == ["api", "screenshots"] {
            await handleGetScreenshots(connection: connection)
        } else if pathComponents.count == 4 && pathComponents[0] == "api" && pathComponents[1] == "screenshots" && pathComponents[3] == "image" {
            await handleGetScreenshotImage(id: pathComponents[2], connection: connection)
        } else if pathComponents == ["api", "health"] {
            sendResponse(connection: connection, statusCode: 200, body: ["status": "ok", "version": "1.0"])
        } else {
            sendResponse(connection: connection, statusCode: 404, body: ["error": "Not found"])
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
