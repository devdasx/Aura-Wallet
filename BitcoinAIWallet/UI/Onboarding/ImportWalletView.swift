import SwiftUI

// MARK: - ImportWalletView
// Allows users to import an existing wallet by entering a 12 or 24-word
// BIP39 recovery phrase. Provides real-time validation feedback, word
// count indicator, and paste-from-clipboard functionality.
//
// Platform: iOS 17.0+
// Dependencies: SwiftUI, Mnemonic (Core/Wallet/Mnemonic.swift),
//               BIP39Wordlist (Core/Wallet/BIP39Wordlist.swift)

struct ImportWalletView: View {

    // MARK: - Callbacks

    let onImported: ([String]) -> Void

    // MARK: - State

    @State private var phraseText: String = ""
    @State private var validationState: ValidationState = .empty
    @State private var contentOpacity: Double = 0.0
    @State private var isImporting: Bool = false
    @FocusState private var isTextEditorFocused: Bool

    // MARK: - Derived

    /// Normalized words extracted from the text input.
    private var enteredWords: [String] {
        phraseText
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: " ")
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// Current word count.
    private var wordCount: Int {
        enteredWords.count
    }

    /// Target word count (12 or 24). Shows 12 until user enters more than 12.
    private var targetWordCount: Int {
        wordCount > 12 ? 24 : 12
    }

    /// Whether the Import button should be enabled.
    private var canImport: Bool {
        validationState == .valid && !isImporting
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            AppColors.backgroundPrimary.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: AppSpacing.xxl) {

                    // MARK: Header

                    headerSection

                    // MARK: Text Editor

                    phraseEditor

                    // MARK: Word Count + Validation

                    statusRow

                    // MARK: Paste Button

                    pasteButton

                    // MARK: Import Button

                    importButton
                }
                .padding(.top, AppSpacing.xxl)
                .padding(.bottom, AppSpacing.huge)
                .padding(.horizontal, AppSpacing.xl)
            }
            .opacity(contentOpacity)
        }
        .onTapGesture {
            isTextEditorFocused = false
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.5).delay(0.1)) {
                contentOpacity = 1.0
            }
        }
        .onChange(of: phraseText) { _, _ in
            validatePhrase()
        }
    }

    // MARK: - Header Section

    private var headerSection: some View {
        VStack(spacing: AppSpacing.md) {
            Image(systemName: AppIcons.key)
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(AppColors.accentGradient)

            Text(L10n.Onboarding.importTitle)
                .font(AppTypography.headingLarge)
                .foregroundColor(AppColors.textPrimary)

            Text(L10n.Onboarding.importInstruction)
                .font(AppTypography.bodyMedium)
                .foregroundColor(AppColors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, AppSpacing.lg)
        }
    }

    // MARK: - Phrase Editor

    private var phraseEditor: some View {
        ZStack(alignment: .topLeading) {
            // Placeholder
            if phraseText.isEmpty {
                Text(L10n.Onboarding.importPlaceholder)
                    .font(AppTypography.monoMedium)
                    .foregroundColor(AppColors.textTertiary)
                    .padding(.horizontal, AppSpacing.lg)
                    .padding(.vertical, AppSpacing.lg)
                    .allowsHitTesting(false)
            }

            TextEditor(text: $phraseText)
                .font(AppTypography.monoMedium)
                .foregroundColor(AppColors.textPrimary)
                .scrollContentBackground(.hidden)
                .autocapitalization(.none)
                .disableAutocorrection(true)
                .textInputAutocapitalization(.never)
                .focused($isTextEditorFocused)
                .padding(.horizontal, AppSpacing.md)
                .padding(.vertical, AppSpacing.md)
                .frame(minHeight: 140)
        }
        .background(AppColors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.large, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppCornerRadius.large, style: .continuous)
                .stroke(editorBorderColor, lineWidth: 1.5)
        )
    }

    /// Border color based on validation state.
    private var editorBorderColor: Color {
        switch validationState {
        case .empty:
            return AppColors.border
        case .partial:
            return AppColors.border
        case .invalidWord:
            return AppColors.error
        case .invalidChecksum:
            return AppColors.error
        case .valid:
            return AppColors.success
        }
    }

    // MARK: - Status Row

    private var statusRow: some View {
        HStack {
            // Word count indicator
            wordCountIndicator

            Spacer()

            // Validation feedback
            validationFeedback
        }
    }

    private var wordCountIndicator: some View {
        let countText = String(format: L10n.Onboarding.wordCountFormat, wordCount, targetWordCount)
        let color: Color = {
            switch validationState {
            case .valid: return AppColors.success
            case .invalidWord, .invalidChecksum: return AppColors.error
            default: return AppColors.textSecondary
            }
        }()

        return Text(countText)
            .font(AppTypography.labelMedium)
            .foregroundColor(color)
    }

    private var validationFeedback: some View {
        Group {
            switch validationState {
            case .empty:
                EmptyView()

            case .partial:
                EmptyView()

            case .invalidWord:
                HStack(spacing: AppSpacing.xxs) {
                    Image(systemName: AppIcons.error)
                        .font(AppTypography.labelSmall)
                    Text(L10n.Error.seedPhraseInvalid)
                        .font(AppTypography.labelSmall)
                }
                .foregroundColor(AppColors.error)

            case .invalidChecksum:
                HStack(spacing: AppSpacing.xxs) {
                    Image(systemName: AppIcons.error)
                        .font(AppTypography.labelSmall)
                    Text(L10n.Error.seedPhraseInvalid)
                        .font(AppTypography.labelSmall)
                }
                .foregroundColor(AppColors.error)

            case .valid:
                HStack(spacing: AppSpacing.xxs) {
                    Image(systemName: AppIcons.success)
                        .font(AppTypography.labelSmall)
                    Text(L10n.Common.success)
                        .font(AppTypography.labelSmall)
                }
                .foregroundColor(AppColors.success)
            }
        }
    }

    // MARK: - Paste Button

    private var pasteButton: some View {
        Button(action: pasteFromClipboard) {
            HStack(spacing: AppSpacing.sm) {
                Image(systemName: AppIcons.copy)
                    .font(AppTypography.buttonMedium)

                Text(L10n.Onboarding.pasteFromClipboard)
                    .font(AppTypography.buttonMedium)
            }
            .foregroundColor(AppColors.accent)
            .padding(.vertical, AppSpacing.md)
            .padding(.horizontal, AppSpacing.xl)
            .background(AppColors.accentDim)
            .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.large, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Import Button

    private var importButton: some View {
        Button(action: performImport) {
            HStack(spacing: AppSpacing.sm) {
                if isImporting {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: AppColors.textOnAccent))
                        .scaleEffect(0.8)
                } else {
                    Image(systemName: AppIcons.key)
                        .font(AppTypography.buttonLarge)
                }

                Text(L10n.Onboarding.importButton)
                    .font(AppTypography.buttonLarge)
            }
            .foregroundColor(canImport ? AppColors.textOnAccent : AppColors.textTertiary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, AppSpacing.lg)
            .background(
                canImport
                    ? AnyShapeStyle(AppColors.accentGradient)
                    : AnyShapeStyle(AppColors.backgroundTertiary)
            )
            .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.pill, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!canImport)
        .padding(.top, AppSpacing.md)
    }

    // MARK: - Actions

    private func pasteFromClipboard() {
        guard let clipboardText = UIPasteboard.general.string else { return }
        phraseText = clipboardText
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        isTextEditorFocused = false

        // Clear the clipboard immediately to prevent the seed phrase from
        // being read by other apps or appearing in clipboard suggestions.
        UIPasteboard.general.string = ""
    }

    private func validatePhrase() {
        let currentWords = enteredWords

        if currentWords.isEmpty {
            validationState = .empty
            return
        }

        // Check if word count is valid (12 or 24)
        let isValidCount = currentWords.count == 12 || currentWords.count == 24

        if !isValidCount {
            // Check individual words for early feedback
            let hasInvalidWord = currentWords.contains { !BIP39Wordlist.isValid(word: $0) }
            if hasInvalidWord && currentWords.count >= 1 {
                // Only show invalid word if the last word looks complete (followed by space)
                let lastChar = phraseText.last
                if lastChar == " " || lastChar == "\n" {
                    validationState = .invalidWord
                } else {
                    validationState = .partial
                }
            } else {
                validationState = .partial
            }
            return
        }

        // Validate all words are in the BIP39 wordlist
        for word in currentWords {
            if !BIP39Wordlist.isValid(word: word) {
                validationState = .invalidWord
                return
            }
        }

        // Validate checksum
        if Mnemonic.validate(words: currentWords) {
            validationState = .valid
        } else {
            validationState = .invalidChecksum
        }
    }

    private func performImport() {
        guard canImport else { return }
        isImporting = true
        isTextEditorFocused = false

        // Brief delay for loading state feedback
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            isImporting = false
            onImported(enteredWords)
        }
    }

    // MARK: - Validation State

    enum ValidationState {
        case empty
        case partial
        case invalidWord
        case invalidChecksum
        case valid
    }
}

// MARK: - Preview

#if DEBUG
struct ImportWalletView_Previews: PreviewProvider {
    static var previews: some View {
        ImportWalletView(onImported: { _ in })
    }
}
#endif
