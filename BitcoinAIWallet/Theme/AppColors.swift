import SwiftUI

// MARK: - AppColors
// Single source of truth for all colors in the Bitcoin AI Wallet app.
// Uses a warm, Claude-inspired palette with automatic light/dark mode switching.
//
// Light mode: Warm cream/beige tones (#F5F0E8 base) — NOT pure white
// Dark mode: Warm dark tones (#1A1714 base) — NOT pure black
// Accent: Terra cotta #DA7756 — consistent across modes

struct AppColors {

    // MARK: - Private Helpers

    /// Creates an adaptive Color that resolves to different hex values in light vs dark mode.
    private static func adaptive(light: String, dark: String) -> Color {
        Color(UIColor { traits in
            hexUIColor(traits.userInterfaceStyle == .dark ? dark : light)
        })
    }

    /// Creates an adaptive Color with separate alpha values per mode.
    private static func adaptiveAlpha(light: String, lightAlpha: CGFloat = 1, dark: String, darkAlpha: CGFloat = 1) -> Color {
        Color(UIColor { traits in
            let isDark = traits.userInterfaceStyle == .dark
            return hexUIColor(isDark ? dark : light, alpha: isDark ? darkAlpha : lightAlpha)
        })
    }

    /// Parses a hex string into a UIColor.
    private static func hexUIColor(_ hex: String, alpha: CGFloat = 1) -> UIColor {
        let h = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: h).scanHexInt64(&int)
        return UIColor(
            red: CGFloat((int >> 16) & 0xFF) / 255,
            green: CGFloat((int >> 8) & 0xFF) / 255,
            blue: CGFloat(int & 0xFF) / 255,
            alpha: alpha
        )
    }

    // MARK: - Brand / Accent

    /// Core brand color — terra cotta
    static let brand = Color(hex: "#DA7756")

    /// Primary accent — terra cotta (same in both modes)
    static let accent = Color(hex: "#DA7756")

    /// Darker accent for pressed / gradient states
    static let accentDark = adaptive(light: "#C4684A", dark: "#E8896A")

    // MARK: - Backgrounds

    /// Main screen background — warm cream (light) / warm dark (dark)
    static let backgroundPrimary = adaptive(light: "#F5F0E8", dark: "#1A1714")

    /// Secondary surface — sidebar, grouped sections
    static let backgroundSecondary = adaptive(light: "#EFEAD8", dark: "#242019")

    /// Tertiary surface — input fields, chips
    static let backgroundTertiary = adaptive(light: "#E5DFD0", dark: "#2A261E")

    /// AI chat bubble background — transparent (no bubble, text on background)
    static let backgroundAIBubble = Color.clear

    /// User chat bubble background — warm tinted
    static let backgroundUserBubble = adaptive(light: "#EBE5D5", dark: "#332E25")

    /// Card surface — white (light) / warm dark (dark)
    static let backgroundCard = adaptive(light: "#FFFFFF", dark: "#2A261E")

    /// Card hover / pressed state
    static let backgroundCardHover = adaptive(light: "#F8F3EB", dark: "#332E25")

    /// Input field background — warm tint, NOT pure white
    static let backgroundInput = adaptive(light: "#F0ECDF", dark: "#2A261E")

    // MARK: - Text

    /// Primary text — warm near-black / warm off-white
    static let textPrimary = adaptive(light: "#1A1613", dark: "#F0EBE0")

    /// Secondary text — timestamps, subtitles
    static let textSecondary = adaptive(light: "#6B6560", dark: "#9C968D")

    /// Tertiary text — placeholders, dimmed info
    static let textTertiary = adaptive(light: "#A39E96", dark: "#6B665E")

    /// Text on accent-colored surfaces
    static let textOnAccent = Color.white

    /// Text on user chat bubble
    static let textOnUserBubble = adaptive(light: "#1A1613", dark: "#F0EBE0")

    // MARK: - Borders & Separators

    /// Default border — subtle warm
    static let border = adaptive(light: "#E0D9CC", dark: "#3A352C")

    /// Stronger / accent border
    static let borderAccent = adaptive(light: "#D0C9BC", dark: "#4A443A")

    /// List / section separator
    static let separator = adaptive(light: "#E5DFD0", dark: "#332E25")

    // MARK: - Semantic

    /// Success — confirmed, positive
    static let success = adaptive(light: "#3D8C5C", dark: "#4DA670")

    /// Success dimmed background
    static let successDim = adaptiveAlpha(light: "#EDFAF2", dark: "#4DA670", darkAlpha: 0.12)

    /// Error — failed, warnings
    static let error = adaptive(light: "#D14343", dark: "#E05555")

    /// Error dimmed background
    static let errorDim = adaptiveAlpha(light: "#FDF2F2", dark: "#E05555", darkAlpha: 0.12)

    /// Warning — pending, caution
    static let warning = adaptive(light: "#D4930D", dark: "#E0A520")

    /// Warning dimmed background
    static let warningDim = adaptiveAlpha(light: "#FEFBE8", dark: "#E0A520", darkAlpha: 0.12)

    /// Info — informational
    static let info = adaptive(light: "#2563EB", dark: "#3B82F6")

    /// Info dimmed background
    static let infoDim = adaptiveAlpha(light: "#EFF6FF", dark: "#3B82F6", darkAlpha: 0.12)

    // MARK: - Accent Variants

    /// Accent dimmed background
    static let accentDim = adaptiveAlpha(light: "#F5EDE8", dark: "#DA7756", darkAlpha: 0.12)

    /// Subtle accent glow
    static let accentGlow = adaptiveAlpha(light: "#DA7756", lightAlpha: 0.15, dark: "#DA7756", darkAlpha: 0.20)

    // MARK: - Transaction Specific

    /// Sent transaction
    static let txSent = adaptive(light: "#D14343", dark: "#E05555")

    /// Received transaction
    static let txReceived = adaptive(light: "#3D8C5C", dark: "#4DA670")

    /// Pending transaction
    static let txPending = adaptive(light: "#D4930D", dark: "#E0A520")

    // MARK: - Sidebar

    /// Sidebar background (same as main in Claude)
    static let sidebarBackground = adaptive(light: "#F5F0E8", dark: "#1A1714")

    /// Selected conversation row
    static let sidebarActiveRow = adaptive(light: "#EBE5D5", dark: "#2A261E")

    // MARK: - Gradients

    /// Primary accent gradient
    static let accentGradient = LinearGradient(
        colors: [Color(hex: "#DA7756"), Color(hex: "#C4684A")],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// Balance text gradient (generic)
    static let balanceGradient = LinearGradient(
        colors: [Color(hex: "#F0EBE0"), Color(hex: "#9C968D")],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// Balance gradient for dark mode — warm off-white to warm gray
    static let darkBalanceGradient = LinearGradient(
        colors: [Color(hex: "#F0EBE0"), Color(hex: "#9C968D")],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// Balance gradient for light mode — warm dark to warm medium
    static let lightBalanceGradient = LinearGradient(
        colors: [Color(hex: "#1A1613"), Color(hex: "#6B6560")],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

// MARK: - Color Hex Extension

extension Color {

    /// Creates a `Color` from a hex string.
    ///
    /// Supported formats: `"#RGB"`, `"#RRGGBB"`, `"#RRGGBBAA"`,
    /// and the same without the leading `#`.
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)

        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255,
                            (int >> 8) * 17,
                            (int >> 4 & 0xF) * 17,
                            (int & 0xF) * 17)
        case 6: // RRGGBB (24-bit)
            (a, r, g, b) = (255,
                            int >> 16,
                            int >> 8 & 0xFF,
                            int & 0xFF)
        case 8: // RRGGBBAA (32-bit)
            (a, r, g, b) = (int & 0xFF,
                            int >> 24,
                            int >> 16 & 0xFF,
                            int >> 8 & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
