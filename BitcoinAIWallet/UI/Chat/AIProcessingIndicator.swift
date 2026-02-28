import SwiftUI

// MARK: - AIProcessingIndicator
// Minimal inline processing indicator that sits inside a standard AI chat bubble.
// Shows a spinning arc + status text that crossfades between steps.
// Replaces the old AIProcessingCard with a single-line "thinking" style indicator.

struct AIProcessingIndicator: View {
    @ObservedObject var processingState: ProcessingState

    @State private var isRotating = false

    var body: some View {
        HStack(spacing: AppSpacing.sm) {
            // 24x24 animation frame
            indicatorIcon
                .frame(width: 24, height: 24)

            // Status text with crossfade
            Text(processingState.statusMessage)
                .font(AppTypography.bodyMedium)
                .foregroundColor(statusColor)
                .id(processingState.statusMessage)
                .transition(.opacity)
                .animation(.easeInOut(duration: 0.2), value: processingState.statusMessage)

            // Retry button on failure
            if processingState.isFailed {
                Button {
                    HapticManager.buttonTap()
                    processingState.retryFromFailedStep()
                } label: {
                    Text(L10n.Common.retry)
                        .font(AppTypography.buttonSmall)
                        .foregroundColor(AppColors.accent)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, AppSpacing.sm)
    }

    // MARK: - Indicator Icon

    @ViewBuilder
    private var indicatorIcon: some View {
        if processingState.isComplete {
            Image(systemName: AppIcons.success)
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(AppColors.success)
                .transition(.opacity)
        } else if processingState.isFailed {
            Image(systemName: AppIcons.error)
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(AppColors.error)
                .transition(.opacity)
        } else {
            Circle()
                .trim(from: 0, to: 0.7)
                .stroke(AppColors.accent, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .frame(width: 18, height: 18)
                .rotationEffect(.degrees(isRotating ? 360 : 0))
                .onAppear {
                    withAnimation(.linear(duration: 1.0).repeatForever(autoreverses: false)) {
                        isRotating = true
                    }
                }
        }
    }

    // MARK: - Status Color

    private var statusColor: Color {
        if processingState.isComplete { return AppColors.success }
        if processingState.isFailed { return AppColors.error }
        return AppColors.textPrimary
    }
}

// MARK: - Preview

#if DEBUG
struct AIProcessingIndicator_Previews: PreviewProvider {
    static var previews: some View {
        let state = ProcessingConfigurations.walletRefresh()
        VStack(spacing: AppSpacing.lg) {
            AIProcessingIndicator(processingState: state)
        }
        .padding(AppSpacing.lg)
        .background(AppColors.backgroundPrimary)
        .preferredColorScheme(.dark)
        .previewLayout(.sizeThatFits)
        .onAppear { state.start() }
    }
}
#endif
