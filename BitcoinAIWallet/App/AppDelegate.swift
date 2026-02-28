// MARK: - AppDelegate.swift
// Bitcoin AI Wallet
//
// UIKit application delegate providing lifecycle hooks for the SwiftUI app.
// Manages background/foreground transitions, auto-lock behavior, orientation
// locking, and system-level event handling.
//
// Platform: iOS 17.0+
// Dependencies: UIKit, LocalAuthentication

import UIKit
import LocalAuthentication

// MARK: - AppDelegate

final class AppDelegate: NSObject, UIApplicationDelegate {

    // MARK: - Properties

    /// Timestamp when the app last entered the background.
    private var backgroundEntryDate: Date?

    /// Maximum time (in seconds) the app can remain in the background before requiring re-authentication.
    private let backgroundLockThreshold: TimeInterval = 30

    /// Reference to the app router for triggering lock state.
    /// Set during scene connection.
    weak var appRouter: AppRouter?

    // MARK: - Application Lifecycle

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {

        // Configure global appearance
        configureAppearance()

        // Disable system screenshots in task switcher for security
        // (handled via overlay in scene delegate)

        // Register for significant time change (e.g., day rollover)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSignificantTimeChange),
            name: UIApplication.significantTimeChangeNotification,
            object: nil
        )

        // Register for memory warnings
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleMemoryWarning),
            name: UIApplication.didReceiveMemoryWarningNotification,
            object: nil
        )

        return true
    }

    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let config = UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
        config.delegateClass = SceneDelegate.self
        return config
    }

    func application(
        _ application: UIApplication,
        didDiscardSceneSessions sceneSessions: Set<UISceneSession>
    ) {
        // Clean up resources for discarded scenes if needed
    }

    // MARK: - Orientation Lock

    /// Forces portrait-only orientation across the entire app.
    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        return .portrait
    }

    // MARK: - Background / Foreground Transitions

    func applicationDidEnterBackground(_ application: UIApplication) {
        backgroundEntryDate = Date()

        // Post notification for other components to respond
        NotificationCenter.default.post(
            name: .appDidEnterBackground,
            object: nil,
            userInfo: ["timestamp": Date()]
        )
    }

    func applicationWillEnterForeground(_ application: UIApplication) {
        guard let backgroundDate = backgroundEntryDate else { return }

        let elapsed = Date().timeIntervalSince(backgroundDate)
        backgroundEntryDate = nil

        if elapsed > backgroundLockThreshold {
            NotificationCenter.default.post(
                name: .appShouldLock,
                object: nil,
                userInfo: ["elapsed": elapsed]
            )
        }

        NotificationCenter.default.post(
            name: .appDidEnterForeground,
            object: nil,
            userInfo: ["backgroundDuration": elapsed]
        )
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        // Remove any security overlay
        NotificationCenter.default.post(name: .appDidBecomeActive, object: nil)
    }

    func applicationWillResignActive(_ application: UIApplication) {
        // Apply security overlay to hide sensitive content in app switcher
        NotificationCenter.default.post(name: .appWillResignActive, object: nil)
    }

    // MARK: - Appearance Configuration

    private func configureAppearance() {
        // Navigation bar appearance
        let navAppearance = UINavigationBarAppearance()
        navAppearance.configureWithDefaultBackground()
        navAppearance.shadowColor = .clear
        UINavigationBar.appearance().standardAppearance = navAppearance
        UINavigationBar.appearance().scrollEdgeAppearance = navAppearance
        UINavigationBar.appearance().compactAppearance = navAppearance

        // Tab bar appearance
        let tabAppearance = UITabBarAppearance()
        tabAppearance.configureWithDefaultBackground()
        tabAppearance.shadowColor = .clear
        UITabBar.appearance().standardAppearance = tabAppearance
        UITabBar.appearance().scrollEdgeAppearance = tabAppearance

        // Disable translucent navigation bars
        UINavigationBar.appearance().isTranslucent = true

        // Set tint color globally
        UIView.appearance(whenContainedInInstancesOf: [UIAlertController.self])
            .tintColor = UIColor(red: 0.96, green: 0.62, blue: 0.07, alpha: 1.0) // Bitcoin orange
    }

    // MARK: - Notification Handlers

    @objc private func handleSignificantTimeChange() {
        // Notify components that need to refresh date-dependent data
        NotificationCenter.default.post(name: .significantTimeDidChange, object: nil)
    }

    @objc private func handleMemoryWarning() {
        // Clear caches and non-essential data
        URLCache.shared.removeAllCachedResponses()
        NotificationCenter.default.post(name: .appDidReceiveMemoryWarning, object: nil)
    }
}

// MARK: - Scene Delegate

final class SceneDelegate: NSObject, UIWindowSceneDelegate {

    /// Privacy protection overlay window shown in app switcher.
    private var privacyWindow: UIWindow?

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else { return }

        // Listen for privacy overlay notifications
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(showPrivacyOverlay),
            name: .appWillResignActive,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(hidePrivacyOverlay),
            name: .appDidBecomeActive,
            object: nil
        )

        // Store window scene reference for privacy window
        _ = windowScene
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        removePrivacyWindow()
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        removePrivacyWindow()
    }

    func sceneWillResignActive(_ scene: UIScene) {
        guard let windowScene = scene as? UIWindowScene else { return }
        showPrivacyWindow(in: windowScene)
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        guard let windowScene = scene as? UIWindowScene else { return }
        showPrivacyWindow(in: windowScene)
    }

    func sceneWillEnterForeground(_ scene: UIScene) {
        // Privacy window will be removed in sceneDidBecomeActive
    }

    // MARK: - Privacy Window

    /// Shows a blur overlay to prevent sensitive content from appearing in the app switcher.
    private func showPrivacyWindow(in windowScene: UIWindowScene) {
        guard privacyWindow == nil else { return }

        let window = UIWindow(windowScene: windowScene)
        window.windowLevel = .alert + 1

        let blurEffect = UIBlurEffect(style: .systemThickMaterial)
        let blurView = UIVisualEffectView(effect: blurEffect)
        blurView.frame = window.bounds
        blurView.autoresizingMask = [.flexibleWidth, .flexibleHeight]

        // Add app icon on top of blur
        let iconConfig = UIImage.SymbolConfiguration(pointSize: 48, weight: .thin)
        let iconImage = UIImage(systemName: "lock.shield.fill", withConfiguration: iconConfig)
        let iconView = UIImageView(image: iconImage)
        iconView.tintColor = UIColor(red: 0.96, green: 0.62, blue: 0.07, alpha: 1.0)
        iconView.translatesAutoresizingMaskIntoConstraints = false
        blurView.contentView.addSubview(iconView)

        NSLayoutConstraint.activate([
            iconView.centerXAnchor.constraint(equalTo: blurView.contentView.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: blurView.contentView.centerYAnchor)
        ])

        let viewController = UIViewController()
        viewController.view.addSubview(blurView)
        window.rootViewController = viewController
        window.isHidden = false

        privacyWindow = window
    }

    private func removePrivacyWindow() {
        privacyWindow?.isHidden = true
        privacyWindow = nil
    }

    @objc private func showPrivacyOverlay() {
        // Handled by sceneWillResignActive
    }

    @objc private func hidePrivacyOverlay() {
        removePrivacyWindow()
    }
}

// MARK: - Custom Notification Names

extension Notification.Name {

    // MARK: App Lifecycle

    /// Posted when the app enters the background.
    static let appDidEnterBackground = Notification.Name("com.bitcoinai.wallet.appDidEnterBackground")

    /// Posted when the app returns to the foreground.
    static let appDidEnterForeground = Notification.Name("com.bitcoinai.wallet.appDidEnterForeground")

    /// Posted when the app becomes active.
    static let appDidBecomeActive = Notification.Name("com.bitcoinai.wallet.appDidBecomeActive")

    /// Posted when the app is about to resign active state.
    static let appWillResignActive = Notification.Name("com.bitcoinai.wallet.appWillResignActive")

    /// Posted when the app should lock due to background timeout.
    static let appShouldLock = Notification.Name("com.bitcoinai.wallet.appShouldLock")

    // MARK: System Events

    /// Posted when a significant time change occurs (e.g., midnight rollover).
    static let significantTimeDidChange = Notification.Name("com.bitcoinai.wallet.significantTimeDidChange")

    /// Posted when the app receives a memory warning.
    static let appDidReceiveMemoryWarning = Notification.Name("com.bitcoinai.wallet.appDidReceiveMemoryWarning")

    // MARK: Wallet Events

    /// Posted when the wallet state changes (balance update, new transaction).
    static let walletStateDidChange = Notification.Name("com.bitcoinai.wallet.walletStateDidChange")

    /// Posted when network connectivity changes.
    static let networkStatusDidChange = Notification.Name("com.bitcoinai.wallet.networkStatusDidChange")
}
