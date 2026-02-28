import Foundation
import SwiftUI

// MARK: - ErrorHandler
// Centralized error handling for the Bitcoin AI Wallet.
// Converts raw errors into user-friendly messages and drives the
// error banner UI through published properties. Singleton pattern
// ensures a single error state across the entire app.
//
// Usage:
//   ErrorHandler.shared.handle(error)
//   ErrorHandler.shared.handle(error) { viewModel.retryLastAction() }
//
// In SwiftUI views:
//   ContentView()
//       .errorBanner()

@MainActor
final class ErrorHandler: ObservableObject {

    // MARK: - Singleton

    static let shared = ErrorHandler()

    // MARK: - Published State

    /// The current error being displayed to the user. `nil` when no error is active.
    @Published var currentError: AppError?

    /// Whether the error banner should be visible.
    @Published var showError: Bool = false

    // MARK: - Initialization

    private init() {}

    // MARK: - AppError

    /// A user-friendly error representation with optional retry support.
    struct AppError: Identifiable {
        let id = UUID()
        let title: String
        let message: String
        let severity: Severity
        let retryAction: (() -> Void)?

        enum Severity {
            case info
            case warning
            case error
            case critical

            /// The semantic color for this severity level.
            var color: Color {
                switch self {
                case .info:     return AppColors.info
                case .warning:  return AppColors.warning
                case .error:    return AppColors.error
                case .critical: return AppColors.error
                }
            }

            /// The dimmed background color for this severity level.
            var dimColor: Color {
                switch self {
                case .info:     return AppColors.infoDim
                case .warning:  return AppColors.warningDim
                case .error:    return AppColors.errorDim
                case .critical: return AppColors.errorDim
                }
            }

            /// The SF Symbol icon name for this severity level.
            var iconName: String {
                switch self {
                case .info:     return AppIcons.info
                case .warning:  return AppIcons.warning
                case .error:    return AppIcons.error
                case .critical: return AppIcons.error
                }
            }
        }
    }

    // MARK: - Generic Error Handling

    /// Handles any `Error` by mapping it to a user-friendly `AppError`
    /// and displaying the error banner.
    ///
    /// - Parameters:
    ///   - error: The error to handle.
    ///   - retryAction: An optional closure to invoke when the user taps "Retry".
    func handle(_ error: Error, retryAction: (() -> Void)? = nil) {
        let appError: AppError

        if let apiError = error as? APIError {
            appError = mapAPIError(apiError, retryAction: retryAction)
        } else if let keychainError = error as? KeychainManager.KeychainError {
            appError = mapKeychainError(keychainError, retryAction: retryAction)
        } else if let biometricError = error as? BiometricAuth.BiometricError {
            appError = mapBiometricError(biometricError, retryAction: retryAction)
        } else if let mnemonicError = error as? MnemonicError {
            appError = mapMnemonicError(mnemonicError, retryAction: retryAction)
        } else {
            appError = AppError(
                title: L10n.Common.error,
                message: error.localizedDescription,
                severity: .error,
                retryAction: retryAction
            )
        }

        AppLogger.error("Error handled: \(error.localizedDescription)", category: .general)
        presentError(appError)
    }

    // MARK: - API Error Handling

    /// Handles an `APIError` specifically, providing network-aware messaging.
    ///
    /// - Parameters:
    ///   - error: The API error to handle.
    ///   - retryAction: An optional closure to invoke when the user taps "Retry".
    func handleAPIError(_ error: APIError, retryAction: (() -> Void)? = nil) {
        let appError = mapAPIError(error, retryAction: retryAction)
        AppLogger.error("API error handled: \(error.errorDescription ?? "unknown")", category: .network)
        presentError(appError)
    }

    // MARK: - Wallet Error Handling

    /// Handles wallet-related errors with appropriate messaging.
    ///
    /// - Parameters:
    ///   - error: The wallet error to handle.
    ///   - retryAction: An optional closure to invoke when the user taps "Retry".
    func handleWalletError(_ error: Error, retryAction: (() -> Void)? = nil) {
        let appError = AppError(
            title: L10n.Common.error,
            message: error.localizedDescription,
            severity: .error,
            retryAction: retryAction
        )
        AppLogger.error("Wallet error handled: \(error.localizedDescription)", category: .wallet)
        presentError(appError)
    }

    // MARK: - Dismiss

    /// Dismisses the current error banner.
    func dismiss() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            showError = false
        }
        // Delay clearing the error to allow the dismiss animation to finish.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            self?.currentError = nil
        }
    }

    // MARK: - Private Helpers

    /// Displays an error by setting published state.
    private func presentError(_ error: AppError) {
        currentError = error
        withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
            showError = true
        }

        // Auto-dismiss info and warning after a delay.
        if error.severity == .info || error.severity == .warning {
            DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) { [weak self] in
                guard self?.currentError?.id == error.id else { return }
                self?.dismiss()
            }
        }
    }

    /// Maps an `APIError` to an `AppError`.
    private func mapAPIError(_ error: APIError, retryAction: (() -> Void)?) -> AppError {
        let severity: AppError.Severity
        let title: String
        let message: String

        switch error {
        case .noConnection:
            severity = .warning
            title = L10n.Error.network
            message = error.errorDescription ?? L10n.Error.network

        case .timeout:
            severity = .warning
            title = L10n.Error.network
            message = error.errorDescription ?? L10n.Error.network

        case .serverUnavailable:
            severity = .error
            title = L10n.Error.api
            message = error.errorDescription ?? L10n.Error.api

        case .rateLimited:
            severity = .warning
            title = L10n.Error.api
            message = error.errorDescription ?? L10n.Error.api

        case .unauthorized:
            severity = .error
            title = L10n.Error.api
            message = error.errorDescription ?? L10n.Error.api

        default:
            severity = .error
            title = L10n.Common.error
            message = error.errorDescription ?? L10n.Error.unknown
        }

        return AppError(
            title: title,
            message: message,
            severity: severity,
            retryAction: error.isRetryable ? retryAction : nil
        )
    }

    /// Maps a `KeychainManager.KeychainError` to an `AppError`.
    private func mapKeychainError(_ error: KeychainManager.KeychainError, retryAction: (() -> Void)?) -> AppError {
        AppError(
            title: L10n.Error.keychain,
            message: error.errorDescription ?? L10n.Error.keychain,
            severity: .critical,
            retryAction: retryAction
        )
    }

    /// Maps a `BiometricAuth.BiometricError` to an `AppError`.
    private func mapBiometricError(_ error: BiometricAuth.BiometricError, retryAction: (() -> Void)?) -> AppError {
        let severity: AppError.Severity

        switch error {
        case .userCancelled, .systemCancel:
            severity = .info
        case .lockout:
            severity = .warning
        default:
            severity = .error
        }

        return AppError(
            title: L10n.Error.biometricFailed,
            message: error.errorDescription ?? L10n.Error.biometricFailed,
            severity: severity,
            retryAction: retryAction
        )
    }

    /// Maps a `MnemonicError` to an `AppError`.
    private func mapMnemonicError(_ error: MnemonicError, retryAction: (() -> Void)?) -> AppError {
        AppError(
            title: L10n.Error.seedPhraseInvalid,
            message: error.errorDescription ?? L10n.Error.seedPhraseInvalid,
            severity: .error,
            retryAction: retryAction
        )
    }
}

// MARK: - Error Banner View Modifier

/// A view modifier that overlays an error banner at the top of the screen
/// when `ErrorHandler.shared` has an active error.
struct ErrorBannerModifier: ViewModifier {
    @ObservedObject var errorHandler: ErrorHandler

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if errorHandler.showError, let error = errorHandler.currentError {
                    ErrorBannerView(
                        error: error,
                        onDismiss: { errorHandler.dismiss() },
                        onRetry: error.retryAction
                    )
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .animation(.spring(response: 0.4, dampingFraction: 0.75), value: errorHandler.showError)
                    .padding(.horizontal, AppSpacing.lg)
                    .padding(.top, AppSpacing.sm)
                }
            }
    }
}

// MARK: - Error Banner View

/// A compact banner that displays an error message with optional dismiss and retry actions.
struct ErrorBannerView: View {
    let error: ErrorHandler.AppError
    let onDismiss: () -> Void
    let onRetry: (() -> Void)?

    var body: some View {
        HStack(spacing: AppSpacing.md) {
            // Severity icon
            Image(systemName: error.severity.iconName)
                .font(AppTypography.bodyMedium)
                .foregroundColor(error.severity.color)

            // Message
            VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                Text(error.title)
                    .font(AppTypography.labelMedium)
                    .foregroundColor(AppColors.textPrimary)

                Text(error.message)
                    .font(AppTypography.bodySmall)
                    .foregroundColor(AppColors.textSecondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)

            // Action buttons
            HStack(spacing: AppSpacing.sm) {
                if let onRetry = onRetry {
                    Button(action: {
                        HapticManager.buttonTap()
                        onDismiss()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                            onRetry()
                        }
                    }) {
                        Text(L10n.Common.retry)
                            .font(AppTypography.buttonSmall)
                            .foregroundColor(error.severity.color)
                    }
                }

                Button(action: {
                    HapticManager.buttonTap()
                    onDismiss()
                }) {
                    Image(systemName: AppIcons.close)
                        .font(AppTypography.labelSmall)
                        .foregroundColor(AppColors.textTertiary)
                }
            }
        }
        .padding(AppSpacing.md)
        .background(error.severity.dimColor)
        .cornerRadius(AppCornerRadius.large)
        .overlay(
            RoundedRectangle(cornerRadius: AppCornerRadius.large)
                .stroke(error.severity.color.opacity(0.3), lineWidth: 1)
        )
        .appShadow(AppShadows.medium)
    }
}

// MARK: - View Extension

extension View {

    /// Attaches the global error banner overlay to this view.
    ///
    /// ```swift
    /// NavigationStack { ... }
    ///     .errorBanner()
    /// ```
    func errorBanner() -> some View {
        modifier(ErrorBannerModifier(errorHandler: ErrorHandler.shared))
    }
}
