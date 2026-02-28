import SwiftUI

// MARK: - BackupView
// Displays the wallet recovery (seed) phrase after biometric authentication.
// Implements security measures including:
//   - Biometric gate before showing the seed phrase
//   - Blur overlay when the app goes to background (screenshot prevention)
//   - Warning against sharing the phrase
//   - 3x4 grid layout matching the onboarding SeedPhraseView
//
// Platform: iOS 17.0+

struct BackupView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    @State private var isAuthenticated = false
    @State private var seedWords: [String] = []
    @State private var isAuthenticating = false
    @State private var authError: String?
    @State private var isBlurred = false
    @State private var isScreenRecording = false
    @State private var showCopiedConfirmation = false

    // Grid layout: 3 columns for a 3x4 word grid.
    private let columns = [
        GridItem(.flexible(), spacing: AppSpacing.sm),
        GridItem(.flexible(), spacing: AppSpacing.sm),
        GridItem(.flexible(), spacing: AppSpacing.sm)
    ]

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
                AppColors.backgroundPrimary.ignoresSafeArea()

                if isAuthenticated {
                    seedPhraseContent
                } else {
                    authenticationGate
                }

                // Blur overlay for background/screenshot protection
                if isBlurred {
                    Rectangle()
                        .fill(.ultraThinMaterial)
                        .ignoresSafeArea()
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: Constants.animationDuration), value: isAuthenticated)
            .animation(.easeInOut(duration: 0.2), value: isBlurred)
            .navigationTitle(L10n.Settings.backupWallet)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: {
                        HapticManager.buttonTap()
                        dismiss()
                    }) {
                        Image(systemName: AppIcons.close)
                            .font(AppTypography.bodyMedium)
                            .foregroundColor(AppColors.textPrimary)
                    }
                }
            }
            .onChange(of: scenePhase) { _, newPhase in
                handleScenePhaseChange(newPhase)
            }
            .onDisappear {
                clearSeedFromMemory()
            }
            .onReceive(NotificationCenter.default.publisher(for: UIScreen.capturedDidChangeNotification)) { _ in
                isScreenRecording = UIScreen.main.isCaptured
                if isScreenRecording && isAuthenticated {
                    isBlurred = true
                }
            }
            .overlay {
                if isScreenRecording && isAuthenticated {
                    VStack(spacing: AppSpacing.md) {
                        Image(systemName: AppIcons.warning)
                            .font(.system(size: 40))
                            .foregroundColor(AppColors.error)
                        Text("Screen recording detected")
                            .font(AppTypography.headingMedium)
                            .foregroundColor(AppColors.textPrimary)
                        Text("Recovery phrase is hidden while screen is being recorded.")
                            .font(AppTypography.bodyMedium)
                            .foregroundColor(AppColors.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(AppColors.backgroundPrimary)
                }
            }
        }
    }

    // MARK: - Authentication Gate

    /// Shows a lock screen requiring biometric authentication before
    /// the seed phrase is revealed.
    private var authenticationGate: some View {
        VStack(spacing: AppSpacing.xxxl) {
            Spacer()

            // Lock icon
            ZStack {
                Circle()
                    .fill(AppColors.accentDim)
                    .frame(width: 100, height: 100)

                Image(systemName: AppIcons.lock)
                    .font(.system(size: 40, weight: .light))
                    .foregroundStyle(AppColors.accentGradient)
            }

            // Title and description
            VStack(spacing: AppSpacing.md) {
                Text(L10n.Backup.authenticateTitle)
                    .font(AppTypography.headingLarge)
                    .foregroundColor(AppColors.textPrimary)

                Text(L10n.Backup.authenticateSubtitle)
                    .font(AppTypography.bodyMedium)
                    .foregroundColor(AppColors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, AppSpacing.xxl)
            }

            // Error message
            if let error = authError {
                HStack(spacing: AppSpacing.xs) {
                    Image(systemName: AppIcons.error)
                        .font(AppTypography.labelSmall)
                    Text(error)
                        .font(AppTypography.bodySmall)
                }
                .foregroundColor(AppColors.error)
                .padding(.horizontal, AppSpacing.xl)
            }

            Spacer()

            // Authenticate button
            Button(action: {
                authenticate()
            }) {
                HStack(spacing: AppSpacing.sm) {
                    if isAuthenticating {
                        ProgressView()
                            .tint(AppColors.textOnAccent)
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: biometricIconName)
                            .font(AppTypography.bodyMedium)
                    }

                    Text(L10n.Backup.authenticateButton)
                        .font(AppTypography.buttonLarge)
                }
                .foregroundColor(AppColors.textOnAccent)
                .frame(maxWidth: .infinity)
                .padding(.vertical, AppSpacing.lg)
                .background(AppColors.accentGradient)
                .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.pill, style: .continuous))
            }
            .disabled(isAuthenticating)
            .padding(.horizontal, AppSpacing.xl)

            Spacer()
                .frame(height: AppSpacing.huge)
        }
    }

    // MARK: - Seed Phrase Content

    /// Displays the 12-word seed phrase in a 3x4 grid with
    /// a security warning and copy functionality.
    private var seedPhraseContent: some View {
        ScrollView {
            VStack(spacing: AppSpacing.xxl) {
                // Security warning banner
                securityWarningBanner

                // 3x4 word grid
                LazyVGrid(columns: columns, spacing: AppSpacing.sm) {
                    ForEach(Array(seedWords.enumerated()), id: \.offset) { index, word in
                        seedWordCell(index: index + 1, word: word)
                    }
                }
                .padding(.horizontal, AppSpacing.lg)

                // Copy warning
                VStack(spacing: AppSpacing.sm) {
                    Image(systemName: AppIcons.shield)
                        .font(AppTypography.headingMedium)
                        .foregroundColor(AppColors.warning)

                    Text(L10n.Backup.neverShare)
                        .font(AppTypography.bodySmall)
                        .foregroundColor(AppColors.warning)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, AppSpacing.xxl)
                }
                .padding(.top, AppSpacing.md)

                // Done button
                Button(action: {
                    HapticManager.buttonTap()
                    // Clear seed words from memory
                    seedWords = []
                    isAuthenticated = false
                    dismiss()
                }) {
                    Text(L10n.Common.done)
                        .font(AppTypography.buttonLarge)
                        .foregroundColor(AppColors.textOnAccent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, AppSpacing.lg)
                        .background(AppColors.accentGradient)
                        .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.pill, style: .continuous))
                }
                .padding(.horizontal, AppSpacing.xl)
                .padding(.top, AppSpacing.lg)
                .padding(.bottom, AppSpacing.huge)
            }
            .padding(.top, AppSpacing.lg)
        }
    }

    // MARK: - Security Warning Banner

    private var securityWarningBanner: some View {
        HStack(spacing: AppSpacing.md) {
            Image(systemName: AppIcons.warning)
                .font(AppTypography.bodyMedium)
                .foregroundColor(AppColors.warning)

            VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                Text(L10n.Backup.warningTitle)
                    .font(AppTypography.labelMedium)
                    .foregroundColor(AppColors.textPrimary)

                Text(L10n.Backup.warningMessage)
                    .font(AppTypography.bodySmall)
                    .foregroundColor(AppColors.textSecondary)
            }

            Spacer()
        }
        .padding(AppSpacing.lg)
        .background(AppColors.warningDim)
        .cornerRadius(AppCornerRadius.large)
        .overlay(
            RoundedRectangle(cornerRadius: AppCornerRadius.large)
                .stroke(AppColors.warning.opacity(0.3), lineWidth: 1)
        )
        .padding(.horizontal, AppSpacing.lg)
    }

    // MARK: - Seed Word Cell

    /// A single numbered word cell in the seed phrase grid.
    private func seedWordCell(index: Int, word: String) -> some View {
        HStack(spacing: AppSpacing.xs) {
            Text("\(index)")
                .font(AppTypography.labelSmall)
                .foregroundColor(AppColors.textTertiary)
                .frame(width: AppSpacing.xxl, alignment: .trailing)

            Text(word)
                .font(AppTypography.monoMedium)
                .foregroundColor(AppColors.textPrimary)
                .lineLimit(1)

            Spacer()
        }
        .padding(.vertical, AppSpacing.sm)
        .padding(.horizontal, AppSpacing.md)
        .background(AppColors.backgroundSecondary)
        .cornerRadius(AppCornerRadius.medium)
        .overlay(
            RoundedRectangle(cornerRadius: AppCornerRadius.medium)
                .stroke(AppColors.border, lineWidth: 1)
        )
    }

    // MARK: - Computed Properties

    /// Returns the SF Symbol name for the device's biometric type.
    private var biometricIconName: String {
        switch BiometricAuth.shared.biometricType {
        case .faceID:  return AppIcons.faceID
        case .touchID: return AppIcons.touchID
        case .none:    return AppIcons.lock
        }
    }

    // MARK: - Actions

    /// Authenticates the user via biometrics and then loads the seed phrase.
    private func authenticate() {
        guard !isAuthenticating else { return }

        isAuthenticating = true
        authError = nil

        Task {
            do {
                try await BiometricAuth.shared.authenticate(reason: L10n.Biometric.reason)

                // Load the seed from keychain (protected by biometric access control).
                // The seed is stored with kSecAttrAccessibleWhenUnlockedThisDeviceOnly
                // and .biometryCurrentSet, so reading it already requires Face ID/Touch ID.
                let encryptedSeed = try KeychainManager.shared.read(key: .encryptedSeed)

                if let phrase = String(data: encryptedSeed, encoding: .utf8) {
                    let words = phrase.components(separatedBy: " ")
                        .map { $0.trimmingCharacters(in: .whitespaces) }
                        .filter { !$0.isEmpty }

                    await MainActor.run {
                        seedWords = words
                        isAuthenticated = true
                        isAuthenticating = false
                        HapticManager.success()
                        AppLogger.info("Seed phrase displayed after biometric authentication", category: .security)
                    }
                } else {
                    await MainActor.run {
                        authError = L10n.Error.walletCorrupted
                        isAuthenticating = false
                        HapticManager.error()
                    }
                }
            } catch let biometricError as BiometricAuth.BiometricError {
                await MainActor.run {
                    isAuthenticating = false
                    switch biometricError {
                    case .userCancelled, .systemCancel:
                        // User cancelled -- no error to show
                        break
                    default:
                        authError = biometricError.errorDescription
                        HapticManager.error()
                    }
                }
            } catch {
                await MainActor.run {
                    authError = error.localizedDescription
                    isAuthenticating = false
                    HapticManager.error()
                    AppLogger.error("Failed to load seed phrase: \(error.localizedDescription)", category: .security)
                }
            }
        }
    }

    /// Handles scene phase changes for screenshot/blur protection.
    private func handleScenePhaseChange(_ newPhase: ScenePhase) {
        switch newPhase {
        case .active:
            // Check for screen recording when returning to foreground
            isScreenRecording = UIScreen.main.isCaptured
            if !isScreenRecording {
                isBlurred = false
            }
        case .inactive, .background:
            if isAuthenticated {
                isBlurred = true
            }
        @unknown default:
            break
        }
    }

    /// Clears seed words from @State memory when the view disappears.
    /// Swift Strings are immutable and can't be securely wiped, but
    /// releasing the references allows ARC to reclaim the memory.
    private func clearSeedFromMemory() {
        seedWords = []
        isAuthenticated = false
    }
}

// MARK: - Preview

#if DEBUG
struct BackupView_Previews: PreviewProvider {
    static var previews: some View {
        BackupView()
            .preferredColorScheme(.dark)
    }
}
#endif
