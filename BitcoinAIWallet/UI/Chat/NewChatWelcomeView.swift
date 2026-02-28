import SwiftUI

// MARK: - NewChatWelcomeView
// Centered greeting screen shown for new empty conversations.
// Displays a time-aware greeting, app logo, and fades into the
// chat view when the user sends their first message.

struct NewChatWelcomeView: View {
    let btcBalance: Decimal
    let fiatBalance: Decimal
    let currencyCode: String

    @State private var logoScale: CGFloat = 0.8
    @State private var logoOpacity: Double = 0.0
    @State private var textOpacity: Double = 0.0

    var body: some View {
        VStack(spacing: AppSpacing.xxxl) {
            Spacer()

            // Balance pill
            if btcBalance > 0 {
                balancePill
            }

            // App logo
            Image(systemName: "bitcoinsign.circle.fill")
                .font(.system(size: 56, weight: .thin))
                .foregroundStyle(AppColors.accentGradient)
                .scaleEffect(logoScale)
                .opacity(logoOpacity)

            // Time-aware greeting
            VStack(spacing: AppSpacing.sm) {
                Text(timeGreeting)
                    .font(AppTypography.headingLarge)
                    .foregroundColor(AppColors.textPrimary)
                    .multilineTextAlignment(.center)

                Text(L10n.Welcome.subtitle)
                    .font(AppTypography.bodyMedium)
                    .foregroundColor(AppColors.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .opacity(textOpacity)

            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColors.backgroundPrimary)
        .onAppear {
            withAnimation(.easeOut(duration: 0.5)) {
                logoScale = 1.0
                logoOpacity = 1.0
            }
            withAnimation(.easeOut(duration: 0.5).delay(0.15)) {
                textOpacity = 1.0
            }
        }
    }

    // MARK: - Balance Pill

    private var balancePill: some View {
        VStack(spacing: AppSpacing.xxxs) {
            Text(formatBTC(btcBalance))
                .font(AppTypography.headingMedium)
                .foregroundColor(AppColors.textPrimary)

            Text("\u{2248} " + formatFiat(fiatBalance))
                .font(AppTypography.bodySmall)
                .foregroundColor(AppColors.textSecondary)
        }
        .padding(.horizontal, AppSpacing.xl)
        .padding(.vertical, AppSpacing.md)
        .background(AppColors.backgroundCard)
        .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.large, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppCornerRadius.large, style: .continuous)
                .stroke(AppColors.border, lineWidth: 1)
        )
    }

    // MARK: - Time Greeting

    private var timeGreeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12:
            return L10n.Welcome.morning
        case 12..<17:
            return L10n.Welcome.afternoon
        case 17..<21:
            return L10n.Welcome.evening
        default:
            return L10n.Welcome.night
        }
    }

    // MARK: - Formatting

    private func formatBTC(_ amount: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 8
        formatter.maximumFractionDigits = 8
        let formatted = formatter.string(from: amount as NSDecimalNumber) ?? "0.00000000"
        return L10n.Format.btcAmount(formatted)
    }

    private func formatFiat(_ amount: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currencyCode
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 2
        return formatter.string(from: amount as NSDecimalNumber) ?? "\(currencyCode) 0.00"
    }
}

// MARK: - Preview

#if DEBUG
struct NewChatWelcomeView_Previews: PreviewProvider {
    static var previews: some View {
        NewChatWelcomeView(
            btcBalance: Decimal(string: "0.00466")!,
            fiatBalance: Decimal(string: "311.15")!,
            currencyCode: "USD"
        )
        .preferredColorScheme(.dark)
    }
}
#endif
