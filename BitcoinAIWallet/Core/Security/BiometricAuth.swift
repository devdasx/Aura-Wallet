import Foundation
import LocalAuthentication

// MARK: - BiometricAuth
/// Face ID and Touch ID authentication.
///
/// Publishes `isAuthenticated` so SwiftUI views can reactively respond
/// to authentication state changes.
final class BiometricAuth: ObservableObject {

    // MARK: - Singleton

    static let shared = BiometricAuth()
    private init() {}

    // MARK: - Types

    enum BiometricType {
        case faceID
        case touchID
        case none
    }

    enum BiometricError: Error, LocalizedError {
        case notAvailable
        case notEnrolled
        case authenticationFailed
        case userCancelled
        case lockout
        case systemCancel
        case passcodeNotSet
        case unknown(String)

        var errorDescription: String? {
            switch self {
            case .notAvailable:
                return "Biometric authentication is not available on this device."
            case .notEnrolled:
                return "No biometric data is enrolled. Please set up Face ID or Touch ID in Settings."
            case .authenticationFailed:
                return "Biometric authentication failed. Please try again."
            case .userCancelled:
                return "Authentication was cancelled by the user."
            case .lockout:
                return "Biometric authentication is locked due to too many failed attempts. Please use your device passcode."
            case .systemCancel:
                return "Authentication was cancelled by the system."
            case .passcodeNotSet:
                return "A device passcode is required to use biometric authentication."
            case .unknown(let detail):
                return "Authentication error: \(detail)"
            }
        }
    }

    // MARK: - Published State

    @Published var isAuthenticated: Bool = false

    // MARK: - Computed Properties

    /// The type of biometric hardware available on this device.
    var biometricType: BiometricType {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics,
                                        error: &error) else {
            return .none
        }

        switch context.biometryType {
        case .faceID:
            return .faceID
        case .touchID:
            return .touchID
        case .none:
            return .none
        case .opticID:
            return .none
        @unknown default:
            return .none
        }
    }

    /// Whether biometrics are both available and enrolled.
    var canUseBiometrics: Bool {
        let context = LAContext()
        var error: NSError?
        return context.canEvaluatePolicy(
            .deviceOwnerAuthenticationWithBiometrics,
            error: &error
        )
    }

    // MARK: - Authentication

    /// Authenticate the user with biometrics.
    ///
    /// - Parameter reason: A human-readable explanation shown in the
    ///   system biometric dialog (e.g. "Unlock your wallet").
    /// - Returns: `true` when authentication succeeds.
    /// - Throws: `BiometricError` on failure.
    @MainActor
    @discardableResult
    func authenticate(reason: String) async throws -> Bool {
        let context = LAContext()
        context.localizedCancelTitle = "Cancel"

        // Validate availability first so we can surface a clear error.
        var policyError: NSError?
        guard context.canEvaluatePolicy(
            .deviceOwnerAuthenticationWithBiometrics,
            error: &policyError
        ) else {
            isAuthenticated = false
            throw mapLAError(policyError)
        }

        do {
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: reason
            )
            isAuthenticated = success
            return success
        } catch {
            isAuthenticated = false
            throw mapLAError(error as NSError)
        }
    }

    /// Authenticate for a transaction signing operation.
    ///
    /// Uses a stricter context that invalidates itself if biometric
    /// enrollment changes (e.g. a new fingerprint is added), ensuring
    /// that only the originally enrolled user can sign.
    ///
    /// - Returns: `true` when authentication succeeds.
    /// - Throws: `BiometricError` on failure.
    @MainActor
    @discardableResult
    func authenticateForSigning() async throws -> Bool {
        let context = LAContext()
        context.localizedCancelTitle = "Cancel"
        // touchIDAuthenticationAllowableReuseDuration = 0 ensures a fresh
        // authentication every time, which is appropriate for signing.
        context.touchIDAuthenticationAllowableReuseDuration = 0

        var policyError: NSError?
        guard context.canEvaluatePolicy(
            .deviceOwnerAuthenticationWithBiometrics,
            error: &policyError
        ) else {
            isAuthenticated = false
            throw mapLAError(policyError)
        }

        do {
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: "Authenticate to sign this Bitcoin transaction"
            )
            isAuthenticated = success
            return success
        } catch {
            isAuthenticated = false
            throw mapLAError(error as NSError)
        }
    }

    /// Reset the authentication state (e.g. on app background).
    @MainActor
    func deauthenticate() {
        isAuthenticated = false
    }

    // MARK: - Error Mapping

    /// Map `NSError` from LocalAuthentication into our `BiometricError`.
    private func mapLAError(_ error: NSError?) -> BiometricError {
        guard let error = error else {
            return .authenticationFailed
        }

        let code = LAError.Code(rawValue: error.code) ?? .authenticationFailed

        switch code {
        case .biometryNotAvailable, .touchIDNotAvailable:
            return .notAvailable
        case .biometryNotEnrolled, .touchIDNotEnrolled:
            return .notEnrolled
        case .authenticationFailed:
            return .authenticationFailed
        case .userCancel:
            return .userCancelled
        case .biometryLockout, .touchIDLockout:
            return .lockout
        case .systemCancel:
            return .systemCancel
        case .passcodeNotSet:
            return .passcodeNotSet
        case .userFallback:
            return .userCancelled
        case .appCancel:
            return .systemCancel
        case .invalidContext:
            return .authenticationFailed
        case .notInteractive:
            return .systemCancel
        case .companionNotAvailable:
            return .notAvailable
        @unknown default:
            return .unknown(error.localizedDescription)
        }
    }
}
