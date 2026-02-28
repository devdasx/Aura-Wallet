import SwiftUI
import LocalAuthentication

// MARK: - SecuritySettingsView
// Security settings screen for the Bitcoin AI Wallet.
// Provides controls for biometric authentication, passcode management,
// and auto-lock timeout configuration.
//
// Platform: iOS 17.0+

struct SecuritySettingsView: View {
    @ObservedObject private var preferences = UserPreferences.shared
    @EnvironmentObject var appRouter: AppRouter

    @State private var showChangePasscode = false
    @State private var currentPasscode: String = ""
    @State private var newPasscode: String = ""
    @State private var confirmPasscode: String = ""
    @State private var passcodeError: String?
    @State private var showPasscodeSuccess = false

    // MARK: - Auto-Lock Options

    /// Available auto-lock timeout options with display labels.
    private let autoLockOptions: [(label: String, seconds: Int)] = [
        (L10n.Settings.oneMinute, 60),
        (L10n.Settings.fiveMinutes, 300),
        (L10n.Settings.fifteenMinutes, 900),
        (L10n.Settings.thirtyMinutes, 1800)
    ]

    // MARK: - Body

    var body: some View {
        List {
            biometricsSection
            autoLockSection
            passcodeSection
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(AppColors.backgroundPrimary.ignoresSafeArea())
        .navigationTitle(L10n.Settings.security)
        .navigationBarTitleDisplayMode(.large)
        .sheet(isPresented: $showChangePasscode) {
            changePasscodeSheet
        }
    }

    // MARK: - Biometrics Section

    private var biometricsSection: some View {
        Section {
            // Biometric type display
            HStack(spacing: AppSpacing.md) {
                biometricIcon
                    .font(.system(size: 24))
                    .foregroundColor(AppColors.accent)
                    .frame(width: AppSpacing.xxxl, height: AppSpacing.xxxl)

                VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                    Text(biometricTypeName)
                        .font(AppTypography.bodyMedium)
                        .foregroundColor(AppColors.textPrimary)

                    Text(biometricDescription)
                        .font(AppTypography.bodySmall)
                        .foregroundColor(AppColors.textSecondary)
                }

                Spacer()

                Toggle("", isOn: Binding(
                    get: { preferences.biometricsEnabled },
                    set: { newValue in
                        toggleBiometrics(newValue)
                    }
                ))
                .tint(AppColors.accent)
                .labelsHidden()
            }
            .listRowBackground(AppColors.backgroundCard)

            // Biometric availability status
            if !BiometricAuth.shared.canUseBiometrics {
                HStack(spacing: AppSpacing.sm) {
                    Image(systemName: AppIcons.warning)
                        .font(AppTypography.labelSmall)
                        .foregroundColor(AppColors.warning)

                    Text(L10n.Settings.biometricsUnavailable)
                        .font(AppTypography.bodySmall)
                        .foregroundColor(AppColors.warning)
                }
                .listRowBackground(AppColors.backgroundCard)
            }
        } header: {
            Text(L10n.Settings.biometrics)
                .font(AppTypography.labelSmall)
                .foregroundColor(AppColors.textSecondary)
        } footer: {
            Text(L10n.Settings.biometricsFooter)
                .font(AppTypography.labelSmall)
                .foregroundColor(AppColors.textTertiary)
        }
    }

    // MARK: - Auto-Lock Section

    private var autoLockSection: some View {
        Section {
            ForEach(autoLockOptions, id: \.seconds) { option in
                Button(action: {
                    HapticManager.selection()
                    preferences.autoLockTimeout = option.seconds
                    appRouter.autoLockTimeoutSeconds = option.seconds
                }) {
                    HStack(spacing: AppSpacing.md) {
                        Image(systemName: AppIcons.lock)
                            .font(AppTypography.bodySmall)
                            .foregroundColor(AppColors.textSecondary)
                            .frame(width: AppSpacing.xxl)

                        Text(option.label)
                            .font(AppTypography.bodyMedium)
                            .foregroundColor(AppColors.textPrimary)

                        Spacer()

                        if preferences.autoLockTimeout == option.seconds {
                            Image(systemName: AppIcons.checkmark)
                                .font(AppTypography.labelMedium)
                                .foregroundColor(AppColors.accent)
                        }
                    }
                }
                .listRowBackground(AppColors.backgroundCard)
            }
        } header: {
            Text(L10n.Settings.autoLock)
                .font(AppTypography.labelSmall)
                .foregroundColor(AppColors.textSecondary)
        } footer: {
            Text(L10n.Settings.autoLockFooter)
                .font(AppTypography.labelSmall)
                .foregroundColor(AppColors.textTertiary)
        }
    }

    // MARK: - Passcode Section

    private var passcodeSection: some View {
        Section {
            Button(action: {
                HapticManager.buttonTap()
                passcodeError = nil
                currentPasscode = ""
                newPasscode = ""
                confirmPasscode = ""
                showPasscodeSuccess = false
                showChangePasscode = true
            }) {
                HStack(spacing: AppSpacing.md) {
                    Image(systemName: AppIcons.key)
                        .font(AppTypography.bodyMedium)
                        .foregroundColor(AppColors.accent)
                        .frame(width: AppSpacing.xxl)

                    Text(L10n.Settings.changePasscode)
                        .font(AppTypography.bodyMedium)
                        .foregroundColor(AppColors.textPrimary)

                    Spacer()

                    Image(systemName: AppIcons.chevronRight)
                        .font(AppTypography.labelSmall)
                        .foregroundColor(AppColors.textTertiary)
                }
            }
            .listRowBackground(AppColors.backgroundCard)
        } header: {
            Text(L10n.Settings.passcode)
                .font(AppTypography.labelSmall)
                .foregroundColor(AppColors.textSecondary)
        }
    }

    // MARK: - Change Passcode Sheet

    private var changePasscodeSheet: some View {
        NavigationStack {
            VStack(spacing: AppSpacing.xxl) {
                Spacer()

                // Lock icon
                Image(systemName: AppIcons.lock)
                    .font(.system(size: 48, weight: .light))
                    .foregroundStyle(AppColors.accentGradient)
                    .padding(.bottom, AppSpacing.lg)

                if showPasscodeSuccess {
                    // Success state
                    VStack(spacing: AppSpacing.md) {
                        Image(systemName: AppIcons.success)
                            .font(.system(size: 40))
                            .foregroundColor(AppColors.success)

                        Text(L10n.Settings.passcodeChanged)
                            .font(AppTypography.headingMedium)
                            .foregroundColor(AppColors.textPrimary)

                        Text(L10n.Settings.passcodeChangedMessage)
                            .font(AppTypography.bodyMedium)
                            .foregroundColor(AppColors.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                } else {
                    // Passcode entry fields
                    VStack(spacing: AppSpacing.lg) {
                        Text(L10n.Settings.changePasscode)
                            .font(AppTypography.headingMedium)
                            .foregroundColor(AppColors.textPrimary)

                        passcodeField(
                            title: L10n.Settings.currentPasscode,
                            text: $currentPasscode
                        )

                        passcodeField(
                            title: L10n.Settings.newPasscode,
                            text: $newPasscode
                        )

                        passcodeField(
                            title: L10n.Settings.confirmNewPasscode,
                            text: $confirmPasscode
                        )

                        // Error message
                        if let error = passcodeError {
                            HStack(spacing: AppSpacing.xs) {
                                Image(systemName: AppIcons.error)
                                    .font(AppTypography.labelSmall)
                                Text(error)
                                    .font(AppTypography.bodySmall)
                            }
                            .foregroundColor(AppColors.error)
                        }
                    }
                    .padding(.horizontal, AppSpacing.xl)
                }

                Spacer()

                // Action button
                if showPasscodeSuccess {
                    Button(action: {
                        showChangePasscode = false
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
                } else {
                    Button(action: {
                        changePasscode()
                    }) {
                        Text(L10n.Common.confirm)
                            .font(AppTypography.buttonLarge)
                            .foregroundColor(AppColors.textOnAccent)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, AppSpacing.lg)
                            .background(
                                canSubmitPasscode
                                    ? AppColors.accentGradient
                                    : LinearGradient(
                                        colors: [AppColors.textTertiary],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                      )
                            )
                            .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.pill, style: .continuous))
                    }
                    .disabled(!canSubmitPasscode)
                    .padding(.horizontal, AppSpacing.xl)
                }

                Spacer()
                    .frame(height: AppSpacing.huge)
            }
            .background(AppColors.backgroundPrimary.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: {
                        showChangePasscode = false
                    }) {
                        Image(systemName: AppIcons.close)
                            .font(AppTypography.bodyMedium)
                            .foregroundColor(AppColors.textPrimary)
                    }
                }
            }
        }
    }

    // MARK: - Passcode Field

    private func passcodeField(title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.xxs) {
            Text(title)
                .font(AppTypography.labelSmall)
                .foregroundColor(AppColors.textSecondary)

            SecureField("", text: text)
                .font(AppTypography.bodyMedium)
                .foregroundColor(AppColors.textPrimary)
                .keyboardType(.numberPad)
                .padding(AppSpacing.md)
                .background(AppColors.backgroundTertiary)
                .cornerRadius(AppCornerRadius.medium)
                .overlay(
                    RoundedRectangle(cornerRadius: AppCornerRadius.medium)
                        .stroke(AppColors.border, lineWidth: 1)
                )
        }
    }

    // MARK: - Computed Properties

    private var biometricIcon: Image {
        switch BiometricAuth.shared.biometricType {
        case .faceID:
            return Image(systemName: AppIcons.faceID)
        case .touchID:
            return Image(systemName: AppIcons.touchID)
        case .none:
            return Image(systemName: AppIcons.shield)
        }
    }

    private var biometricTypeName: String {
        switch BiometricAuth.shared.biometricType {
        case .faceID:  return L10n.Biometric.faceID
        case .touchID: return L10n.Biometric.touchID
        case .none:    return L10n.Settings.biometrics
        }
    }

    private var biometricDescription: String {
        switch BiometricAuth.shared.biometricType {
        case .faceID:
            return L10n.Settings.faceIdDescription
        case .touchID:
            return L10n.Settings.touchIdDescription
        case .none:
            return L10n.Settings.biometricNoneDescription
        }
    }

    private var canSubmitPasscode: Bool {
        !currentPasscode.isEmpty
            && newPasscode.count >= 4
            && !confirmPasscode.isEmpty
    }

    // MARK: - Actions

    private func toggleBiometrics(_ enabled: Bool) {
        if enabled {
            // Verify biometric availability before enabling
            guard BiometricAuth.shared.canUseBiometrics else {
                HapticManager.error()
                return
            }

            Task {
                do {
                    try await BiometricAuth.shared.authenticate(reason: L10n.Biometric.reason)
                    await MainActor.run {
                        preferences.biometricsEnabled = true
                        appRouter.biometricLockEnabled = true
                        HapticManager.success()
                        AppLogger.info("Biometrics enabled", category: .security)
                    }
                } catch {
                    await MainActor.run {
                        preferences.biometricsEnabled = false
                        appRouter.biometricLockEnabled = false
                        HapticManager.error()
                        AppLogger.warning("Failed to enable biometrics: \(error.localizedDescription)", category: .security)
                    }
                }
            }
        } else {
            HapticManager.selection()
            preferences.biometricsEnabled = false
            appRouter.biometricLockEnabled = false
            AppLogger.info("Biometrics disabled", category: .security)
        }
    }

    private func changePasscode() {
        // Validate new passcode length
        guard newPasscode.count >= 4 else {
            passcodeError = L10n.Settings.passcodeTooShort
            HapticManager.error()
            return
        }

        // Validate passcode match
        guard newPasscode == confirmPasscode else {
            passcodeError = L10n.Onboarding.passcodeMismatch
            HapticManager.error()
            return
        }

        // Verify current passcode against stored hash using salted iterated hash
        do {
            let storedHash = try KeychainManager.shared.read(key: .walletPasscodeHash)
            let storedSalt = try KeychainManager.shared.read(key: .walletSalt)

            // Constant-time comparison via EncryptionHelper
            guard EncryptionHelper.verifyPasscode(currentPasscode, against: storedHash, salt: storedSalt) else {
                passcodeError = L10n.Settings.currentPasscodeWrong
                HapticManager.error()
                return
            }

            // Generate a fresh salt for the new passcode
            let newSalt = EncryptionHelper.generateSalt()
            let newHash = EncryptionHelper.hashPasscode(newPasscode, salt: newSalt)

            // Save new hash and new salt
            try KeychainManager.shared.save(key: .walletPasscodeHash, data: newHash)
            try KeychainManager.shared.save(key: .walletSalt, data: newSalt)

            HapticManager.success()
            showPasscodeSuccess = true
            AppLogger.info("Passcode changed successfully", category: .security)
        } catch {
            passcodeError = L10n.Error.keychain
            HapticManager.error()
            AppLogger.error("Failed to change passcode: \(error.localizedDescription)", category: .security)
        }
    }
}

// MARK: - Preview

#if DEBUG
struct SecuritySettingsView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            SecuritySettingsView()
                .environmentObject(AppRouter())
        }
        .preferredColorScheme(.dark)
    }
}
#endif
