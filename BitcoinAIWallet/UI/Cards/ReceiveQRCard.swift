import SwiftUI
import CoreImage.CIFilterBuiltins

// MARK: - ReceiveQRCard
// Inline chat card that displays a QR code and Bitcoin receive address.
// Allows copy and share actions. QR is generated using CoreImage.

struct ReceiveQRCard: View {
    let address: String
    let addressType: String
    let onCopy: () -> Void
    let onShare: () -> Void

    // MARK: - Body

    var body: some View {
        VStack(spacing: AppSpacing.lg) {
            headerRow
            Divider().background(AppColors.border)
            qrCodeSection
            addressSection
            addressTypeLabel
            Divider().background(AppColors.border)
            actionButtons
            privacyNote
        }
        .padding(AppSpacing.xl)
        .background(AppColors.backgroundCard)
        .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.xl, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppCornerRadius.xl, style: .continuous)
                .stroke(AppColors.border, lineWidth: 1)
        )
    }

    // MARK: - Header

    private var headerRow: some View {
        HStack {
            Text(L10n.Receive.title)
                .font(AppTypography.headingLarge)
                .foregroundColor(AppColors.textPrimary)

            Spacer()

            Image(systemName: AppIcons.receive)
                .font(AppTypography.headingLarge)
                .foregroundColor(AppColors.accent)
        }
    }

    // MARK: - QR Code

    private var qrCodeSection: some View {
        ZStack {
            RoundedRectangle(cornerRadius: AppCornerRadius.large, style: .continuous)
                .fill(Color.white) // QR codes require white background for scannability
                .frame(width: 180, height: 180)

            if let qrImage = generateQRCode(from: address) {
                Image(uiImage: qrImage)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 160, height: 160)
            } else {
                Image(systemName: AppIcons.qrCode)
                    .font(.system(size: AppSpacing.huge))
                    .foregroundColor(AppColors.textTertiary)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Address Display

    private var addressSection: some View {
        Text(address)
            .font(AppTypography.monoMedium)
            .foregroundColor(AppColors.textPrimary)
            .multilineTextAlignment(.center)
            .lineSpacing(AppSpacing.xxs)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, AppSpacing.sm)
    }

    // MARK: - Address Type Label

    private var addressTypeLabel: some View {
        Text(addressType)
            .font(AppTypography.labelMedium)
            .foregroundColor(AppColors.accent)
            .padding(.horizontal, AppSpacing.sm)
            .padding(.vertical, AppSpacing.xxxs)
            .background(AppColors.accentDim)
            .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.small, style: .continuous))
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        HStack(spacing: AppSpacing.md) {
            Button(action: onCopy) {
                HStack(spacing: AppSpacing.xs) {
                    Image(systemName: AppIcons.copy)
                        .font(AppTypography.labelMedium)

                    Text(L10n.Common.copy)
                        .font(AppTypography.buttonMedium)
                }
                .foregroundColor(AppColors.textPrimary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, AppSpacing.md)
                .background(AppColors.backgroundCard)
                .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.large, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: AppCornerRadius.large, style: .continuous)
                        .stroke(AppColors.border, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)

            Button(action: onShare) {
                HStack(spacing: AppSpacing.xs) {
                    Image(systemName: AppIcons.share)
                        .font(AppTypography.labelMedium)

                    Text(L10n.Common.share)
                        .font(AppTypography.buttonMedium)
                }
                .foregroundColor(AppColors.textOnAccent)
                .frame(maxWidth: .infinity)
                .padding(.vertical, AppSpacing.md)
                .background(AppColors.accentGradient)
                .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.large, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Privacy Note

    private var privacyNote: some View {
        Text(L10n.Chat.newAddressNote)
            .font(AppTypography.labelSmall)
            .foregroundColor(AppColors.textTertiary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
    }

    // MARK: - QR Code Generation

    private func generateQRCode(from string: String) -> UIImage? {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"
        guard let outputImage = filter.outputImage else { return nil }
        let scaled = outputImage.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

// MARK: - Preview

#if DEBUG
struct ReceiveQRCard_Previews: PreviewProvider {
    static var previews: some View {
        ReceiveQRCard(
            address: "bc1p5cyxnuxmeuwuvkwfem96lqzszee02v3tg0eh9gqeqgr2hrs2ceqy5yqth",
            addressType: "Taproot",
            onCopy: {},
            onShare: {}
        )
        .padding(AppSpacing.lg)
        .background(AppColors.backgroundPrimary)
        .previewLayout(.sizeThatFits)
    }
}
#endif
