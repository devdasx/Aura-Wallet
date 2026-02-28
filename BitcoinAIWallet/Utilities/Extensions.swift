import SwiftUI

// MARK: - Extensions
// Common Swift and SwiftUI extensions used across the Bitcoin AI Wallet.
// Provides formatting helpers, data conversions, and view modifiers
// that are shared by multiple features.

// MARK: - String Extensions

extension String {

    /// Truncates the string in the middle, preserving the first and last characters.
    ///
    /// Useful for displaying Bitcoin addresses and transaction IDs in a compact form.
    ///
    /// ```swift
    /// "bc1qxy2kgdygjrsqtzq2n0yrf2493p83kkfjhx0wlh".truncatedMiddle()
    /// // => "bc1qxy2kgdygjr...3kkfjhx0wlh"
    /// ```
    ///
    /// - Parameter maxLength: The maximum length of the returned string (default 20).
    ///   If the string is shorter than or equal to `maxLength`, it is returned unchanged.
    /// - Returns: The truncated string with an ellipsis in the middle.
    func truncatedMiddle(maxLength: Int = 20) -> String {
        guard count > maxLength else { return self }
        let headCount = (maxLength - 3) / 2
        let tailCount = maxLength - 3 - headCount
        let head = prefix(headCount)
        let tail = suffix(tailCount)
        return "\(head)...\(tail)"
    }

    /// Whether the string is a valid hexadecimal representation.
    ///
    /// Returns `true` for strings composed entirely of characters in `[0-9a-fA-F]`
    /// with an even length (complete byte pairs). Empty strings return `false`.
    var isValidHex: Bool {
        guard !isEmpty, count % 2 == 0 else { return false }
        return allSatisfy { $0.isHexDigit }
    }

    /// Converts a hexadecimal string to `Data`.
    ///
    /// Returns `nil` if the string is not valid hex.
    var hexToData: Data? {
        guard isValidHex else { return nil }
        var data = Data(capacity: count / 2)
        var index = startIndex
        while index < endIndex {
            let nextIndex = self.index(index, offsetBy: 2)
            guard let byte = UInt8(self[index..<nextIndex], radix: 16) else {
                return nil
            }
            data.append(byte)
            index = nextIndex
        }
        return data
    }
}

// MARK: - Data Extensions

extension Data {

    /// Converts the data to a lowercase hexadecimal string.
    ///
    /// ```swift
    /// Data([0xDE, 0xAD, 0xBE, 0xEF]).hexString // => "deadbeef"
    /// ```
    var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }

    /// Initializes `Data` from a hexadecimal string.
    ///
    /// Returns `nil` if the string is not valid hex.
    ///
    /// - Parameter hex: A hexadecimal string (e.g. "deadbeef").
    init?(hex: String) {
        guard let data = hex.hexToData else { return nil }
        self = data
    }
}

// MARK: - Decimal Extensions

extension Decimal {

    /// Formats the decimal as a BTC amount with 8 decimal places.
    ///
    /// ```swift
    /// Decimal(string: "0.001")!.formattedBTC // => "0.00100000"
    /// ```
    var formattedBTC: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 8
        formatter.maximumFractionDigits = 8
        formatter.groupingSeparator = ","
        formatter.decimalSeparator = "."
        return formatter.string(from: self as NSDecimalNumber) ?? "0.00000000"
    }

    /// Formats the decimal as a fiat currency amount.
    ///
    /// ```swift
    /// Decimal(string: "1234.56")!.formattedFiat(currency: "USD") // => "$1,234.56"
    /// ```
    ///
    /// - Parameter currency: ISO 4217 currency code (default "USD").
    /// - Returns: A locale-aware formatted currency string.
    func formattedFiat(currency: String = "USD") -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: self as NSDecimalNumber) ?? "$0.00"
    }

    /// Converts a BTC amount to satoshis.
    ///
    /// ```swift
    /// Decimal(string: "0.001")!.satoshis // => 100_000
    /// ```
    var satoshis: Int64 {
        let sats = self * Constants.satoshisPerBTC
        return NSDecimalNumber(decimal: sats).int64Value
    }

    /// Creates a `Decimal` BTC amount from a satoshi count.
    ///
    /// ```swift
    /// Decimal.fromSatoshis(100_000) // => 0.001
    /// ```
    ///
    /// - Parameter sats: The amount in satoshis.
    /// - Returns: The equivalent BTC amount as a `Decimal`.
    static func fromSatoshis(_ sats: Int64) -> Decimal {
        Decimal(sats) / Constants.satoshisPerBTC
    }
}

// MARK: - Date Extensions

extension Date {

    /// Returns a human-readable relative time string.
    ///
    /// Examples: "Just now", "5m ago", "2h ago", "Yesterday", "Feb 15"
    var relativeString: String {
        let now = Date()
        let interval = now.timeIntervalSince(self)

        if interval < 60 {
            return NSLocalizedString("date.just_now", comment: "Just now")
        } else if interval < 3600 {
            let minutes = Int(interval / 60)
            return String(format: NSLocalizedString("date.minutes_ago", comment: "%dm ago"), minutes)
        } else if interval < 86400 {
            let hours = Int(interval / 3600)
            return String(format: NSLocalizedString("date.hours_ago", comment: "%dh ago"), hours)
        } else if Calendar.current.isDateInYesterday(self) {
            return NSLocalizedString("date.yesterday", comment: "Yesterday")
        } else if interval < 604800 {
            let days = Int(interval / 86400)
            return String(format: NSLocalizedString("date.days_ago", comment: "%dd ago"), days)
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = Calendar.current.isDate(self, equalTo: now, toGranularity: .year)
                ? "MMM d"
                : "MMM d, yyyy"
            return formatter.string(from: self)
        }
    }

    /// Formats the date for display in transaction lists.
    ///
    /// Uses a medium date style and short time style for clarity.
    /// Example: "Feb 15, 2026 at 3:42 PM"
    var transactionDateString: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: self)
    }
}

// MARK: - View Extensions

extension View {

    /// Applies a transformation only when the condition is true.
    ///
    /// ```swift
    /// Text("Hello")
    ///     .if(isHighlighted) { $0.foregroundColor(.red) }
    /// ```
    ///
    /// - Parameters:
    ///   - condition: The boolean condition to evaluate.
    ///   - transform: A closure that transforms the view when the condition is true.
    /// - Returns: The original view or the transformed view.
    @ViewBuilder
    func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }

    /// Dismisses the keyboard by resigning the first responder.
    func hideKeyboard() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
    }

    /// Applies the standard card appearance used throughout the app.
    ///
    /// Sets the card background color, corner radius, and a subtle border.
    func cardStyle() -> some View {
        self
            .background(AppColors.backgroundCard)
            .cornerRadius(AppCornerRadius.xl)
            .overlay(
                RoundedRectangle(cornerRadius: AppCornerRadius.xl)
                    .stroke(AppColors.border, lineWidth: 1)
            )
    }
}

// MARK: - ShapeStyle Extension

extension ShapeStyle where Self == Color {

    /// Convenient shorthand for the app accent color.
    static var appAccent: Color { AppColors.accent }
}
