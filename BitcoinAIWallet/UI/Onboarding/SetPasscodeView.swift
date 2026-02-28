import SwiftUI
import LocalAuthentication

// MARK: - SetPasscodeView
// Allows the user to set a 6-digit passcode to protect their wallet,
// then optionally enable biometric authentication (Face ID / Touch ID).
// The flow is: enter passcode -> confirm passcode -> biometric opt-in -> done.
//
// Platform: iOS 17.0+
// Dependencies: SwiftUI, LocalAuthentication

struct SetPasscodeView: View {

    // MARK: - Callbacks

    let onComplete: () -> Void

    // MARK: - State

    @State private var currentPhase: PasscodePhase = .enter
    @State private var enteredDigits: [Int] = []
    @State private var firstPasscode: [Int] = []
    @State private var showError: Bool = false
    @State private var errorMessage: String = ""
    @State private var shakeOffset: CGFloat = 0
    @State private var contentOpacity: Double = 0.0
    @State private var biometricEnabled: Bool = false

    // MARK: - Constants

    private let passcodeLength = 6

    // MARK: - Biometric Info

    private var biometricType: LABiometryType {
        let context = LAContext()
        var error: NSError?
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
        return context.biometryType
    }

    private var canUseBiometrics: Bool {
        let context = LAContext()
        var error: NSError?
        return context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
    }

    private var biometricIconName: String {
        switch biometricType {
        case .faceID:
            return AppIcons.faceID
        case .touchID:
            return AppIcons.touchID
        default:
            return AppIcons.faceID
        }
    }

    private var biometricName: String {
        switch biometricType {
        case .faceID:
            return L10n.Biometric.faceID
        case .touchID:
            return L10n.Biometric.touchID
        default:
            return L10n.Biometric.faceID
        }
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            AppColors.backgroundPrimary.ignoresSafeArea()

            VStack(spacing: .zero) {
                switch currentPhase {
                case .enter:
                    passcodeEntryContent(
                        title: L10n.Onboarding.setPasscodeTitle,
                        subtitle: L10n.Onboarding.setPasscodeSubtitle
                    )
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))

                case .confirm:
                    passcodeEntryContent(
                        title: L10n.Onboarding.confirmPasscode,
                        subtitle: L10n.Onboarding.confirmPasscodeSubtitle
                    )
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))

                case .biometric:
                    biometricOptIn
                        .transition(.asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal: .opacity
                        ))
                }
            }
            .animation(.easeInOut(duration: 0.3), value: currentPhase)
            .opacity(contentOpacity)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.5).delay(0.1)) {
                contentOpacity = 1.0
            }
        }
    }

    // MARK: - Passcode Entry Content

    private func passcodeEntryContent(title: String, subtitle: String) -> some View {
        VStack(spacing: .zero) {
            Spacer()
                .frame(height: AppSpacing.massive)

            // MARK: Header

            VStack(spacing: AppSpacing.md) {
                Image(systemName: AppIcons.lock)
                    .font(.system(size: 36, weight: .light))
                    .foregroundStyle(AppColors.accentGradient)

                Text(title)
                    .font(AppTypography.headingLarge)
                    .foregroundColor(AppColors.textPrimary)

                Text(subtitle)
                    .font(AppTypography.bodyMedium)
                    .foregroundColor(AppColors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, AppSpacing.xl)
            }

            Spacer()
                .frame(height: AppSpacing.xxxl)

            // MARK: Dot Indicators

            dotIndicators
                .offset(x: shakeOffset)

            // MARK: Error Message

            if showError {
                Text(errorMessage)
                    .font(AppTypography.bodySmall)
                    .foregroundColor(AppColors.error)
                    .padding(.top, AppSpacing.md)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            Spacer()

            // MARK: Number Pad

            numberPad

            Spacer()
                .frame(height: AppSpacing.huge)
        }
    }

    // MARK: - Dot Indicators

    private var dotIndicators: some View {
        HStack(spacing: AppSpacing.lg) {
            ForEach(0..<passcodeLength, id: \.self) { index in
                Circle()
                    .fill(index < enteredDigits.count ? AppColors.accent : AppColors.backgroundTertiary)
                    .frame(width: 16, height: 16)
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
        VStack(spacing: AppSpacing.lg) {
            // Row 1: 1, 2, 3
            numberPadRow([1, 2, 3])

            // Row 2: 4, 5, 6
            numberPadRow([4, 5, 6])

            // Row 3: 7, 8, 9
            numberPadRow([7, 8, 9])

            // Row 4: empty, 0, delete
            HStack(spacing: AppSpacing.lg) {
                // Empty spacer
                Color.clear
                    .frame(width: numberPadButtonSize, height: numberPadButtonSize)

                // 0 button
                numberPadButton(digit: 0)

                // Delete button
                deleteButton
            }
        }
        .padding(.horizontal, AppSpacing.xxxl)
    }

    private func numberPadRow(_ digits: [Int]) -> some View {
        HStack(spacing: AppSpacing.lg) {
            ForEach(digits, id: \.self) { digit in
                numberPadButton(digit: digit)
            }
        }
    }

    private var numberPadButtonSize: CGFloat { 72 }

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
                .font(.system(size: 20, weight: .medium))
                .foregroundColor(AppColors.textPrimary)
                .frame(width: numberPadButtonSize, height: numberPadButtonSize)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Biometric Opt-In

    private var biometricOptIn: some View {
        VStack(spacing: .zero) {
            Spacer()

            VStack(spacing: AppSpacing.xxl) {
                // Biometric Icon
                ZStack {
                    Circle()
                        .fill(AppColors.accentDim)
                        .frame(width: 100, height: 100)

                    Image(systemName: biometricIconName)
                        .font(.system(size: 44, weight: .light))
                        .foregroundStyle(AppColors.accentGradient)
                }

                // Prompt Text
                VStack(spacing: AppSpacing.md) {
                    Text(L10n.Onboarding.enableBiometrics)
                        .font(AppTypography.headingLarge)
                        .foregroundColor(AppColors.textPrimary)
                        .multilineTextAlignment(.center)

                    Text(String(format: L10n.Onboarding.enableBiometricsPrompt, biometricName))
                        .font(AppTypography.bodyMedium)
                        .foregroundColor(AppColors.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, AppSpacing.xl)
                }

                // Toggle
                HStack(spacing: AppSpacing.lg) {
                    Image(systemName: biometricIconName)
                        .font(AppTypography.bodyLarge)
                        .foregroundColor(AppColors.accent)

                    Text(biometricName)
                        .font(AppTypography.bodyLarge)
                        .foregroundColor(AppColors.textPrimary)

                    Spacer()

                    Toggle("", isOn: $biometricEnabled)
                        .tint(AppColors.accent)
                        .labelsHidden()
                }
                .padding(.horizontal, AppSpacing.xl)
                .padding(.vertical, AppSpacing.lg)
                .background(AppColors.backgroundSecondary)
                .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.large, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: AppCornerRadius.large, style: .continuous)
                        .stroke(AppColors.border, lineWidth: 1)
                )
                .padding(.horizontal, AppSpacing.xl)
            }

            Spacer()

            // MARK: Action Buttons

            VStack(spacing: AppSpacing.md) {
                // Enable / Continue button
                Button(action: completeBiometricSetup) {
                    Text(L10n.Common.next)
                        .font(AppTypography.buttonLarge)
                        .foregroundColor(AppColors.textOnAccent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, AppSpacing.lg)
                        .background(AppColors.accentGradient)
                        .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.pill, style: .continuous))
                }
                .buttonStyle(.plain)

                // Skip button
                Button(action: skipBiometrics) {
                    Text(L10n.Onboarding.skipForNow)
                        .font(AppTypography.buttonMedium)
                        .foregroundColor(AppColors.textSecondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, AppSpacing.xl)

            Spacer()
                .frame(height: AppSpacing.huge)
        }
    }

    // MARK: - Actions

    private func enterDigit(_ digit: Int) {
        guard enteredDigits.count < passcodeLength else { return }

        withAnimation(.easeOut(duration: 0.1)) {
            showError = false
            enteredDigits.append(digit)
        }

        // Check if all digits entered
        if enteredDigits.count == passcodeLength {
            handlePasscodeComplete()
        }
    }

    private func deleteDigit() {
        guard !enteredDigits.isEmpty else { return }
        withAnimation(.easeOut(duration: 0.1)) {
            showError = false
            enteredDigits.removeLast()
        }
    }

    private func handlePasscodeComplete() {
        switch currentPhase {
        case .enter:
            firstPasscode = enteredDigits
            // Brief delay before transitioning to confirm
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                withAnimation(.easeInOut(duration: 0.3)) {
                    enteredDigits = []
                    currentPhase = .confirm
                }
            }

        case .confirm:
            if enteredDigits == firstPasscode {
                // Passcodes match - save passcode and proceed
                savePasscode(enteredDigits)

                if canUseBiometrics {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            currentPhase = .biometric
                        }
                    }
                } else {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                        onComplete()
                    }
                }
            } else {
                // Mismatch - show error and reset
                errorMessage = L10n.Onboarding.passcodeMismatch
                withAnimation(.easeInOut(duration: 0.15)) {
                    showError = true
                }
                triggerShake()

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        enteredDigits = []
                        firstPasscode = []
                        currentPhase = .enter
                        showError = false
                    }
                }
            }

        case .biometric:
            break
        }
    }

    private func savePasscode(_ digits: [Int]) {
        let passcodeString = digits.map { String($0) }.joined()

        do {
            // Generate a cryptographic salt for this passcode
            let salt = EncryptionHelper.generateSalt()

            // Hash the passcode with the salt (iterated SHA-256, 100k rounds)
            let hash = EncryptionHelper.hashPasscode(passcodeString, salt: salt)

            // Store the hash and salt in the Keychain (never the plaintext)
            try KeychainManager.shared.save(key: .walletPasscodeHash, data: hash)
            try KeychainManager.shared.save(key: .walletSalt, data: salt)

            UserDefaults.standard.set(true, forKey: "has_passcode_set")
        } catch {
            AppLogger.error("Failed to save passcode hash: \(error.localizedDescription)", category: .security)
        }
    }

    private func completeBiometricSetup() {
        if biometricEnabled {
            UserDefaults.standard.set(true, forKey: "biometric_lock_enabled")
        } else {
            UserDefaults.standard.set(false, forKey: "biometric_lock_enabled")
        }
        onComplete()
    }

    private func skipBiometrics() {
        UserDefaults.standard.set(false, forKey: "biometric_lock_enabled")
        onComplete()
    }

    private func triggerShake() {
        withAnimation(.default) { shakeOffset = 12 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            withAnimation(.default) { shakeOffset = -10 }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
            withAnimation(.default) { shakeOffset = 8 }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.24) {
            withAnimation(.default) { shakeOffset = -5 }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) {
            withAnimation(.default) { shakeOffset = 0 }
        }
    }

    // MARK: - Passcode Phase

    enum PasscodePhase: Equatable {
        case enter
        case confirm
        case biometric
    }
}

// MARK: - NumberPadButtonStyle

/// Custom button style for number pad buttons that provides
/// a subtle press feedback effect without the default highlight.
struct NumberPadButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1.0)
            .opacity(configuration.isPressed ? 0.7 : 1.0)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

// MARK: - Preview

#if DEBUG
struct SetPasscodeView_Previews: PreviewProvider {
    static var previews: some View {
        SetPasscodeView(onComplete: {})
    }
}
#endif
