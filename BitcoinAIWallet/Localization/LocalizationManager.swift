import Foundation
import SwiftUI

// MARK: - Localization Manager
// Manages app-wide language settings, RTL detection, and locale configuration.
// Provides a custom bundle that loads the correct .lproj for the selected language,
// enabling in-app language switching independent of the device's system language.

final class LocalizationManager: ObservableObject {
    static let shared = LocalizationManager()

    @AppStorage("app_language") var currentLanguage: String = "en" {
        didSet {
            _cachedBundle = nil
            objectWillChange.send()
        }
    }

    var isRTL: Bool { currentLanguage == "ar" }
    var locale: Locale { Locale(identifier: currentLanguage) }

    static let supportedLanguages: [(code: String, name: String)] = [
        ("en", "English"),
        ("ar", "العربية"),
        ("es", "Español")
    ]

    // MARK: - Bundle

    /// Cache to avoid repeated bundle lookups.
    private var _cachedBundle: Bundle?

    /// Returns a Bundle pointing to the .lproj directory for the current language.
    /// Falls back to the main bundle if the .lproj is not found.
    var bundle: Bundle {
        if let cached = _cachedBundle { return cached }

        let resolved: Bundle
        if let path = Bundle.main.path(forResource: currentLanguage, ofType: "lproj"),
           let lprojBundle = Bundle(path: path) {
            resolved = lprojBundle
        } else {
            resolved = .main
        }
        _cachedBundle = resolved
        return resolved
    }
}

// MARK: - Localization Helper

/// Looks up a localized string using the current language bundle from LocalizationManager.
/// This enables in-app language switching without restarting the app.
func localizedString(_ key: String, comment: String = "") -> String {
    NSLocalizedString(key, bundle: LocalizationManager.shared.bundle, comment: comment)
}

/// Looks up a localized format string and applies arguments.
func localizedFormat(_ key: String, _ arguments: CVarArg..., comment: String = "") -> String {
    let format = NSLocalizedString(key, bundle: LocalizationManager.shared.bundle, comment: comment)
    return String(format: format, arguments: arguments)
}
