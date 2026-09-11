import Foundation

/// Decides how hard the scan is allowed to push right now.
///
/// A duplicate scan is the kind of work that will happily cook a phone: thousands of resource
/// reads and image decodes, back to back. Throttling is not politeness — a throttled device
/// runs everything else the user is doing slowly too, and a scan that makes the phone hot is
/// a scan they force quit.
public protocol ScanThrottling: Sendable {
    /// Reads allowed in flight, given the pipeline's configured ceiling.
    func concurrencyLimit(base: Int) -> Int
}

public struct SystemThrottle: ScanThrottling {

    public init() {}

    public func concurrencyLimit(base: Int) -> Int {
        Self.limit(
            base: base,
            thermalState: ProcessInfo.processInfo.thermalState,
            isLowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled
        )
    }

    /// Separated from the live system state so the policy itself is testable.
    public static func limit(
        base: Int,
        thermalState: ProcessInfo.ThermalState,
        isLowPowerMode: Bool
    ) -> Int {
        guard base > 0 else { return 1 }

        // Low Power Mode is an explicit instruction from the user about their battery.
        if isLowPowerMode { return 1 }

        switch thermalState {
        case .critical, .serious:
            return 1
        case .fair:
            return max(1, base / 2)
        case .nominal:
            return base
        @unknown default:
            return max(1, base / 2)
        }
    }
}

/// Runs flat out. For tests, and for previews where nothing real is being read.
public struct UnthrottledScan: ScanThrottling {
    public init() {}
    public func concurrencyLimit(base: Int) -> Int { max(1, base) }
}
