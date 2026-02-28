import SwiftUI
import LocalAuthentication

// MARK: - AuthenticationSheet
// Modern bottom sheet for authentication. Tries Face ID / Touch ID first,
// then falls back to the app's 6-digit PIN entry.
//
// Usage:
//   .sheet(isPresented: $showAuth) {
//       AuthenticationSheet(
//           reason: "Authenticate to sign this transaction",
//           onSuccess: { handleSuccess() },
//           onCancel: { handleCancel() }
//       )
//   }
//
// NOTE: Do NOT use this for wallet creation/import — keep SetPasscodeView there.

struct AuthenticationSheet: View {

    // MARK: - Properties

    let reason: String
    let onSuccess: () -> Void
    let onCancel: () -> Void

    // MARK: - State

    @State private var enteredDigits: [Int] = []
    @State private var showError: Bool = false
    @State private var errorMessage: String = ""
    @State private var shakeOffset: CGFloat = 0
    @State private var biometricFailed: Bool = false
    @State private var isAuthenticating: Bool = false
    @State private var attemptsRemaining: Int = Constants.maxPasscodeAttempts
    @State private var isLockedOut: Bool = false
    @State private var lockoutEndTime: Date?

    @Environment(\.dismiss) private var dismiss

    // MARK: - Constants

    private let passcodeLength = 6
    /// Lockout duration in seconds after exceeding max attempts.
    private let lockoutDuration: TimeInterval = 30

    // MARK: - Biometric Info

    private var canUseBiometrics: Bool {
        BiometricAuth.shared.canUseBiometrics
    }

    private var biometricType: BiometricAuth.BiometricType {
        BiometricAuth.shared.biometricType
    }

    private var biometricIconName: String {
        switch biometricType {
        case .faceID: return AppIcons.faceID
        case .touchID: return AppIcons.touchID
        case .none: return AppIcons.faceID
        }
    }

    private var biometricName: String {
        switch biometricType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        case .none: return "Biometrics"
        }
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: .zero) {
            // Drag indicator
            dragIndicator

            if !biometricFailed && canUseBiometrics && !isAuthenticating {
                // Biometric prompt view
                biometricPromptView
            } else {
                // PIN entry view
                pinEntryView
            }
        }
        .background(AppColors.backgroundPrimary)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.hidden)
        .presentationCornerRadius(AppCornerRadius.xl)
        .interactiveDismissDisabled()
        .onAppear {
            if canUseBiometrics {
                attemptBiometric()
            }
        }
    }

    // MARK: - Drag Indicator

    private var dragIndicator: some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(AppColors.textTertiary.opacity(0.4))
            .frame(width: 36, height: 5)
            .padding(.top, AppSpacing.md)
            .padding(.bottom, AppSpacing.sm)
    }

    // MARK: - Biometric Prompt View

    private var biometricPromptView: some View {
        VStack(spacing: AppSpacing.xxl) {
            Spacer()

            // Icon
            ZStack {
                Circle()
                    .fill(AppColors.accentDim)
                    .frame(width: 80, height: 80)

                Image(systemName: biometricIconName)
                    .font(.system(size: 36, weight: .light))
                    .foregroundStyle(AppColors.accentGradient)
            }

            // Text
            VStack(spacing: AppSpacing.sm) {
                Text("Authenticate")
                    .font(AppTypography.headingLarge)
                    .foregroundColor(AppColors.textPrimary)

                Text(reason)
                    .font(AppTypography.bodyMedium)
                    .foregroundColor(AppColors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, AppSpacing.xl)
            }

            Spacer()

            // Buttons
            VStack(spacing: AppSpacing.md) {
                Button(action: attemptBiometric) {
                    Text("Use \(biometricName)")
                        .font(AppTypography.buttonLarge)
                        .foregroundColor(AppColors.textOnAccent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, AppSpacing.lg)
                        .background(AppColors.accentGradient)
                        .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.pill, style: .continuous))
                }
                .buttonStyle(.plain)

                Button(action: switchToPIN) {
                    Text("Use PIN Instead")
                        .font(AppTypography.buttonMedium)
                        .foregroundColor(AppColors.textSecondary)
                }
                .buttonStyle(.plain)

                Button(action: handleCancel) {
                    Text(L10n.Common.cancel)
                        .font(AppTypography.buttonMedium)
                        .foregroundColor(AppColors.textTertiary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, AppSpacing.xl)
            .padding(.bottom, AppSpacing.huge)
        }
    }

    // MARK: - PIN Entry View

    private var pinEntryView: some View {
        VStack(spacing: .zero) {
            Spacer()
                .frame(height: AppSpacing.xl)

            // Header
            VStack(spacing: AppSpacing.sm) {
                Image(systemName: AppIcons.lock)
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(AppColors.accentGradient)

                Text("Enter PIN")
                    .font(AppTypography.headingLarge)
                    .foregroundColor(AppColors.textPrimary)

                Text(reason)
                    .font(AppTypography.bodySmall)
                    .foregroundColor(AppColors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, AppSpacing.xl)
            }

            Spacer()
                .frame(height: AppSpacing.xxl)

            // Dot indicators
            dotIndicators
                .offset(x: shakeOffset)

            // Error message
            if showError {
                Text(errorMessage)
                    .font(AppTypography.bodySmall)
                    .foregroundColor(AppColors.error)
                    .padding(.top, AppSpacing.sm)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            Spacer()

            // Number pad
            numberPad

            // Bottom actions
            HStack {
                if canUseBiometrics {
                    Button(action: attemptBiometric) {
                        HStack(spacing: AppSpacing.xs) {
                            Image(systemName: biometricIconName)
                                .font(.system(size: 16))
                            Text(biometricName)
                                .font(AppTypography.buttonMedium)
                        }
                        .foregroundColor(AppColors.accent)
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                Button(action: handleCancel) {
                    Text(L10n.Common.cancel)
                        .font(AppTypography.buttonMedium)
                        .foregroundColor(AppColors.textSecondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, AppSpacing.xl)
            .padding(.bottom, AppSpacing.lg)
        }
    }

    // MARK: - Dot Indicators

    private var dotIndicators: some View {
        HStack(spacing: AppSpacing.lg) {
            ForEach(0..<passcodeLength, id: \.self) { index in
                Circle()
                    .fill(index < enteredDigits.count ? AppColors.accent : AppColors.backgroundTertiary)
                    .frame(width: 14, height: 14)
                    .overlay(
                        Circle()
                            .stroke(
                                index < enteredDigits.count ? AppColors.accent : AppColors.border,
                                lineWidth: 1.5
                            )
                    )
                    .scaleEffect(index < enteredDigits.count ? 1.1 : 1.0)
                    .animation(.easeOut(duration: 0.15), value: enteredDigits.count)
            }
        }
    }

    // MARK: - Number Pad

    private var numberPad: some View {
        VStack(spacing: AppSpacing.md) {
            numberPadRow([1, 2, 3])
            numberPadRow([4, 5, 6])
            numberPadRow([7, 8, 9])

            HStack(spacing: AppSpacing.md) {
                Color.clear
                    .frame(width: numberPadButtonSize, height: numberPadButtonSize)

                numberPadButton(digit: 0)

                deleteButton
            }
        }
        .padding(.horizontal, AppSpacing.xxxl)
    }

    private func numberPadRow(_ digits: [Int]) -> some View {
        HStack(spacing: AppSpacing.md) {
            ForEach(digits, id: \.self) { digit in
                numberPadButton(digit: digit)
            }
        }
    }

    private var numberPadButtonSize: CGFloat { 64 }

    private func numberPadButton(digit: Int) -> some View {
        Button(action: { enterDigit(digit) }) {
            Text("\(digit)")
                .font(AppTypography.displayMedium)
                .foregroundColor(AppColors.textPrimary)
                .frame(width: numberPadButtonSize, height: numberPadButtonSize)
                .background(AppColors.backgroundSecondary)
                .clipShape(Circle())
        }
        .buttonStyle(NumberPadButtonStyle())
    }

    private var deleteButton: some View {
        Button(action: deleteDigit) {
            Image(systemName: "delete.left")
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(AppColors.textPrimary)
                .frame(width: numberPadButtonSize, height: numberPadButtonSize)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Actions

    private func enterDigit(_ digit: Int) {
        guard enteredDigits.count < passcodeLength else { return }

        withAnimation(.easeOut(duration: 0.1)) {
            showError = false
            enteredDigits.append(digit)
        }

        if enteredDigits.count == passcodeLength {
            verifyPasscode()
        }
    }

    private func deleteDigit() {
        guard !enteredDigits.isEmpty else { return }
        withAnimation(.easeOut(duration: 0.1)) {
            showError = false
            enteredDigits.removeLast()
        }
    }

    private func verifyPasscode() {
        guard !isLockedOut else { return }

        let passcodeString = enteredDigits.map { String($0) }.joined()

        do {
            let storedHash = try KeychainManager.shared.read(key: .walletPasscodeHash)
            let storedSalt = try KeychainManager.shared.read(key: .walletSalt)

            if EncryptionHelper.verifyPasscode(passcodeString, against: storedHash, salt: storedSalt) {
                HapticManager.success()
                dismiss()
                onSuccess()
            } else {
                attemptsRemaining -= 1
                handleIncorrectPasscode()
            }
        } catch {
            errorMessage = "Unable to verify PIN. Please try again."
            withAnimation { showError = true }
            triggerShake()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                withAnimation { enteredDigits = [] }
            }
        }
    }

    private func handleIncorrectPasscode() {
        if attemptsRemaining <= 0 {
            // Enforce lockout
            isLockedOut = true
            lockoutEndTime = Date().addingTimeInterval(lockoutDuration)
            errorMessage = "Too many attempts. Locked for \(Int(lockoutDuration))s."
            AppLogger.warning("Passcode lockout triggered after \(Constants.maxPasscodeAttempts) failed attempts", category: .security)

            // Unlock after lockout duration
            DispatchQueue.main.asyncAfter(deadline: .now() + lockoutDuration) {
                isLockedOut = false
                lockoutEndTime = nil
                attemptsRemaining = Constants.maxPasscodeAttempts
                errorMessage = ""
                showError = false
            }
        } else {
            errorMessage = "Incorrect PIN. \(attemptsRemaining) attempts remaining."
        }

        withAnimation(.easeInOut(duration: 0.15)) {
            showError = true
        }
        HapticManager.error()
        triggerShake()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            withAnimation(.easeInOut(duration: 0.2)) {
                enteredDigits = []
            }
        }
    }

    private func attemptBiometric() {
        guard canUseBiometrics else {
            biometricFailed = true
            return
        }

        isAuthenticating = true

        Task { @MainActor in
            do {
                try await BiometricAuth.shared.authenticateForSigning()
                isAuthenticating = false
                HapticManager.success()
                dismiss()
                onSuccess()
            } catch let error as BiometricAuth.BiometricError {
                isAuthenticating = false
                switch error {
                case .userCancelled, .systemCancel:
                    // User cancelled -- switch to PIN
                    biometricFailed = true
                default:
                    biometricFailed = true
                }
            } catch {
                isAuthenticating = false
                biometricFailed = true
            }
        }
    }

    private func switchToPIN() {
        withAnimation(.easeInOut(duration: 0.3)) {
            biometricFailed = true
        }
    }

    private func handleCancel() {
        dismiss()
        onCancel()
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

// MARK: - Preview

#if DEBUG
struct AuthenticationSheet_Previews: PreviewProvider {
    static var previews: some View {
        Color.clear
            .sheet(isPresented: .constant(true)) {
                AuthenticationSheet(
                    reason: "Authenticate to sign this transaction",
                    onSuccess: {},
                    onCancel: {}
                )
            }
    }
}
#endif
