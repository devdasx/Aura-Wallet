import SwiftUI

// MARK: - SeedPhraseView
// Displays the 12-word BIP39 recovery phrase for the user to write down.
// Includes a security warning, a numbered 3x4 grid of words, and screenshot
// prevention that blurs the view when the app enters the background.
//
// Platform: iOS 17.0+
// Dependencies: SwiftUI

struct SeedPhraseView: View {

    // MARK: - Properties

    let words: [String]
    let onContinue: () -> Void

    // MARK: - State

    @Environment(\.scenePhase) private var scenePhase
    @State private var isBlurred: Bool = false
    @State private var isScreenRecording: Bool = false
    @State private var contentOpacity: Double = 0.0
    @State private var hasSavedPhrase: Bool = false
    @State private var showWords: Bool = false

    // MARK: - Grid Layout

    private let gridColumns = [
        GridItem(.flexible(), spacing: AppSpacing.sm),
        GridItem(.flexible(), spacing: AppSpacing.sm),
        GridItem(.flexible(), spacing: AppSpacing.sm)
    ]

    // MARK: - Body

    var body: some View {
        ZStack {
            AppColors.backgroundPrimary.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: AppSpacing.xxl) {

                    // MARK: Header

                    headerSection

                    // MARK: Warning Banner

                    warningBanner

                    // MARK: Instruction

                    Text(L10n.Onboarding.seedPhraseInstruction)
                        .font(AppTypography.bodyMedium)
                        .foregroundColor(AppColors.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, AppSpacing.lg)

                    // MARK: Word Grid

                    wordGrid

                    // MARK: Continue Button

                    continueButton
                }
                .padding(.top, AppSpacing.xxl)
                .padding(.bottom, AppSpacing.huge)
                .padding(.horizontal, AppSpacing.xl)
            }
            .opacity(contentOpacity)

            // MARK: Screenshot Prevention Overlay

            if isBlurred {
                screenshotPreventionOverlay
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .active:
                isScreenRecording = UIScreen.main.isCaptured
                if !isScreenRecording {
                    withAnimation(.easeOut(duration: 0.2)) {
                        isBlurred = false
                    }
                }
            case .inactive, .background:
                withAnimation(.easeIn(duration: 0.1)) {
                    isBlurred = true
                }
            @unknown default:
                break
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIScreen.capturedDidChangeNotification)) { _ in
            isScreenRecording = UIScreen.main.isCaptured
            if isScreenRecording {
                isBlurred = true
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.5).delay(0.1)) {
                contentOpacity = 1.0
            }
            // Briefly delay showing words for dramatic effect
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                withAnimation(.easeOut(duration: 0.4)) {
                    showWords = true
                }
            }
        }
    }

    // MARK: - Header Section

    private var headerSection: some View {
        VStack(spacing: AppSpacing.sm) {
            Image(systemName: AppIcons.shield)
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(AppColors.accentGradient)

            Text(L10n.Onboarding.seedPhraseTitle)
                .font(AppTypography.headingLarge)
                .foregroundColor(AppColors.textPrimary)
        }
    }

    // MARK: - Warning Banner

    private var warningBanner: some View {
        HStack(alignment: .top, spacing: AppSpacing.md) {
            Image(systemName: AppIcons.warning)
                .font(AppTypography.bodyLarge)
                .foregroundColor(AppColors.warning)

            Text(L10n.Onboarding.seedPhraseWarning)
                .font(AppTypography.bodySmall)
                .foregroundColor(AppColors.warning)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(AppSpacing.lg)
        .background(AppColors.warningDim)
        .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.medium, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppCornerRadius.medium, style: .continuous)
                .stroke(AppColors.warning.opacity(0.3), lineWidth: 1)
        )
    }

    // MARK: - Word Grid

    private var wordGrid: some View {
        LazyVGrid(columns: gridColumns, spacing: AppSpacing.sm) {
            ForEach(Array(words.enumerated()), id: \.offset) { index, word in
                wordCard(number: index + 1, word: word)
                    .opacity(showWords ? 1.0 : 0.0)
                    .offset(y: showWords ? 0 : 10)
                    .animation(
                        .easeOut(duration: 0.3).delay(Double(index) * 0.04),
                        value: showWords
                    )
            }
        }
    }

    // MARK: - Word Card

    private func wordCard(number: Int, word: String) -> some View {
        HStack(spacing: AppSpacing.xs) {
            Text("\(number)")
                .font(AppTypography.labelSmall)
                .foregroundColor(AppColors.textTertiary)
                .frame(width: 20, alignment: .trailing)

            Text(word)
                .font(AppTypography.monoMedium)
                .foregroundColor(AppColors.textPrimary)
                .lineLimit(1)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, AppSpacing.md)
        .padding(.vertical, AppSpacing.md)
        .background(AppColors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.medium, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppCornerRadius.medium, style: .continuous)
                .stroke(AppColors.border, lineWidth: 1)
        )
    }

    // MARK: - Continue Button

    private var continueButton: some View {
        Button(action: onContinue) {
            HStack(spacing: AppSpacing.sm) {
                Image(systemName: AppIcons.checkmark)
                    .font(AppTypography.buttonLarge)

                Text(L10n.Onboarding.iSavedIt)
                    .font(AppTypography.buttonLarge)
            }
            .foregroundColor(AppColors.textOnAccent)
            .frame(maxWidth: .infinity)
            .padding(.vertical, AppSpacing.lg)
            .background(AppColors.accentGradient)
            .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.pill, style: .continuous))
        }
        .buttonStyle(.plain)
        .padding(.top, AppSpacing.md)
    }

    // MARK: - Screenshot Prevention Overlay

    private var screenshotPreventionOverlay: some View {
        ZStack {
            AppColors.backgroundPrimary.ignoresSafeArea()

            VStack(spacing: AppSpacing.lg) {
                Image(systemName: AppIcons.eyeSlash)
                    .font(.system(size: 48, weight: .light))
                    .foregroundColor(AppColors.textTertiary)

                Text(L10n.Onboarding.seedPhraseTitle)
                    .font(AppTypography.headingMedium)
                    .foregroundColor(AppColors.textSecondary)
            }
        }
        .transition(.opacity)
    }
}

// MARK: - Preview

#if DEBUG
struct SeedPhraseView_Previews: PreviewProvider {
    static var previews: some View {
        SeedPhraseView(
            words: [
                "abandon", "ability", "able", "about",
                "above", "absent", "absorb", "abstract",
                "absurd", "abuse", "access", "accident"
            ],
            onContinue: {}
        )
    }
}
#endif
