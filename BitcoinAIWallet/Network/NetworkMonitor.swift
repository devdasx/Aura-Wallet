// MARK: - NetworkMonitor.swift
// Bitcoin AI Wallet
//
// Observes device network connectivity using the Network framework's
// NWPathMonitor. Publishes connection status and type changes so that
// SwiftUI views and services can adapt behavior when the device goes
// offline or transitions between Wi-Fi and cellular.
//
// Platform: iOS 17.0+
// Dependencies: Foundation, Network, Combine (via ObservableObject)

import Foundation
import Network
import os.log

// MARK: - ConnectionType

/// The kind of network interface currently in use.
///
/// Determined by inspecting the `NWPath` reported by `NWPathMonitor`.
enum ConnectionType: String, Sendable {

    /// Connected via Wi-Fi.
    case wifi

    /// Connected via a cellular data network (LTE, 5G, etc.).
    case cellular

    /// Connected via a wired Ethernet adapter.
    case wired

    /// The connection type could not be determined, or no connection exists.
    case unknown
}

// MARK: - NetworkMonitorProtocol

/// Abstraction over network reachability monitoring.
///
/// Conform to this protocol in test doubles to simulate connectivity
/// changes without relying on real hardware.
protocol NetworkMonitorProtocol: AnyObject {

    /// Whether the device currently has a satisfactory network path.
    var isConnected: Bool { get }

    /// The type of the active network interface.
    var connectionType: ConnectionType { get }

    /// Begin monitoring network path changes.
    func startMonitoring()

    /// Stop monitoring and release system resources.
    func stopMonitoring()
}

// MARK: - NetworkMonitor

/// Monitors device network connectivity in real time using `NWPathMonitor`.
///
/// The monitor is designed as a singleton (``shared``) because the entire app
/// needs a single, consistent view of the device's connectivity state.
/// Published properties update on the main thread so they can drive SwiftUI
/// views directly.
///
/// ```swift
/// struct ContentView: View {
///     @ObservedObject var network = NetworkMonitor.shared
///
///     var body: some View {
///         if !network.isConnected {
///             Text("No internet connection")
///         }
///     }
/// }
/// ```
///
/// > Important: Call ``stopMonitoring()`` only when the app is being torn down.
/// > Under normal operation the monitor should remain active for the app's lifetime.
final class NetworkMonitor: ObservableObject, NetworkMonitorProtocol {

    // MARK: - Singleton

    /// Shared instance used throughout the app.
    static let shared = NetworkMonitor()

    // MARK: - Published Properties

    /// Whether the device currently has a satisfactory network path.
    ///
    /// Updated on the main thread whenever the underlying `NWPath` changes.
    /// `true` when `NWPath.status == .satisfied`.
    @Published private(set) var isConnected: Bool = true

    /// The type of network interface currently in use.
    ///
    /// Updated on the main thread alongside ``isConnected``.
    @Published private(set) var connectionType: ConnectionType = .unknown

    /// Whether the current path is considered "expensive" (e.g. cellular or personal hotspot).
    ///
    /// Use this to gate large data transfers or defer non-critical background work.
    @Published private(set) var isExpensive: Bool = false

    /// Whether the current path is "constrained" (e.g. Low Data Mode is enabled).
    ///
    /// When `true`, the app should minimize data usage.
    @Published private(set) var isConstrained: Bool = false

    // MARK: - Private Properties

    /// The underlying Network framework path monitor.
    /// This is `var` because `NWPathMonitor` cannot be restarted after
    /// cancellation -- a new instance must be created.
    private var monitor: NWPathMonitor

    /// Dedicated serial queue for receiving path update callbacks.
    ///
    /// `NWPathMonitor` delivers callbacks on whichever queue is provided at start time.
    /// Using a dedicated serial queue avoids blocking the main thread and prevents
    /// data races on internal state.
    private let queue: DispatchQueue

    /// Logger for connectivity diagnostics.
    private let logger = Logger(subsystem: "com.bitcoinai.wallet", category: "NetworkMonitor")

    /// Tracks whether the monitor is actively observing path changes.
    private var isMonitoring: Bool = false

    // MARK: - Initialization

    /// Create a network monitor.
    ///
    /// The default initializer is private to enforce singleton usage via ``shared``.
    /// In tests, use ``init(monitor:queue:)`` to inject a mock `NWPathMonitor`.
    private init() {
        self.monitor = NWPathMonitor()
        self.queue = DispatchQueue(label: "com.bitcoinai.wallet.networkmonitor", qos: .utility)
        startMonitoring()
    }

    /// Create a network monitor with injected dependencies.
    ///
    /// This initializer is available for testing purposes only. It accepts
    /// a custom `NWPathMonitor` and dispatch queue.
    ///
    /// - Parameters:
    ///   - monitor: The `NWPathMonitor` to observe.
    ///   - queue: The dispatch queue for path update callbacks.
    init(monitor: NWPathMonitor, queue: DispatchQueue) {
        self.monitor = monitor
        self.queue = queue
    }

    deinit {
        stopMonitoring()
    }

    // MARK: - Public API

    /// Begin monitoring network path changes.
    ///
    /// Calling this method when already monitoring is a no-op. If the previous
    /// monitor was cancelled, a fresh `NWPathMonitor` instance is created
    /// because `NWPathMonitor` cannot be restarted after cancellation.
    /// The `pathUpdateHandler` fires immediately with the current path state
    /// and subsequently on every change.
    func startMonitoring() {
        guard !isMonitoring else {
            logger.debug("Network monitor is already active. Ignoring duplicate start.")
            return
        }

        // NWPathMonitor cannot be restarted after cancel(). Create a new
        // instance to ensure the handler will actually fire.
        monitor = NWPathMonitor()

        logger.info("Starting network path monitoring")
        isMonitoring = true

        monitor.pathUpdateHandler = { [weak self] path in
            guard let self = self else { return }
            self.handlePathUpdate(path)
        }

        monitor.start(queue: queue)
    }

    /// Stop monitoring and release the `NWPathMonitor`.
    ///
    /// After calling this method, ``isConnected`` and ``connectionType`` retain
    /// their last-known values but are no longer updated. Calling
    /// ``startMonitoring()`` again after cancellation is **not** supported by
    /// `NWPathMonitor`; create a new instance instead.
    func stopMonitoring() {
        guard isMonitoring else { return }

        logger.info("Stopping network path monitoring")
        monitor.cancel()
        isMonitoring = false
    }

    // MARK: - Private Helpers

    /// Process an `NWPath` update from the monitor.
    ///
    /// Extracts connection status, interface type, and cost flags, then
    /// dispatches the results to the main thread for SwiftUI observation.
    ///
    /// - Parameter path: The updated `NWPath` from `NWPathMonitor`.
    private func handlePathUpdate(_ path: NWPath) {
        let connected = path.status == .satisfied
        let type = resolveConnectionType(from: path)
        let expensive = path.isExpensive
        let constrained = path.isConstrained

        logger.info(
            "Network path updated: connected=\(connected), type=\(type.rawValue), expensive=\(expensive), constrained=\(constrained)"
        )

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.isConnected = connected
            self.connectionType = type
            self.isExpensive = expensive
            self.isConstrained = constrained
        }
    }

    /// Determine the ``ConnectionType`` from an `NWPath`.
    ///
    /// The checks are ordered by priority: Wi-Fi is preferred over cellular,
    /// and cellular over wired, matching the typical precedence on iOS devices.
    ///
    /// - Parameter path: The `NWPath` to inspect.
    /// - Returns: The resolved ``ConnectionType``.
    private func resolveConnectionType(from path: NWPath) -> ConnectionType {
        if path.usesInterfaceType(.wifi) {
            return .wifi
        }
        if path.usesInterfaceType(.cellular) {
            return .cellular
        }
        if path.usesInterfaceType(.wiredEthernet) {
            return .wired
        }
        return .unknown
    }
}
