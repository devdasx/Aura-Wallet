// MARK: - BitcoinAIWalletApp.swift
// Bitcoin AI Wallet
//
// @main entry point for the Bitcoin AI Wallet iOS application.
// Configures the root scene, injects environment objects, and manages
// the top-level navigation state through AppRouter.
//
// Platform: iOS 17.0+
// Framework: SwiftUI
// Dependencies: System frameworks only
//
// References:
//   - AppRouter:            UI/Navigation/AppRouter.swift
//   - AppDelegate:          App/AppDelegate.swift
//   - AppColors:            Theme/AppColors.swift
//   - AppSpacing:           Theme/AppSpacing.swift
//   - AppCornerRadius:      Theme/AppCornerRadius.swift
//   - L10n:                 Localization/LocalizedStrings.swift
//   - LocalizationManager:  Localization/LocalizationManager.swift

import SwiftUI
import SwiftData

// MARK: - App Entry Point

@main
struct BitcoinAIWalletApp: App {

    // MARK: - UIKit Lifecycle Bridge

    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    // MARK: - State Objects

    @StateObject private var appRouter = AppRouter()
    @StateObject private var localizationManager = LocalizationManager.shared

    // MARK: - Scene

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appRouter)
                .environmentObject(localizationManager)
                .preferredColorScheme(appRouter.colorScheme)
                .modelContainer(for: [
                    Conversation.self,
                    PersistedMessage.self,
                    WalletAccountRecord.self,
                    TransactionRecord.self,
                    UTXORecord.self,
                    AddressRecord.self,
                    ContactRecord.self,
                    AlertRecord.self
                ])
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
                    appRouter.handleAppWillResignActive()
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                    appRouter.handleAppDidBecomeActive()
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                    appRouter.handleAppWillEnterForeground()
                }
                .onOpenURL { url in
                    appRouter.handleDeepLink(url)
                }
        }
    }
}

// MARK: - Root View

/// The root view that switches between onboarding, main wallet, and lock screen
/// based on the current navigation state managed by AppRouter.
struct RootView: View {
    @EnvironmentObject var appRouter: AppRouter

    var body: some View {
        Group {
            switch appRouter.currentScreen {
            case .onboarding:
                OnboardingView()
            case .main:
                WalletTabView()
            case .locked:
                LockScreenView()
            }
        }
        .animation(.easeInOut(duration: 0.3), value: appRouter.currentScreen)
    }
}

// MARK: - Lock Screen View

/// Displayed when the app is locked due to inactivity or returning from background.
/// Requires biometric authentication or manual unlock to proceed.
struct LockScreenView: View {
    @EnvironmentObject var appRouter: AppRouter
    @State private var isAuthenticating = false
    @State private var authError: String?
    @State private var showError = false
    @State private var lockIconScale: CGFloat = 0.8
    @State private var lockIconOpacity: Double = 0.0

    var body: some View {
        VStack(spacing: AppSpacing.xxxl) {
            Spacer()

            // MARK: Lock Icon

            Image(systemName: "lock.shield.fill")
                .font(.system(size: 64, weight: .thin))
                .foregroundStyle(AppColors.accentGradient)
                .scaleEffect(lockIconScale)
                .opacity(lockIconOpacity)
                .onAppear {
                    withAnimation(.easeOut(duration: 0.6)) {
                        lockIconScale = 1.0
                        lockIconOpacity = 1.0
                    }
                }

            // MARK: App Title

            VStack(spacing: AppSpacing.sm) {
                Text(L10n.Common.appName)
                    .font(.title2.bold())
                    .foregroundColor(AppColors.textPrimary)

                Text(L10n.LockScreen.subtitle)
                    .font(.subheadline)
                    .foregroundColor(AppColors.textSecondary)
            }

            Spacer()

            // MARK: Unlock Button

            Button(action: performAuthentication) {
                HStack(spacing: AppSpacing.md) {
                    if isAuthenticating {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: AppColors.textOnAccent))
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: lockScreenBiometricIcon)
                            .font(.system(size: 18, weight: .medium))
                    }
                    Text(L10n.LockScreen.unlockButton)
                        .font(.headline)
                }
                .foregroundColor(AppColors.textOnAccent)
                .frame(maxWidth: .infinity)
                .padding(.vertical, AppSpacing.lg)
                .background(AppColors.accentGradient)
                .cornerRadius(AppCornerRadius.pill)
            }
            .disabled(isAuthenticating)
            .padding(.horizontal, AppSpacing.xl)

            // MARK: Error Display

            if showError, let errorMessage = authError {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundColor(AppColors.error)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, AppSpacing.xl)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            Spacer()
                .frame(height: AppSpacing.huge)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColors.backgroundPrimary.ignoresSafeArea())
        .onAppear {
            // Auto-trigger authentication when lock screen appears
            Task {
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s delay
                performAuthentication()
            }
        }
    }

    // MARK: - Computed Properties

    /// Returns the appropriate SF Symbol name for the device's biometric type.
    private var lockScreenBiometricIcon: String {
        switch appRouter.biometricType {
        case .touchID:
            return "touchid"
        case .faceID:
            return "faceid"
        case .opticID:
            return "opticid"
        @unknown default:
            return "lock.fill"
        }
    }

    // MARK: - Authentication

    private func performAuthentication() {
        guard !isAuthenticating else { return }
        isAuthenticating = true
        showError = false
        authError = nil

        appRouter.authenticate { success, error in
            isAuthenticating = false
            if !success {
                authError = error ?? L10n.LockScreen.authFailed
                withAnimation(.easeInOut(duration: 0.3)) {
                    showError = true
                }
            }
        }
    }
}

// MARK: - Placeholder Views (replaced by other agents)

// OnboardingView is now implemented in UI/Onboarding/OnboardingView.swift

// MainWalletView is defined in UI/Main/MainWalletView.swift

// Lock screen localization keys are defined in L10n.LockScreen
// (see Localization/LocalizedStrings.swift)
// Bundle language switching is handled by LocalizationManager.shared.bundle
