import Foundation
import LocalAuthentication
import os

/// Handles biometric (Touch ID) and password authentication for sensitive content
@MainActor
class AuthenticationService: ObservableObject {
    static let shared = AuthenticationService()

    /// Set of item IDs that have been authenticated this session
    @Published private(set) var authenticatedItems: Set<UUID> = []

    /// Whether authentication is currently in progress
    @Published private(set) var isAuthenticating = false

    /// Time interval after which authentication expires (default: 5 minutes)
    var authenticationTimeout: TimeInterval = 300

    /// Tracks when items were authenticated
    private var authenticationTimes: [UUID: Date] = [:]

    private init() {}

    /// Checks if an item is currently authenticated (not expired)
    func isAuthenticated(_ itemId: UUID) -> Bool {
        guard authenticatedItems.contains(itemId),
              let authTime = authenticationTimes[itemId] else {
            return false
        }

        // Check if authentication has expired
        if Date().timeIntervalSince(authTime) > authenticationTimeout {
            authenticatedItems.remove(itemId)
            authenticationTimes.removeValue(forKey: itemId)
            return false
        }

        return true
    }

    /// Authenticates access to a sensitive item
    /// - Parameters:
    ///   - itemId: The UUID of the item to authenticate
    ///   - reason: The reason displayed to the user
    /// - Returns: True if authentication succeeded
    func authenticate(for itemId: UUID, reason: String = "authenticate to view sensitive content") async -> Bool {
        // Already authenticated and not expired
        if isAuthenticated(itemId) {
            return true
        }

        isAuthenticating = true
        defer { isAuthenticating = false }

        let context = LAContext()
        var error: NSError?

        // Check if biometric/password authentication is available
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            AppLogger.general.error("Authentication not available: \(error?.localizedDescription ?? "unknown", privacy: .public)")
            return false
        }

        do {
            // Use .deviceOwnerAuthentication which allows both biometric AND password fallback
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: reason
            )

            if success {
                authenticatedItems.insert(itemId)
                authenticationTimes[itemId] = Date()
                AppLogger.general.info("Authentication successful for item")
            }

            return success
        } catch {
            AppLogger.general.error("Authentication failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    /// Authenticates for a general action (not tied to a specific item)
    /// - Parameter reason: The reason displayed to the user
    /// - Returns: True if authentication succeeded
    func authenticateGeneral(reason: String = "authenticate to access sensitive content") async -> Bool {
        isAuthenticating = true
        defer { isAuthenticating = false }

        let context = LAContext()
        var error: NSError?

        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            AppLogger.general.error("Authentication not available: \(error?.localizedDescription ?? "unknown", privacy: .public)")
            return false
        }

        do {
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: reason
            )
            return success
        } catch {
            AppLogger.general.error("Authentication failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    /// Clears authentication for a specific item
    func clearAuthentication(for itemId: UUID) {
        authenticatedItems.remove(itemId)
        authenticationTimes.removeValue(forKey: itemId)
    }

    /// Clears all authenticated items
    func clearAllAuthentication() {
        authenticatedItems.removeAll()
        authenticationTimes.removeAll()
    }

    /// Checks if biometric authentication is available on this device
    var isBiometricAvailable: Bool {
        let context = LAContext()
        var error: NSError?
        return context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
    }

    /// Returns the type of biometric available (Touch ID, Face ID, or none)
    var biometricType: LABiometryType {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            return .none
        }
        return context.biometryType
    }
}
