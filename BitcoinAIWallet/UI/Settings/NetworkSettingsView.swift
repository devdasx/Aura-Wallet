import SwiftUI

// MARK: - NetworkSettingsView
// Server configuration and network status screen.
// Allows the user to configure the Blockbook server URL, test the
// connection, view current connectivity information, and reset to
// the default server.
//
// Platform: iOS 17.0+

struct NetworkSettingsView: View {
    @ObservedObject private var preferences = UserPreferences.shared
    @ObservedObject private var networkMonitor = NetworkMonitor.shared

    @State private var customURL: String = ""
    @State private var isTestingConnection: Bool = false
    @State private var connectionStatus: ConnectionTestResult?

    @FocusState private var isURLFieldFocused: Bool

    // MARK: - Connection Test Result

    enum ConnectionTestResult: Equatable {
        case success
        case failure(String)

        var isSuccess: Bool {
            if case .success = self { return true }
            return false
        }

        var message: String {
            switch self {
            case .success:
                return L10n.Settings.connectionSuccess
            case .failure(let reason):
                return reason
            }
        }
    }

    // MARK: - Body

    var body: some View {
        List {
            serverConfigSection
            connectionStatusSection
            networkInfoSection
            resetSection
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(AppColors.backgroundPrimary.ignoresSafeArea())
        .navigationTitle(L10n.Settings.network)
        .navigationBarTitleDisplayMode(.large)
        .onAppear {
            customURL = preferences.blockbookURL
        }
        .onTapGesture {
            isURLFieldFocused = false
        }
    }

    // MARK: - Server Configuration Section

    private var serverConfigSection: some View {
        Section {
            // Server URL field
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                Text(L10n.Settings.blockbookServer)
                    .font(AppTypography.labelMedium)
                    .foregroundColor(AppColors.textSecondary)

                HStack(spacing: AppSpacing.sm) {
                    Image(systemName: AppIcons.network)
                        .font(AppTypography.bodySmall)
                        .foregroundColor(AppColors.textTertiary)

                    TextField(Constants.defaultBlockbookURL, text: $customURL)
                        .font(AppTypography.monoMedium)
                        .foregroundColor(AppColors.textPrimary)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .focused($isURLFieldFocused)
                        .submitLabel(.done)
                        .onSubmit {
                            saveURL()
                        }
                }
                .padding(AppSpacing.md)
                .background(AppColors.backgroundTertiary)
                .cornerRadius(AppCornerRadius.medium)

                // URL validation indicator
                if !customURL.isEmpty && !isURLValid(customURL) {
                    HStack(spacing: AppSpacing.xxs) {
                        Image(systemName: AppIcons.warning)
                            .font(AppTypography.labelSmall)
                        Text(L10n.Settings.invalidUrl)
                            .font(AppTypography.labelSmall)
                    }
                    .foregroundColor(AppColors.warning)
                }
            }
            .listRowBackground(AppColors.backgroundCard)

            // Save & Test buttons
            HStack(spacing: AppSpacing.md) {
                // Save button
                Button(action: {
                    HapticManager.buttonTap()
                    saveURL()
                }) {
                    Text(L10n.Common.save)
                        .font(AppTypography.buttonMedium)
                        .foregroundColor(AppColors.textOnAccent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, AppSpacing.md)
                        .background(isURLValid(customURL) ? AppColors.accent : AppColors.textTertiary)
                        .cornerRadius(AppCornerRadius.medium)
                }
                .disabled(!isURLValid(customURL))

                // Test Connection button
                Button(action: {
                    HapticManager.buttonTap()
                    testConnection()
                }) {
                    HStack(spacing: AppSpacing.xs) {
                        if isTestingConnection {
                            ProgressView()
                                .tint(AppColors.accent)
                                .scaleEffect(0.8)
                        }
                        Text(L10n.Settings.testConnection)
                            .font(AppTypography.buttonMedium)
                            .foregroundColor(AppColors.accent)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, AppSpacing.md)
                    .background(AppColors.accentDim)
                    .cornerRadius(AppCornerRadius.medium)
                }
                .disabled(isTestingConnection || !isURLValid(customURL))
            }
            .listRowBackground(AppColors.backgroundCard)

            // Test result
            if let result = connectionStatus {
                HStack(spacing: AppSpacing.sm) {
                    Image(systemName: result.isSuccess ? AppIcons.success : AppIcons.error)
                        .font(AppTypography.bodyMedium)
                        .foregroundColor(result.isSuccess ? AppColors.success : AppColors.error)

                    Text(result.message)
                        .font(AppTypography.bodySmall)
                        .foregroundColor(result.isSuccess ? AppColors.success : AppColors.error)

                    Spacer()
                }
                .padding(AppSpacing.md)
                .background(result.isSuccess ? AppColors.successDim : AppColors.errorDim)
                .cornerRadius(AppCornerRadius.medium)
                .listRowBackground(AppColors.backgroundCard)
            }
        } header: {
            Text(L10n.Settings.serverConfiguration)
                .font(AppTypography.labelSmall)
                .foregroundColor(AppColors.textSecondary)
        }
    }

    // MARK: - Connection Status Section

    private var connectionStatusSection: some View {
        Section {
            // Connection status
            HStack(spacing: AppSpacing.md) {
                Circle()
                    .fill(networkMonitor.isConnected ? AppColors.success : AppColors.error)
                    .frame(width: 10, height: 10)

                Text(L10n.Settings.networkStatus)
                    .font(AppTypography.bodyMedium)
                    .foregroundColor(AppColors.textPrimary)

                Spacer()

                Text(networkMonitor.isConnected ? L10n.Settings.connected : L10n.Settings.disconnected)
                    .font(AppTypography.labelMedium)
                    .foregroundColor(networkMonitor.isConnected ? AppColors.success : AppColors.error)
            }
            .listRowBackground(AppColors.backgroundCard)

            // Network type
            HStack(spacing: AppSpacing.md) {
                Image(systemName: connectionTypeIcon)
                    .font(AppTypography.bodyMedium)
                    .foregroundColor(AppColors.textSecondary)
                    .frame(width: AppSpacing.xxl)

                Text(L10n.Settings.connectionType)
                    .font(AppTypography.bodyMedium)
                    .foregroundColor(AppColors.textPrimary)

                Spacer()

                Text(connectionTypeLabel)
                    .font(AppTypography.labelMedium)
                    .foregroundColor(AppColors.textSecondary)
            }
            .listRowBackground(AppColors.backgroundCard)

            // Current server
            HStack(spacing: AppSpacing.md) {
                Image(systemName: AppIcons.network)
                    .font(AppTypography.bodyMedium)
                    .foregroundColor(AppColors.textSecondary)
                    .frame(width: AppSpacing.xxl)

                Text(L10n.Settings.currentServer)
                    .font(AppTypography.bodyMedium)
                    .foregroundColor(AppColors.textPrimary)

                Spacer()

                Text(serverHostname)
                    .font(AppTypography.monoSmall)
                    .foregroundColor(AppColors.textTertiary)
                    .lineLimit(1)
            }
            .listRowBackground(AppColors.backgroundCard)
        } header: {
            Text(L10n.Settings.connectionInfo)
                .font(AppTypography.labelSmall)
                .foregroundColor(AppColors.textSecondary)
        }
    }

    // MARK: - Network Info Section

    private var networkInfoSection: some View {
        Section {
            // Expensive connection indicator
            if networkMonitor.isExpensive {
                HStack(spacing: AppSpacing.md) {
                    Image(systemName: AppIcons.warning)
                        .font(AppTypography.bodyMedium)
                        .foregroundColor(AppColors.warning)
                        .frame(width: AppSpacing.xxl)

                    Text(L10n.Settings.expensiveConnection)
                        .font(AppTypography.bodyMedium)
                        .foregroundColor(AppColors.textPrimary)

                    Spacer()

                    Text(L10n.Settings.active)
                        .font(AppTypography.labelMedium)
                        .foregroundColor(AppColors.warning)
                }
                .listRowBackground(AppColors.backgroundCard)
            }

            // Constrained connection indicator
            if networkMonitor.isConstrained {
                HStack(spacing: AppSpacing.md) {
                    Image(systemName: AppIcons.info)
                        .font(AppTypography.bodyMedium)
                        .foregroundColor(AppColors.info)
                        .frame(width: AppSpacing.xxl)

                    Text(L10n.Settings.lowDataMode)
                        .font(AppTypography.bodyMedium)
                        .foregroundColor(AppColors.textPrimary)

                    Spacer()

                    Text(L10n.Settings.enabled)
                        .font(AppTypography.labelMedium)
                        .foregroundColor(AppColors.info)
                }
                .listRowBackground(AppColors.backgroundCard)
            }

            // If neither expensive nor constrained, show a clean status
            if !networkMonitor.isExpensive && !networkMonitor.isConstrained {
                HStack(spacing: AppSpacing.md) {
                    Image(systemName: AppIcons.success)
                        .font(AppTypography.bodyMedium)
                        .foregroundColor(AppColors.success)
                        .frame(width: AppSpacing.xxl)

                    Text(L10n.Settings.unrestrictedConnection)
                        .font(AppTypography.bodyMedium)
                        .foregroundColor(AppColors.textPrimary)

                    Spacer()
                }
                .listRowBackground(AppColors.backgroundCard)
            }
        } header: {
            Text(L10n.Settings.networkQuality)
                .font(AppTypography.labelSmall)
                .foregroundColor(AppColors.textSecondary)
        }
    }

    // MARK: - Reset Section

    private var resetSection: some View {
        Section {
            Button(action: {
                HapticManager.buttonTap()
                resetToDefault()
            }) {
                HStack(spacing: AppSpacing.md) {
                    Image(systemName: AppIcons.refresh)
                        .font(AppTypography.bodyMedium)
                        .foregroundColor(AppColors.accent)
                        .frame(width: AppSpacing.xxl)

                    Text(L10n.Settings.resetToDefault)
                        .font(AppTypography.bodyMedium)
                        .foregroundColor(AppColors.accent)

                    Spacer()
                }
            }
            .listRowBackground(AppColors.backgroundCard)
        } footer: {
            Text(L10n.Settings.defaultServerNote)
                .font(AppTypography.labelSmall)
                .foregroundColor(AppColors.textTertiary)
        }
    }

    // MARK: - Computed Properties

    private var connectionTypeIcon: String {
        switch networkMonitor.connectionType {
        case .wifi:     return "wifi"
        case .cellular: return "antenna.radiowaves.left.and.right"
        case .wired:    return "cable.connector"
        case .unknown:  return "questionmark.circle"
        }
    }

    private var connectionTypeLabel: String {
        switch networkMonitor.connectionType {
        case .wifi:     return "Wi-Fi"
        case .cellular: return L10n.Settings.cellular
        case .wired:    return L10n.Settings.wired
        case .unknown:  return L10n.Error.unknown
        }
    }

    private var serverHostname: String {
        URL(string: preferences.blockbookURL)?.host ?? preferences.blockbookURL
    }

    // MARK: - Actions

    private func isURLValid(_ urlString: String) -> Bool {
        guard let url = URL(string: urlString) else { return false }
        return url.scheme?.lowercased() == "https" && url.host != nil
    }

    private func saveURL() {
        guard isURLValid(customURL) else { return }

        isURLFieldFocused = false
        preferences.blockbookURL = customURL
        connectionStatus = nil
        HapticManager.success()
        AppLogger.info("Blockbook server URL updated to: \(customURL)", category: .network)
    }

    private func testConnection() {
        guard isURLValid(customURL) else { return }

        isTestingConnection = true
        connectionStatus = nil

        // Build a simple health-check URL from the Blockbook base URL.
        let testURLString = customURL.hasSuffix("/")
            ? "\(customURL)api"
            : "\(customURL)/api"

        guard let testURL = URL(string: testURLString) else {
            connectionStatus = .failure(L10n.Error.network)
            isTestingConnection = false
            HapticManager.error()
            return
        }

        var request = URLRequest(url: testURL)
        request.timeoutInterval = Constants.requestTimeoutSeconds
        request.httpMethod = "GET"

        Task {
            do {
                let (_, httpResponse) = try await HTTPClient.shared.execute(request)
                await MainActor.run {
                    isTestingConnection = false
                    if (200..<300).contains(httpResponse.statusCode) {
                        connectionStatus = .success
                        HapticManager.success()
                        AppLogger.info("Connection test to \(customURL) succeeded", category: .network)
                    } else {
                        connectionStatus = .failure(
                            L10n.Settings.serverError + " (\(httpResponse.statusCode))"
                        )
                        HapticManager.error()
                        AppLogger.warning("Connection test to \(customURL) returned status \(httpResponse.statusCode)", category: .network)
                    }
                }
            } catch {
                await MainActor.run {
                    isTestingConnection = false
                    connectionStatus = .failure(error.localizedDescription)
                    HapticManager.error()
                    AppLogger.error("Connection test to \(customURL) failed: \(error.localizedDescription)", category: .network)
                }
            }
        }
    }

    private func resetToDefault() {
        customURL = Constants.defaultBlockbookURL
        preferences.blockbookURL = Constants.defaultBlockbookURL
        connectionStatus = nil
        HapticManager.success()
        AppLogger.info("Blockbook server URL reset to default", category: .network)
    }
}

// MARK: - Preview

#if DEBUG
struct NetworkSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            NetworkSettingsView()
        }
        .preferredColorScheme(.dark)
    }
}
#endif
