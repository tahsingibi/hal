import Foundation
import IOKit
import IOKit.ps

/// One reading of the battery and power state, read from the system's
/// smart battery service.
struct PowerReading: Equatable {
    var chargePercent: Int?
    var isCharging = false
    var onAdapter = false
    /// Minutes until empty (on battery) or full (charging); nil while the
    /// system is still estimating.
    var minutesRemaining: Int?
    var cycleCount: Int?
    /// Current full-charge capacity against the design capacity.
    var healthPercent: Int?
    var temperatureCelsius: Double?
    var fullChargeCapacity: Int?
    var designCapacity: Int?
    /// Positive while charging, negative while the battery supplies the Mac.
    var batteryWatts: Double?
    /// What the whole system draws, when the hardware reports it.
    var systemWatts: Double?
    var adapterWatts: Int?
    var adapterInputWatts: Double?
    var hasBattery = false
}

/// Samples power while the panel shows it, and keeps a short history of the
/// system draw for the chart.
@MainActor
final class PowerService: ObservableObject {
    static let shared = PowerService()

    @Published private(set) var reading = PowerReading()
    @Published private(set) var systemHistory: [Double] = []
    @Published private(set) var chargeHistory: [Double] = []

    private var timer: Timer?
    private var viewers = 0
    private static let historyLength = 60

    private init() {
        reading = Self.read()
    }

    /// The panel calls these as the section appears and disappears, so nothing
    /// polls while no one is looking.
    func beginObserving() {
        viewers += 1
        guard timer == nil else { return }
        refresh()
        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        timer.tolerance = 0.5
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func endObserving() {
        viewers = max(0, viewers - 1)
        guard viewers == 0 else { return }
        timer?.invalidate()
        timer = nil
    }

    func refresh() {
        let next = Self.read()
        if next != reading { reading = next }
        if let percent = next.chargePercent {
            chargeHistory.append(Double(percent))
            if chargeHistory.count > Self.historyLength {
                chargeHistory.removeFirst(chargeHistory.count - Self.historyLength)
            }
        }
        if let watts = next.systemWatts ?? next.batteryWatts.map(abs) {
            systemHistory.append(watts)
            if systemHistory.count > Self.historyLength {
                systemHistory.removeFirst(systemHistory.count - Self.historyLength)
            }
        }
    }

    // MARK: - Reading

    nonisolated static func read() -> PowerReading {
        var result = PowerReading()
        readPowerSource(into: &result)
        readSmartBattery(into: &result)
        if result.hasBattery, result.temperatureCelsius == nil {
            result.temperatureCelsius = readBatteryPackTemperature()
        }
        return result
    }

    /// Recent macOS versions publish temperature on the battery pack rather
    /// than on the aggregate AppleSmartBattery service.
    private nonisolated static func readBatteryPackTemperature() -> Double? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceNameMatching("AppleSmartBatteryPack"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        guard let raw = IORegistryEntryCreateCFProperty(service, "BatteryData" as CFString, kCFAllocatorDefault, 0),
              let data = raw.takeRetainedValue() as? [String: Any] else { return nil }
        return temperature(in: data)
    }

    nonisolated static func temperature(in data: [String: Any]) -> Double? {
        guard let raw = data["Temperature"] as? NSNumber else { return nil }
        let value = raw.doubleValue / 100
        guard value.isFinite, value > -20, value < 100, value != 0 else { return nil }
        return value
    }

    private nonisolated static func readPowerSource(into result: inout PowerReading) {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return }
        for source in list {
            guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue()
                    as? [String: Any],
                  (description[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType else { continue }
            result.hasBattery = true
            if let current = description[kIOPSCurrentCapacityKey] as? Int,
               let maximum = description[kIOPSMaxCapacityKey] as? Int, maximum > 0 {
                result.chargePercent = min(100, max(0, Int((Double(current) / Double(maximum) * 100).rounded())))
            }
            result.isCharging = description[kIOPSIsChargingKey] as? Bool ?? false
            result.onAdapter = (description[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
            let minutes = result.isCharging
                ? description[kIOPSTimeToFullChargeKey] as? Int
                : (!result.onAdapter ? description[kIOPSTimeToEmptyKey] as? Int : nil)
            if let minutes, minutes > 0 { result.minutesRemaining = minutes }
        }
        if let adapter = IOPSCopyExternalPowerAdapterDetails()?.takeRetainedValue() as? [String: Any],
           let watts = adapter[kIOPSPowerAdapterWattsKey] as? Int {
            result.adapterWatts = watts
            result.onAdapter = true
        }
    }

    private nonisolated static func readSmartBattery(into result: inout PowerReading) {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return }
        defer { IOObjectRelease(service) }
        var unmanaged: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &unmanaged, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let properties = unmanaged?.takeRetainedValue() as? [String: Any] else { return }
        applySmartBattery(properties, to: &result)
    }

    /// Newer Macs place raw mAh capacities in BatteryData. MaxCapacity at the
    /// root can be a charge percentage, so it must not be used as raw capacity.
    nonisolated static func applySmartBattery(_ properties: [String: Any], to result: inout PowerReading) {
        guard properties["BatteryInstalled"] as? Bool != false else { return }
        result.hasBattery = true
        let data = properties["BatteryData"] as? [String: Any] ?? [:]
        func integer(_ key: String) -> Int? {
            (properties[key] as? NSNumber ?? data[key] as? NSNumber)?.intValue
        }
        func positive(_ key: String) -> Int? {
            guard let value = integer(key), value > 0 else { return nil }
            return value
        }
        if let cycles = integer("CycleCount"), cycles >= 0 { result.cycleCount = cycles }
        result.designCapacity = positive("DesignCapacity")
        result.fullChargeCapacity = positive("NominalChargeCapacity")
            ?? positive("AppleRawMaxCapacity") ?? positive("FullChargeCapacity")
        if let design = result.designCapacity, let fullCharge = result.fullChargeCapacity {
            result.healthPercent = min(100, max(0, Int((Double(fullCharge) / Double(design) * 100).rounded())))
        }
        result.temperatureCelsius = temperature(in: properties) ?? temperature(in: data)
        // NSNumber.intValue also handles discharge current encoded as unsigned
        // two's complement in the registry.
        if let millivolts = positive("Voltage"), let milliamps = integer("Amperage") {
            result.batteryWatts = Double(millivolts) * Double(milliamps) / 1_000_000
        }
        if let telemetry = properties["PowerTelemetryData"] as? [String: Any] {
            if let load = telemetry["SystemLoad"] as? Int, load >= 0 {
                result.systemWatts = Double(load) / 1000
            }
            if result.onAdapter, let input = telemetry["SystemPowerIn"] as? Int, input >= 0 {
                result.adapterInputWatts = Double(input) / 1000
            }
        }
    }
}
