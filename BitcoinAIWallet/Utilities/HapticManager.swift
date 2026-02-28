import UIKit

// MARK: - HapticManager
// Centralized haptic feedback utility for the Bitcoin AI Wallet.
// Provides a simple API for triggering impact, notification, and
// selection haptics throughout the app. Each method lazily creates
// a feedback generator, fires the haptic, and lets the system
// deallocate the generator automatically.
//
// Usage:
//   HapticManager.success()    // transaction broadcast succeeded
//   HapticManager.buttonTap()  // user tapped a button
//   HapticManager.error()      // validation failure

enum HapticManager {

    // MARK: - Impact Feedback

    /// Trigger an impact haptic with the specified style.
    ///
    /// - Parameter style: The intensity of the impact (.light, .medium, .heavy, .soft, .rigid).
    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .medium) {
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.prepare()
        generator.impactOccurred()
    }

    // MARK: - Notification Feedback

    /// Trigger a notification haptic with the specified type.
    ///
    /// - Parameter type: The semantic meaning of the notification (.success, .warning, .error).
    static func notification(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(type)
    }

    // MARK: - Selection Feedback

    /// Trigger a light selection-change haptic.
    /// Ideal for picker changes, toggles, and segmented controls.
    static func selection() {
        let generator = UISelectionFeedbackGenerator()
        generator.prepare()
        generator.selectionChanged()
    }

    // MARK: - Convenience Methods

    /// Success haptic -- use after a transaction broadcast, copy confirmation, etc.
    static func success() {
        notification(.success)
    }

    /// Error haptic -- use on validation failures, broadcast errors, etc.
    static func error() {
        notification(.error)
    }

    /// Warning haptic -- use for destructive action confirmations, low balance, etc.
    static func warning() {
        notification(.warning)
    }

    /// Light tap -- use for small interactive elements.
    static func lightTap() {
        impact(.light)
    }

    /// Medium tap -- general purpose feedback for most interactions.
    static func mediumTap() {
        impact(.medium)
    }

    /// Heavy tap -- use for significant state changes (e.g. send confirmation).
    static func heavyTap() {
        impact(.heavy)
    }

    /// Button tap -- light impact suitable for standard button presses.
    static func buttonTap() {
        impact(.light)
    }

    /// Card tap -- selection feedback for tapping cards or list rows.
    static func cardTap() {
        selection()
    }
}
