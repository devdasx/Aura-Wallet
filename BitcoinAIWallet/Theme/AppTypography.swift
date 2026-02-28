import SwiftUI

// MARK: - FontPreference
// User-selectable chat font options matching Claude's Settings > Appearance.
// Stored via @AppStorage("chat_font") in UserPreferences.

enum FontPreference: String, CaseIterable, Identifiable {
    case `default` = "default"     // Georgia (serif) — Claude's default
    case system = "system"         // SF Pro (system)
    case monospace = "monospace"   // SF Mono / Menlo
    case dyslexic = "dyslexic"    // OpenDyslexic (bundled)

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .default:   return localizedString("settings.chat_font.default")
        case .system:    return localizedString("settings.chat_font.system")
        case .monospace: return localizedString("settings.chat_font.monospace")
        case .dyslexic:  return localizedString("settings.chat_font.dyslexic")
        }
    }

    /// Font for the preview line in Settings.
    var previewFont: Font {
        switch self {
        case .default:   return .custom("Georgia", size: 14)
        case .system:    return .system(size: 14)
        case .monospace: return .system(size: 13, design: .monospaced)
        case .dyslexic:  return .custom("OpenDyslexic3", size: 14)
        }
    }
}

// MARK: - AppTypography
// Single source of truth for ALL text styles in the app.
//
// Chat fonts: Depend on user's font preference (Georgia, SF Pro, Mono, OpenDyslexic).
//             Used in chat messages, input bar, and formatted message content.
//
// UI chrome fonts: Always SF Pro (system). Used in nav bars, settings, labels,
//                  buttons, cards, sidebar — everything outside chat messages.
//
// Design mapping:
//   chatBody / chatBodySmall → preference-aware, for message text
//   body / heading / label   → SF Pro, for UI chrome
//   mono                     → SF Mono, for addresses and TXIDs (always)

struct AppTypography {

    // MARK: - Font Preference Resolution

    /// The current font preference, read from UserDefaults.
    static var fontPreference: FontPreference {
        FontPreference(rawValue: UserDefaults.standard.string(forKey: "chat_font") ?? "default") ?? .default
    }

    // MARK: - Chat Fonts (preference-aware)

    /// Main chat message body text — 16pt, changes with font preference.
    static var chatBody: Font {
        chatFont(size: 16)
    }

    /// Smaller chat text — 14pt, changes with font preference.
    static var chatBodySmall: Font {
        chatFont(size: 14)
    }

    /// Resolves a chat font at the given size based on the current preference.
    private static func chatFont(size: CGFloat) -> Font {
        switch fontPreference {
        case .default:   return .custom("Georgia", size: size)
        case .system:    return .system(size: size)
        case .monospace: return .system(size: size - 1, design: .monospaced)
        case .dyslexic:  return .custom("OpenDyslexic3", size: size)
        }
    }

    // MARK: - Display — Large balance numbers (UI chrome)

    static let displayLarge = Font.system(size: 32, weight: .bold, design: .default)
    static let displayMedium = Font.system(size: 24, weight: .bold, design: .default)

    // MARK: - Headings (UI chrome)

    static let headingLarge = Font.system(size: 20, weight: .semibold, design: .default)
    static let headingMedium = Font.system(size: 16, weight: .semibold, design: .default)
    static let headingSmall = Font.system(size: 14, weight: .semibold, design: .default)

    // MARK: - Body (UI chrome — settings, sidebar, cards)

    static let bodyLarge = Font.system(size: 16, weight: .regular, design: .default)
    static let bodyMedium = Font.system(size: 14.5, weight: .regular, design: .default)
    static let bodySmall = Font.system(size: 13, weight: .regular, design: .default)

    // MARK: - Labels (UI chrome)

    static let labelLarge = Font.system(size: 13, weight: .medium, design: .default)
    static let labelMedium = Font.system(size: 12, weight: .medium, design: .default)
    static let labelSmall = Font.system(size: 11, weight: .medium, design: .default)

    // MARK: - Monospace — Addresses, TXIDs, technical data (always mono)

    static let monoLarge = Font.system(size: 13, weight: .medium, design: .monospaced)
    static let monoMedium = Font.system(size: 12, weight: .regular, design: .monospaced)
    static let monoSmall = Font.system(size: 11, weight: .regular, design: .monospaced)

    // MARK: - Button text (UI chrome)

    static let buttonLarge = Font.system(size: 15, weight: .semibold, design: .default)
    static let buttonMedium = Font.system(size: 13, weight: .semibold, design: .default)
    static let buttonSmall = Font.system(size: 12, weight: .medium, design: .default)

    // MARK: - Currency display (UI chrome)

    static let currencySymbol = Font.system(size: 14, weight: .medium, design: .default)
    static let fiatAmount = Font.system(size: 14, weight: .regular, design: .default)
}
