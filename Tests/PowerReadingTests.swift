import Foundation
import Combine

@main
struct PowerReadingTests {
    static func main() {
        // Current Apple Silicon layout: root MaxCapacity is a percentage;
        // capacity in mAh lives inside BatteryData, and temperature is absent.
        var modern = PowerReading()
        modern.onAdapter = true
        PowerService.applySmartBattery([
            "CycleCount": 54, "MaxCapacity": 100,
            "BatteryData": ["DesignCapacity": 6249, "NominalChargeCapacity": 6218,
                            "AppleRawMaxCapacity": 6066],
            "PowerTelemetryData": ["SystemLoad": 15000, "SystemPowerIn": 16000]
        ], to: &modern)
        precondition(modern.cycleCount == 54 && modern.healthPercent == 100)
        precondition(modern.fullChargeCapacity == 6218 && modern.designCapacity == 6249)
        precondition(modern.temperatureCelsius == nil)
        precondition(modern.systemWatts == 15 && modern.adapterInputWatts == 16)

        var legacy = PowerReading()
        PowerService.applySmartBattery([
            "CycleCount": 0, "DesignCapacity": 5000, "AppleRawMaxCapacity": 4000,
            "Temperature": 2510, "Voltage": 12000,
            "Amperage": NSNumber(value: UInt64.max - 999)
        ], to: &legacy)
        precondition(legacy.healthPercent == 80 && legacy.cycleCount == 0)
        precondition(legacy.temperatureCelsius == 25.1 && legacy.batteryWatts == -12)

        var incomplete = PowerReading()
        PowerService.applySmartBattery(["CycleCount": 54, "MaxCapacity": 100,
                                       "DesignCapacity": 0, "Temperature": 65535], to: &incomplete)
        precondition(incomplete.cycleCount == 54 && incomplete.healthPercent == nil)
        precondition(incomplete.temperatureCelsius == nil)
        precondition(PowerService.temperature(in: ["Temperature": 2859]) == 28.59)
        precondition(PowerService.temperature(in: ["Temperature": Double.nan]) == nil)
        precondition(PowerService.temperature(in: ["Temperature": 65535]) == nil)
        print("PASS: nested and legacy battery data, missing fields, signed discharge and adapter power")
        if CommandLine.arguments.contains("--live") {
            let reading = PowerService.read()
            print("Live: temperature=\(String(describing: reading.temperatureCelsius)) °C, cycles=\(String(describing: reading.cycleCount)), health=\(String(describing: reading.healthPercent)), capacity=\(String(describing: reading.fullChargeCapacity))/\(String(describing: reading.designCapacity)) mAh")
        }
    }
}
