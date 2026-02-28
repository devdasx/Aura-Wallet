import Foundation
import UIKit

// MARK: - TypingAnimator
// Character-by-character text reveal animation for AI responses.
// Simulates a streaming/typing effect similar to Claude's interface.
//
// Features:
//   - Variable speed: pauses longer after punctuation (. ! ? , \n)
//   - Haptic pulses every ~5 characters (per-word feel)
//   - Tap to skip: instantly reveals the full text
//   - Only animates new messages (old messages from history show instantly)
//   - Respects UserPreferences.shared.typingHapticsEnabled
//
// Usage:
//   let animator = TypingAnimator()
//   animator.startTyping("Hello, world!")
//   // animator.displayedText updates progressively
//   animator.skipToEnd()  // instant reveal
//
// Platform: iOS 17.0+
// Framework: Foundation, UIKit (haptics)

@MainActor
final class TypingAnimator: ObservableObject {

    // MARK: - Published Properties

    /// The progressively revealed text — bind to a Text view.
    @Published var displayedText: String = ""

    /// Whether the typing animation is currently active.
    @Published var isAnimating: Bool = false

    // MARK: - Private State

    /// The complete text to reveal.
    private var fullText: String = ""

    /// The active typing task.
    private var typingTask: Task<Void, Never>?

    // MARK: - Configuration

    /// Base characters per second. ~80 cps feels like fast, fluid typing.
    private let charsPerSecond: Double = 80

    /// Number of characters between haptic pulses.
    private let hapticInterval: Int = 5

    /// Number of characters between scroll notifications.
    private let scrollNotifyInterval: Int = 10

    // MARK: - Public API

    /// Start typing out the given text character by character.
    ///
    /// Any existing animation is cancelled before starting.
    ///
    /// - Parameter text: The full text to reveal progressively.
    func startTyping(_ text: String) {
        // Cancel any existing animation
        typingTask?.cancel()

        fullText = text
        displayedText = ""
        isAnimating = true

        typingTask = Task { [weak self] in
            guard let self = self else { return }

            let baseInterval = 1.0 / self.charsPerSecond
            var charCount = 0

            for char in text {
                guard !Task.isCancelled else { break }

                self.displayedText.append(char)
                charCount += 1

                // Haptic pulse every ~5 characters
                if charCount % self.hapticInterval == 0 {
                    self.triggerTypingHaptic()
                }

                // Notify ChatView to auto-scroll every ~10 characters
                if charCount % self.scrollNotifyInterval == 0 {
                    NotificationCenter.default.post(name: .typingAnimationProgress, object: nil)
                }

                // Variable delay based on punctuation
                let delay: Double
                switch char {
                case ".", "!", "?":
                    delay = baseInterval * 6   // Sentence-end pause
                case ",", ":", ";":
                    delay = baseInterval * 3   // Clause pause
                case "\n":
                    delay = baseInterval * 8   // Line break pause
                default:
                    delay = baseInterval
                }

                try? await Task.sleep(for: .seconds(delay))
            }

            if !Task.isCancelled {
                self.isAnimating = false
            }
        }
    }

    /// Instantly reveal the full text, cancelling any active animation.
    func skipToEnd() {
        typingTask?.cancel()
        displayedText = fullText
        isAnimating = false
    }

    /// Show text instantly with no animation (for loaded history messages).
    func showInstantly(_ text: String) {
        typingTask?.cancel()
        fullText = text
        displayedText = text
        isAnimating = false
    }

    // MARK: - Haptics

    /// Trigger a very subtle haptic pulse during typing.
    private func triggerTypingHaptic() {
        guard UserPreferences.shared.typingHapticsEnabled else { return }
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.prepare()
        generator.impactOccurred(intensity: 0.3)
    }
}
