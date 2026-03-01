// MARK: - FeeEstimator.swift
// Bitcoin AI Wallet
//
// Estimates Bitcoin transaction fees using a two-tier approach:
//   PRIMARY: mempool.space /api/v1/fees/recommended (returns sat/vB directly)
//   FALLBACK: Blockbook /api/v2/estimatefee/<blocks> (returns BTC/kB, converted)
//
// Three speed tiers: fast (~1 block), medium (~2 blocks), slow (~6 blocks).
// Caches results for 5 minutes. Publishes state via @Published for SwiftUI.
//
// Platform: iOS 17.0+
// Dependencies: Foundation, Combine (via ObservableObject)

import Foundation
import os.log

// MARK: - FeeEstimatorProtocol

/// Public interface for fee estimation.
///
/// Consumers depend on this protocol rather than the concrete ``FeeEstimator``
/// to allow dependency injection and testability.
protocol FeeEstimatorProtocol {

    /// Fetch fee estimates for all three speed tiers (slow, medium, fast).
    ///
    /// - Returns: A ``FeeEstimates`` containing rates for each tier and a freshness timestamp.
    /// - Throws: ``APIError`` when all underlying API calls fail.
    func estimateFees() async throws -> FeeEstimates

    /// Estimate the fee rate for a single target block count.
    ///
    /// - Parameter blocks: Number of blocks within which confirmation is desired.
    /// - Returns: The estimated fee rate in sat/vB as a `Decimal`.
    /// - Throws: ``APIError`` on failure.
    func estimateFee(for blocks: Int) async throws -> Decimal

    /// Calculate the total transaction fee in satoshis.
    ///
    /// - Parameters:
    ///   - virtualSize: The transaction's virtual size in vBytes.
    ///   - feeRate: The fee rate in sat/vB.
    /// - Returns: The total fee in satoshis.
    func calculateTransactionFee(virtualSize: Int, feeRate: Decimal) -> Decimal
}

// MARK: - FeeEstimates

/// A snapshot of fee rates across three confirmation speed tiers.
///
/// Each estimate includes the sat/vB rate, the target block count, and the
/// approximate wait time in minutes. Check ``isStale`` to decide whether
/// to refresh before presenting to the user.
struct FeeEstimates: Sendable {

    /// Economy tier: targets confirmation within ~6 blocks (~60 minutes).
    let slow: FeeRate

    /// Standard tier: targets confirmation within ~2 blocks (~20 minutes).
    let medium: FeeRate

    /// Priority tier: targets confirmation within ~1 block (~10 minutes).
    let fast: FeeRate

    /// The time at which these estimates were fetched.
    let timestamp: Date

    /// Whether these estimates are older than 5 minutes and should be refreshed.
    ///
    /// Fee rates can change rapidly, especially during periods of high demand.
    /// A staleness window of 5 minutes balances freshness against API load.
    var isStale: Bool {
        Date().timeIntervalSince(timestamp) > 300
    }

    /// The age of these estimates in seconds.
    var ageInSeconds: TimeInterval {
        Date().timeIntervalSince(timestamp)
    }
}

// MARK: - FeeRate

/// A fee rate for a specific confirmation speed tier.
///
/// Encapsulates the sat/vB rate alongside the target block count and
/// estimated wait time. Provides convenience methods for computing
/// the total fee for a given transaction size.
struct FeeRate: Sendable {

    /// Fee rate in satoshis per virtual byte.
    let satPerVByte: Decimal

    /// Number of blocks targeted for confirmation.
    let estimatedBlocks: Int

    /// Approximate wait time in minutes for confirmation at this rate.
    let estimatedMinutes: Int

    // MARK: - Fee Calculation

    /// Calculate the total fee in satoshis for a transaction of the given virtual size.
    ///
    /// - Parameter vsize: The transaction's virtual size in vBytes.
    /// - Returns: Total fee in satoshis (sat/vB * vsize).
    func feeForSize(_ vsize: Int) -> Decimal {
        satPerVByte * Decimal(vsize)
    }

    /// Calculate the total fee in BTC for a transaction of the given virtual size.
    ///
    /// - Parameter vsize: The transaction's virtual size in vBytes.
    /// - Returns: Total fee in BTC (fee_sats / 100,000,000).
    func feeInBTC(_ vsize: Int) -> Decimal {
        feeForSize(vsize) / Decimal(100_000_000)
    }

    /// A human-readable description of this fee rate and its confirmation target.
    var displayDescription: String {
        let roundedRate = NSDecimalNumber(decimal: satPerVByte).rounding(accordingToBehavior: nil)
        return "\(roundedRate) sat/vB (~\(estimatedMinutes) min)"
    }
}

// MARK: - FeeEstimator

/// Fetches and caches Bitcoin fee estimates from a Blockbook API backend.
///
/// The estimator queries Blockbook's `/api/v2/estimatefee/<blocks>` endpoint
/// for three confirmation targets (1, 2, and 6 blocks), converts the returned
/// BTC/kB values to sat/vB, and publishes the results via `@Published` properties
/// for SwiftUI observation.
///
/// ```swift
/// let estimator = FeeEstimator(blockbookAPI: blockbook)
/// let fees = try await estimator.estimateFees()
/// print("Fast: \(fees.fast.satPerVByte) sat/vB")
/// ```
final class FeeEstimator: FeeEstimatorProtocol, ObservableObject {

    // MARK: - Published Properties

    /// The most recently fetched fee estimates, or `nil` if no fetch has completed yet.
    @Published var currentEstimates: FeeEstimates?

    /// Whether a fee estimation request is currently in flight.
    @Published var isLoading: Bool = false

    /// The most recent error encountered during fee estimation, if any.
    @Published var lastError: Error?

    // MARK: - Private Properties

    /// The Blockbook API client used to fetch raw fee rate data.
    private let blockbookAPI: BlockbookAPIProtocol

    /// Logger for fee estimation diagnostics.
    private let logger = Logger(subsystem: "com.bitcoinai.wallet", category: "FeeEstimator")

    /// Minimum fee rate in sat/vB.
    ///
    /// Many nodes enforce a minimum relay fee of 1-3 sat/vB.
    /// Using 3 as floor to avoid "min relay fee not met" rejections.
    private let minimumFeeRate: Decimal = 3

    /// Fallback fee rate for the slow tier (6-block target) when all APIs are unreachable.
    private let fallbackSlow: Decimal = 8

    /// Fallback fee rate for the medium tier (2-block target) when all APIs are unreachable.
    private let fallbackMedium: Decimal = 20

    /// Fallback fee rate for the fast tier (1-block target) when all APIs are unreachable.
    private let fallbackFast: Decimal = 40

    /// mempool.space API URL for recommended fees.
    private let mempoolFeeURL = "https://mempool.space/api/v1/fees/recommended"

    // MARK: - Initialization

    /// Create a fee estimator backed by a Blockbook API client.
    ///
    /// - Parameter blockbookAPI: The Blockbook client to query for fee estimates.
    init(blockbookAPI: BlockbookAPIProtocol) {
        self.blockbookAPI = blockbookAPI
    }

    // MARK: - Public API

    /// Fetch fee estimates for all three speed tiers in parallel.
    ///
    /// This method queries Blockbook for 1-block, 2-block, and 6-block confirmation
    /// targets simultaneously using structured concurrency. The results are converted
    /// from BTC/kB to sat/vB, clamped to the minimum fee rate, and packaged into
    /// a ``FeeEstimates`` value.
    ///
    /// If any individual tier fails, its fallback rate is used so that the method
    /// returns a complete set of estimates whenever possible. The method only throws
    /// if all three tiers fail.
    ///
    /// - Returns: A ``FeeEstimates`` snapshot containing rates for slow, medium, and fast tiers.
    /// - Throws: ``APIError`` when all three tier queries fail.
    @discardableResult
    func estimateFees() async throws -> FeeEstimates {
        await MainActor.run {
            self.isLoading = true
            self.lastError = nil
        }
        defer {
            Task { @MainActor in
                self.isLoading = false
            }
        }

        logger.info("Fetching fee estimates...")

        // PRIMARY: Try mempool.space first (returns sat/vB directly, no conversion)
        if let mempoolEstimates = await fetchMempoolFees() {
            logger.info("Using mempool.space fees: fast=\(mempoolEstimates.fast.satPerVByte) med=\(mempoolEstimates.medium.satPerVByte) slow=\(mempoolEstimates.slow.satPerVByte) sat/vB")
            await MainActor.run { self.currentEstimates = mempoolEstimates }
            return mempoolEstimates
        }

        logger.warning("mempool.space failed, falling back to Blockbook...")

        // FALLBACK: Blockbook API (BTC/kB → sat/vB conversion)
        var fastRate: Decimal = fallbackFast
        var mediumRate: Decimal = fallbackMedium
        var slowRate: Decimal = fallbackSlow
        var failureCount = 0

        await withTaskGroup(of: (Int, Decimal?, Error?).self) { group in
            group.addTask { [self] in
                do {
                    let rate = try await self.estimateFee(for: 1)
                    return (1, rate, nil)
                } catch {
                    return (1, nil, error)
                }
            }
            group.addTask { [self] in
                do {
                    let rate = try await self.estimateFee(for: 2)
                    return (2, rate, nil)
                } catch {
                    return (2, nil, error)
                }
            }
            group.addTask { [self] in
                do {
                    let rate = try await self.estimateFee(for: 6)
                    return (6, rate, nil)
                } catch {
                    return (6, nil, error)
                }
            }

            for await (blocks, rate, error) in group {
                if let rate = rate {
                    switch blocks {
                    case 1:  fastRate = rate
                    case 2:  mediumRate = rate
                    case 6:  slowRate = rate
                    default: break
                    }
                } else {
                    failureCount += 1
                    if let error = error {
                        logger.warning("Blockbook fee estimate for \(blocks)-block target failed: \(error.localizedDescription)")
                    }
                }
            }
        }

        if failureCount == 3 {
            let error = APIError.serverUnavailable
            await MainActor.run { self.lastError = error }
            logger.error("All fee estimate requests failed; using fallback rates")
        }

        // Enforce monotonicity: fast >= medium >= slow
        let adjustedSlow = max(slowRate, minimumFeeRate)
        let adjustedMedium = max(mediumRate, adjustedSlow)
        let adjustedFast = max(fastRate, adjustedMedium)

        let estimates = FeeEstimates(
            slow: FeeRate(satPerVByte: adjustedSlow, estimatedBlocks: 6, estimatedMinutes: 60),
            medium: FeeRate(satPerVByte: adjustedMedium, estimatedBlocks: 2, estimatedMinutes: 20),
            fast: FeeRate(satPerVByte: adjustedFast, estimatedBlocks: 1, estimatedMinutes: 10),
            timestamp: Date()
        )

        await MainActor.run { self.currentEstimates = estimates }
        logger.info("Fee estimates (Blockbook): fast=\(adjustedFast) med=\(adjustedMedium) slow=\(adjustedSlow) sat/vB")
        return estimates
    }

    // MARK: - mempool.space API

    /// Fetches fee estimates from mempool.space. Returns sat/vB directly — no conversion needed.
    /// Response: { "fastestFee": N, "halfHourFee": N, "hourFee": N, "economyFee": N, "minimumFee": N }
    private func fetchMempoolFees() async -> FeeEstimates? {
        guard let url = URL(string: mempoolFeeURL) else { return nil }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                logger.warning("mempool.space returned non-200 status")
                return nil
            }

            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                logger.warning("mempool.space returned invalid JSON")
                return nil
            }

            // Extract fee rates (all in sat/vB)
            guard let fastestFee = (json["fastestFee"] as? NSNumber)?.decimalValue,
                  let halfHourFee = (json["halfHourFee"] as? NSNumber)?.decimalValue,
                  let hourFee = (json["hourFee"] as? NSNumber)?.decimalValue else {
                logger.warning("mempool.space missing required fee fields")
                return nil
            }

            // Clamp to minimum
            let fast = max(fastestFee, minimumFeeRate)
            let medium = max(halfHourFee, minimumFeeRate)
            let slow = max(hourFee, minimumFeeRate)

            return FeeEstimates(
                slow: FeeRate(satPerVByte: slow, estimatedBlocks: 6, estimatedMinutes: 60),
                medium: FeeRate(satPerVByte: medium, estimatedBlocks: 3, estimatedMinutes: 30),
                fast: FeeRate(satPerVByte: fast, estimatedBlocks: 1, estimatedMinutes: 10),
                timestamp: Date()
            )
        } catch {
            logger.warning("mempool.space fetch failed: \(error.localizedDescription)")
            return nil
        }
    }

    /// Estimate the fee rate for a specific confirmation target.
    ///
    /// Queries the Blockbook `/api/v2/estimatefee/<blocks>` endpoint and converts
    /// the returned BTC/kB value to sat/vB:
    ///
    /// ```
    /// sat/vB = BTC/kB * 100,000,000 (sat/BTC) / 1,000 (B/kB) = BTC/kB * 100,000
    /// ```
    ///
    /// The result is clamped to a minimum of 1 sat/vB, since rates below this
    /// threshold are unlikely to be relayed by most nodes.
    ///
    /// - Parameter blocks: The target number of blocks for confirmation.
    /// - Returns: The estimated fee rate in sat/vB.
    /// - Throws: ``APIError`` on failure; callers should handle this by using a fallback rate.
    func estimateFee(for blocks: Int) async throws -> Decimal {
        let response = try await blockbookAPI.estimateFee(blocks: blocks)

        // The Blockbook response returns the fee rate as BTC/kB in a string field.
        // A value of "-1" or "0" indicates that the backend cannot provide an estimate.
        // Maximum sane fee rate: 10,000 sat/vB (0.1 BTC/kB).
        // Anything above this is almost certainly a malicious or erroneous response.
        let maxBtcPerKB: Decimal = 1 / 10  // 0.1 BTC/kB = 10,000 sat/vB

        guard let btcPerKB = Decimal(string: response.result), btcPerKB > 0 else {
            logger.warning("Invalid fee estimate for \(blocks)-block target: \"\(response.result)\". Using fallback.")
            return fallbackRate(for: blocks)
        }

        guard btcPerKB <= maxBtcPerKB else {
            logger.warning("Fee estimate \(response.result) BTC/kB exceeds safety maximum (\(maxBtcPerKB) BTC/kB). Using fallback.")
            return fallbackRate(for: blocks)
        }

        // Convert BTC/kB to sat/vB:
        //   BTC/kB * 100,000,000 sat/BTC / 1,000 B/kB = BTC/kB * 100,000
        //
        // Note: For SegWit transactions, the virtual size (vB) is smaller than the
        // actual size (B), so sat/B slightly overestimates sat/vB. This is acceptable
        // because it provides a small safety margin for faster confirmation.
        let satPerVByte = btcPerKB * Decimal(100_000)

        // Clamp to the minimum relay fee
        let clampedRate = max(satPerVByte, minimumFeeRate)

        logger.debug("Fee estimate for \(blocks)-block target: \(clampedRate) sat/vB (raw BTC/kB: \(response.result))")
        return clampedRate
    }

    /// Calculate the total transaction fee in satoshis.
    ///
    /// ```swift
    /// let fee = estimator.calculateTransactionFee(virtualSize: 141, feeRate: 20)
    /// // fee = 2820 satoshis
    /// ```
    ///
    /// - Parameters:
    ///   - virtualSize: The transaction's virtual size in vBytes. For a typical
    ///     single-input, single-output P2WPKH transaction this is around 110-141 vB.
    ///   - feeRate: The fee rate in sat/vB.
    /// - Returns: Total fee in satoshis (`feeRate * virtualSize`).
    func calculateTransactionFee(virtualSize: Int, feeRate: Decimal) -> Decimal {
        guard virtualSize > 0, feeRate > 0 else {
            return Decimal.zero
        }
        return feeRate * Decimal(virtualSize)
    }

    /// Convert a fee in satoshis to BTC.
    ///
    /// - Parameter satoshis: The fee amount in satoshis.
    /// - Returns: The equivalent amount in BTC.
    func satoshisToBTC(_ satoshis: Decimal) -> Decimal {
        satoshis / Decimal(100_000_000)
    }

    /// Refresh fee estimates if the current ones are stale or absent.
    ///
    /// This is a convenience method for views that want to ensure fresh data
    /// without unconditionally hitting the network.
    ///
    /// - Returns: The current (possibly refreshed) ``FeeEstimates``.
    /// - Throws: ``APIError`` if the refresh fails and no cached estimates exist.
    @discardableResult
    func refreshIfNeeded() async throws -> FeeEstimates {
        if let existing = currentEstimates, !existing.isStale {
            logger.debug("Fee estimates are still fresh (\(Int(existing.ageInSeconds))s old). Skipping refresh.")
            return existing
        }

        logger.info("Fee estimates are stale or missing. Refreshing...")
        return try await estimateFees()
    }

    // MARK: - Private Helpers

    /// Return the hardcoded fallback fee rate for a given block target.
    ///
    /// Fallback rates are deliberately conservative (slightly higher than
    /// typical mempool conditions) to avoid transactions getting stuck.
    ///
    /// - Parameter blocks: The target number of blocks.
    /// - Returns: A reasonable default fee rate in sat/vB.
    private func fallbackRate(for blocks: Int) -> Decimal {
        switch blocks {
        case 1:
            return fallbackFast
        case 2:
            return fallbackMedium
        case 3...6:
            return fallbackSlow
        default:
            // For targets beyond 6 blocks, use the slow rate as a floor
            return fallbackSlow
        }
    }
}
