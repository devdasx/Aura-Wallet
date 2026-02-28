import SwiftUI

// MARK: - AppShadows
// Single source of truth for ALL shadow definitions.

struct AppShadows {
    struct ShadowStyle {
        let color: Color
        let radius: CGFloat
        let x: CGFloat
        let y: CGFloat
    }

    static let small = ShadowStyle(color: Color.black.opacity(0.06), radius: 4, x: 0, y: 2)
    static let medium = ShadowStyle(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 4)
    static let large = ShadowStyle(color: Color.black.opacity(0.12), radius: 16, x: 0, y: 8)
    static let card = ShadowStyle(color: Color.black.opacity(0.05), radius: 6, x: 0, y: 3)
    static let glow = ShadowStyle(color: AppColors.accent.opacity(0.3), radius: 12, x: 0, y: 0)
    static let none = ShadowStyle(color: .clear, radius: 0, x: 0, y: 0)
}

// MARK: - View Extension for Shadows
extension View {
    func appShadow(_ style: AppShadows.ShadowStyle) -> some View {
        self.shadow(color: style.color, radius: style.radius, x: style.x, y: style.y)
    }
}
