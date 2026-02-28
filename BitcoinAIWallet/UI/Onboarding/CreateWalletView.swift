import SwiftUI

// MARK: - CreateWalletView
// Displays an animated loading/generating state while creating a new wallet.
// Uses the Mnemonic struct to generate a BIP39 12-word recovery phrase,
// then passes the words to the next step in the onboarding flow.
//
// Platform: iOS 17.0+
// Dependencies: SwiftUI, Mnemonic (Core/Wallet/Mnemonic.swift)

struct CreateWalletView: View {

    // MARK: - Callbacks

    let onComplete: ([String]) -> Void

    // MARK: - State

    @State private var progress: Double = 0.0
    @State private var iconRotation: Double = 0.0
    @State private var iconScale: CGFloat = 0.8
    @State private var iconOpacity: Double = 0.0
    @State private var textOpacity: Double = 0.0
    @State private var isGenerating: Bool = true
    @State private var generationError: String?

    // MARK: - Body

    var body: some View {
        VStack(spacing: AppSpacing.xxxl) {
            Spacer()

            // MARK: Animated Bitcoin Icon

            animatedIcon

            // MARK: Generating Text

            VStack(spacing: AppSpacing.md) {
                Text(L10n.Onboarding.generatingWallet)
                    .font(AppTypography.headingLarge)
                    .foregroundColor(AppColors.textPrimary)

                Text(L10n.Onboarding.securingWallet)
                    .font(AppTypography.bodyMedium)
                    .foregroundColor(AppColors.textSecondary)
            }
            .opacity(textOpacity)

            // MARK: Progress Indicator

            progressBar
                .opacity(textOpacity)

            // MARK: Error Display

            if let error = generationError {
                VStack(spacing: AppSpacing.md) {
                    Text(error)
                        .font(AppTypography.bodySmall)
                        .foregroundColor(AppColors.error)
                        .multilineTextAlignment(.center)

                    Button(action: generateWallet) {
                        Text(L10n.Common.retry)
                            .font(AppTypography.buttonMedium)
                            .foregroundColor(AppColors.accent)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, AppSpacing.xl)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColors.backgroundPrimary.ignoresSafeArea())
        .onAppear {
            runEntryAnimation()
            generateWallet()
        }
    }

    // MARK: - Animated Icon

    private var animatedIcon: some View {
        ZStack {
            // Pulsing glow
            Circle()
                .fill(AppColors.accentGlow)
                .frame(width: 140, height: 140)
                .blur(radius: 25)
                .scaleEffect(isGenerating ? 1.2 : 1.0)
                .animation(
                    .easeInOut(duration: 1.5).repeatForever(autoreverses: true),
                    value: isGenerating
                )

            Circle()
                .fill(AppColors.accentDim)
                .frame(width: 100, height: 100)

            Image(systemName: AppIcons.bitcoin)
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(AppColors.accentGradient)
                .rotationEffect(.degrees(iconRotation))
        }
        .scaleEffect(iconScale)
        .opacity(iconOpacity)
    }

    // MARK: - Progress Bar

    private var progressBar: some View {
        VStack(spacing: AppSpacing.sm) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Track
                    RoundedRectangle(cornerRadius: AppCornerRadius.small, style: .continuous)
                        .fill(AppColors.backgroundTertiary)
                        .frame(height: AppSpacing.xs)

                    // Fill
                    RoundedRectangle(cornerRadius: AppCornerRadius.small, style: .continuous)
                        .fill(AppColors.accentGradient)
                        .frame(
                            width: geometry.size.width * progress,
                            height: AppSpacing.xs
                        )
                }
            }
            .frame(height: AppSpacing.xs)
        }
        .padding(.horizontal, AppSpacing.massive)
    }

    // MARK: - Entry Animation

    private func runEntryAnimation() {
        withAnimation(.spring(response: 0.6, dampingFraction: 0.7).delay(0.1)) {
            iconScale = 1.0
            iconOpacity = 1.0
        }
        withAnimation(.easeOut(duration: 0.4).delay(0.3)) {
            textOpacity = 1.0
        }
        // Continuous rotation during generation
        withAnimation(.linear(duration: 4.0).repeatForever(autoreverses: false)) {
            iconRotation = 360.0
        }
    }

    // MARK: - Wallet Generation

    private func generateWallet() {
        generationError = nil
        isGenerating = true
        progress = 0.0

        // Animate progress bar in stages to give visual feedback
        // while the actual generation happens quickly
        animateProgress(to: 0.3, duration: 0.4) {
            animateProgress(to: 0.6, duration: 0.3) {
                // Actually generate the mnemonic
                do {
                    let mnemonic = try Mnemonic.generate(strength: .twelve)
                    let words = mnemonic.words

                    animateProgress(to: 0.9, duration: 0.2) {
                        animateProgress(to: 1.0, duration: 0.15) {
                            // Brief pause to show completion
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                isGenerating = false
                                onComplete(words)
                            }
                        }
                    }
                } catch {
                    isGenerating = false
                    generationError = L10n.Error.unknown
                }
            }
        }
    }

    /// Animates the progress bar to a target value over a duration.
    private func animateProgress(
        to target: Double,
        duration: TimeInterval,
        completion: @escaping () -> Void
    ) {
        withAnimation(.easeInOut(duration: duration)) {
            progress = target
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            completion()
        }
    }
}

// MARK: - Preview

#if DEBUG
struct CreateWalletView_Previews: PreviewProvider {
    static var previews: some View {
        CreateWalletView(onComplete: { _ in })
    }
}
#endif
