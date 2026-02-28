import SwiftUI

// MARK: - WelcomeView
// First screen of the onboarding flow. Displays app branding,
// a brief description, and two CTAs: create a new wallet or import an existing one.
//
// Platform: iOS 17.0+
// Dependencies: SwiftUI

struct WelcomeView: View {

    // MARK: - Callbacks

    let onCreateWallet: () -> Void
    let onImportWallet: () -> Void

    // MARK: - Animation State

    @State private var iconScale: CGFloat = 0.6
    @State private var iconOpacity: Double = 0.0
    @State private var textOpacity: Double = 0.0
    @State private var buttonsOpacity: Double = 0.0
    @State private var iconRotation: Double = -30.0

    // MARK: - Body

    var body: some View {
        VStack(spacing: .zero) {

            Spacer()

            // MARK: - Branding Section

            brandingSection

            Spacer()

            // MARK: - CTA Buttons

            ctaButtons

            Spacer()
                .frame(height: AppSpacing.huge)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColors.backgroundPrimary.ignoresSafeArea())
        .onAppear(perform: runEntryAnimation)
    }

    // MARK: - Branding Section

    private var brandingSection: some View {
        VStack(spacing: AppSpacing.xxl) {
            // Bitcoin Icon
            ZStack {
                // Glow background
                Circle()
                    .fill(AppColors.accentGlow)
                    .frame(width: 140, height: 140)
                    .blur(radius: 20)

                Circle()
                    .fill(AppColors.accentDim)
                    .frame(width: 110, height: 110)

                Image(systemName: AppIcons.bitcoin)
                    .font(.system(size: 64, weight: .light))
                    .foregroundStyle(AppColors.accentGradient)
            }
            .scaleEffect(iconScale)
            .opacity(iconOpacity)
            .rotationEffect(.degrees(iconRotation))

            // App Name and Subtitle
            VStack(spacing: AppSpacing.md) {
                Text(L10n.Common.appName)
                    .font(AppTypography.displayLarge)
                    .foregroundColor(AppColors.textPrimary)
                    .multilineTextAlignment(.center)

                Text(L10n.Onboarding.welcomeSubtitle)
                    .font(AppTypography.bodyLarge)
                    .foregroundColor(AppColors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, AppSpacing.xxxl)
            }
            .opacity(textOpacity)
        }
    }

    // MARK: - CTA Buttons

    private var ctaButtons: some View {
        VStack(spacing: AppSpacing.md) {

            // MARK: Create New Wallet Button

            Button(action: onCreateWallet) {
                HStack(spacing: AppSpacing.sm) {
                    Image(systemName: AppIcons.plus)
                        .font(AppTypography.buttonLarge)

                    Text(L10n.Onboarding.createWallet)
                        .font(AppTypography.buttonLarge)
                }
                .foregroundColor(AppColors.textOnAccent)
                .frame(maxWidth: .infinity)
                .padding(.vertical, AppSpacing.lg)
                .background(AppColors.accentGradient)
                .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.pill, style: .continuous))
            }
            .buttonStyle(.plain)

            // MARK: Import Existing Wallet Button

            Button(action: onImportWallet) {
                HStack(spacing: AppSpacing.sm) {
                    Image(systemName: AppIcons.key)
                        .font(AppTypography.buttonLarge)

                    Text(L10n.Onboarding.importWallet)
                        .font(AppTypography.buttonLarge)
                }
                .foregroundColor(AppColors.accent)
                .frame(maxWidth: .infinity)
                .padding(.vertical, AppSpacing.lg)
                .background(AppColors.backgroundPrimary)
                .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.pill, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: AppCornerRadius.pill, style: .continuous)
                        .stroke(AppColors.accent, lineWidth: 1.5)
                )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, AppSpacing.xl)
        .opacity(buttonsOpacity)
    }

    // MARK: - Entry Animation

    private func runEntryAnimation() {
        withAnimation(.spring(response: 0.7, dampingFraction: 0.65).delay(0.1)) {
            iconScale = 1.0
            iconOpacity = 1.0
            iconRotation = 0.0
        }
        withAnimation(.easeOut(duration: 0.5).delay(0.3)) {
            textOpacity = 1.0
        }
        withAnimation(.easeOut(duration: 0.5).delay(0.5)) {
            buttonsOpacity = 1.0
        }
    }
}

// MARK: - Preview

#if DEBUG
struct WelcomeView_Previews: PreviewProvider {
    static var previews: some View {
        WelcomeView(
            onCreateWallet: {},
            onImportWallet: {}
        )
    }
}
#endif
