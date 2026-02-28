import SwiftUI

// MARK: - AppSpacing
// Single source of truth for ALL spacing values.
// NEVER use magic numbers for padding/spacing — always use AppSpacing.

struct AppSpacing {
    static let xxxs: CGFloat = 2
    static let xxs: CGFloat = 4
    static let xs: CGFloat = 6
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 20
    static let xxl: CGFloat = 24
    static let xxxl: CGFloat = 32
    static let huge: CGFloat = 40
    static let massive: CGFloat = 56
}
