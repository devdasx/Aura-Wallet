// MARK: - AppRouter.swift
// Bitcoin AI Wallet
//
// Central navigation state machine for the application.
// Manages screen transitions between onboarding, main wallet, and lock screen.
// Handles biometric authentication, auto-lock timers, theme preferences,
// and app lifecycle state management.
//
// Platform: iOS 17.0+
// Dependencies: SwiftUI, LocalAuthentication, Combine

import SwiftUI
@preconcurrency import LocalAuthentication
import Combine

// MARK: - App Screen Enum

/// Represents the top-level screens in the application navigation hierarchy.
enum AppScreen: Equatable, Hashable, Sendable {
    /// First-time user onboarding flow.
    case onboarding
    /// Main wallet interface (dashboard, send, receive, history, settings).
    case main
    /// Locked state requiring biometric or passcode authentication.
    case locked
}

// MARK: - Theme Preference

/// User-selectable theme options.
enum ThemePreference: String, CaseIterable, Identifiable, Sendable {
    case dark = "dark"
    case light = "light"
    case system = "system"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .dark: return "Dark"
        case .light: return "Light"
        case .system: return "System"
        }
    }

    var iconName: String {
        switch self {
        case .dark: return "moon.fill"
        case .light: return "sun.max.fill"
        case .system: return "circle.lefthalf.filled"
        }
    }
}

// MARK: - App Router

/// Main navigation state machine and app-level configuration manager.
///
/// `AppRouter` is the single source of truth for:
/// - Which top-level screen is displayed (onboarding, main, or locked)
/// - Theme/color scheme preference
/// - Auto-lock timer management
/// - Biometric authentication state
///
/// Injected as an `@EnvironmentObject` throughout the view hierarchy.
@MainActor
final class AppRouter: ObservableObject {

    // MARK: - Published State

    /// The currently displayed top-level screen.
    @Published var currentScreen: AppScreen = .onboarding

    /// The active color scheme. `nil` means follow system setting.
    @Published var colorScheme: ColorScheme? = .dark

    /// Whether biometric authentication is available on this device.
    @Published private(set) var isBiometricAvailable: Bool = false

    /// The type of biometric authentication available (Face ID, Touch ID, or none).
    @Published private(set) var biometricType: LABiometryType = .none

    /// Whether the app is currently in the authentication flow.
    @Published private(set) var isAuthenticating: Bool = false

    // MARK: - Persisted State

    /// Whether the user has completed the onboarding flow.
    @AppStorage("has_completed_onboarding") private var hasCompletedOnboarding = false

    /// The user's theme preference (dark, light, or system).
    @AppStorage("theme_preference") var themePreference: String = ThemePreference.dark.rawValue {
        didSet {
            updateColorScheme()
        }
    }

    /// Whether biometric lock is enabled by the user.
    @AppStorage("biometric_lock_enabled") var biometricLockEnabled: Bool = true

    /// Auto-lock timeout in seconds. Default is 5 minutes (300 seconds).
    @AppStorage("auto_lock_timeout") var autoLockTimeoutSeconds: Int = 300

    // MARK: - Private State

    /// Timer that triggers auto-lock after inactivity.
    private var lockTimer: Timer?

    /// Cancellable subscriptions.
    private var cancellables = Set<AnyCancellable>()

    /// Timestamp when the app last went to the background.
    private var backgroundTimestamp: Date?

    /// Stored biometric domain state to detect enrollment changes.
    /// If a new face/fingerprint is added, this will differ and we require re-setup.
    private var lastKnownBiometricDomainState: Data?

    /// The auto-lock timeout interval derived from the stored seconds value.
    private var lockTimeout: TimeInterval {
        TimeInterval(autoLockTimeoutSeconds)
    }

    // MARK: - Initialization

    init() {
        // Determine initial screen based on onboarding completion
        if hasCompletedOnboarding {
            currentScreen = .locked
        } else {
            currentScreen = .onboarding
        }

        // Configure color scheme from persisted preference
        updateColorScheme()

        // Check biometric availability
        checkBiometricAvailability()

        // Listen for app lifecycle lock requests
        setupNotificationObservers()

        // Start the inactivity timer if the user is already authenticated
        if currentScreen == .main {
            resetLockTimer()
        }
    }

    deinit {
        lockTimer?.invalidate()
        lockTimer = nil
    }

    // MARK: - Navigation Actions

    /// Marks onboarding as complete and navigates to the main wallet view.
    func completeOnboarding() {
        hasCompletedOnboarding = true
        currentScreen = .main
        resetLockTimer()
    }

    /// Locks the app, requiring re-authentication to continue.
    func lockApp() {
        guard currentScreen == .main else { return }
        invalidateLockTimer()
        withAnimation(.easeInOut(duration: 0.3)) {
            currentScreen = .locked
        }
    }

    /// Performs biometric authentication and navigates to the main screen on success.
    ///
    /// - Parameter completion: Called with `(success, errorMessage)` after the auth attempt.
    func authenticate(completion: @escaping (Bool, String?) -> Void) {
        guard !isAuthenticating else {
            completion(false, "Authentication already in progress.")
            return
        }

        isAuthenticating = true

        let context = LAContext()
        context.localizedCancelTitle = L10n.Common.cancel
        context.localizedFallbackTitle = "Enter Passcode"

        var error: NSError?
        let canEvaluate = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)

        // Use biometrics if enabled and available; otherwise fall back to device passcode.
        // Even with biometric lock disabled, we always require device-owner authentication
        // to prevent unauthenticated access to wallet data.
        let policy: LAPolicy = (biometricLockEnabled && canEvaluate)
            ? .deviceOwnerAuthenticationWithBiometrics
            : .deviceOwnerAuthentication

        let reason = "Authenticate to access your Bitcoin wallet"

        // Detect biometric enrollment changes (new face/fingerprint added)
        if biometricLockEnabled && canEvaluate {
            let currentDomainState = context.evaluatedPolicyDomainState
            if let lastState = lastKnownBiometricDomainState,
               let currentState = currentDomainState,
               lastState != currentState {
                // Biometric enrollment changed -- force device passcode for safety
                isAuthenticating = false
                completion(false, "Biometric enrollment has changed. Please re-authenticate with your device passcode and re-enable biometrics in Settings.")
                return
            }
        }

        context.evaluatePolicy(policy, localizedReason: reason) { [weak self] success, authError in
            DispatchQueue.main.async {
                self?.isAuthenticating = false

                if success {
                    // Store the current biometric domain state for future comparison
                    self?.lastKnownBiometricDomainState = context.evaluatedPolicyDomainState
                    self?.navigateToMain()
                    completion(true, nil)
                } else {
                    let message = self?.authenticationErrorMessage(for: authError)
                    completion(false, message)
                }
            }
        }
    }

    /// Resets the app state to the onboarding flow.
    /// Used when the user deletes their wallet or resets the app.
    func resetToOnboarding() {
        invalidateLockTimer()
        hasCompletedOnboarding = false
        withAnimation(.easeInOut(duration: 0.3)) {
            currentScreen = .onboarding
        }
    }

    // MARK: - Theme Management

    /// Updates the color scheme based on the current theme preference.
    func updateColorScheme() {
        guard let preference = ThemePreference(rawValue: themePreference) else {
            colorScheme = .dark
            return
        }

        switch preference {
        case .dark:
            colorScheme = .dark
        case .light:
            colorScheme = .light
        case .system:
            colorScheme = nil // Follow system setting
        }
    }

    /// Sets the theme preference and immediately updates the color scheme.
    ///
    /// - Parameter theme: The desired theme preference.
    func setTheme(_ theme: ThemePreference) {
        themePreference = theme.rawValue
    }

    // MARK: - Lock Timer Management

    /// Resets the auto-lock inactivity timer.
    /// Should be called on any meaningful user interaction.
    func resetLockTimer() {
        invalidateLockTimer()

        guard currentScreen == .main, autoLockTimeoutSeconds > 0 else { return }

        lockTimer = Timer.scheduledTimer(
            withTimeInterval: lockTimeout,
            repeats: false
        ) { [weak self] _ in
            DispatchQueue.main.async {
                self?.lockApp()
            }
        }

        // Ensure the timer fires even during scroll tracking
        if let timer = lockTimer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    /// Invalidates and clears the current lock timer.
    private func invalidateLockTimer() {
        lockTimer?.invalidate()
        lockTimer = nil
    }

    // MARK: - App Lifecycle Handling

    /// Called when the app is about to resign active state (e.g., entering app switcher).
    func handleAppWillResignActive() {
        backgroundTimestamp = Date()
        invalidateLockTimer()
    }

    /// Called when the app returns to the foreground.
    func handleAppWillEnterForeground() {
        guard let timestamp = backgroundTimestamp else { return }

        let elapsed = Date().timeIntervalSince(timestamp)
        backgroundTimestamp = nil

        // Lock if the app was in the background longer than the configured timeout.
        // Always lock regardless of biometricLockEnabled -- the authenticate()
        // method will use device passcode as fallback when biometrics are disabled.
        // Use the user's auto-lock timeout, but cap at a minimum of 30 seconds
        // to prevent the app from never locking.
        let backgroundLockThreshold: TimeInterval = max(30, lockTimeout)
        if elapsed > backgroundLockThreshold && currentScreen == .main {
            withAnimation(.easeInOut(duration: 0.3)) {
                currentScreen = .locked
            }
        }
    }

    /// Called when the app becomes active (returned to foreground and is interactive).
    func handleAppDidBecomeActive() {
        if currentScreen == .main {
            resetLockTimer()
        }
    }

    // MARK: - Biometric Availability

    /// Checks whether biometric authentication is available and updates published state.
    func checkBiometricAvailability() {
        let context = LAContext()
        var error: NSError?

        isBiometricAvailable = context.canEvaluatePolicy(
            .deviceOwnerAuthenticationWithBiometrics,
            error: &error
        )

        biometricType = context.biometryType
    }

    /// Returns a human-readable description of the available biometric type.
    var biometricTypeName: String {
        switch biometricType {
        case .none:
            return "Biometrics"
        case .faceID:
            return "Face ID"
        case .touchID:
            return "Touch ID"
        case .opticID:
            return "Optic ID"
        @unknown default:
            return "Biometrics"
        }
    }

    // MARK: - Private Helpers

    /// Navigates to the main screen and starts the lock timer.
    private func navigateToMain() {
        withAnimation(.easeInOut(duration: 0.3)) {
            currentScreen = .main
        }
        resetLockTimer()
        processPendingDeepLink()
    }

    /// Maps a LocalAuthentication error to a user-friendly message.
    private func authenticationErrorMessage(for error: Error?) -> String {
        guard let laError = error as? LAError else {
            return L10n.LockScreen.authFailed
        }

        switch laError.code {
        case .authenticationFailed:
            return "Authentication failed. Please try again."
        case .userCancel:
            return "Authentication was cancelled."
        case .userFallback:
            return "Please use your device passcode."
        case .biometryNotAvailable, .touchIDNotAvailable:
            return "Biometric authentication is not available on this device."
        case .biometryNotEnrolled, .touchIDNotEnrolled:
            return "No biometric data is enrolled. Please set up Face ID or Touch ID in Settings."
        case .biometryLockout, .touchIDLockout:
            return "Biometric authentication is locked. Please use your device passcode."
        case .passcodeNotSet:
            return "No device passcode is set. Please enable a passcode in Settings."
        case .systemCancel:
            return "Authentication was cancelled by the system."
        case .appCancel:
            return "Authentication was cancelled."
        case .invalidContext:
            return "Authentication context is invalid. Please try again."
        case .notInteractive:
            return "Authentication is not possible right now."
        case .companionNotAvailable:
            return "Companion device is not available for authentication."
        @unknown default:
            return L10n.LockScreen.authFailed
        }
    }

    /// Subscribes to app-level notifications for lock/unlock behavior.
    private func setupNotificationObservers() {
        NotificationCenter.default.publisher(for: .appShouldLock)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.lockApp()
            }
            .store(in: &cancellables)
    }
}

// MARK: - User Activity Tracking

extension AppRouter {

    /// Call this method from interactive views to signal user activity
    /// and reset the auto-lock timer.
    ///
    /// Usage:
    /// ```swift
    /// .onTapGesture { appRouter.registerUserActivity() }
    /// ```
    func registerUserActivity() {
        guard currentScreen == .main else { return }
        resetLockTimer()
    }
}

// MARK: - Deep Link Handling

extension AppRouter {

    /// Handles incoming deep links or universal links.
    ///
    /// Supported schemes:
    /// - `bitcoin:` — Opens the send flow with a pre-filled address.
    /// - `bitcoinai://` — Internal navigation links.
    ///
    /// - Parameter url: The incoming URL to handle.
    /// - Returns: `true` if the URL was handled, `false` otherwise.
    @discardableResult
    func handleDeepLink(_ url: URL) -> Bool {
        guard currentScreen == .main else {
            // Queue the deep link for handling after authentication
            pendingDeepLink = url
            return true
        }

        return processDeepLink(url)
    }

    /// Stores a deep link to be processed after authentication.
    private(set) var pendingDeepLink: URL? {
        get { _pendingDeepLink }
        set { _pendingDeepLink = newValue }
    }

    /// Backing storage for pending deep link.
    private static var _pendingDeepLinkStorage: URL?

    private var _pendingDeepLink: URL? {
        get { Self._pendingDeepLinkStorage }
        set { Self._pendingDeepLinkStorage = newValue }
    }

    /// Processes a deep link URL and triggers the appropriate navigation.
    private func processDeepLink(_ url: URL) -> Bool {
        let scheme = url.scheme?.lowercased() ?? ""

        switch scheme {
        case "bitcoin":
            // Bitcoin URI: bitcoin:<address>?amount=<amount>&label=<label>
            // Will be handled by the send flow when implemented
            NotificationCenter.default.post(
                name: .bitcoinURIReceived,
                object: nil,
                userInfo: ["url": url]
            )
            return true

        case "bitcoinai":
            // Internal navigation: bitcoinai://screen/parameter
            guard let host = url.host?.lowercased() else { return false }

            switch host {
            case "send":
                NotificationCenter.default.post(
                    name: .navigateToSend,
                    object: nil,
                    userInfo: ["url": url]
                )
                return true
            case "receive":
                NotificationCenter.default.post(
                    name: .navigateToReceive,
                    object: nil
                )
                return true
            case "settings":
                NotificationCenter.default.post(
                    name: .navigateToSettings,
                    object: nil
                )
                return true
            default:
                return false
            }

        default:
            return false
        }
    }

    /// Processes any pending deep link that was received while the app was locked.
    /// Only processes if the user is authenticated and on the main screen.
    func processPendingDeepLink() {
        guard currentScreen == .main else { return }
        guard let url = pendingDeepLink else { return }
        pendingDeepLink = nil
        _ = processDeepLink(url)
    }
}

// MARK: - Navigation Notification Names

extension Notification.Name {
    /// A bitcoin: URI was received via deep link or QR scan.
    static let bitcoinURIReceived = Notification.Name("com.bitcoinai.wallet.bitcoinURIReceived")

    /// Navigate to the send screen.
    static let navigateToSend = Notification.Name("com.bitcoinai.wallet.navigateToSend")

    /// Navigate to the receive screen.
    static let navigateToReceive = Notification.Name("com.bitcoinai.wallet.navigateToReceive")

    /// Navigate to the settings screen.
    static let navigateToSettings = Notification.Name("com.bitcoinai.wallet.navigateToSettings")

    /// Inject a command into the chat input and send it.
    static let chatInjectCommand = Notification.Name("com.bitcoinai.wallet.chatInjectCommand")

    /// Request a full wallet refresh (triggered from chat commands like "refresh", "reload").
    static let walletRefreshRequested = Notification.Name("com.bitcoinai.wallet.walletRefreshRequested")

    /// Open QR scanner from inline action button during send flow.
    static let openQRScannerForSend = Notification.Name("com.bitcoinai.wallet.openQRScannerForSend")

    /// Typing animation progress — triggers auto-scroll in ChatView.
    static let typingAnimationProgress = Notification.Name("com.bitcoinai.wallet.typingAnimationProgress")
}
