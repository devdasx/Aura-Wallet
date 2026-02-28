import SwiftUI

// MARK: - SettingsView
// Main settings screen for the Bitcoin AI Wallet.
// Organized into standard iOS-style grouped sections:
//   - General (theme, language, currency)
//   - Security (biometrics, passcode, backup)
//   - Network (server URL, connection status)
//   - About (app version)
//   - Danger zone (delete wallet)
//
// Platform: iOS 17.0+

struct SettingsView: View {
    @EnvironmentObject var appRouter: AppRouter
    @ObservedObject private var preferences = UserPreferences.shared
    @Environment(\.dismiss) private var dismiss

    @State private var showDeleteConfirmation = false
    @State private var showBackupView = false
    @State private var showSecuritySettings = false
    @State private var showNetworkSettings = false

    // MARK: - Body

    var body: some View {
        NavigationStack {
            List {
                appearanceSection
                generalSection
                chatSection
                securitySection
                networkSection
                aboutSection
                dangerZoneSection
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(AppColors.backgroundPrimary.ignoresSafeArea())
            .navigationTitle(L10n.Settings.title)
            .navigationBarTitleDisplayMode(.large)
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
            .tint(AppColors.accent)
        }
        .alert(L10n.Settings.deleteWallet, isPresented: $showDeleteConfirmation) {
            Button(L10n.Common.cancel, role: .cancel) {}
            Button(L10n.Common.delete, role: .destructive) {
                deleteWallet()
            }
        } message: {
            Text(L10n.Settings.deleteWalletWarning)
        }
        .sheet(isPresented: $showBackupView) {
            BackupView()
        }
        .sheet(isPresented: $showSecuritySettings) {
            NavigationStack {
                SecuritySettingsView()
                    .toolbar {
                        ToolbarItem(placement: .navigationBarLeading) {
                            Button(action: {
                                showSecuritySettings = false
                            }) {
                                Image(systemName: AppIcons.close)
                                    .font(AppTypography.bodyMedium)
                                    .foregroundColor(AppColors.textPrimary)
                            }
                        }
                    }
            }
            .environmentObject(appRouter)
            .tint(AppColors.accent)
        }
        .sheet(isPresented: $showNetworkSettings) {
            NavigationStack {
                NetworkSettingsView()
                    .toolbar {
                        ToolbarItem(placement: .navigationBarLeading) {
                            Button(action: {
                                showNetworkSettings = false
                            }) {
                                Image(systemName: AppIcons.close)
                                    .font(AppTypography.bodyMedium)
                                    .foregroundColor(AppColors.textPrimary)
                            }
                        }
                    }
            }
            .tint(AppColors.accent)
        }
    }

    // MARK: - Appearance Section

    private var appearanceSection: some View {
        Section {
            // Color Mode — segmented picker
            colorModeRow

            // Chat Font — radio list with preview
            chatFontRow
        } header: {
            Text(L10n.Settings.appearance)
                .font(AppTypography.labelSmall)
                .foregroundColor(AppColors.textSecondary)
        }
    }

    private var colorModeRow: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text(L10n.Settings.colorMode)
                .font(AppTypography.bodyMedium)
                .foregroundColor(AppColors.textPrimary)

            Picker("", selection: Binding(
                get: { ThemePreference(rawValue: preferences.themePreference) ?? .system },
                set: { newTheme in
                    HapticManager.selection()
                    preferences.themePreference = newTheme.rawValue
                    appRouter.setTheme(newTheme)
                }
            )) {
                Text(L10n.Settings.lightMode).tag(ThemePreference.light)
                Text(L10n.Settings.systemMode).tag(ThemePreference.system)
                Text(L10n.Settings.darkMode).tag(ThemePreference.dark)
            }
            .pickerStyle(.segmented)
        }
        .listRowBackground(AppColors.backgroundCard)
    }

    private var chatFontRow: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            Text(L10n.Settings.chatFont)
                .font(AppTypography.bodyMedium)
                .foregroundColor(AppColors.textPrimary)

            ForEach(FontPreference.allCases) { font in
                fontOptionButton(font)
            }
        }
        .listRowBackground(AppColors.backgroundCard)
    }

    private func fontOptionButton(_ font: FontPreference) -> some View {
        Button {
            HapticManager.selection()
            preferences.chatFont = font.rawValue
        } label: {
            HStack(spacing: AppSpacing.md) {
                VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                    Text(font.displayName)
                        .font(AppTypography.bodyMedium)
                        .foregroundColor(AppColors.textPrimary)

                    Text(L10n.Settings.chatFontPreview)
                        .font(font.previewFont)
                        .foregroundColor(AppColors.textSecondary)
                        .lineLimit(1)
                }

                Spacer()

                Image(systemName: preferences.chatFont == font.rawValue
                    ? "checkmark.circle.fill"
                    : "circle"
                )
                .font(.system(size: 20))
                .foregroundColor(preferences.chatFont == font.rawValue
                    ? AppColors.accent
                    : AppColors.textTertiary
                )
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - General Section

    private var generalSection: some View {
        Section {
            // Language picker
            languageRow

            // Display currency
            currencyRow
        } header: {
            Text(L10n.Settings.general)
                .font(AppTypography.labelSmall)
                .foregroundColor(AppColors.textSecondary)
        }
    }

    private var languageRow: some View {
        HStack(spacing: AppSpacing.md) {
            settingsIcon(AppIcons.globe, color: AppColors.info)

            Text(L10n.Settings.language)
                .font(AppTypography.bodyMedium)
                .foregroundColor(AppColors.textPrimary)

            Spacer()

            Picker("", selection: $preferences.appLanguage) {
                ForEach(LocalizationManager.supportedLanguages, id: \.code) { language in
                    Text(language.name).tag(language.code)
                }
            }
            .pickerStyle(.menu)
            .tint(AppColors.textSecondary)
            .onChange(of: preferences.appLanguage) { _, _ in
                HapticManager.selection()
            }
        }
        .listRowBackground(AppColors.backgroundCard)
    }

    private var currencyRow: some View {
        HStack(spacing: AppSpacing.md) {
            settingsIcon(AppIcons.bitcoin, color: AppColors.warning)

            Text(L10n.Settings.currency)
                .font(AppTypography.bodyMedium)
                .foregroundColor(AppColors.textPrimary)

            Spacer()

            Picker("", selection: $preferences.displayCurrency) {
                ForEach(UserPreferences.supportedCurrencies, id: \.0) { currency in
                    Text(currency.0).tag(currency.0)
                }
            }
            .pickerStyle(.menu)
            .tint(AppColors.textSecondary)
            .onChange(of: preferences.displayCurrency) { _, _ in
                HapticManager.selection()
            }
        }
        .listRowBackground(AppColors.backgroundCard)
    }

    // MARK: - Chat Section

    private var chatSection: some View {
        Section {
            HStack(spacing: AppSpacing.md) {
                settingsIcon("lightbulb.fill", color: AppColors.warning)

                VStack(alignment: .leading, spacing: AppSpacing.xxxs) {
                    Text(L10n.Settings.tipsEnabled)
                        .font(AppTypography.bodyMedium)
                        .foregroundColor(AppColors.textPrimary)

                    Text(L10n.Settings.tipsEnabledSubtitle)
                        .font(AppTypography.labelSmall)
                        .foregroundColor(AppColors.textTertiary)
                }

                Spacer()

                Toggle("", isOn: $preferences.tipsEnabled)
                    .tint(AppColors.accent)
                    .labelsHidden()
                    .onChange(of: preferences.tipsEnabled) { _, _ in
                        HapticManager.selection()
                    }
            }
            .listRowBackground(AppColors.backgroundCard)

            // Typing haptics toggle
            HStack(spacing: AppSpacing.md) {
                settingsIcon("waveform", color: AppColors.accent)

                VStack(alignment: .leading, spacing: AppSpacing.xxxs) {
                    Text(L10n.Settings.typingHaptics)
                        .font(AppTypography.bodyMedium)
                        .foregroundColor(AppColors.textPrimary)

                    Text(L10n.Settings.typingHapticsSubtitle)
                        .font(AppTypography.labelSmall)
                        .foregroundColor(AppColors.textTertiary)
                }

                Spacer()

                Toggle("", isOn: $preferences.typingHapticsEnabled)
                    .tint(AppColors.accent)
                    .labelsHidden()
                    .onChange(of: preferences.typingHapticsEnabled) { _, _ in
                        HapticManager.selection()
                    }
            }
            .listRowBackground(AppColors.backgroundCard)
        } header: {
            Text(L10n.Settings.chat)
                .font(AppTypography.labelSmall)
                .foregroundColor(AppColors.textSecondary)
        }
    }

    // MARK: - Security Section

    private var securitySection: some View {
        Section {
            // Biometrics toggle
            biometricsToggleRow

            // Security settings (passcode, auto-lock)
            Button(action: {
                HapticManager.buttonTap()
                showSecuritySettings = true
            }) {
                HStack(spacing: AppSpacing.md) {
                    settingsIcon(AppIcons.lock, color: AppColors.accent)

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

            // Backup wallet
            Button(action: {
                HapticManager.buttonTap()
                showBackupView = true
            }) {
                HStack(spacing: AppSpacing.md) {
                    settingsIcon(AppIcons.key, color: AppColors.warning)

                    Text(L10n.Settings.backupWallet)
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
            Text(L10n.Settings.security)
                .font(AppTypography.labelSmall)
                .foregroundColor(AppColors.textSecondary)
        }
    }

    private var biometricsToggleRow: some View {
        HStack(spacing: AppSpacing.md) {
            settingsIcon(biometricIconName, color: AppColors.success)

            Text(L10n.Settings.biometrics)
                .font(AppTypography.bodyMedium)
                .foregroundColor(AppColors.textPrimary)

            Spacer()

            Toggle("", isOn: Binding(
                get: { preferences.biometricsEnabled },
                set: { newValue in
                    // Require biometric authentication before changing this setting
                    Task {
                        do {
                            try await BiometricAuth.shared.authenticate(
                                reason: "Authenticate to change biometric lock setting"
                            )
                            await MainActor.run {
                                HapticManager.selection()
                                preferences.biometricsEnabled = newValue
                                appRouter.biometricLockEnabled = newValue
                            }
                        } catch {
                            await MainActor.run {
                                HapticManager.error()
                                // Revert: the toggle will snap back since the
                                // binding get { } still returns the old value.
                            }
                        }
                    }
                }
            ))
            .tint(AppColors.accent)
            .labelsHidden()
        }
        .listRowBackground(AppColors.backgroundCard)
    }

    /// Returns the appropriate biometric icon based on device capability.
    private var biometricIconName: String {
        switch appRouter.biometricType {
        case .touchID:
            return AppIcons.touchID
        default:
            return AppIcons.faceID
        }
    }

    // MARK: - Network Section

    private var networkSection: some View {
        Section {
            // Network settings
            Button(action: {
                HapticManager.buttonTap()
                showNetworkSettings = true
            }) {
                HStack(spacing: AppSpacing.md) {
                    settingsIcon(AppIcons.network, color: AppColors.info)

                    Text(L10n.Settings.blockbookServer)
                        .font(AppTypography.bodyMedium)
                        .foregroundColor(AppColors.textPrimary)

                    Spacer()

                    Image(systemName: AppIcons.chevronRight)
                        .font(AppTypography.labelSmall)
                        .foregroundColor(AppColors.textTertiary)
                }
            }
            .listRowBackground(AppColors.backgroundCard)

            // Network status indicator
            HStack(spacing: AppSpacing.md) {
                settingsIcon(AppIcons.globe, color: networkStatusColor)

                Text(L10n.Settings.networkStatus)
                    .font(AppTypography.bodyMedium)
                    .foregroundColor(AppColors.textPrimary)

                Spacer()

                HStack(spacing: AppSpacing.xs) {
                    Circle()
                        .fill(networkStatusColor)
                        .frame(width: 8, height: 8)

                    Text(networkStatusText)
                        .font(AppTypography.labelMedium)
                        .foregroundColor(networkStatusColor)
                }
            }
            .listRowBackground(AppColors.backgroundCard)
        } header: {
            Text(L10n.Settings.network)
                .font(AppTypography.labelSmall)
                .foregroundColor(AppColors.textSecondary)
        }
    }

    private var networkStatusColor: Color {
        NetworkMonitor.shared.isConnected ? AppColors.success : AppColors.error
    }

    private var networkStatusText: String {
        NetworkMonitor.shared.isConnected ? L10n.Settings.connected : L10n.Settings.disconnected
    }

    // MARK: - About Section

    private var aboutSection: some View {
        Section {
            HStack(spacing: AppSpacing.md) {
                settingsIcon(AppIcons.info, color: AppColors.textSecondary)

                Text(L10n.Settings.version)
                    .font(AppTypography.bodyMedium)
                    .foregroundColor(AppColors.textPrimary)

                Spacer()

                Text(appVersionString)
                    .font(AppTypography.labelMedium)
                    .foregroundColor(AppColors.textTertiary)
            }
            .listRowBackground(AppColors.backgroundCard)
        } header: {
            Text(L10n.Settings.about)
                .font(AppTypography.labelSmall)
                .foregroundColor(AppColors.textSecondary)
        }
    }

    private var appVersionString: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    // MARK: - Danger Zone Section

    private var dangerZoneSection: some View {
        Section {
            Button(action: {
                HapticManager.warning()
                showDeleteConfirmation = true
            }) {
                HStack(spacing: AppSpacing.md) {
                    settingsIcon(AppIcons.trash, color: AppColors.error)

                    Text(L10n.Settings.deleteWallet)
                        .font(AppTypography.bodyMedium)
                        .foregroundColor(AppColors.error)

                    Spacer()
                }
            }
            .listRowBackground(AppColors.backgroundCard)
        }
    }

    // MARK: - Icon Helper

    /// Creates a consistently styled settings row icon.
    private func settingsIcon(_ systemName: String, color: Color) -> some View {
        Image(systemName: systemName)
            .font(AppTypography.bodyMedium)
            .foregroundColor(color)
            .frame(width: AppSpacing.xxl, height: AppSpacing.xxl)
    }

    // MARK: - Actions

    /// Deletes all wallet data and returns to onboarding.
    private func deleteWallet() {
        AppLogger.warning("User initiated wallet deletion", category: .wallet)
        HapticManager.heavyTap()

        // Clear all persisted data
        do {
            try KeychainManager.shared.deleteAll()
        } catch {
            AppLogger.error("Failed to clear keychain during wallet deletion: \(error.localizedDescription)", category: .security)
        }

        do {
            try CoreDataStack.shared.deleteAll()
        } catch {
            AppLogger.error("Failed to clear Core Data during wallet deletion: \(error.localizedDescription)", category: .wallet)
        }

        // Reset preferences to defaults
        UserPreferences.shared.resetToDefaults()

        // Navigate back to onboarding
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            appRouter.resetToOnboarding()
        }
    }
}

// MARK: - Preview

#if DEBUG
struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView()
            .environmentObject(AppRouter())
            .preferredColorScheme(.dark)
    }
}
#endif
