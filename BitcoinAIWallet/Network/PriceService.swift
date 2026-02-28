// MARK: - PriceService.swift
// Bitcoin AI Wallet
//
// Fetches the current Bitcoin spot price from the Coinbase public API
// and provides BTC-to-fiat conversion for the user's selected currency.
//
// The service maintains a 60-second cache to avoid excessive API calls
// and publishes price updates via Combine (`@Published`) so SwiftUI
// views can reactively display fiat equivalents.
//
// Platform: iOS 17.0+
// Dependencies: Foundation, Combine (via ObservableObject)
// Concurrency: Swift Concurrency (async/await)

import Foundation
import os.log

// MARK: - Coinbase Response Models

/// Top-level response from the Coinbase spot price endpoint.
///
/// Endpoint: `GET https://api.coinbase.com/v2/prices/BTC-{CURRENCY}/spot`
///
/// Example response:
/// ```json
/// {"data":{"base":"BTC","currency":"USD","amount":"97000.00"}}
/// ```
struct CoinbasePriceResponse: Codable {
    let data: CoinbasePriceData
}

/// The nested price data returned by Coinbase.
///
/// - `base`: Always `"BTC"` for Bitcoin price queries.
/// - `currency`: The fiat currency code (e.g. `"USD"`, `"EUR"`).
/// - `amount`: The spot price as a decimal string (e.g. `"97000.00"`).
struct CoinbasePriceData: Codable {
    let base: String
    let currency: String
    let amount: String
}

// MARK: - PriceService

/// Fetches and caches the current Bitcoin spot price from Coinbase.
///
/// `PriceService` is a singleton observable object that SwiftUI views can
/// depend on to display live fiat equivalents for BTC balances and amounts.
///
/// The service caches the most recent price for 60 seconds to minimise
/// network usage while keeping displayed values reasonably fresh.
///
/// ```swift
/// let price = await PriceService.shared.fetchPrice(for: "USD")
/// let fiatValue = PriceService.shared.convertBTCToFiat(Decimal(0.5))
/// ```
final class PriceService: ObservableObject {

    // MARK: - Singleton

    /// The default shared instance for production use.
    static let shared = PriceService()

    // MARK: - Published Properties

    /// The most recently fetched Bitcoin price in the selected fiat currency,
    /// or `nil` if no price has been fetched yet.
    @Published var currentPrice: Decimal?

    /// The fiat currency code currently in use (e.g. `"USD"`, `"EUR"`).
    ///
    /// Changing this value does **not** automatically trigger a new fetch;
    /// call ``fetchPrice(for:)`` after updating to refresh the price.
    @Published var currencyCode: String = "USD"

    // MARK: - Private Properties

    /// The base URL for Coinbase spot price queries.
    ///
    /// The full endpoint is constructed by appending `BTC-{CURRENCY}/spot`
    /// to this base path.
    private let coinbaseBaseURL = "https://api.coinbase.com/v2/prices"

    /// The URL session used for all price fetches.
    private let session: URLSession

    /// Timestamp of the last successful price fetch.
    ///
    /// Used together with ``cacheDuration`` to decide whether a new
    /// network request is necessary.
    private var lastFetchTime: Date?

    /// The currency code that was used for the most recent cached price.
    ///
    /// If the caller requests a different currency, the cache is
    /// considered invalid regardless of its age.
    private var lastFetchedCurrency: String?

    /// Duration in seconds for which a fetched price is considered fresh.
    private let cacheDuration: TimeInterval = 60

    // MARK: - Initialization

    /// Creates a new price service.
    ///
    /// - Parameter session: The URL session to use for network requests.
    ///   Defaults to `.shared`. Pass a custom session in tests.
    init(session: URLSession = .shared) {
        self.session = session
    }

    // MARK: - Public API

    /// Fetch the current Bitcoin spot price for the given fiat currency.
    ///
    /// If a cached price for the same currency exists and is less than 60
    /// seconds old, the cached value is returned immediately without making
    /// a network request.
    ///
    /// On success the ``currentPrice`` and ``currencyCode`` published
    /// properties are updated on the main actor so SwiftUI views
    /// automatically reflect the new value.
    ///
    /// - Parameter currencyCode: An ISO 4217 currency code (e.g. `"USD"`,
    ///   `"EUR"`, `"GBP"`, `"JPY"`).
    /// - Returns: The spot price as a `Decimal`, or `nil` if the fetch failed.
    @discardableResult
    func fetchPrice(for currencyCode: String) async -> Decimal? {
        // Return cached price if still fresh and for the same currency
        if let cached = currentPrice,
           let lastTime = lastFetchTime,
           lastFetchedCurrency == currencyCode,
           Date().timeIntervalSince(lastTime) < cacheDuration {
            AppLogger.debug(
                "PriceService: returning cached price for BTC-\(currencyCode) (\(Int(Date().timeIntervalSince(lastTime)))s old)",
                category: .network
            )
            return cached
        }

        // Build the request URL
        let urlString = "\(coinbaseBaseURL)/BTC-\(currencyCode)/spot"

        guard let url = URL(string: urlString) else {
            AppLogger.error(
                "PriceService: invalid URL constructed: \(urlString)",
                category: .network
            )
            return nil
        }

        AppLogger.info(
            "PriceService: fetching BTC-\(currencyCode) spot price from Coinbase",
            category: .network
        )

        do {
            let (data, response) = try await session.data(from: url)

            // Validate HTTP status
            guard let httpResponse = response as? HTTPURLResponse else {
                AppLogger.error(
                    "PriceService: response is not an HTTPURLResponse",
                    category: .network
                )
                return nil
            }

            guard (200...299).contains(httpResponse.statusCode) else {
                AppLogger.error(
                    "PriceService: HTTP \(httpResponse.statusCode) for BTC-\(currencyCode)",
                    category: .network
                )
                return nil
            }

            // Decode the Coinbase response
            let decoded = try JSONDecoder().decode(CoinbasePriceResponse.self, from: data)

            // Parse the amount string into a Decimal
            guard let price = Decimal(string: decoded.data.amount) else {
                AppLogger.error(
                    "PriceService: failed to parse amount \"\(decoded.data.amount)\" as Decimal",
                    category: .network
                )
                return nil
            }

            // Update published state on the main actor
            await MainActor.run {
                self.currentPrice = price
                self.currencyCode = currencyCode
            }

            // Update cache metadata
            lastFetchTime = Date()
            lastFetchedCurrency = currencyCode

            AppLogger.info(
                "PriceService: BTC-\(currencyCode) spot price updated to \(decoded.data.amount)",
                category: .network
            )

            return price

        } catch let urlError as URLError {
            AppLogger.error(
                "PriceService: network error fetching BTC-\(currencyCode): \(urlError.localizedDescription)",
                category: .network
            )
            return nil

        } catch let decodingError as DecodingError {
            AppLogger.error(
                "PriceService: decoding error for BTC-\(currencyCode): \(decodingError.localizedDescription)",
                category: .network
            )
            return nil

        } catch {
            AppLogger.error(
                "PriceService: unexpected error fetching BTC-\(currencyCode): \(error.localizedDescription)",
                category: .network
            )
            return nil
        }
    }

    /// Convert a BTC amount to its fiat equivalent using the current cached price.
    ///
    /// If no price has been fetched yet (``currentPrice`` is `nil`), this
    /// method returns `Decimal.zero` rather than crashing.
    ///
    /// ```swift
    /// let fiat = PriceService.shared.convertBTCToFiat(Decimal(0.005))
    /// // If currentPrice is 97000, fiat == 485.00
    /// ```
    ///
    /// - Parameter btcAmount: The amount of Bitcoin to convert.
    /// - Returns: The equivalent value in the current fiat currency,
    ///   or `Decimal.zero` if no price is available.
    func convertBTCToFiat(_ btcAmount: Decimal) -> Decimal {
        guard let price = currentPrice else {
            AppLogger.warning(
                "PriceService: convertBTCToFiat called with no cached price; returning zero",
                category: .network
            )
            return Decimal.zero
        }
        return btcAmount * price
    }

    // MARK: - Currency Symbols

    /// Returns the symbol for a given ISO 4217 currency code.
    ///
    /// Covers the most commonly used fiat currencies. For unrecognised
    /// codes the code itself is returned as a fallback (e.g. `"CHF"`).
    ///
    /// ```swift
    /// PriceService.currencySymbol(for: "USD")  // "$"
    /// PriceService.currencySymbol(for: "EUR")  // "€"
    /// PriceService.currencySymbol(for: "XYZ")  // "XYZ"
    /// ```
    ///
    /// - Parameter code: An ISO 4217 currency code.
    /// - Returns: The corresponding currency symbol, or the code itself
    ///   if no symbol is known.
    static func currencySymbol(for code: String) -> String {
        switch code.uppercased() {
        case "USD": return "$"
        case "EUR": return "€"
        case "GBP": return "£"
        case "JPY": return "¥"
        case "CNY": return "¥"
        case "KRW": return "₩"
        case "INR": return "₹"
        case "RUB": return "₽"
        case "TRY": return "₺"
        case "BRL": return "R$"
        case "CAD": return "CA$"
        case "AUD": return "A$"
        case "CHF": return "CHF"
        case "SEK": return "kr"
        case "NOK": return "kr"
        case "DKK": return "kr"
        case "PLN": return "zł"
        case "THB": return "฿"
        case "MXN": return "MX$"
        case "ZAR": return "R"
        case "SGD": return "S$"
        case "HKD": return "HK$"
        case "NZD": return "NZ$"
        case "ILS": return "₪"
        case "ARS": return "ARS$"
        case "NGN": return "₦"
        case "PHP": return "₱"
        case "CZK": return "Kč"
        case "TWD": return "NT$"
        default:    return code
        }
    }
}
