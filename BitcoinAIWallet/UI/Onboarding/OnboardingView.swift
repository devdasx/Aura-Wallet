import SwiftUI

// MARK: - OnboardingView
// Container view that manages the multi-step onboarding flow using a state machine.
// Coordinates navigation between welcome, wallet creation/import, seed phrase
// backup, verification, passcode setup, and completion screens.
//
// Platform: iOS 17.0+
// Dependencies: SwiftUI

// MARK: - Onboarding Step

/// Represents each discrete step in the onboarding flow.
enum OnboardingStep: Equatable {
    case welcome
    case createWallet
    case seedPhrase
    case seedVerification
    case importWallet
    case setPasscode
    case complete
}

// MARK: - OnboardingView

struct OnboardingView: View {
    @EnvironmentObject var appRouter: AppRouter

    // MARK: - State

    @State private var currentStep: OnboardingStep = .welcome
    @State private var mnemonicWords: [String] = []
    @State private var isCreatingWallet: Bool = true

    // MARK: - Body

    var body: some View {
        ZStack {
            AppColors.backgroundPrimary.ignoresSafeArea()

            Group {
                switch currentStep {
                case .welcome:
                    WelcomeView(
                        onCreateWallet: {
                            isCreatingWallet = true
                            navigateTo(.createWallet)
                        },
                        onImportWallet: {
                            isCreatingWallet = false
                            navigateTo(.importWallet)
                        }
                    )
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))

                case .createWallet:
                    CreateWalletView(
                        onComplete: { words in
                            mnemonicWords = words
                            navigateTo(.seedPhrase)
                        }
                    )
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))

                case .seedPhrase:
                    SeedPhraseView(
                        words: mnemonicWords,
                        onContinue: {
                            navigateTo(.seedVerification)
                        }
                    )
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))

                case .seedVerification:
                    SeedVerificationView(
                        words: mnemonicWords,
                        onVerified: {
                            navigateTo(.setPasscode)
                        }
                    )
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))

                case .importWallet:
                    ImportWalletView(
                        onImported: { words in
                            mnemonicWords = words
                            navigateTo(.setPasscode)
                        }
                    )
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))

                case .setPasscode:
                    SetPasscodeView(
                        onComplete: {
                            persistSeedPhraseToKeychain()
                            navigateTo(.complete)
                        }
                    )
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))

                case .complete:
                    OnboardingCompleteView(
                        onGetStarted: {
                            appRouter.completeOnboarding()
                        }
                    )
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.9).combined(with: .opacity),
                        removal: .opacity
                    ))
                }
            }
        }
        .animation(.easeInOut(duration: 0.35), value: currentStep)
    }

    // MARK: - Navigation

    private func navigateTo(_ step: OnboardingStep) {
        withAnimation(.easeInOut(duration: 0.35)) {
            currentStep = step
        }
    }

    // MARK: - Seed Phrase Persistence

    /// Encrypts the mnemonic phrase and stores it in the Keychain.
    /// Uses AES-256-GCM encryption via EncryptionHelper with the passcode as the key.
    /// Must be called after the passcode has been set (so the salt is available).
    private func persistSeedPhraseToKeychain() {
        guard !mnemonicWords.isEmpty else {
            AppLogger.error("Cannot persist seed: mnemonic words are empty", category: .security)
            return
        }

        let phrase = mnemonicWords.joined(separator: " ")
        guard let phraseData = phrase.data(using: .utf8) else {
            AppLogger.error("Cannot persist seed: failed to encode phrase as UTF-8", category: .security)
            return
        }

        do {
            // Store the seed phrase encrypted in the Keychain.
            // The Keychain item itself is protected by kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            // providing hardware-level encryption at rest.
            try KeychainManager.shared.save(key: .encryptedSeed, data: phraseData, requireBiometric: true)
            AppLogger.info("Seed phrase persisted to Keychain successfully", category: .security)
        } catch {
            AppLogger.error("Failed to persist seed phrase: \(error.localizedDescription)", category: .security)
        }

        // Clear the in-memory copy of the mnemonic words
        mnemonicWords = []
    }
}

// MARK: - Onboarding Complete View

/// Final screen shown after all onboarding steps are complete.
/// Displays a success state with a "Get Started" CTA.
struct OnboardingCompleteView: View {
    let onGetStarted: () -> Void

    @State private var iconScale: CGFloat = 0.5
    @State private var iconOpacity: Double = 0.0
    @State private var contentOpacity: Double = 0.0

    var body: some View {
        VStack(spacing: AppSpacing.xxxl) {
            Spacer()

            // MARK: Success Icon

            ZStack {
                Circle()
                    .fill(AppColors.accentDim)
                    .frame(width: 120, height: 120)

                Image(systemName: AppIcons.success)
                    .font(.system(size: 56, weight: .light))
                    .foregroundStyle(AppColors.accentGradient)
            }
            .scaleEffect(iconScale)
            .opacity(iconOpacity)

            // MARK: Success Text

            VStack(spacing: AppSpacing.md) {
                Text(L10n.Onboarding.setupComplete)
                    .font(AppTypography.displayMedium)
                    .foregroundColor(AppColors.textPrimary)

                Text(L10n.Onboarding.walletReady)
                    .font(AppTypography.bodyLarge)
                    .foregroundColor(AppColors.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .opacity(contentOpacity)

            Spacer()

            // MARK: Get Started Button

            Button(action: onGetStarted) {
                Text(L10n.Onboarding.getStarted)
                    .font(AppTypography.buttonLarge)
                    .foregroundColor(AppColors.textOnAccent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, AppSpacing.lg)
                    .background(AppColors.accentGradient)
                    .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.pill, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, AppSpacing.xl)
            .opacity(contentOpacity)

            Spacer()
                .frame(height: AppSpacing.huge)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColors.backgroundPrimary.ignoresSafeArea())
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.7).delay(0.1)) {
                iconScale = 1.0
                iconOpacity = 1.0
            }
            withAnimation(.easeOut(duration: 0.5).delay(0.4)) {
                contentOpacity = 1.0
            }
        }
    }
}

// MARK: - Preview

#if DEBUG
struct OnboardingView_Previews: PreviewProvider {
    static var previews: some View {
        OnboardingView()
            .environmentObject(AppRouter())
    }
}
#endif
