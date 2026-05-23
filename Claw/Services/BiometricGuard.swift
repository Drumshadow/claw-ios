import LocalAuthentication
import Foundation

@MainActor
final class BiometricGuard {
    static let shared = BiometricGuard()

    private init() {}

    enum BiometricType {
        case none
        case touchID
        case faceID
    }

    var availableType: BiometricType {
        let context = LAContext()
        var error: NSError?

        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            return .none
        }

        switch context.biometryType {
        case .touchID:
            return .touchID
        case .faceID:
            return .faceID
        case .none:
            return .none
        @unknown default:
            return .none
        }
    }

    var isAvailable: Bool {
        availableType != .none
    }

    // Returns true if authenticated, false if failed or cancelled
    func authenticate(reason: String) async -> Bool {
        let context = LAContext()
        var error: NSError?

        // Check if biometric authentication is available
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            #if DEBUG
            print("BiometricGuard: Biometric authentication not available: \(error?.localizedDescription ?? "unknown")")
            #endif
            // Fall back to device passcode if biometrics unavailable
            return await authenticateWithPasscode(reason: reason)
        }

        do {
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: reason
            )
            return success
        } catch let error as LAError {
            #if DEBUG
            print("BiometricGuard: Authentication failed: \(error.localizedDescription)")
            #endif

            // If biometric fails, offer passcode as fallback for critical operations
            switch error.code {
            case .biometryLockout, .biometryNotAvailable:
                return await authenticateWithPasscode(reason: reason)
            default:
                return false
            }
        } catch {
            #if DEBUG
            print("BiometricGuard: Unexpected error: \(error)")
            #endif
            return false
        }
    }

    // Fallback to device passcode
    private func authenticateWithPasscode(reason: String) async -> Bool {
        let context = LAContext()

        do {
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: reason
            )
            return success
        } catch {
            #if DEBUG
            print("BiometricGuard: Passcode authentication failed: \(error.localizedDescription)")
            #endif
            return false
        }
    }

    // Convenience: only triggers biometric if riskLevel.requiresBiometric
    func authenticateIfNeeded(for risk: RiskLevel, reason: String) async -> Bool {
        guard risk.requiresBiometric else {
            return true  // No authentication needed
        }

        return await authenticate(reason: reason)
    }

    // For policy-based authentication (can override risk level)
    func authenticateIfNeeded(
        for risk: RiskLevel,
        policy: ApprovalPolicy?,
        reason: String
    ) async -> Bool {
        let requiresAuth = policy?.requireBiometric ?? risk.requiresBiometric

        guard requiresAuth else {
            return true
        }

        return await authenticate(reason: reason)
    }
}
