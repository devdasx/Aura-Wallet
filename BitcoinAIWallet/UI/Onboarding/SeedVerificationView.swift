import SwiftUI

// MARK: - SeedVerificationView
// Verifies the user has saved their recovery phrase by requiring them to
// tap the words in the correct order. Words are presented in a shuffled
// bank; the user taps to select and deselect words, and can only proceed
// when all 12 words are in the original sequence.
//
// Platform: iOS 17.0+
// Dependencies: SwiftUI

struct SeedVerificationView: View {

    // MARK: - Properties

    let words: [String]
    let onVerified: () -> Void

    // MARK: - State

    @State private var selectedWords: [IndexedWord] = []
    @State private var shuffledWords: [IndexedWord] = []
    @State private var showError: Bool = false
    @State private var shakeOffset: CGFloat = 0
    @State private var contentOpacity: Double = 0.0

    // MARK: - Computed

    /// Whether the current selection matches the original word order.
    private var isCorrectOrder: Bool {
        guard selectedWords.count == words.count else { return false }
        return selectedWords.enumerated().allSatisfy { index, indexedWord in
            indexedWord.originalIndex == index
        }
    }

    /// Whether a word from the bank has already been selected.
    private func isSelected(_ indexedWord: IndexedWord) -> Bool {
        selectedWords.contains(where: { $0.id == indexedWord.id })
    }

    /// Whether all slots are filled (valid or not).
    private var allSlotsFilled: Bool {
        selectedWords.count == words.count
    }

    // MARK: - Grid Layout

    private let selectedColumns = [
        GridItem(.flexible(), spacing: AppSpacing.sm),
        GridItem(.flexible(), spacing: AppSpacing.sm),
        GridItem(.flexible(), spacing: AppSpacing.sm)
    ]

    private let bankColumns = [
        GridItem(.adaptive(minimum: 90), spacing: AppSpacing.sm)
    ]

    // MARK: - Body

    var body: some View {
        ZStack {
            AppColors.backgroundPrimary.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: AppSpacing.xxl) {

                    // MARK: Header

                    headerSection

                    // MARK: Selected Words Grid

                    selectedWordsGrid

                    // MARK: Error Feedback

                    if showError {
                        errorFeedback
                    }

                    // MARK: Divider

                    dividerSection

                    // MARK: Word Bank

                    wordBank

                    // MARK: Verify Button

                    verifyButton
                }
                .padding(.top, AppSpacing.xxl)
                .padding(.bottom, AppSpacing.huge)
                .padding(.horizontal, AppSpacing.xl)
            }
            .opacity(contentOpacity)
        }
        .onAppear {
            setupShuffledWords()
            withAnimation(.easeOut(duration: 0.5).delay(0.1)) {
                contentOpacity = 1.0
            }
        }
    }

    // MARK: - Header Section

    private var headerSection: some View {
        VStack(spacing: AppSpacing.md) {
            Text(L10n.Onboarding.seedVerifyTitle)
                .font(AppTypography.headingLarge)
                .foregroundColor(AppColors.textPrimary)

            Text(L10n.Onboarding.seedVerifyInstruction)
                .font(AppTypography.bodyMedium)
                .foregroundColor(AppColors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, AppSpacing.lg)
        }
    }

    // MARK: - Selected Words Grid

    private var selectedWordsGrid: some View {
        LazyVGrid(columns: selectedColumns, spacing: AppSpacing.sm) {
            ForEach(0..<words.count, id: \.self) { index in
                selectedSlot(at: index)
            }
        }
        .offset(x: shakeOffset)
    }

    /// A single slot in the selected words grid. Shows either the tapped word
    /// or an empty placeholder with the slot number.
    private func selectedSlot(at index: Int) -> some View {
        Group {
            if index < selectedWords.count {
                // Filled slot
                let indexedWord = selectedWords[index]
                Button(action: { deselectWord(indexedWord) }) {
                    HStack(spacing: AppSpacing.xs) {
                        Text("\(index + 1)")
                            .font(AppTypography.labelSmall)
                            .foregroundColor(AppColors.textTertiary)
                            .frame(width: 18, alignment: .trailing)

                        Text(indexedWord.word)
                            .font(AppTypography.monoMedium)
                            .foregroundColor(AppColors.textPrimary)
                            .lineLimit(1)

                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, AppSpacing.md)
                    .padding(.vertical, AppSpacing.md)
                    .background(AppColors.accentDim)
                    .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.medium, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: AppCornerRadius.medium, style: .continuous)
                            .stroke(AppColors.accent.opacity(0.3), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .transition(.scale.combined(with: .opacity))
            } else {
                // Empty slot
                HStack(spacing: AppSpacing.xs) {
                    Text("\(index + 1)")
                        .font(AppTypography.labelSmall)
                        .foregroundColor(AppColors.textTertiary)
                        .frame(width: 18, alignment: .trailing)

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, AppSpacing.md)
                .padding(.vertical, AppSpacing.md)
                .background(AppColors.backgroundSecondary)
                .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.medium, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: AppCornerRadius.medium, style: .continuous)
                        .stroke(
                            AppColors.border,
                            style: StrokeStyle(lineWidth: 1, dash: [5, 3])
                        )
                )
            }
        }
    }

    // MARK: - Error Feedback

    private var errorFeedback: some View {
        HStack(spacing: AppSpacing.sm) {
            Image(systemName: AppIcons.error)
                .font(AppTypography.bodySmall)
                .foregroundColor(AppColors.error)

            Text(L10n.Onboarding.verificationFailed)
                .font(AppTypography.bodySmall)
                .foregroundColor(AppColors.error)
        }
        .padding(.vertical, AppSpacing.sm)
        .padding(.horizontal, AppSpacing.lg)
        .background(AppColors.errorDim)
        .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.small, style: .continuous))
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    // MARK: - Divider

    private var dividerSection: some View {
        Rectangle()
            .fill(AppColors.border)
            .frame(height: 1)
            .padding(.horizontal, AppSpacing.lg)
    }

    // MARK: - Word Bank

    private var wordBank: some View {
        LazyVGrid(columns: bankColumns, spacing: AppSpacing.sm) {
            ForEach(shuffledWords) { indexedWord in
                wordBankChip(indexedWord)
            }
        }
    }

    /// A tappable chip representing a word in the bank.
    private func wordBankChip(_ indexedWord: IndexedWord) -> some View {
        let selected = isSelected(indexedWord)

        return Button(action: {
            if selected {
                deselectWord(indexedWord)
            } else {
                selectWord(indexedWord)
            }
        }) {
            Text(indexedWord.word)
                .font(AppTypography.monoMedium)
                .foregroundColor(selected ? AppColors.textTertiary : AppColors.textPrimary)
                .lineLimit(1)
                .padding(.horizontal, AppSpacing.md)
                .padding(.vertical, AppSpacing.sm)
                .frame(maxWidth: .infinity)
                .background(selected ? AppColors.backgroundTertiary : AppColors.backgroundSecondary)
                .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.medium, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: AppCornerRadius.medium, style: .continuous)
                        .stroke(
                            selected ? AppColors.border.opacity(0.5) : AppColors.border,
                            lineWidth: 1
                        )
                )
                .opacity(selected ? 0.4 : 1.0)
        }
        .buttonStyle(.plain)
        .disabled(selected)
    }

    // MARK: - Verify Button

    private var verifyButton: some View {
        Button(action: verifySelection) {
            Text(L10n.Common.next)
                .font(AppTypography.buttonLarge)
                .foregroundColor(allSlotsFilled ? AppColors.textOnAccent : AppColors.textTertiary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, AppSpacing.lg)
                .background(
                    allSlotsFilled
                        ? AnyShapeStyle(AppColors.accentGradient)
                        : AnyShapeStyle(AppColors.backgroundTertiary)
                )
                .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.pill, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!allSlotsFilled)
        .padding(.top, AppSpacing.md)
    }

    // MARK: - Actions

    private func setupShuffledWords() {
        shuffledWords = words.enumerated().map { index, word in
            IndexedWord(originalIndex: index, word: word)
        }.shuffled()
    }

    private func selectWord(_ indexedWord: IndexedWord) {
        guard !isSelected(indexedWord) else { return }
        guard selectedWords.count < words.count else { return }

        withAnimation(.easeOut(duration: 0.2)) {
            showError = false
            selectedWords.append(indexedWord)
        }
    }

    private func deselectWord(_ indexedWord: IndexedWord) {
        withAnimation(.easeOut(duration: 0.2)) {
            showError = false
            selectedWords.removeAll(where: { $0.id == indexedWord.id })
        }
    }

    private func verifySelection() {
        if isCorrectOrder {
            onVerified()
        } else {
            // Show error and shake animation
            withAnimation(.easeInOut(duration: 0.15)) {
                showError = true
            }
            triggerShake()
        }
    }

    private func triggerShake() {
        withAnimation(.default) { shakeOffset = 10 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            withAnimation(.default) { shakeOffset = -8 }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
            withAnimation(.default) { shakeOffset = 6 }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.24) {
            withAnimation(.default) { shakeOffset = -4 }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) {
            withAnimation(.default) { shakeOffset = 0 }
        }
    }
}

// MARK: - IndexedWord

/// Represents a word from the seed phrase with its original position,
/// enabling correct order verification while supporting shuffled display.
struct IndexedWord: Identifiable, Equatable {
    let id = UUID()
    let originalIndex: Int
    let word: String
}

// MARK: - Preview

#if DEBUG
struct SeedVerificationView_Previews: PreviewProvider {
    static var previews: some View {
        SeedVerificationView(
            words: [
                "abandon", "ability", "able", "about",
                "above", "absent", "absorb", "abstract",
                "absurd", "abuse", "access", "accident"
            ],
            onVerified: {}
        )
    }
}
#endif
