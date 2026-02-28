import Foundation
import SwiftUI

// MARK: - ProcessingStep
// A single step within a multi-step async operation.
// Uses localization keys for display labels.

struct ProcessingStep: Identifiable, Equatable {
    let id: UUID
    let labelKey: String
    var status: StepStatus

    var localizedLabel: String {
        localizedString(labelKey)
    }

    init(labelKey: String, status: StepStatus = .pending) {
        self.id = UUID()
        self.labelKey = labelKey
        self.status = status
    }
}

// MARK: - StepStatus

enum StepStatus: Equatable {
    case pending
    case active
    case completed
    case failed
}

// MARK: - ProcessingState
// Observable state for a multi-step async operation.
// Drives the AIProcessingIndicator with step progression, completion, and failure.

@MainActor
final class ProcessingState: ObservableObject {

    @Published var steps: [ProcessingStep]
    @Published private(set) var isComplete: Bool = false
    @Published private(set) var isFailed: Bool = false
    @Published private(set) var failureMessage: String?

    init(steps: [ProcessingStep]) {
        self.steps = steps
    }

    // MARK: - Actions

    /// Marks the first step as active and triggers a haptic.
    func start() {
        guard !steps.isEmpty else { return }
        steps[0].status = .active
        HapticManager.lightTap()
    }

    /// Marks the current active step as completed and advances to the next.
    /// Sets `isComplete` and triggers success haptic on the last step.
    func completeCurrentStep() {
        guard let activeIndex = steps.firstIndex(where: { $0.status == .active }) else { return }

        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            steps[activeIndex].status = .completed
        }

        let nextIndex = activeIndex + 1
        if nextIndex < steps.count {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                steps[nextIndex].status = .active
            }
            HapticManager.lightTap()
        } else {
            isComplete = true
            HapticManager.success()
        }
    }

    /// Marks the current active step as failed with an error message.
    func failCurrentStep(error: String? = nil) {
        guard let activeIndex = steps.firstIndex(where: { $0.status == .active }) else { return }

        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            steps[activeIndex].status = .failed
        }
        isFailed = true
        failureMessage = error
        HapticManager.error()
    }

    /// Resets a failed step back to active for retry.
    func retryFromFailedStep() {
        guard let failedIndex = steps.firstIndex(where: { $0.status == .failed }) else { return }

        isFailed = false
        failureMessage = nil
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            steps[failedIndex].status = .active
        }
        HapticManager.lightTap()
    }

    // MARK: - Computed

    /// A human-readable status message derived from the current state.
    var statusMessage: String {
        if isComplete {
            return L10n.Common.success
        }
        if isFailed {
            return failureMessage ?? L10n.Common.error
        }
        if let active = steps.first(where: { $0.status == .active }) {
            return active.localizedLabel
        }
        return L10n.Common.loading
    }
}
